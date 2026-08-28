"""Compiler-generated image and execution regressions.

The table is the Bazel replacement for the former Makefile's image recipes and
serial c-test recipe. Each program becomes a cached image plus independent
golden-model and RTL tests.
"""

load("//tools:j_machine_rules.bzl", "image_argument_test", "image_runner_test", "jmc_image")

def _checks(peeks, expects):
    args = []
    for value in peeks:
        args.extend(["--peek", value])
    for value in expects:
        args.extend(["--expect", value])
    return args

def _program(
        name,
        events,
        cycles,
        peeks,
        expects,
        srcs = None,
        compiler_args = [],
        nodes = 1,
        golden_extra = [],
        rtl_extra = [],
        rtl_peeks = None,
        rtl_expects = None):
    return struct(
        name = name,
        srcs = srcs if srcs != None else ["examples/{}.c".format(name)],
        compiler_args = compiler_args,
        golden_args = (["--nodes", str(nodes)] if nodes != 1 else []) +
                      ["--events", str(events)] + golden_extra +
                      _checks(peeks, expects),
        rtl_args = ["--cycles", str(cycles)] + rtl_extra + _checks(
            rtl_peeks if rtl_peeks != None else peeks,
            rtl_expects if rtl_expects != None else expects,
        ),
    )

