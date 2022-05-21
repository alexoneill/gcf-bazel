load("@gcf-bazel//:rules.bzl", "py_gcf_local", "py_gcf_deploy")

# HTTP Trigger
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

# Pub/Sub Trigger
py_binary(
    name = "pubsub",
    srcs = ["pubsub.py"],
)

py_gcf_local(
    name = "pubsub_local",
    src = ":pubsub",
    entrypoint = 'main',
    is_pubsub = True,
)

py_gcf_deploy(
    name = "pubsub_deploy",
    src = ":pubsub",
    function_name = "pubsub",
    entrypoint = 'main',
    args = [
        '--region=us-central1',
        '--trigger-topic=my-topic',
    ],
)
