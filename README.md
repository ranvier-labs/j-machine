# J-Machine / MDP SystemVerilog model

This directory contains a clean-room SystemVerilog implementation of the
J-Machine's Message-Driven Processor (MDP) and network. The architectural
contract is MDP Architecture Version 11 from MIT AI Memo 1069. Instruction
fields, opcodes, word tags, register modes, contexts, faults, address
translation, queue behavior, and message operations use the published Version
11 encodings.

The first executable target is a Verilator software simulation. The reusable
RTL is kept independent of that target:

```text
j_machine/
  rtl/                 target-independent processor, queues, and mesh
  golden/              independent instruction-accurate C++ oracle and CLI
  compiler/            Lean 4 C-subset compiler and runnable examples
  aws_f2/              AWS EC2 F2 Small Shell target and HDK bundle
  sim/                 Verilator memory model, top, and C++ conformance test
  historical/          provenance for surviving original software evidence
  docs/CONFORMANCE.md  implemented and verified architectural contracts
  j_machine.f          ordered target-independent RTL source list
```

The boundary in `j_machine_mesh` has separate processor word transactions and
four-word queue-row writes. Network links expose the two priority virtual
networks as ready/valid 18-bit flow-control digits. FPGA targets can bind the
transaction interfaces to BRAM/DRAM controllers and the network interfaces to
a 9-bit physical-channel serializer. These bindings sit outside the MDP core,
queue machinery, and routers.

## Implemented architecture

- 36-bit tagged words and the sixteen published tag values;
- two packed 17-bit instructions per instruction word, high instruction first;
- all published Version 11 opcodes, normal operands, register-mode
  operands, checked/unchecked operation, and tagged fault selection;
- background, priority-0, and priority-1 register contexts with message
  preemption and `SUSPEND` restoration;
- the 20-bit physical address space, priority-switched low 64 words, fault and
  call vectors, ROM protection, base/limit addressing, and queue-relative A3;
- the two-way associative translation-table row layout used by `ENTER`,
  `XLATE`, `INVAL`, and `PROBE`;
- independent priority queues, four-word queue row buffers, circular allocation,
  `EARLY`/`QUEUE` conditions, and dispatch after the first committed row;
- `SEND`, `SENDE`, `SEND2`, and `SEND2E`, an eight-word output FIFO, X-Y-Z
  routing headers, header removal, message locks, priority-1 preemption, and
  tail-delimited delivery; and
- a parameterized three-dimensional mesh with one MDP node per router.

## Run

A host C++20 toolchain and Bazel 9 are required. Bazel resolves the pinned
Lean, Verilator, HardFloat, SoftFloat, and AWS shell inputs used by each target.

```sh
bazel test //:tests
bazel build //compiler:images
bazel build --config=rtl-lint //sim:j_machine_verilator_rtl
bazel test //compiler:historical_dirichlet_rtl_test
bazel test //compiler:send_fault_rtl_test
bazel test //:long_tests
bazel test //rtl/fpu:j_fpu_hardfloat_test
bazel test //rtl/fpu:j_fpu_mmio_hardfloat_test
bazel build //aws_f2:hdk
bazel build //aws_f2:cl_bundle
bazel test //aws_f2:tests
```

The build is Bazel-only. Bazel 9.2.0, Lean 4.33.1, rules_verilator 1.1.2,
Verilator 5.046, HardFloat Release 1, and SoftFloat 3e are pinned. The main test
suite runs the compiler unit tests, all generated-image golden and RTL tests,
the full two-node RTL conformance suite, floating-point differential tests, and
the F2 adapter tests. The explicit long suite adds the 512-node workloads.

## IEEE floating point

Floating point uses a target-neutral ready/valid service and retains the
published Version 11 opcode and tag maps. The service implements binary32 and
binary64 add/subtract/multiply/FMA/divide/square-root, quiet comparison,
integer conversions, precision conversion, all HardFloat rounding modes, and
all five IEEE exception flags. The RTL backend is Berkeley HardFloat; the
independent randomized oracle is Berkeley SoftFloat.