_PROGRAMS = [
    _program("factorial", 10000, 10000,
             ["0:300"], ["0:300:1000002d0"]),
    _program("control", 10000, 10000,
             ["0:300", "0:800"],
             ["0:300:100000028", "0:800:100000028"]),
    _program("conditional_updates", 500000, 500000,
             ["0:300", "0:800", "0:801", "0:802", "0:803", "0:804"],
             ["0:300:10000014b", "0:800:100000003", "0:801:100000001",
              "0:802:100000001", "0:803:1000000c0", "0:804:10000000d"]),
    _program("declarations_goto", 500000, 500000,
             ["0:300", "0:804", "0:805", "1:803"],
             ["0:300:100000091", "0:804:100000003", "0:805:100000006",
              "1:803:100000005"],
             compiler_args = ["--nodes", "2", "--broadcast-image"], nodes = 2),
    _program("block_declarations", 100000, 200000,
             ["0:300", "0:800"],
             ["0:300:100000086", "0:800:100000009"]),
    _program("nested_calls", 10000, 10000,
             ["0:300"], ["0:300:100000021"]),
    _program("operators", 10000, 20000,
             ["0:300"], ["0:300:10000003b"]),
    _program("remote_call", 50000, 100000,
             ["0:300", "1:800"],
             ["0:300:10000008e", "1:800:100000029"],
             compiler_args = ["--nodes", "2"], nodes = 2),
    _program("remote_function_pointer", 100000, 200000,
             ["0:300"], ["0:300:10000002b"],
             compiler_args = ["--nodes", "2"], nodes = 2),
    _program("remote_integer_types", 300000, 500000,
             ["0:300", "1:800", "1:801"],
             ["0:300:100000003", "1:800:1ffffffff", "1:801:100000001"],
             compiler_args = ["--nodes", "2"], nodes = 2),
    _program("remote_bulk", 100000, 150000,
             ["0:300", "1:800"],
             ["0:300:10000001d", "1:800:10000001c"],
             compiler_args = ["--nodes", "2", "--broadcast-image"], nodes = 2),
    _program("remote_bulk_limit", 200000, 300000,
             ["0:300", "0:70d", "1:70d", "1:bff"],
             ["0:300:0", "0:70d:100000001", "1:70d:100000000",
              "1:bff:100000000"],
             compiler_args = ["--nodes", "2", "--broadcast-image"], nodes = 2),
    _program("futures", 100000, 150000,
             ["0:300", "1:800"],
             ["0:300:100000020", "1:800:100000002"],
             compiler_args = ["--nodes", "2"], nodes = 2),
    _program("suspension", 200000, 300000,
             ["0:300", "0:800", "1:800", "0:708", "1:708"],
             ["0:300:100000029", "0:800:100000001", "1:800:100000001",
              "0:708:100000000", "1:708:100000001"],
             compiler_args = ["--nodes", "2"], nodes = 2),
    _program("division", 50000, 100000,
             ["0:300", "0:800", "0:801", "0:802"],
             ["0:300:10000002a", "0:800:1fffffffc", "0:801:100000004",
              "0:802:100000000"]),
    _program("integer_types", 1000000, 1000000,
             ["0:300"], ["0:300:10000ffff"]),
    _program("string_literals", 500000, 500000,
             ["0:300"], ["0:300:1000000ff"]),
    _program("wide_literals", 1000000, 1200000,
             ["0:300", "0:800", "0:801", "0:802", "0:80c", "0:80d",
              "0:80e", "0:80f", "0:810", "0:811", "0:812", "0:813",
              "0:818", "0:819", "0:81a", "0:81d", "0:81e", "0:81f",
              "0:820", "0:821", "0:822"],
             ["0:300:1000004c6", "0:800:100000041", "0:801:1000003a9",
              "0:802:10001f600", "0:80c:100000044", "0:80d:1000000ce",
              "0:80e:1000000a9", "0:80f:1000000f0", "0:810:10000009f",
              "0:811:100000098", "0:812:100000080", "0:813:100000000",
              "0:818:1000000ce", "0:819:1000000a9", "0:81a:100000000",
              "0:81d:1000003a9", "0:81e:10001f600", "0:81f:100000000",
              "0:820:1000000ce", "0:821:1000000a9", "0:822:100000000"],
             compiler_args = ["--nodes", "2"], nodes = 2),
    _program("remote_string_literals", 200000, 300000,
             ["0:300", "1:800"],
             ["0:300:1000000d5", "1:800:1000000d4"],
             compiler_args = ["--nodes", "2"], nodes = 2),
    _program("remote_aggregate", 3000000, 2000000,
             ["0:300", "0:800", "1:800", "0:708", "1:708"],
             ["0:300:10000007f", "0:800:100000049", "1:800:100000049",
              "0:708:100000000", "1:708:100000001"],
             compiler_args = ["--nodes", "2"], nodes = 2),
    _program("remote_bit_fields", 500000, 800000,
             ["0:300", "1:800", "1:801"],
             ["0:300:100000014", "1:800:10000078d", "1:801:10000000e"],
             compiler_args = ["--nodes", "2"], nodes = 2),
    _program("switch", 10000, 20000,
             ["0:300"], ["0:300:1000000d3"]),
    _program("pointers", 20000, 40000,
             ["0:300"], ["0:300:100000025"]),
    _program("pointer_arithmetic", 40000, 80000,
             ["0:300"], ["0:300:100000074"]),
    _program("aggregates", 250000, 300000,
             ["0:300"], ["0:300:100000188"]),
    _program("aggregate_by_value", 500000, 500000,
             ["0:300"], ["0:300:1000000d0"]),
    _program("compound_literals", 500000, 500000,
             ["0:300"], ["0:300:1000000a7"]),
    _program("designated_initializers", 1000000, 1000000,
             ["0:300"], ["0:300:100000409"]),
    _program("typedefs", 50000, 100000,
             ["0:300"], ["0:300:100000014"]),
    _program("function_pointers", 50000, 100000,
             ["0:300"], ["0:300:100000080"]),
    _program("qualifiers", 100000, 200000,
             ["0:300"], ["0:300:10000001f"]),
    _program("enums", 100000, 200000,
             ["0:300", "0:800"],
             ["0:300:100000014", "0:800:10000000d"]),
    _program("multi_file", 50000, 100000,
             ["0:300", "0:800"],
             ["0:300:10000001d", "0:800:100000009"],
             srcs = ["examples/multi_main.c", "examples/multi_library.c"],
             rtl_peeks = ["0:300"], rtl_expects = ["0:300:10000001d"]),
    _program("static_linkage", 100000, 200000,
             ["0:300"], ["0:300:1000000a2"],
             srcs = ["examples/static_main.c", "examples/static_library.c"]),
    _program("function_specifiers", 100000, 200000,
             ["0:300"], ["0:300:100000029"],
             srcs = ["examples/function_specifiers_main.c",
                     "examples/function_specifiers_external.c"]),
    _program("alignment", 100000, 200000,
             ["0:300", "0:800", "0:810"],
             ["0:300:10000044a", "0:800:100000005", "0:810:100000007"]),
    _program("atomics", 200000, 200000,
             ["0:300", "0:803", "0:804", "0:805", "0:806", "0:807",
              "0:80a", "0:80b", "0:80c", "0:80d", "0:80e"],
             ["0:300:1000002d5", "0:803:100000003", "0:804:1000000ff",
              "0:805:300200003", "0:806:100000025", "0:807:100000029",
              "0:80a:10000001d", "0:80b:10000001f", "0:80c:10000002b",
              "0:80d:10000002f", "0:80e:100000035"]),
    _program("stdatomic", 200000, 200000,
             ["0:300", "0:804", "0:805", "0:806", "0:807", "0:808", "0:809"],
             ["0:300:1000000a0", "0:804:10000000f", "0:805:100000001",
              "0:806:300200404", "0:807:100000008", "0:808:100000009",
              "0:809:100000001"]),
    _program("generic_selection", 100000, 200000,
             ["0:300", "0:800"],
             ["0:300:100000023", "0:800:100000000"]),
    _program("bit_fields", 400000, 500000,
             ["0:300", "0:800", "0:801", "0:803", "0:80a", "0:80d",
              "0:810", "0:811"],
             ["0:300:100000b2a", "0:800:1000090fe", "0:801:10000000f",
              "0:803:1000000fe", "0:80a:10000a0f3", "0:80d:10000b0fa",
              "0:810:100000001", "0:811:10000abca"]),
    _program("flexible_arrays", 200000, 300000,
             ["0:300", "0:800", "0:801", "0:802", "0:803", "0:804", "0:805"],
             ["0:300:100000030", "0:800:100000005", "0:801:100000003",
              "0:802:100000005", "0:803:100000007", "0:804:10000000b",
              "0:805:10000000d"]),
    _program("thread_local", 500000, 800000,
             ["0:300", "0:800", "0:801", "0:802", "1:800", "1:801", "1:802"],
             ["0:300:10000001e", "0:800:100000005", "0:801:100000006",
              "0:802:100000002", "1:800:100000008", "1:801:100000006",
              "1:802:100000002"],
             compiler_args = ["--nodes", "2"], nodes = 2),
    _program("reclamation", 1000000, 1000000,
             ["0:300", "1:800", "1:700", "1:702", "1:703"],
             ["0:300:100000302", "1:800:100000014", "1:700:100010600",
              "1:702:100010000", "1:703:100010200"],
             compiler_args = ["--nodes", "2"], nodes = 2),
    _program("code_cache", 500000, 1000000,
             ["0:300", "1:800", "0:705", "0:707", "1:704", "1:706",
              "1:30000", "1:307b8"],
             ["0:300:100000462", "1:800:100000002", "0:705:100000001",
              "0:707:100000002", "1:704:100000001", "1:706:100000002",
              "1:30000:c30180000", "1:307b8:c70040000"],
             compiler_args = ["--nodes", "2", "--distributed-code"], nodes = 2),
    _program("historical_factorial", 1000000, 1000000,
             ["0:300", "0:708", "1:708", "0:702", "1:702"],
             ["0:300:1000002d0", "0:708:100000002", "1:708:100000003",
              "0:702:100010000", "1:702:100010000"],
             compiler_args = ["--nodes", "2", "--distributed-code"], nodes = 2),
    _program("historical_hop", 1000000, 1000000,
             ["0:300", "0:800", "0:801", "0:802", "1:800", "1:801", "1:802"],
             ["0:300:100000000", "0:800:100000004", "0:801:100000000",
              "0:802:100000005", "1:800:100000004", "1:801:100000004",
              "1:802:100000000"],
             compiler_args = ["--nodes", "2", "--distributed-code"], nodes = 2),
    _program("historical_producer_one_way", 1000000, 500000,
             ["0:300", "1:800", "1:801", "1:802"],
             ["0:300:100000000", "1:800:100000028", "1:801:100000001",
              "1:802:100000460"],
             compiler_args = ["--nodes", "2", "--broadcast-image"], nodes = 2),
    _program("historical_producer_two_way", 1000000, 500000,
             ["0:300", "0:800", "0:801", "1:802", "1:803", "0:705",
              "0:707", "1:704", "1:706", "0:708", "0:702", "1:702", "1:703"],
             ["0:300:100000000", "0:800:100000002", "0:801:100000000",
              "1:802:100000010", "1:803:1000001c0", "0:705:100000001",
              "0:707:100000002", "1:704:100000001", "1:706:100000002",
              "0:708:10000000e", "0:702:100010000", "1:702:100010000",
              "1:703:100010200"],
             compiler_args = ["--nodes", "2", "--distributed-code"], nodes = 2),
]

