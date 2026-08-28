# MDP Version 11 conformance status

This file separates architectural implementation from current test coverage.
"Implemented" means the published mechanism is represented in RTL. "Verified"
means the current Verilator regression directly exercises it. A mechanism that
has not yet received a directed test remains part of the RTL; it is not replaced
by a compact substitute.

| Contract | Implemented | Directed Verilator test |
| --- | --- | --- |
| 36-bit word and all 16 tag encodings | yes | every tag in the checked pure-opcode differential matrix |
| Packed 17-bit high/low instructions | yes | high instruction and phase advance |
| Published Version 11 opcode numbers | yes | all 26 pure ALU/tag opcodes plus directed stateful READ, WRITE, READR, WRITER, LDIP, LDIPR, ENTER, XLATE, INVAL, PROBE, SEND, SEND2E, all seven branches, CALL, and SUSPEND paths |
| Normal and register-mode operands | yes | register, immediate, memory, special register |
| Checked/unchecked execution | yes | 6,656 checked opcode/tag-pair cases plus unchecked setup and fault handlers |
| Fault priority, save state, and vectors 0x00-0x12 | yes | TYPE, FUT, asynchronous QUEUE, and re-entrant SEND vectoring plus catastrophe guard |
| Three contexts and priority preemption | yes | background and priority-1 dispatch |
| Full 20-bit address space and priority switch | yes | ROM/external memory paths |
| Base/limit, absolute A0, and queue-relative A3 | yes | absolute fetch and A3 message arguments |
| Two-way associative translation row `[data0,key0,data1,key1]` | yes | exact two-way row, XLATE/PROBE hits, PROBE miss, and INVAL scope |
| Two priority queues and four-word QRB commit | yes | priority-1 receive, wrap accounting, and a four-word active queue raising QUEUE before the next fetch |
| Four send instructions and eight-word output FIFO | yes | SEND plus SEND2E; forced-full FIFO takes and recovers from SEND fault 3 |
| X-Y-Z routing, header stripping, message locks, and priority preemption | yes | X route with lock and tail |
| Parameterized 3-D mesh | yes | 2 x 1 x 1 differential target and 8 x 8 x 8 executable target |
| DRAM-error input and architectural DRAMERR fault | yes | external operand read at `0x03000`; vector `0x45` records fault-time MAR and FIP |
| External interrupt and INTERRUPT vector | yes | asserted after software unmasks interrupts; vector `0x41` records the interrupted FIP |
| `CFUT`/`FUT` and tag-specific checked faults | yes | recursive MDC factorial forces `FUT` with exact EQ on both nodes |
| CALL-vector table | yes | linked external-code targets exercised by every compiled local/remote call |
| All arithmetic, logical, comparison, and branch edge cases | yes | pure checked tag matrix plus taken/not-taken outcomes for every conditional branch; arithmetic data edges are representative, not exhaustive |
| IEEE binary32/binary64 target service | yes | 7,800 randomized add/subtract/multiply/FMA/divide/square-root cases against Berkeley SoftFloat plus directed rounding, conversion, comparison, exception, and backpressure cases |
| AWS F2 HDK source target | yes | pinned official F2 HDK, Small Shell CL directory bundle, OCL contract, 4 GiB PCIM mapping, queue-row backpressure, AXI stall/error regression; routed Vivado DCP remains external and unverified |
| Tagged-word FPU MMIO adapter | yes | binary32 add, iterative binary64 divide, status/done clearing, word order, and invalid address/tag/op rejection |

## Golden-model differential verification

The C++ golden model is independent of Verilator and the SystemVerilog decoder.
It consumes encoded 36-bit memory images and advances architectural events,
whereas the RTL advances clock cycles. The current regression compares:

- checked ADD and external-memory writes;
- all 26 pure ALU/tag opcodes over every pair of the 16 input tags (6,656
  cases), comparing the exact result word or selected fault;
- both associative `ENTER` ways, `XLATE`/`PROBE` hits, `PROBE` miss, and
  foreground-only `INVAL` results;
- direct/register IP loads, CALL-vector/FIP return, and both outcomes of every
  conditional branch;
- two-node priority message delivery, queue consumption, and `SUSPEND`;
- node-number special-register initialization; and
- checked TYPE-fault selection and vectoring;
- an asynchronous external interrupt after architectural unmasking, including
  the exact saved continuation; and
- an active priority queue becoming full with `I=F=0`, including the QUEUE
  vector and exact pre-fetch FIP; and
- an injected external-memory read error, including DRAMERR selection and the
  exact fault-time MAR/FIP recorded by the handler.

Its standalone warning-as-error suite additionally covers representative
arithmetic, carry, multiply, shift, rotate, logical, tag, comparison, equality,
encoding, and fault cases. The remaining cross-product work is on stateful
memory/register/translation/message/control opcodes, whose legal setup and
observable state require directed fixtures rather than arbitrary tag pairs.