The service has a tagged-word MMIO adapter at a target-selected address. This
supports per-node, per-tile shared, and dedicated-service-node FPGA placements
with the same semantics. A 512-node build can share the service among tiles or
nodes, reducing the number of binary64 dividers. See
[`docs/FLOATING_POINT.md`](docs/FLOATING_POINT.md) for the request,
response, register, and 512-node topology contracts.

`bazel build //:mdp-golden` builds a standalone instruction-accurate C++
simulator. `bazel test //:tests` first runs its warning-clean unit suite, then builds a cycle-stepped C++
harness around a `2 x 1 x 1` RTL machine. The same encoded ROM words are loaded
into the independent golden and RTL implementations, which run on their own
time bases and are compared at architectural checkpoints. The regression checks:

- Version 11 instruction/word encoding and checked integer execution;
- a 6,656-case golden/RTL matrix covering all 26 pure ALU/tag opcodes over
  every pair of the 16 architectural tags, with bit-for-bit result and fault
  comparison;
- a checked tag mismatch dispatching through the TYPE fault vector;
- both ways of the `ENTER` table, `XLATE` and `PROBE` hit/miss results, and
  foreground-only `INVAL` address invalidation;
- direct `LDIP`, register-mode `LDIPR`, CALL-vector dispatch/FIP return, and
  taken and fall-through outcomes for every conditional branch;
- external INTERRUPT vectoring and saved FIP after software unmasking;
- asynchronous QUEUE vectoring with the expected pre-fetch FIP when a four-word
  active priority queue becomes full with interrupts enabled;
- injected external-memory DRAMERR vectoring with saved MAR/FIP;
- a priority-1 message routed from node 0 to node 1;
- queue row commit, dispatch, A3 argument access, circular queue accounting,
and `SUSPEND`; and
- node-number initialization and catastrophe-state checks.

## Lean 4 compiler

`compiler/` contains `jmc`, a clean-room Lean 4 compiler from a documented
C11 subset, extended with Message-Driven C (MDC) remote calls, to MDP Version 11
tagged-word images. The C++ golden model and the Verilated RTL load the same
image.

### At a glance

```c
// compiler/examples/remote_call.c
int observed = 0;

void record(int value) { observed = value + computer(); }
int remote_add(int l, int r) { return l + r + computer() * 100; }

int main(void) {
  record(40)@1;                  // one-way message to node 1
  return remote_add(20, 22)@1;   // remote call; result is a future
}
```

```sh
bazel run //compiler:jmc -- compiler/examples/remote_call.c --nodes 2 \
  -o /tmp/remote_call.image
bazel run //:mdp-golden -- --image /tmp/remote_call.image --nodes 2 --events 50000 \
  --expect 0:300:10000008e --expect 1:800:100000029
```

Node 0 returns `INT(142)`. Node 1's `observed` is `INT(41)`.

### Pipeline

| Stage    | What it does                                                           |
| -------- | ---------------------------------------------------------------------- |
| Parse    | Lexes and parses one or more translation units, with source-positioned diagnostics |
| Check    | Validates types, declarations, storage classes, control flow, and linkage |
| Lower    | Maps C to the MDP stack-frame ABI, native memory transactions, faults, messages, and `CALL` vectors |
| Link     | Resolves branches, object addresses, function pointers, and external or internal symbols into one image |

Protected bootstrap and runtime code is linked at `0x1000`. Application code
and its `CALL`-vector targets start at the code-cache base `0x30000`.
Unsupported constructs produce diagnostics rather than silently compiling.

### Language surface

| Area              | Supported                                                         |
| ----------------- | ----------------------------------------------------------------- |
| Types             | signed/unsigned word scalars, `_Bool`, enums, structs, unions, bounded pointers, multidimensional arrays, function pointers, scoped typedefs |
| Qualifiers        | recursive `const` / `volatile` / `restrict`                       |
| Expressions       | C integer promotions, pointer arithmetic and casts, `?:`, short-circuit, single-evaluation updates |
| Control flow      | all loops, nested `switch` labels, `goto`                         |
| Initialization    | recursive and designated initializers, compound literals, tentative definitions, block statics |
| Linkage           | multiple translation units, external and internal linkage         |
| Layout            | word-addressed aggregates, by-value aggregate params/results, LSB-first bit-fields, flexible array members, `_Alignas` through 64 words |
| C11               | `_Atomic`, `<stdatomic.h>`, `_Generic`, `_Thread_local`, `_Static_assert`, `inline`, `_Noreturn` |
| Literals          | integer suffixes, character constants, `u8` / `L` / `u` / `U` strings |
| MDC               | `f(...)@node` remote calls (direct and indirect), futures, bulk and aggregate arguments |