_DIRICHLET_CHECKS = _checks(
    ["0:300", "0:800", "1:800", "2:800", "3:800", "0:802", "1:802",
     "2:802", "3:802", "0:803", "1:803", "2:803", "3:803", "0:80b",
     "0:80c", "0:80d", "0:80e", "0:80f"],
    ["0:300:100000000", "0:800:100000005", "1:800:100000005",
     "2:800:100000005", "3:800:100000005", "0:802:100000005",
     "1:802:100000005", "2:802:100000005", "3:802:100000005",
     "0:803:100000001", "1:803:100000001", "2:803:100000001",
     "3:803:100000001", "0:80b:100000000", "0:80c:100000005",
     "0:80d:100000004", "0:80e:100000014", "0:80f:100000014"],
)

_MESH512_CHECKS = _checks(
    ["0:300", "511:800", "0:701", "256:701", "511:701", "0:705", "0:707",
     "511:704", "511:706", "511:30000"],
    ["0:300:10000021b", "511:800:10000001c", "0:701:100000000",
     "256:701:100001000", "511:701:100001ce7", "0:705:100000001",
     "0:707:100000001", "511:704:100000001", "511:706:100000001",
     "511:30000:c30180000"],
)

_HISTORICAL512_CHECKS = _checks(
    ["0:300", "0:800", "0:801", "0:802", "256:800", "256:801", "511:800",
     "511:801", "511:802", "0:702", "511:702"],
    ["0:300:100000000", "0:800:100000004", "0:801:100000000",
     "0:802:100000005", "256:800:100000004", "256:801:100000400",
     "511:800:100000004", "511:801:1000007fc", "511:802:100000000",
     "0:702:100010000", "511:702:100010000"],
)

