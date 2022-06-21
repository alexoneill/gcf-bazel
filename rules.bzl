# Google Cloud Function Bazel rules.


# Top level entrypoint for extracting code from the compiled zip.
# This ensures a hermetic build for deploy.
def _zip_entry(ctx, zipfile):
  return '''\
#!/bin/bash
DIR="$(cd "$(dirname "${{BASH_SOURCE[0]}}")" &> /dev/null && pwd)"
BASE="${{DIR??}}/$(basename "${{BASH_SOURCE[0]}}").runfiles/{workspace_name}"

# Extract the source files into a temporary location.
SRC_TMP=$(mktemp -d)
unzip "${{BASE?}}/{zipfile}" 'runfiles/{workspace_name}/*' -d "${{SRC_TMP?}}" >/dev/null
SRC_TMP="${{SRC_TMP?}}/runfiles/{workspace_name}"
'''.format(zipfile=zipfile, workspace_name=ctx.workspace_name)


# Top level entrypoint for using symlinked code from Bazel.
# This ensures changes in the client can trigger Flask reloads during local
# serving.
def _symlink_entry(ctx):
  return '''\
#!/bin/bash
DIR="$(cd "$(dirname "${{BASH_SOURCE[0]}}")" &> /dev/null && pwd)"
BASE="${{DIR??}}/$(basename "${{BASH_SOURCE[0]}}").runfiles/{workspace_name}"

# Extract the source files into a temporary location.
SRC_TMP=$(mktemp -d)
cp -r "${{BASE}}/"* "${{SRC_TMP}}"
'''.format(workspace_name=ctx.workspace_name)


# Logic to inject the "env.yaml" file into the root of the output. Used for
# both deploy and local execution.
def _inject_env(maybe_env):
  if maybe_env == None:
    return '''\
# Insert a value for GCP_PROJECT (for compatibility with newer runtimes).
PROJECT=$(gcloud config get-value project)
ENV_PATH="${SRC_TMP?}/env.yaml"
cat << EOF > "${ENV_PATH?}"
# Project and environment.
GCP_PROJECT: ${PROJECT?}
FLASK_ENV: production
EOF
'''

  return '''\
# Insert a value for GCP_PROJECT (for compatibility with newer runtimes).
ENV_PATH="${{SRC_TMP?}}/env.yaml"
cp "${{BASE?}}/{env}" "${{ENV_PATH?}}"

PROJECT=$(gcloud config get-value project)
cat << EOF >> "${{ENV_PATH?}}"

# Project and environment.
GCP_PROJECT: ${{PROJECT?}}
FLASK_ENV: production
EOF
'''.format(env=maybe_env.path)


# Logic to install packages from the "requirements.txt" file. Used for
# py_gcf_local below.
def _install_requirements(maybe_requirements):
  if maybe_requirements == None:
    return ''

  return '''\
# Install dependencies.
if ! python3 -c \\
      "import pkg_resources;pkg_resources.require(open('"${{BASE?}}/{reqs}"'))" \\
      2>/dev/null; then
  python3 -m pip install -r "${{BASE?}}/{reqs}" >/dev/null
  python3 -m pip install flask pyyaml >/dev/null
fi
'''.format(reqs=maybe_requirements.path)


# Logic to add a Google Cloud Service Account (SA) check to the deploy script,
# only if the service account is added on the rule.
def _service_account_check(maybe_sa):
  if maybe_sa == '':
    return ''

  return '''
# Search for the service account.
! ACCT=$(gcloud iam service-accounts list --format 'csv(email)' \\
  | tail -n +2 \\
  | grep '^{service_account}@') \\
  && echo 'err: Could not find service account "{service_account}"' \\
  && return 1
'''.format(service_account=maybe_sa)


# Get the Python code to call the entrypoint with.
#
# This switches between handling HTTP or Pub/Sub inputs.
def _get_call_code(is_pubsub):
  if is_pubsub:
    return "return __ENTRYPOINT(dict(data=request.data), object()) or ''"
  return "return __ENTRYPOINT(request) or ''"