Runtime mapping notes:

- **Atomics:** sequentially consistent RMW and multiword aggregate operations
  mask message dispatch around their critical sequence.
- **Threads:** `_Thread_local` maps one C abstract thread to each physical node.
  Remote activations see the destination node's thread-local state.
- **Memory reclamation:** node-local free lists recycle 512-word process blocks
  and 1024-word bulk-payload blocks.

### Tests

`bazel test //compiler:generated_tests` compiles every program in
[`compiler/examples/`](compiler/examples). It runs each image in both the
golden model and the RTL and checks exact tagged-word results.

| Target                                     | Mesh        | What it checks                                                       |
| ------------------------------------------ | ----------- | -------------------------------------------------------------------- |
| `//compiler:generated_tests`               | 1-2 nodes   | Language features, linkage, remote calls, suspension, reclamation, bounded failures |
| `//compiler:historical_dirichlet_rtl_test` | 4 x 1 x 1   | Maskit Figs. 5.3-5.5: neighbor exchange, five global-norm barriers, termination |
| `//compiler:send_fault_rtl_test`           | 1 node      | SEND-buffer fault taken twice, backpressure released, resumes with `INT(77)` |
| `//compiler:mesh512_golden_test`           | 8 x 8 x 8   | Array transfer from node 0 to node 511 and remote code fetch (sparse golden model) |
| `//compiler:mesh512_rtl_test`              | 8 x 8 x 8   | Same image on all 512 MDP/router instances; done at 66,496 cycles     |
| `//compiler:historical_hop512_golden_test` | 8 x 8 x 8   | Hop: four tours, 2,048 remote invocations, process-block reclamation |

The 512-node targets belong to `//:long_tests`, not the fast suite.

Historical adaptations (factorial, Hop, one- and two-way producers, Dirichlet)
are attributed to Maskit. The factorial case takes five `FUT` faults, wakes the
frames in reverse order, and returns `720`.

<details>
<summary>512-node image and topology details</summary>

- Common bootstrap, runtime, and data rows are broadcast. Node state uses
  explicit rows, and application rows initially target node 0 only. Simulator
  and FPGA loaders share this contract.
- Source ranks are dense `0..511`. NNR and routing words use
  `x | (y << 5) | (z << 10)`, so ranks 0, 256, and 511 map to `0x0000`,
  `0x1000`, and `0x1ce7`.
- More than 32 nodes requires an explicit `--mesh XxYxZ` topology.
- `bazel build --config=rtl-lint //sim:j_machine_sparse512_rtl` elaborates the
  full `8 x 8 x 8` RTL.

</details>

[`compiler/README.md`](compiler/README.md) is the full reference. It covers
the accepted grammar, ABI, image format, CLI flags, and what is unsupported.

## Source hierarchy

