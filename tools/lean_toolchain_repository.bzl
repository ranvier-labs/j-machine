"""Pinned prebuilt Lean toolchain for the Bazel-owned compiler build."""

_LEAN_VERSION = "4.33.1"

_RELEASES = {
    "darwin_aarch64": (
        "lean-4.33.1-darwin_aarch64",
        "88c45aad985b5d2a8d925fe10bd1296bd35f66f408480ab182d3facccd065a9d",
    ),
    "darwin_x86_64": (
        "lean-4.33.1-darwin",
        "93c475c1600360df35471bf6ed1c7fe118d7fb42be6915ead67724f7ad58dfaf",
    ),
    "linux_aarch64": (
        "lean-4.33.1-linux_aarch64",
        "f7353a8b2a8741c84558523e450556f9a1c45e3cafcf54399ce68c6a24c55f07",
    ),
    "linux_x86_64": (
        "lean-4.33.1-linux",
        "890afd185370f85666025b883914ab4f4b339136f8c96167b69cfb62aecaf235",
    ),
}

def _platform(repository_ctx):
    os_name = repository_ctx.os.name.lower()
    if "mac" in os_name or "darwin" in os_name:
        os_id = "darwin"
    elif "linux" in os_name:
        os_id = "linux"
    else:
        fail("Lean {} is not packaged for host OS '{}'".format(_LEAN_VERSION, os_name))

    machine = repository_ctx.execute(["uname", "-m"], quiet = True)
    if machine.return_code:
        fail("could not identify the host architecture: {}".format(machine.stderr))
    arch = machine.stdout.strip()
    if arch in ["arm64", "aarch64"]:
        arch_id = "aarch64"
    elif arch == "x86_64":
        arch_id = "x86_64"
    else:
        fail("Lean {} is not packaged for host architecture '{}'".format(_LEAN_VERSION, arch))
    return "{}_{}".format(os_id, arch_id)

def _lean_toolchain_repository_impl(repository_ctx):
    platform = _platform(repository_ctx)
    if platform not in _RELEASES:
        fail("no Lean {} toolchain for {}".format(_LEAN_VERSION, platform))
    archive, sha256 = _RELEASES[platform]
    repository_ctx.download_and_extract(
        url = "https://github.com/leanprover/lean4/releases/download/v{}/{}.tar.zst".format(
            _LEAN_VERSION,
            archive,
        ),
        sha256 = sha256,
        stripPrefix = archive,
    )
    repository_ctx.file("BUILD.bazel", """
package(default_visibility = ["//visibility:public"])

exports_files(["bin/lake"])

filegroup(
    name = "toolchain",
    srcs = glob(["**"], exclude = ["BUILD.bazel"]),
)
""")

lean_toolchain_repository = repository_rule(
    implementation = _lean_toolchain_repository_impl,
    local = False,
)