# Create a test script to validate the function locally.
def _py_gcf_local_impl(ctx):
  # Create a bash script that deploys the binary contents.
  executable = ctx.actions.declare_file(ctx.label.name + '.sh')
  ctx.actions.write(
      output=executable,
      content=_symlink_entry(ctx) + _inject_env(ctx.file.environment) +
      _install_requirements(ctx.file.requirements) + '''
# Place a suitable test harness in.
cat << EOF > "${{SRC_TMP?}}/main.py"
#!/usr/bin/env python3

from flask import Flask, request
from werkzeug.routing import Rule
from yaml import FullLoader, load

import json
import os
import sys

def main(port='8080'):
  # If the port is malformed, error out.
  if not port.isdigit() or int(port) <= 0:
    print('error: Bad argument for port')
    print('usage: main.py <port>')
    return 1

  # Load environment variables.
  env = load(open("${{ENV_PATH?}}"), Loader=FullLoader)
  for var in env:
    if env[var] is not None:
      os.environ[var] = env[var]

  # Overwrite environment to be development.
  os.environ['FLASK_ENV'] = 'development'
  from {module} import {entrypoint} as __ENTRYPOINT

  # Simulate a request to a Flask app.
  app = Flask(__name__)

  # Route all traffic to the handler.
  app.url_map.add(Rule('/', endpoint='index'))
  app.url_map.add(Rule('/<path:path>', endpoint='index'))

  @app.endpoint('index')
  def index(*args, **kwargs):
    {call_code}

  app.run(port=port)

if __name__ == '__main__':
  main(*sys.argv[1:])
EOF

chmod +x "${{SRC_TMP?}}/main.py"
"${{SRC_TMP?}}/main.py" "$@"
'''.format(
          module='%s.%s' %
          (ctx.label.package.replace('/', '.'), ctx.attr.src.label.name),
          entrypoint=ctx.attr.entrypoint,
          call_code=_get_call_code(ctx.attr.is_pubsub),
      ))

  # Collect runtime files to bundle with the deploy.
  runfiles = ctx.runfiles(
      files=ctx.files.data +
      ([ctx.file.environment] if ctx.file.environment else []) +
      ([ctx.file.requirements] if ctx.file.requirements else []))
  runfiles = runfiles.merge(ctx.attr.src[DefaultInfo].default_runfiles)
  for target in ctx.attr.data:
    runfiles = runfiles.merge(target[DefaultInfo].default_runfiles)

  return [
      DefaultInfo(executable=executable, runfiles=runfiles),
  ]


# Logic to inject the "requirements.txt" file into the root of the output. Used
# for py_gcf_deploy below.
def _inject_requirements(maybe_requirements):
  if maybe_requirements == None:
    return ''

  return '''\
# Copy the requirements.txt file.
cp "{reqs}" "${{SRC_TMP?}}/requirements.txt"
'''.format(reqs=maybe_requirements.path)


# Create a deploy script for the Python binary to use it on GCP's Functions.
def _py_gcf_deploy_impl(ctx):
  # Create a bash script that deploys the binary contents.
  executable = ctx.actions.declare_file(ctx.label.name + '.sh')
  ctx.actions.write(
      output=executable,
      content=_zip_entry(
          ctx, '%s/%s.zip' % (ctx.label.package, ctx.attr.src.label.name)) +
      _inject_env(ctx.file.environment) +
      _inject_requirements(ctx.file.requirements) + '''
# Check gcloud.
! gcloud auth print-access-token >/dev/null 2>&1 \\
  && echo 'err: Check your gcloud' \\
  && return 1
''' + _service_account_check(ctx.attr.service_account) +
      ('''
# Place a dummy root file with the right entrypoint.
echo "from {module} import {entrypoint}" > "${{SRC_TMP?}}/main.py"

# Deploy the function.
gcloud functions deploy \\
  --runtime=python39 \\
  --source="${{SRC_TMP?}}" \\
  --env-vars-file="${{ENV_PATH?}}" \\''' +
       ('''
  --service-account=${{ACCT?}} \\''' if ctx.attr.service_account else '') + '''
  --entry-point={entrypoint} \\
  "${{@}}" \\
  {name}
''').format(
           module='%s.%s' %
           (ctx.label.package.replace('/', '.'), ctx.attr.src.label.name),
           entrypoint=ctx.attr.entrypoint,
           name=ctx.attr.function_name,
       ))

  # Collect runtime files to bundle with the deploy.
  runfiles = ctx.runfiles(
      files=ctx.files.data +
      ([ctx.file.environment] if ctx.file.environment else []) +
      ([ctx.file.requirements] if ctx.file.requirements else []))
  runfiles = runfiles.merge(ctx.attr.src[DefaultInfo].default_runfiles)
  for target in ctx.attr.data:
    runfiles = runfiles.merge(target[DefaultInfo].default_runfiles)

  return [
      DefaultInfo(executable=executable, runfiles=runfiles),
  ]


