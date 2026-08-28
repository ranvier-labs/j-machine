"""Project rules for the Bazel-only J-Machine build and regression graph."""

LakePackageInfo = provider(fields = ["executables"])
JmcImageInfo = provider(fields = ["image", "listing"])

def _lake_package_impl(ctx):
    outputs = []
    executables = {}
    for target in ctx.attr.targets:
        output = ctx.actions.declare_file(ctx.label.name + "/" + target)
        outputs.append(output)
        executables[target] = output

    args = ctx.actions.args()
    args.add(ctx.executable._lake)
    args.add(ctx.label.package)
    args.add(len(ctx.attr.targets))
    for index, target in enumerate(ctx.attr.targets):
        args.add(target)
        args.add(outputs[index])
    args.add_all(ctx.files.srcs)

    ctx.actions.run(
        executable = ctx.executable._builder,
        arguments = [args],
        inputs = depset(ctx.files.srcs + ctx.files._lean_toolchain),
        tools = [ctx.executable._builder, ctx.executable._lake],
        outputs = outputs,
        mnemonic = "LakeBuild",
        progress_message = "Building Lean package {}".format(ctx.label),
    )
    return [
        DefaultInfo(files = depset(outputs)),
        LakePackageInfo(executables = executables),
    ]

lake_package = rule(
    implementation = _lake_package_impl,
    attrs = {
        "srcs": attr.label_list(allow_files = True, mandatory = True),
        "targets": attr.string_list(mandatory = True),
        "_builder": attr.label(
            default = "//tools:build_lake_package.sh",
            allow_single_file = True,
            executable = True,
            cfg = "exec",
        ),
        "_lake": attr.label(
            default = "@lean_toolchain//:bin/lake",
            allow_single_file = True,
            executable = True,
            cfg = "exec",
        ),
        "_lean_toolchain": attr.label(
            default = "@lean_toolchain//:toolchain",
            allow_files = True,
            cfg = "exec",
        ),
    },
)

def _lake_executable_impl(ctx):
    package = ctx.attr.package[LakePackageInfo]
    binary = ctx.attr.binary if ctx.attr.binary else ctx.label.name
    if binary not in package.executables:
        fail("{} does not provide Lake target '{}'".format(ctx.attr.package.label, binary))
    output = ctx.actions.declare_file(ctx.label.name)
    ctx.actions.symlink(
        output = output,
        target_file = package.executables[binary],
        is_executable = True,
    )
    runfiles = ctx.runfiles(files = [package.executables[binary]] + ctx.files.data)
    for data in ctx.attr.data:
        runfiles = runfiles.merge(data[DefaultInfo].default_runfiles)
    return [DefaultInfo(
        executable = output,
        files = depset([output]),
        runfiles = runfiles,
    )]

_lake_executable = rule(
    implementation = _lake_executable_impl,
    executable = True,
    attrs = {
        "binary": attr.string(),
        "data": attr.label_list(allow_files = True),
        "package": attr.label(
            mandatory = True,
            cfg = "exec",
            providers = [LakePackageInfo],
        ),
    },
)

_lake_test = rule(
    implementation = _lake_executable_impl,
    test = True,
    attrs = {
        "binary": attr.string(),
        "data": attr.label_list(allow_files = True),
        "package": attr.label(
            mandatory = True,
            cfg = "exec",
            providers = [LakePackageInfo],
        ),
    },
)

def lake_executable(name, package, binary = "", test = False, **kwargs):
    implementation = _lake_test if test else _lake_executable
    implementation(
        name = name,
        package = package,
        binary = binary,
        **kwargs
    )

