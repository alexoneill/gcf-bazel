load("@gcf-bazel//:rules.bzl", "py_gcf_local", "py_gcf_deploy")
# load("@gcf-bazel//rules:gcf.bzl", "py_gcf_local", "py_gcf_deploy")

py_binary(
    name = "echo",
    srcs = ["echo.py"],
)

py_gcf_local(
    name = "echo_local",
    src = ":echo",
    entrypoint = 'main',
)

py_gcf_deploy(
    name = "echo_deploy",
    src = ":echo",
    function_name = "echo",
    entrypoint = 'main',
    args = [
        '--allow-unauthenticated',
        '--region=us-central1',
        '--trigger-http',
    ],
)
