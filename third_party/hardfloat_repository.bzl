"""Pinned repository rule for Berkeley HardFloat Release 1."""

_HARDFLOAT_URL = "https://www.jhauser.us/arithmetic/HardFloat-1.zip"
_HARDFLOAT_SHA256 = "6b3757c9fbfa2230c6a2b84605e39372cb589dd7500e979c4f0b8ecc8a03b14b"

_VERILOG_SOURCES = [
    "HardFloat_primitives.v",
    "HardFloat_rawFN.v",
    "isSigNaNRecFN.v",
    "fNToRecFN.v",
    "recFNToFN.v",
    "iNToRecFN.v",
    "recFNToIN.v",
    "recFNToRecFN.v",
    "addRecFN.v",
    "mulRecFN.v",
    "mulAddRecFN.v",
    "divSqrtRecFN_small.v",
    "compareRecFN.v",
]

_INCLUDE_FILES = [
    "HardFloat_consts.vi",
    "HardFloat_localFuncs.vi",
    "RISCV/HardFloat_specialize.vi",
]

def _hardfloat_repository_impl(repository_ctx):
    repository_ctx.download_and_extract(
        url = _HARDFLOAT_URL,
        sha256 = _HARDFLOAT_SHA256,
        stripPrefix = "HardFloat-1",
    )

    # Release 1 calls Verilog include files `.vi`.  The foundational Bazel
    # Verilog provider intentionally recognizes `.vh`; materialize that purely
    # mechanical spelling change inside the external repository and update the
    # include directives.  The checked upstream archive and license stay intact.
    for source in _VERILOG_SOURCES:
        path = "source/" + source
        contents = repository_ctx.read(path).replace(".vi\"", ".vh\"")
        # Verilator 5.046 correctly applies SystemVerilog's stricter ANSI-port
        # redeclaration rule even to mixed-language designs.  Release 1 repeats
        # sqrtOpOut as a wire after declaring it as an output; deleting that
        # redundant declaration is the upstream-compatible fix already used by
        # the project's reference HardFloat checkout.
        if source == "divSqrtRecFN_small.v":
            contents = contents.replace("    wire sqrtOpOut;\r\n", "")
            contents = contents.replace("    wire sqrtOpOut;\n", "")
        repository_ctx.file(
            path,
            contents,
        )
    for include in _INCLUDE_FILES:
        source_path = "source/" + include
        target_path = source_path[:-3] + ".vh"
        repository_ctx.file(target_path, repository_ctx.read(source_path))

    repository_ctx.file("MODULE.bazel", "module(name = \"berkeley_hardfloat\")\n")
    repository_ctx.file("BUILD.bazel", """
load("@rules_verilog//verilog:defs.bzl", "verilog_library")

package(default_visibility = ["//visibility:public"])

licenses(["notice"])

filegroup(
    name = "license",
    srcs = ["COPYING.txt"],
)

verilog_library(
    name = "hardfloat",
    srcs = [
        "source/HardFloat_primitives.v",
        "source/HardFloat_rawFN.v",
        "source/isSigNaNRecFN.v",
        "source/RISCV/HardFloat_specialize.v",
        "source/fNToRecFN.v",
        "source/recFNToFN.v",
        "source/iNToRecFN.v",
        "source/recFNToIN.v",
        "source/recFNToRecFN.v",
        "source/addRecFN.v",
        "source/mulRecFN.v",
        "source/mulAddRecFN.v",
        "source/divSqrtRecFN_small.v",
        "source/compareRecFN.v",
    ],
    hdrs = [
        "source/HardFloat_consts.vh",
        "source/HardFloat_localFuncs.vh",
        "source/RISCV/HardFloat_specialize.vh",
    ],
)
""")

hardfloat_repository = repository_rule(
    implementation = _hardfloat_repository_impl,
)

def _hardfloat_deps_impl(_module_ctx):
    hardfloat_repository(name = "berkeley_hardfloat")

hardfloat_deps = module_extension(implementation = _hardfloat_deps_impl)