# Logic to inject the "Dockerfile" file into the root of the output. Used for
# py_gcp_run_deploy below.
def _inject_dockerfile(maybe_dockerfile):
  if maybe_dockerfile == None:
    return ''

  return '''\
# Copy the Dockerfile.
cp "{df}" "${{SRC_TMP?}}/Dockerfile"
'''.format(df=maybe_dockerfile.path)


# Create a deploy script for the Python binary to use it on GCP's Cloud Run.
def _py_gcp_run_deploy_impl(ctx):
  # Create a bash script that deploys the binary contents.
  executable = ctx.actions.declare_file(ctx.label.name + '.sh')
  ctx.actions.write(
      output=executable,
      content=_zip_entry(
          ctx, '%s/%s.zip' % (ctx.label.package, ctx.attr.src.label.name)) +
      _inject_env(ctx.file.environment) +
      _inject_requirements(ctx.file.requirements) +
      _inject_dockerfile(ctx.file.dockerfile) + '''
# Check gcloud.
! gcloud auth print-access-token >/dev/null 2>&1 \\
  && echo 'err: Check your gcloud' \\
  && return 1
''' + _service_account_check(ctx.attr.service_account) +
      ('''
# Place a dummy root file.
echo "from {module} import *" > "${{SRC_TMP?}}/main.py"

# Deploy the function.
gcloud run deploy \\
  {name} \\
  --source="${{SRC_TMP?}}" \\
  --env-vars-file="${{ENV_PATH?}}" \\''' +
       ('''
  --service-account=${{ACCT?}} \\''' if ctx.attr.service_account else '') + '''
  "${{@}}"
''').format(
           module='%s.%s' %
           (ctx.label.package.replace('/', '.'), ctx.attr.src.label.name),
           name=ctx.attr.run_name,
       ))

  # Collect runtime files to bundle with the deploy.
  runfiles = ctx.runfiles(
      files=ctx.files.data +
      ([ctx.file.environment] if ctx.file.environment else []) +
      ([ctx.file.dockerfile] if ctx.file.dockerfile else []) +
      ([ctx.file.requirements] if ctx.file.requirements else []))
  runfiles = runfiles.merge(ctx.attr.src[DefaultInfo].default_runfiles)
  for target in ctx.attr.data:
    runfiles = runfiles.merge(target[DefaultInfo].default_runfiles)

  return [
      DefaultInfo(executable=executable, runfiles=runfiles),
  ]


# Rule to test a py_binary rule as a local GCP Cloud Function.
py_gcf_local = rule(
    implementation=_py_gcf_local_impl,
    attrs={
        'src': attr.label(mandatory=True),
        'data': attr.label_list(allow_files=True),
        'requirements': attr.label(allow_single_file=True),
        'environment': attr.label(allow_single_file=True),
        'entrypoint': attr.string(mandatory=True),
        'is_pubsub': attr.bool(default=False),
    },
    executable=True,
)

# Rule to deploy a py_binary rule onto GCP's Cloud Function product.
py_gcf_deploy = rule(
    implementation=_py_gcf_deploy_impl,
    attrs={
        'src': attr.label(mandatory=True),
        'data': attr.label_list(allow_files=True),
        'requirements': attr.label(allow_single_file=True),
        'environment': attr.label(allow_single_file=True),
        'function_name': attr.string(mandatory=True),
        'service_account': attr.string(),
        'entrypoint': attr.string(mandatory=True),
    },
    executable=True,
)

# Rule to deploy a py_binary rule onto GCP's Cloud Run product.
py_gcp_run_deploy = rule(
    implementation=_py_gcp_run_deploy_impl,
    attrs={
        'src': attr.label(mandatory=True),
        'data': attr.label_list(allow_files=True),
        'requirements': attr.label(allow_single_file=True),
        'environment': attr.label(allow_single_file=True),
        'dockerfile': attr.label(allow_single_file=True),
        'run_name': attr.string(mandatory=True),
        'service_account': attr.string(),
    },
    executable=True,
)
