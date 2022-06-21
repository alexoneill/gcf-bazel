# gcf-bazel

Bazel rules for Google Cloud Functions (GCF)

## Usage

### Installing

Add the following to your `WORKSPACE` file:

```bazel
load("@bazel_tools//tools/build_defs/repo:git.bzl", "git_repository")
git_repository(
    name = "gcf-bazel",
    remote = "https://github.com/alexoneill/gcf-bazel.git",
    branch = "main",
)
```

Optionally specify `commit = <hash>` to pin a specific version of these rules.

Additionally, copy `.bazelrc` from this repository into your destination repo.

### Rules

These rules require a `py_binary` rule that produces a binary which contains
the source code for the GCF. The output of this rule is then used as an input
for the functions explored below.

#### `py_gcf_local`

```
py_gcf_local(src, data, requirements, environment, entrypoint, is_pubsub)
```

Provides a `bash` script to run a GCF on a local port, simulating the
environment on GCP.

| Attribute | Description |
| --------- | ----------- |
| `src` |  `Label; required` <br><br> The `py_binary` target that contains the GCF source |
| `entrypoint` | `String; required` <br><br> The name of the function that is the central entrypoint for the GCF. |
| `data` | `List of labels; optional` <br><br> Any data dependencies to link in. Data dependencies from the `src` label are copied in. |
| `requirements` | `Label; optional` <br><br> Optionally provide the name of the `requirements.txt` file to use within the GCF runtime to install external Python packages. |
| `environment` | `Label; optional` <br><br> Optionally provide the name of the `env.yaml` file to populate environment variables within the local process. |
| `is_pubsub` | `Label; optional` <br><br> Optionally indicate if the given function entrypoint is for a Pub/Sub triggered function. Defaults to `False`, but if `True`, the entrypoint method will be called with a dictionary for the first argument (whose only key, `'data'` will be populated with the contents of any `POST`-ed bytes to the local GCF function) and an empty `object()` for the second argument. |

#### `py_gcf_deploy`

```
py_gcf_deploy(src, data, requirements, environment, function_name, service_account, entrypoint)
```

Provides a `bash` script to deploy a GCF with specific `gcloud` arguments.

| Attribute | Description |
| --------- | ----------- |
| `src` |  `Label; required` <br><br> The `py_binary` target that contains the GCF source |
| `entrypoint` | `String; required` <br><br> The name of the function that is the central entrypoint for the GCF. |
| `function_name` | `String; required` <br><br> What to name the deployed GCF function on GCP. |
| `data` | `List of labels; optional` <br><br> Any data dependencies to link in. Data dependencies from the `src` label are copied in. |
| `requirements` | `Label; optional` <br><br> Provide the name of the `requirements.txt` file to use within the GCF runtime to install external Python packages. |
| `environment` | `Label; optional` <br><br> Provide the name of the `env.yaml` file to to use within the GCF runtime to populate default environment variables. |
| `service_account` | `String; optional` <br><br> Provide the name of the Service Account to run the GCF as on GCP. |
| `args` | `List of strings; optional` <br><br> Provide additional arguments to `gcloud` not covered by the above (e.g. `--region`). Do not specify any of the following: `--runtime`, `--source`, `--env-vars-file`, `--service-account`, `--entry-point` |

#### `py_gcp_run_deploy`

```
py_gcp_run_deploy(src, data, requirements, dockerfile, environment, run_name, service_account)
```

Provides a `bash` script to deploy a GCP Run with specific `gcloud` arguments.

| Attribute | Description |
| --------- | ----------- |
| `src` |  `Label; required` <br><br> The `py_binary` target that contains the GCP Run source |
| `run_name` | `String; required` <br><br> What to name the deployed GCP Run on GCP. |
| `data` | `List of labels; optional` <br><br> Any data dependencies to link in. Data dependencies from the `src` label are copied in. |
| `requirements` | `Label; optional` <br><br> Provide the name of the `requirements.txt` file to use within the GCP Run runtime to install external Python packages. |
| `dockerfile` | `Label; optional` <br><br> Provide the name of the `Dockerfile` to use within the GCP Run runtime to configure the underlying Docker container. This Dockerfile should reference `main:app` as the entry point regardless of the name of the `py_binary` in the `src` attribute. |
| `environment` | `Label; optional` <br><br> Provide the name of the `env.yaml` file to to use within the GCP Run runtime to populate default environment variables. |
| `service_account` | `String; optional` <br><br> Provide the name of the Service Account to run the GCP Run as on GCP. |
| `args` | `List of strings; optional` <br><br> Provide additional arguments to `gcloud` not covered by the above (e.g. `--region`). Do not specify any of the following: `--source`, `--env-vars-file`, `--service-account` |

## Examples

See the `examples` folder for concrete usage examples.
