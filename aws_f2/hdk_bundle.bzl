"""Rule for producing an AWS HDK-compatible customer-logic source archive."""


def _hdk_cl_bundle_impl(ctx):
    output = ctx.actions.declare_file(ctx.label.name + ".tar")
    arguments = ctx.actions.args()
    arguments.add(output.path)

    inputs = []
    for destination, files in [
        ("design", ctx.files.design_srcs),
        ("design/rtl", ctx.files.rtl_srcs),
        ("build/scripts", ctx.files.build_scripts),
        ("build/constraints", ctx.files.constraints),
        ("", ctx.files.docs),
    ]:
        for source in files:
            inputs.append(source)
            arguments.add(destination + "/" + source.basename if destination else source.basename)
            arguments.add(source.path)

    ctx.actions.run(
        executable = ctx.executable._bundler,
        arguments = [arguments],
        inputs = inputs,
        outputs = [output],
        mnemonic = "JMachineF2Bundle",
        progress_message = "Packaging AWS F2 HDK customer logic %{label}",
    )
    return DefaultInfo(files = depset([output]))


hdk_cl_bundle = rule(
    implementation = _hdk_cl_bundle_impl,
    attrs = {
        "design_srcs": attr.label_list(allow_files = True),
        "rtl_srcs": attr.label_list(allow_files = True),
        "build_scripts": attr.label_list(allow_files = True),
        "constraints": attr.label_list(allow_files = True),
        "docs": attr.label_list(allow_files = True),
        "_bundler": attr.label(
            default = Label("//aws_f2/tools:build_hdk_bundle"),
            executable = True,
            cfg = "exec",
        ),
    },
)
