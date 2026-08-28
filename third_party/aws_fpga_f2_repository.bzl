"""Pinned repository rule for the official AWS FPGA F2 development kit."""

_AWS_FPGA_F2_COMMIT = "b603a81f65666e0cf7a67ee5cf18b148eb6b08c3"
_AWS_FPGA_F2_URL = "https://github.com/aws/aws-fpga/archive/%s.tar.gz" % _AWS_FPGA_F2_COMMIT
_AWS_FPGA_F2_SHA256 = "4fbdf95d3592334354cbaf0b739120efe57627d554d954d8eab210dc6323e619"


def _aws_fpga_f2_repository_impl(repository_ctx):
    repository_ctx.download_and_extract(
        url = _AWS_FPGA_F2_URL,
        sha256 = _AWS_FPGA_F2_SHA256,
        stripPrefix = "aws-fpga-%s" % _AWS_FPGA_F2_COMMIT,
    )
    repository_ctx.file("MODULE.bazel", "module(name = \"aws_fpga_f2\")\n")
    repository_ctx.file("BUILD.bazel", """
package(default_visibility = ["//visibility:public"])

licenses(["restricted"])

filegroup(
    name = "license",
    srcs = ["LICENSE.txt"],
)

filegroup(
    name = "documentation",
    srcs = [
        "User_Guide_AWS_EC2_FPGA_Development_Kit.md",
        "hdk/README.md",
        "hdk/docs/AWS_Shell_Interface_Specification.md",
        "hdk/docs/AWS_Fpga_Pcie_Memory_Map.md",
    ],
)

filegroup(
    name = "shell_interfaces",
    srcs = glob(["hdk/common/shell_stable/design/interfaces/**"]),
)

filegroup(
    name = "shell_build_support",
    srcs = glob([
        "hdk/common/shell_stable/build/**",
        "hdk/common/shell_stable/design/sh_ddr/**",
        "hdk/common/lib/**",
    ]),
)

filegroup(
    name = "hdk",
    srcs = glob(["hdk/**"]),
)
""")


aws_fpga_f2_repository = repository_rule(
    implementation = _aws_fpga_f2_repository_impl,
)


def _aws_fpga_f2_deps_impl(_module_ctx):
    aws_fpga_f2_repository(name = "aws_fpga_f2")


aws_fpga_f2_deps = module_extension(implementation = _aws_fpga_f2_deps_impl)
