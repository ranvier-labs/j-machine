"""Pinned repository rule for Berkeley SoftFloat Release 3e."""

_SOFTFLOAT_URL = "https://www.jhauser.us/arithmetic/SoftFloat-3e.zip"
_SOFTFLOAT_SHA256 = "21130ce885d35c1fe73fc1e1bf2244178167e05c6747cad5f450cc991714c746"

def _softfloat_repository_impl(repository_ctx):
    repository_ctx.download_and_extract(
        url = _SOFTFLOAT_URL,
        sha256 = _SOFTFLOAT_SHA256,
        stripPrefix = "SoftFloat-3e",
    )
    repository_ctx.file("MODULE.bazel", "module(name = \"berkeley_softfloat\")\n")
    repository_ctx.file("BUILD.bazel", """
load("@rules_cc//cc:defs.bzl", "cc_library")

package(default_visibility = ["//visibility:public"])

licenses(["notice"])

filegroup(
    name = "license",
    srcs = ["COPYING.txt"],
)

cc_library(
    name = "softfloat",
    srcs = glob(
        ["source/*.c"],
        exclude = [
            "source/s_addCarryM.c",
            "source/s_addComplCarryM.c",
            "source/s_addExtF80M.c",
            "source/s_addF128M.c",
            "source/s_addM.c",
            "source/s_compare128M.c",
            "source/s_compare96M.c",
            "source/s_compareNonnormExtF80M.c",
            "source/s_invalidExtF80M.c",
            "source/s_invalidF128M.c",
            "source/s_isNaNF128M.c",
            "source/s_mul128MTo256M.c",
            "source/s_mul64To128M.c",
            "source/s_mulAddF128M.c",
            "source/s_negXM.c",
            "source/s_normExtF80SigM.c",
            "source/s_normRoundPackMToExtF80M.c",
            "source/s_normRoundPackMToF128M.c",
            "source/s_normSubnormalF128SigM.c",
            "source/s_remStepMBy32.c",
            "source/s_roundMToI64.c",
            "source/s_roundMToUI64.c",
            "source/s_roundPackMToExtF80M.c",
            "source/s_roundPackMToF128M.c",
            "source/s_shiftLeftM.c",
            "source/s_shiftNormSigF128M.c",
            "source/s_shiftRightJamM.c",
            "source/s_shiftRightM.c",
            "source/s_shortShiftLeft64To96M.c",
            "source/s_shortShiftLeftM.c",
            "source/s_shortShiftRightExtendM.c",
            "source/s_shortShiftRightJamM.c",
            "source/s_shortShiftRightM.c",
            "source/s_sub1XM.c",
            "source/s_subM.c",
            "source/s_tryPropagateNaNExtF80M.c",
            "source/s_tryPropagateNaNF128M.c",
        ],
    ) + select({
        "@platforms//cpu:arm64": glob(["source/ARM-VFPv2/*.c"]),
        "//conditions:default": glob(["source/8086-SSE/*.c"]),
    }),
    hdrs = glob(["source/include/*.h"]) + select({
        "@platforms//cpu:arm64": glob([
            "source/ARM-VFPv2/*.h",
            "build/Linux-ARM-VFPv2-GCC/*.h",
        ]),
        "//conditions:default": glob([
            "source/8086-SSE/*.h",
            "build/Linux-x86_64-GCC/*.h",
        ]),
    }),
    includes = ["source/include"] + select({
        "@platforms//cpu:arm64": [
            "source/ARM-VFPv2",
            "build/Linux-ARM-VFPv2-GCC",
        ],
        "//conditions:default": [
            "source/8086-SSE",
            "build/Linux-x86_64-GCC",
        ],
    }),
    defines = [
        "SOFTFLOAT_FAST_INT64",
        "SOFTFLOAT_ROUND_ODD",
        "INLINE_LEVEL=5",
        "SOFTFLOAT_FAST_DIV32TO16",
        "SOFTFLOAT_FAST_DIV64TO32",
    ],
    copts = [
        "-O2",
        "-Wno-implicit-function-declaration",
    ],
)
""")

softfloat_repository = repository_rule(
    implementation = _softfloat_repository_impl,
)

def _softfloat_deps_impl(_module_ctx):
    softfloat_repository(name = "berkeley_softfloat")

softfloat_deps = module_extension(implementation = _softfloat_deps_impl)