def define_program_targets(
        compiler = ":jmc",
        golden_runner = "//:mdp-golden",
        rtl_runner = "//sim:image_runner",
        sparse4_runner = "//sim:sparse4_image_runner",
        sparse512_runner = "//sim:sparse512_image_runner",
        send_fault_runner = "//sim:send_fault_runner"):
    images = []
    generated_tests = []
    golden_tests = []
    rtl_tests = []

    for program in _PROGRAMS:
        jmc_image(
            name = program.name,
            compiler = compiler,
            compiler_args = program.compiler_args,
            srcs = program.srcs,
        )
        images.append(":" + program.name)

        golden_name = program.name + "_golden_test"
        image_runner_test(
            name = golden_name,
            image = ":" + program.name,
            runner = golden_runner,
            runner_args = program.golden_args,
            size = "medium",
        )
        golden_tests.append(":" + golden_name)
        generated_tests.append(":" + golden_name)

        rtl_name = program.name + "_rtl_test"
        image_runner_test(
            name = rtl_name,
            image = ":" + program.name,
            runner = rtl_runner,
            runner_args = program.rtl_args,
            size = "medium",
        )
        rtl_tests.append(":" + rtl_name)
        generated_tests.append(":" + rtl_name)

    jmc_image(
        name = "historical_dirichlet",
        compiler = compiler,
        compiler_args = ["--nodes", "4", "--mesh", "4x1x1", "--broadcast-image"],
        srcs = ["examples/historical_dirichlet.c"],
    )
    images.append(":historical_dirichlet")
    image_runner_test(
        name = "historical_dirichlet_golden_test",
        image = ":historical_dirichlet",
        runner = golden_runner,
        runner_args = ["--nodes", "4", "--events", "1000000"] + _DIRICHLET_CHECKS,
        size = "large",
    )
    image_runner_test(
        name = "historical_dirichlet_rtl_test",
        image = ":historical_dirichlet",
        runner = sparse4_runner,
        runner_args = [
            "--cycles", "1000000",
            "--stop-when", "0:80d:100000004",
            "--stop-when", "0:80e:100000014",
            "--stop-when", "0:80f:100000014",
            "--stop-when", "0:300:100000000",
            "--status", "0", "--status", "1", "--status", "2", "--status", "3",
        ] + _DIRICHLET_CHECKS,
        size = "large",
    )
    generated_tests.extend([
        ":historical_dirichlet_golden_test",
        ":historical_dirichlet_rtl_test",
    ])
    golden_tests.append(":historical_dirichlet_golden_test")
    rtl_tests.append(":historical_dirichlet_rtl_test")

    jmc_image(
        name = "send_fault",
        compiler = compiler,
        compiler_args = ["--nodes", "2", "--broadcast-image"],
        srcs = ["examples/send_fault.c"],
    )
    images.append(":send_fault")
    image_argument_test(
        name = "send_fault_rtl_test",
        image = ":send_fault",
        runner = send_fault_runner,
        size = "medium",
    )
    generated_tests.append(":send_fault_rtl_test")
    rtl_tests.append(":send_fault_rtl_test")

    jmc_image(
        name = "mesh512",
        compiler = compiler,
        compiler_args = ["--nodes", "512", "--mesh", "8x8x8", "--distributed-code"],
        srcs = ["examples/mesh512.c"],
    )
    jmc_image(
        name = "historical_hop512",
        compiler = compiler,
        compiler_args = ["--nodes", "512", "--mesh", "8x8x8", "--broadcast-image"],
        srcs = ["examples/historical_hop.c"],
    )
    images.extend([":mesh512", ":historical_hop512"])

    image_runner_test(
        name = "mesh512_golden_test",
        image = ":mesh512",
        runner = golden_runner,
        runner_args = [
            "--nodes", "512", "--events", "60000000",
            "--status", "0", "--status", "511",
        ] + _MESH512_CHECKS,
        size = "enormous",
        tags = ["manual", "long"],
        timeout = "long",
    )
    image_runner_test(
        name = "mesh512_rtl_test",
        image = ":mesh512",
        runner = sparse512_runner,
        runner_args = [
            "--cycles", "300000", "--stop-when", "0:300:10000021b",
            "--status", "0", "--status", "256", "--status", "511",
        ] + _MESH512_CHECKS,
        size = "enormous",
        tags = ["manual", "long"],
        timeout = "long",
    )
    image_runner_test(
        name = "historical_hop512_golden_test",
        image = ":historical_hop512",
        runner = golden_runner,
        runner_args = [
            "--nodes", "512", "--events", "1800000000",
            "--status", "0", "--status", "256", "--status", "511",
        ] + _HISTORICAL512_CHECKS,
        size = "enormous",
        tags = ["manual", "long"],
        timeout = "eternal",
    )

    native.filegroup(name = "images", srcs = images)
    native.test_suite(name = "golden_image_tests", tests = golden_tests)
    native.test_suite(name = "rtl_image_tests", tests = rtl_tests)
    native.test_suite(name = "generated_tests", tests = generated_tests)
    native.test_suite(
        name = "long_tests",
        tests = [
            ":mesh512_golden_test",
            ":mesh512_rtl_test",
            ":historical_hop512_golden_test",
        ],
    )
