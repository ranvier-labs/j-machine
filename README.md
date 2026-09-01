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

`compiler/` contains `jmc`, a self-contained Lean 4 compiler that lowers a
documented C subset directly to Version 11 tagged words. It has a lexer,
precedence parser, source diagnostics, program validation, stack-frame ABI,
CALL-vector linking, recursive/nested calls, globals, bounded pointers and
multidimensional arrays, typed pointer arithmetic/casts, structs/unions,
scoped typedef and enum names, recursive const/volatile/restrict types,
`_Bool` plus signed/unsigned word-scalar ranks with C integer promotions,
scalar boolean normalization, division/remainder,
integer suffixes, character constants, narrow word strings, initializer-inferred
array bounds, global/static object-address relocations, the conditional operator,
`do`/`while`, declaration-form `for`, comma expressions, labels/`goto`,
single-evaluation prefix/postfix updates and compound assignments,
arbitrary nested `switch` labels, multiple declarators, block-scope externs and
function prototypes, `auto`/`register` storage classes, `_Static_assert`,
frame-backed C99 scalar/array/aggregate compound literals with addressable
lvalue identity, recursively nested/designated initialization with brace
elision and source-order overrides, and type-correct implicit null initialization,
multi-file external and translation-unit-local linkage, tentative definitions,
persistent block statics, full-width local
aggregate parameters/results, multiword remote aggregate envelopes and
per-word FUT/SET completion, recursive function
declarators, local/global/static function pointers lowered to native MDP
`CALL`, C11 external/static `inline` and `_Noreturn` semantics, and direct or
indirect MDC `call(...)@node` placement. C11 `_Alignas`/`_Alignof` determines
word-addressed global, frame, compound-literal, member, aggregate, and
by-value-parameter layout with supported power-of-two alignment through 64
words. C11 `_Atomic(type-name)` and `_Atomic` qualifiers are implemented for
integer, pointer, structure, and union objects. Scalar loads/stores use native
MDP memory transactions; aggregate lvalue conversion takes a masked snapshot
of the complete aggregate, and aggregate assignment stores the complete
aggregate under the mask. Sequentially
consistent scalar/pointer `++`/`--` and compound read-modify-write operations
likewise preserve and mask the architectural message-dispatch state around the
critical sequence. C11 `_Generic` is resolved at
translation time; its control and unselected associations remain unevaluated,
including preservation of a selected lvalue for assignment or address-taking.
The built-in C11 `<stdatomic.h>` surface provides `memory_order`, `atomic_flag`,
the ABI-representable standard atomic typedefs and lock-free macros,
`ATOMIC_VAR_INIT`/`ATOMIC_FLAG_INIT`, fences, lock-free queries, and the complete
load/store/exchange/compare-exchange/fetch generic-operation families. Explicit
orders are constraint-checked; scalar and pointer operations use native
single-word transactions, while read-modify-write and multiword aggregate
operations use the same message-dispatch masking protocol.
Packed C bit-fields use an explicit LSB-first 32-bit-word ABI with unnamed and
zero-width padding, signed extraction, source-ordered static/automatic
initialization, and masked updates that preserve neighboring fields.
Flexible array members determine alignment and a checked trailing-member offset;
they add zero bytes to `sizeof`. Access keeps the bounds of an explicitly larger
backing capability, and recursive structure/union containment constraints are
enforced.
C11 `_Thread_local` maps one C abstract thread to each physical node, so file-
scope and block-static instances are initialized independently on all nodes and
remote message activations observe the destination node's thread state.
All C11 encoded literal prefixes are supported. Ordinary and `L`/`u`/`U`
execution characters occupy one 32-bit word per Unicode scalar, while `u8`
uses UTF-8 byte values stored one per word; adjacent-token prefix promotion is
performed before encoding.
Protected
bootstrap/runtime code is linked at
`0x1000`, while application functions and their CALL-vector targets are linked
at the external code-cache base `0x30000`. Unsupported C constructs produce
diagnostics.

`bazel test //compiler:generated_tests` compiles recursive factorial, loop/global control flow, conditional
selection and update operators, nested
multi-argument calls, signed/unsigned scalar arithmetic, switching,
pointer/aggregate code, compound literals and nested/designated initializers, a linked
two-file function-specifier program, an executable alignment/layout program,
executable core-language atomic and `<stdatomic.h>` scalar/pointer/aggregate
programs,
an executable generic-selection/type-dispatch program,
an executable packed bit-field layout/update/initialization program,
an executable flexible-array/backing-capability program,
an executable two-node thread-local storage program,
an executable two-node wide/Unicode literal and placed-call program,
and linked programs with both external
and same-spelling internal-linkage
entities, executable typedef/qualifier/function-pointer programs, two-node
direct/indirect signed/unsigned scalar, multiword aggregate, string-bulk, and general bulk
remote-call programs, a packed bit-field aggregate round trip, an oversized
dynamic-bulk fail-stop test, and a
multi-chunk distributed-code/cache test. It also compiles executable,
attributed adaptations of Maskit's recursive factorial, Hop,
one-way producer, two-way deferred-return producer, and parallel Dirichlet
examples. It then executes each emitted image independently in the C++ golden
model and the Verilated RTL, with exact tagged-word expectations.