| File | Role |
| --- | --- |
| `rtl/j_machine_pkg.sv` | Exact tags, opcode/fault numbers, encoders, and link types |
| `rtl/j_mdp_core.sv` | Instruction engine, contexts, register file, faults, and translation table |
| `rtl/mdp_message_unit.sv` | QBM/QHL queues and four-word queue-row-buffer commits |
| `rtl/mdp_network_output.sv` | Message assembly, eight-word FIFO, headers, and flit emission |
| `rtl/j_machine_mesh_512.sv` | Concrete 512-node, 8 x 8 x 8 FPGA-facing mesh configuration |
| `rtl/fpu/j_fpu_hardfloat.sv` | Complete binary32/binary64 HardFloat service backend |
| `rtl/fpu/j_fpu_mmio.sv` | Target-neutral tagged-word MMIO/service adapter |
| `aws_f2/design/cl_j_machine.sv` | AWS F2 Small Shell top using OCL control and PCIM memory |
| `aws_f2/design/j_machine_f2_pcim_memory.sv` | Lossless 512-node to 4 GiB PCIM memory binding |
| `rtl/mdp_network_input.sv` | Flit-pair reassembly and receive backpressure |
| `rtl/j_mesh_router.sv` | Dimension routing, header stripping, locks, and two priorities |
| `rtl/j_node.sv` | MDP/message/network integration and target interfaces |
| `rtl/j_machine_mesh.sv` | Parameterized 3-D system interconnect |
| `golden/mdp_golden.hpp` | Public golden-model encoding, state, trace, and control API |
| `golden/mdp_golden.cpp` | Independent instruction-accurate MDP and multicomputer model |
| `golden/mdp_golden_cli.cpp` | Text-image loader, event runner, trace, and state CLI |
| `golden/golden_test.cpp` | Standalone golden-model unit vectors |
| `compiler/JMachineC/Codegen.lean` | Lean lowering, ABI, relocation, and image generation |
| `compiler/Main.lean` | `jmc` compiler command-line entry point |
| `compiler/Test.lean` | Compiler-front-end and code-generation tests |
| `sim/mdp_memory_sim.sv` | Full 1M-word Verilator memory and queue-row port |
| `sim/j_machine_verilator_top.sv` | Two-node executable target with explicit interrupt and DRAM-error injection ports |
| `sim/mdp_sparse_memory_dpi.sv` | Sparse-memory adapter with the same processor/QRB timing contract |
| `sim/j_machine_verilator_sparse_top.sv` | Parameterized hierarchical Verilator mesh target |
| `sim/verilator.f` | Ordered SystemVerilog file list for target-level semantic tools |
| `sim/main.cpp` | ROM loader and self-checking architectural test |
| `sim/image_runner.cpp` | Generic image loader and self-checking Verilator runner |
| `sim/sparse_image_runner.cpp` | Compile-time-sized broadcast/override sparse loader and self-checking runner (4- and 512-node targets) |
| `sim/j_node_backpressure_top.sv` | Standalone node target with controllable egress backpressure |
| `sim/send_fault_runner.cpp` | Re-entrant architectural SEND-fault oracle |

## Normative references

The instruction-level contract comes from [Message-Driven Processor
Architecture Version 11, MIT AI Memo 1069](https://www.bitsavers.org/pdf/mit/ai/aim/AIM-1069.pdf).
The associative translation organization follows [Architecture of a
Message-Driven Processor](https://people.eecs.berkeley.edu/~kubitron/courses/cs258-S02/handouts/papers/dally-architecture.pdf).
The routed-link mechanisms follow [The J-Machine
Network](https://www.researchgate.net/publication/3514621_The_J-machine_network),
DOI 10.1109/ICCD.1992.276305. The system-level cross-check is [The J-Machine
Multicomputer: An Architectural Evaluation](https://people.eecs.berkeley.edu/~kubitron/courses/cs258-S08/handouts/papers/p224-noakes.pdf).

See [docs/CONFORMANCE.md](docs/CONFORMANCE.md) for the implemented, tested, and
target-adapter boundaries. It also lists each unverified behavior explicitly.

## License

Copyright 2026 Ranvier Labs.

Except for the historical examples listed below, this repository is licensed
under the [Apache License 2.0](LICENSE):

- `compiler/examples/historical_factorial.c`, adapted from Maskit Figure 2.1;
- `compiler/examples/historical_hop.c`, adapted from Maskit Figure 3.3;
- `compiler/examples/historical_producer_one_way.c`, adapted from Maskit Figure
  5.1;
- `compiler/examples/historical_producer_two_way.c`, adapted from Maskit Figure
  5.2; and
- `compiler/examples/historical_dirichlet.c`, based on Maskit Figures 5.3-5.5.

Each file identifies its source as Daniel Maskit, *A Message-Driven Programming
System for Fine-Grain Multicomputers*, Caltech master's thesis, 1994, DOI
[`10.7907/Z9J38QKJ`](https://doi.org/10.7907/Z9J38QKJ). The project license does
not apply to material attributed to that publication. Build dependencies are
fetched separately and remain under their upstream licenses.
