load("@gcf-bazel//:rules.bzl", "py_gcp_run_deploy")

py_binary(
    name = "hello",
    srcs = ["hello.py"],
)

py_gcp_run_deploy(
    name = "hello_deploy",
    src = ":hello",
    run_name = "hello-world",
    environment = "env.yaml",
    requirements = "requirements.txt",
    dockerfile = "Dockerfile",
    args = [
        '--region=us-central1',
        '--allow-unauthenticated',
    ],
)