def _jmc_image_impl(ctx):
    image = ctx.actions.declare_file(ctx.label.name + ".image")
    listing = ctx.actions.declare_file(ctx.label.name + ".lst")
    args = ctx.actions.args()
    args.add_all(ctx.files.srcs)
    args.add("-o")
    args.add(image)
    args.add("--listing")
    args.add(listing)
    args.add_all(ctx.attr.compiler_args)
    ctx.actions.run(
        executable = ctx.executable.compiler,
        arguments = [args],
        inputs = ctx.files.srcs,
        tools = [ctx.executable.compiler],
        outputs = [image, listing],
        mnemonic = "JmcImage",
        progress_message = "Compiling J-Machine image {}".format(ctx.label),
    )
    return [
        DefaultInfo(files = depset([image, listing])),
        JmcImageInfo(image = image, listing = listing),
    ]

jmc_image = rule(
    implementation = _jmc_image_impl,
    attrs = {
        "compiler": attr.label(mandatory = True, executable = True, cfg = "exec"),
        "compiler_args": attr.string_list(),
        "srcs": attr.label_list(allow_files = [".c"], mandatory = True),
    },
)

def _image_runner_test_impl(ctx):
    image = ctx.attr.image[JmcImageInfo].image
    runner = ctx.executable.runner
    script = ctx.actions.declare_file(ctx.label.name + ".sh")
    lines = [
        "#!/usr/bin/env bash",
        "set -euo pipefail",
        "runfiles_root=\"${TEST_SRCDIR:?}/${TEST_WORKSPACE:?}\"",
        "runner=\"$runfiles_root/{}\"".format(runner.short_path),
        "image=\"$runfiles_root/{}\"".format(image.short_path),
        "exec \"$runner\" --image \"$image\" {}".format(
            " ".join(["'{}'".format(arg.replace("'", "'\\''")) for arg in ctx.attr.runner_args]),
        ),
    ]
    ctx.actions.write(script, "\n".join(lines) + "\n", is_executable = True)
    runfiles = ctx.runfiles(files = [runner, image])
    runfiles = runfiles.merge(ctx.attr.runner[DefaultInfo].default_runfiles)
    runfiles = runfiles.merge(ctx.attr.image[DefaultInfo].default_runfiles)
    return [DefaultInfo(
        executable = script,
        runfiles = runfiles,
    )]

image_runner_test = rule(
    implementation = _image_runner_test_impl,
    test = True,
    attrs = {
        "runner_args": attr.string_list(),
        "image": attr.label(mandatory = True, providers = [JmcImageInfo]),
        "runner": attr.label(mandatory = True, executable = True, cfg = "target"),
    },
)

def _image_argument_test_impl(ctx):
    image = ctx.attr.image[JmcImageInfo].image
    runner = ctx.executable.runner
    script = ctx.actions.declare_file(ctx.label.name + ".sh")
    lines = [
        "#!/usr/bin/env bash",
        "set -euo pipefail",
        "runfiles_root=\"${TEST_SRCDIR:?}/${TEST_WORKSPACE:?}\"",
        "runner=\"$runfiles_root/{}\"".format(runner.short_path),
        "image=\"$runfiles_root/{}\"".format(image.short_path),
        "exec \"$runner\" \"$image\" {}".format(
            " ".join(["'{}'".format(arg.replace("'", "'\\''")) for arg in ctx.attr.runner_args]),
        ),
    ]
    ctx.actions.write(script, "\n".join(lines) + "\n", is_executable = True)
    runfiles = ctx.runfiles(files = [runner, image])
    runfiles = runfiles.merge(ctx.attr.runner[DefaultInfo].default_runfiles)
    runfiles = runfiles.merge(ctx.attr.image[DefaultInfo].default_runfiles)
    return [DefaultInfo(
        executable = script,
        runfiles = runfiles,
    )]

image_argument_test = rule(
    implementation = _image_argument_test_impl,
    test = True,
    attrs = {
        "runner_args": attr.string_list(),
        "image": attr.label(mandatory = True, providers = [JmcImageInfo]),
        "runner": attr.label(mandatory = True, executable = True, cfg = "target"),
    },
)