`bazel test //compiler:historical_dirichlet_rtl_test` is the focused four-node target for Maskit's
Figures 5.3-5.5 control structure. It runs a `4 x 1 x 1` mesh through
distributed initialization, neighbor-face exchange, five global-norm barriers,
and coordinated termination. Both models require every node to finish at value
5 after five steps and require coordinator value/step checksums of 20.

The MDC examples also include two deferred future assignments: both
remote messages are issued before either destination is consumed, and generated
loads synchronize at access time. `suspension.c` then exercises a cyclic
two-node dependency that requires the priority-0 FUT fault handler to save and
suspend a process, accept intervening work, and restore it through a wake
message.

The historical recursive factorial is the directed suspension test: its five
dependent remote frames take Version 11 `FUT` faults, wake in reverse
order, return `720`, and recycle every process block. The forcing sequence
respects the published distinction that `READ` may move a `FUT`; the equality
comparison is the checked primitive that consumes it and faults.

Compiler-generated images also install both priority-mapped SEND vectors. A
Version 11 SEND-buffer fault enters an unchecked, absolute-A0 runtime handler
that preserves FIP, FIR, FOP0/FOP1, all four data registers, and A1-A3 in one
of three context-private retry frames. It decodes and retries every
`SEND`/`SENDE`/`SEND2`/`SEND2E` and output-priority combination, survives a
second full-buffer fault while preserving the original continuation, and
returns through `LDIPR FIP`. `bazel test //compiler:send_fault_rtl_test` blocks a standalone node's
network egress until that handler has re-entered twice, releases backpressure,
and requires the compiled `send_fault.c` program to resume with `INT(77)`.

The MDC runtime uses independent node-local free lists for completed 512-word
process blocks and 1024-word bulk-payload blocks. `reclamation.c` performs
twenty sequential remote bulk calls and verifies a constant heap high-water
mark after the first call in both execution models.

`bazel test //compiler:mesh512_golden_test` builds and executes a 512-node image in the sparse-paged
golden model. `bazel test //compiler:mesh512_rtl_test` executes that same image on all 512
MDP/router instances in the hierarchical Verilator target, using sparse
per-node simulation memories to avoid allocating 512 dense million-word
arrays. The checked run reaches its specified terminal predicate at 66,496 cycles
on the current model. Its program transfers an eight-word array from node 0 to node 511
and checks both the remote global and returned tagged value. Application code
is present initially only on node zero; the test also proves one request,
install, and acknowledgement across the full X-Y-Z route, a clear initial
cache-ready flag on node 511, and the fetched linked word at `0x30000`.
`bazel build --config=rtl-lint //sim:j_machine_sparse512_rtl` elaborates the concrete `8 x 8 x 8` RTL configuration; this is a
large structural lint target and is separate from the fast suite.
The image uses broadcast rows for common bootstrap/runtime/data, explicit
node-state rows, and node-zero-only application rows. Both software loaders
implement that target-neutral placement contract, so a later FPGA programming
controller can bind the same broadcast and targeted writes through the shared
loader interface.

Logical image-node keys and MDC source-level ranks remain dense `0..511`.
Architectural NNR and routing words use the published packed coordinates:
`x | (y << 5) | (z << 10)`. Thus ranks 0, 256, and 511 in the `8 x 8 x 8`
target have NNR values `0x0000`, `0x1000`, and `0x1ce7`. The Lean compiler
performs both rank/NNR conversions and rejects a node count above 32 unless an
explicit topology is supplied.

`bazel test //compiler:historical_hop512_golden_test` compiles the published Hop control flow for the same
512-node configuration and performs four complete tours: 2,048 remote MDC
invocations over the 8 x 8 x 8 machine. The sparse golden model checks visit
counts and final observations at nodes 0, 256, and 511, as well as terminal
process-block reclamation. Its target-neutral image currently contains 2,051
broadcast rows and 1,024 node-specific rows, expanding to 1,051,136 loader
writes; the 1.8-billion-event bound was measured against the specified terminal
state after topology lowering. This long architectural regression is separate
from the fast suite.
See [`compiler/README.md`](compiler/README.md) for the accepted language, ABI,
image layout, commands, and explicit unsupported-feature boundary.

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