## Compiler-generated image verification

The Lean 4 compiler's regression produces fresh Version 11 images before each
run. Both independent execution models check exact final tagged words:

| Source program | Property | Expected word |
| --- | --- | --- |
| `factorial.c` | recursion, `factorial(6)` | `INT(720) = 0x1000002d0` |
| `control.c` | global state, `for`, `if`, `continue` | `INT(40) = 0x100000028` |
| `conditional_updates.c` | selected-arm and right-associative `?:`, `do`/`while` break/continue, single-evaluation prefix/postfix and compound updates, signed/unsigned and pointer compound operations | result `INT(331)`; exact trace globals `3`, `1`, `1`, `192`, `13` |
| `declarations_goto.c` | multiple declarators, comma expressions, declaration-form `for`, labels/`goto`, pointer scalar conditions and null conversions across initialization/assignment/argument/return, plus placed-call coexistence | node 0 `INT(145)`; static locals `3`, `6`; node 1 observes `INT(5)` |
| `block_declarations.c` | block function prototypes and extern-object shadowing, mixed function/object declarators, `auto`/`register`, register parameters, and file/block `_Static_assert` | result `INT(134)`; global updated to `INT(9)` |
| `nested_calls.c` | nested multi-argument frame/spill safety | `INT(33) = 0x100000021` |
| `operators.c` | `while`, `break`, short circuit, update, shift, bitwise | `INT(59) = 0x10000003b` |
| `division.c` | signed general division/remainder plus power-of-two remainder, including `INT_MIN` | result `INT(42)`; exact `-4`, `4`, `0` fast-path observations |
| `integer_types.c` | `_Bool`, distinct word-sized integer ranks, promotions, suffix/character literals, modulo unsigned arithmetic, division, shift, and ordering | `INT(65535) = 0x10000ffff` |
| `string_literals.c` | adjacent/escaped narrow word strings, inferred and explicit array bounds, `sizeof`, global/static string and object-address relocations | `INT(255) = 0x1000000ff` |
| `wide_literals.c` | C11 `L`/`u`/`U` character constants, `u8`/wide strings, universal character names, raw Unicode, prefix-promoted concatenation, target-defined multicharacter constants, typed pointers/arrays, and a placed call carrying the three wide integer types | node 0 `INT(1222) = 0x1000004c6`; exact scalar-word and UTF-8-word storage checked |
| `switch.c` | cases nested beneath `if`/`while`, a non-compound switch body, nested switches, default, fallthrough, and nearest-break behavior | `INT(211) = 0x1000000d3` |
| `pointers.c` | ADDR bounds, arrays, decay, dereference, `sizeof` | `INT(37) = 0x100000025` |
| `pointer_arithmetic.c` | typed ADDR movement/difference, casts, null and pointer comparison | `INT(116) = 0x100000074` |
| `aggregates.c` | structs, unions, nested/indirect members, copy, self pointers | `INT(392) = 0x100000188` |
| `aggregate_by_value.c` | full-width struct/union parameters and caller-owned results through direct, nested, and function-pointer calls | `INT(208) = 0x1000000d0` |
| `compound_literals.c` | frame-backed C99 scalar/array/struct compound literals, lvalue mutation and identity, aggregate arguments, unevaluated `sizeof`, and typed null initialization of omitted pointer subobjects | `INT(167) = 0x1000000a7` |
| `designated_initializers.c` | recursively nested initialization, brace elision, chained array/member designators, source-order continuation and override, inferred aggregate-array bounds, nested strings, aggregate-valued expressions, and union active-member zeroing | `INT(1033) = 0x100000409` |
| `typedefs.c` | scoped aliases for scalar, pointer, array, and aggregate types | `INT(20) = 0x100000014` |
| `function_pointers.c` | recursive function declarators, function typedefs, non-null index encoding, null comparison, local/global/static relocations, and native indirect `CALL Rn` | `INT(128) = 0x100000080` |
| `qualifiers.c` | recursive const/volatile/restrict types and qualified access | `INT(31) = 0x10000001f` |
| `enums.c` | distinct enum types, enumerator constant expressions, bounds and switch labels | `INT(20) = 0x100000014` |
| `multi_main.c` + `multi_library.c` | prototypes, two translation units, `extern` data linkage | `INT(29) = 0x10000001d` |
| `static_main.c` + `static_library.c` | same-spelling internal-linkage functions/objects and persistent block statics in two translation units | `INT(162) = 0x1000000a2` |
| `function_specifiers_main.c` + `function_specifiers_external.c` | C11 declaration-specifier ordering, repeated/static/external `inline`, a distinct inline definition plus one external definition, and `_Noreturn` propagation/fallthrough trapping | `INT(41) = 0x100000029` |
| `alignment.c` | C11 `_Alignas`/`_Alignof`, zero and repeated alignment specifiers, aligned globals/locals/compound literals, member-induced aggregate padding, pointer-visible placement, and aligned by-value aggregate parameters | `INT(1098) = 0x10000044a`; globals at aligned addresses `0x800` and `0x810` |
| `atomics.c` | C11 `_Atomic(type-name)` and qualifier forms for integer, pointer, structure, and union objects; scalar transactions, masked multiword aggregate snapshots/stores, stable assignment-expression values, and sequentially consistent prefix/postfix/compound read-modify-write operations that preserve the MDP message-dispatch mask | `INT(725) = 0x1000002d5`; counter `INT(3)`, flags `INT(255)`, cursor capability at `0x805`; final aggregate words checked at `0x806..0x80e` |
| `stdatomic.c` | compiler-owned C11 `<stdatomic.h>` typedefs/macros and generic operations: initialization, scalar/pointer/aggregate load/store/exchange/compare-exchange, integer/pointer fetch operations, atomic flags, lock-free queries, dependency suppression, fences, explicit orders, and failure-order checking | `INT(160) = 0x1000000a0`; counter `INT(15)`, bits `INT(1)`, cursor `values + 1`, pair `{8, 9}`, flag set |
| `generic_selection.c` | C11 `_Generic` compatible-type/default selection, non-evaluation of the control and unselected associations, scalar/pointer/aggregate matching, and preservation of selected lvalues for assignment and address-taking | `INT(35) = 0x100000023`; side-effect counter remains `INT(0)` |
| `bit_fields.c` | LSB-first 32-bit allocation units, signed/unsigned/`_Bool` fields, unnamed and zero-width padding, non-straddling rollover, union overlap, positional/designated static and automatic initialization, and masked assignment/prefix/postfix/compound updates | `INT(2858) = 0x100000b2a`; packed state words `0x1000090fe`, `0x10000000f`; crossing words `0x100000001`, `0x10000abca` |
| `flexible_arrays.c` | C99 flexible member prefix layout and `sizeof`, recursive containment constraints, fixed-prefix initialization/copy, and bounded trailing access through a larger array capability | `INT(48) = 0x100000030`; backing prefix/contents `5, 3, 5, 7, 11, 13` |
| `thread_local.c` | C11 `_Thread_local` at file and block scope, `static`/`extern` combinations, and destination-node thread state across a placed call | node 0 `INT(30)` with state `5, 6, 2`; node 1 state `8, 6, 2` |
| `remote_call.c` | two-node void spawn, FUT/SET value return, NNR | node 0 `INT(142)`, node 1 global `INT(41)` |
| `remote_function_pointer.c` | runtime-selected nonzero CALL-vector index transported by `function(args)@rank` | node 0 `INT(43) = 0x10000002b` |
| `remote_integer_types.c` | unsigned and `_Bool` scalar arguments/future returns through `function(args)@rank` | node 0 `INT(3)`; node 1 observes `INT(0xffffffff)` and `_Bool(1)` |
| `remote_string_literals.c` | a narrow string transported through the historical length-delimited word-pointer envelope | node 0 `INT(213)`; node 1 checksum `INT(212)` |
| `remote_aggregate.c` | direct/indirect multiword parameter and result envelopes, caller-owned per-word FUTs, priority-process suspension/wake, and result-block reclamation | node 0 `INT(127)`; both nodes score `INT(73)`; node 1 records one FUT fault |
| `remote_bit_fields.c` | packed bit-field object representation transported as a two-word aggregate parameter/result, with signed extraction and masked updates on the receiver | node 0 `INT(20)`; node 1 packed observation words `0x10000078d`, `0x10000000e` |
| `remote_bulk.c` | historical length-delimited `(length, pointer)` argument | node 0 `INT(29)`, node 1 global `INT(28)` |
| `remote_bulk_limit.c` | dynamic bulk envelope above QHL's 1020-word maximum fails before mailbox allocation or SEND | node 0 result remains `SYM(0)`, error status `INT(1)`; node 1 callee-entry global remains `INT(0)` |
| `code_cache.c` | cold distributed-code fetch, two install chunks, acknowledgement pacing, second-call cache hit | node 0 `INT(1122)`, one request, two installs/acks |
| `futures.c` | two deferred assignments followed by access-time forcing | node 0 `INT(32)`, node 1 global `INT(2)` |
| `suspension.c` | FUT fault, process save/link, `SUSPEND`, SET wake, restore | node 0 `INT(41)`, both node globals `INT(1)` |
| `reclamation.c` | twenty bulk calls, process/payload free-list reuse and fixed high-water mark | node 0 `INT(770)`, node 1 global `INT(20)` |
| `send_fault.c` | full output FIFO, two re-entrant architectural SEND faults, state restore | standalone RTL resumes with `INT(77)`, counter at least `2`, last fault `3` |
| `mesh512.c` | 512 identities and node-0 to node-511 bulk invocation | node 0 `INT(539)`, node 511 global `INT(28)` |
| `historical_factorial.c` | Maskit Figure 2.1 remote recursion, five FUT suspensions/wakes, reclamation | node 0 `INT(720)`, FUT counts node 0 `2`, node 1 `3` |
| `historical_hop.c` | Maskit Figure 3.3 control/communication flow on two nodes | four visits per node, terminal count `5` |
| `historical_hop.c` (512 nodes) | four complete tours of the concrete 8 x 8 x 8 allocation | 2,048 remote calls; node 511 last observation `INT(2044)` |
| `historical_producer_one_way.c` | Maskit Figure 5.1 one-way bulk-message flow | 40 arrivals; payload checksum `INT(1120)` |
| `historical_producer_two_way.c` | Maskit Figure 5.2 deferred remote returns and second forcing loop | 16 arrivals, 14 architectural FUT faults, payload checksum `INT(448)` |
| `historical_dirichlet.c` | Figures 5.3-5.5 distributed initialization, face exchange, per-step norm barriers, and termination | four nodes converge to `INT(5)` after five steps; final/step checksums `INT(20)` |

