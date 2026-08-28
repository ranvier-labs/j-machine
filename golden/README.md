# Golden MDP simulator

`mdp_golden.cpp` is an instruction-accurate C++ model of the MDP Version 11
architectural state. It does not call Verilated code, reuse the SystemVerilog
decoder, or advance RTL cycles. The only common input in differential tests is
the array of encoded 36-bit memory words.

The model includes:

- all published tags, instruction fields, opcodes, and fault numbers;
- three contexts, normal and register-mode operands, checked operation, fault
  save registers, fault/call vectors, and priority-switched low memory;
- base/limit and absolute addressing, QBM/QHL circular queues, A3 queue-relative
  access, priority dispatch, and `SUSPEND`;
- the two-way associative translation table;
- multicomputer message construction, routing by node number, queue-row commit,
  and priority delivery; and
- full architectural state snapshots and an event trace.

Architectural memory is sparse-paged in the golden model. Unwritten words still
read as `NIL`, but a 512-node machine no longer reserves four GiB merely to
represent empty address spaces.

The golden clock is an architectural event, not a hardware cycle. A constant
fetch, instruction retirement, message dispatch, fault, or suspend consumes one
event. Network delivery is functionally atomic when an ending send instruction
completes. This intentionally lets the model remain a valid functional oracle
when the RTL pipeline, memory latency, or eventual FPGA link timing changes.

## Build and test

```sh
bazel build //:mdp-golden
bazel test //:golden_test
bazel test //:tests
```

`bazel test //:golden_test` tests encoding,
arithmetic, shifts, logic, tags, comparisons, and fault-vector behavior.
`bazel test //:tests` runs those tests and then runs the two-node Verilator program
against the golden model, comparing architectural memory, node numbers, and
fault results as well as current IP/R0, execution-mode flags, context selection,
priority, and queue status. Directed external-interrupt and DRAM-error phases
also compare handler-recorded fault-time FIP and MAR state. A generated matrix
then checks all 26 pure ALU/tag opcodes against every pair of the 16
architectural input tags: 6,656 exact result-or-fault comparisons.
Directed stateful fixtures additionally compare both translation-table ways,
`PROBE` miss behavior, `INVAL` context scope, `LDIP`/`LDIPR`, CALL/FIP return,
and both outcomes of all six conditional branch opcodes.

## Command-line simulator

```sh
bazel run //:mdp-golden -- --nodes 1 --image golden/examples/add.image \
  --events 24 --trace
```

Repeat `--status NODE` to restrict the final status report on large machines;
peeks, expectations, and catastrophe checks still apply across the full system.

Images are plain text. Each non-comment row has three fields:

```text
NODE  HEX_WORD_ADDRESS  HEX_36_BIT_WORD
```

Addresses are 20-bit word addresses and values are 36-bit tagged words. The
loader bypasses ROM write protection, as a ROM-image loader should. Processor
`WRITE` instructions still enforce the architectural ROM region.

The public API in `mdp_golden.hpp` additionally exposes interrupt and DRAM-error
injection, memory access, bounded stepping, complete node/context snapshots, and
trace events for fuzzing or a future trace-by-trace differential runner.