The Lean unit executable separately checks the Version 11 ADD encoding, the
split protected-ROM/external-application link map, direct CALL-vector targets,
global initialization, symbol generation, and positioned diagnostics for
rejected constructs. The accepted C subset and the ABI are
specified in [`compiler/README.md`](../compiler/README.md); unsupported syntax
is not counted as conforming compiler behavior.

## Target boundary

The target-independent mesh exposes two storage transactions per node:

- a stable request/response 36-bit processor word port with 20-bit addresses;
- a 144-bit, four-enable queue-row write port with 18-bit row addresses.

The two-node Verilator target supplies full `2^20`-word arrays. The parameterized
four-node Dirichlet and 512-node targets supply sparse per-node memories through
the same processor/QRB
protocol, preserving architectural ROM write protection, one-cycle reads,
loader/debug access, and the DRAM-error input without allocating 512 dense
arrays. These are target bindings, not changes to the MDP address or queue
semantics.

The two-node Verilator adapter exposes independent interrupt inputs and
per-node DRAM-error enables plus an injected external address. Normal image
runs drive them low; the differential test drives node zero and compares the
resulting vectors and saved state with the golden model.

The standalone-node backpressure target binds those same ports to the dense
memory and leaves receive links idle. Its only additional control gates the
ordinary ready inputs of the two egress virtual networks. The self-checking
runner holds both low until the compiler runtime records two SEND faults, then
raises ready and verifies the original background continuation, retry-frame
release, fault number, and final tagged result.

The text loader accepts either `NODE ADDRESS WORD` or `* ADDRESS WORD`.
Wildcard rows are broadcast to every configured node before explicit node rows
are applied. `mesh512.image` uses 1,338 common rows plus 1,828 targeted state and
node-zero application rows: 3,166 data rows encode 686,884 loader writes. The
node-511 external application section is absent from the initial image and its
ready flag is clear until the priority-1 installer writes the linked code at
`0x30000` and publishes readiness.

The replicated historical Hop image uses 2,051 common rows plus 1,024
node-specific identity/state rows, encoding 1,051,136 loader writes. Its
1.8-billion-event oracle completes all 2,048 remote invocations and verifies
terminal observations and process-pool reclamation rather than relying on an
event count alone.

The internal network boundary is an 18-bit flit (two historical 9-bit phits)
for each of the two priority virtual networks. The published route operations,
three dimension headers, header consumption, priority preemption, and tail
behavior are modeled. A pin-level 9-bit serializer, synchronizer, and pad
turnaround block belongs in the eventual FPGA target; none is substituted into
the current software-simulation target.

## Work still requiring primary-source validation

- exhaustive stateful-opcode directed tests, including every addressing mode
  and fault-precedence combination (the complete pure ALU/tag matrix is now
  differential-tested);
- cycle-by-cycle comparison with surviving MDP simulator traces, if those
  artifacts can be recovered;
- exact external DRAM refresh/ECC register behavior beyond the visible memory
  and error interfaces;
- physical 9-bit channel serialization and board-level timing for the FPGA
  target; and
- the remaining ISO C front end: `long long`, floating literals and types,
  variadics/old-style calls, variable-length arrays,
  the `long long`-dependent `<stdatomic.h>` aliases, and full preprocessing.
