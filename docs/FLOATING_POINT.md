# Floating-point architecture

The MDP Architecture Version 11 instruction and tag encodings do not define
floating-point operations.  This implementation therefore does not consume a
spare opcode or reinterpret one of the sixteen historical tags.  Floating
values are stored as standard IEEE binary32 or binary64 bit strings in one or
two `INT`-tagged payload words and are evaluated by a target service.

That service has one ready/valid request and one backpressured response.  Its
contract is independent of the implementation target:

- `format`: binary32 or binary64;
- `operation`: add, subtract, multiply, fused multiply-add, divide, square
  root, quiet compare, signed/unsigned 32-bit integer conversion, or binary32
  / binary64 precision conversion;
- all five IEEE rounding directions supported by HardFloat, plus round-to-odd;
- selectable tininess detection before or after rounding; and
- the five sticky IEEE flags in `{invalid, divide-by-zero, overflow,
  underflow, inexact}` order.

`rtl/fpu/j_fpu_hardfloat.sv` is the FPGA-capable implementation of this
contract.  It converts standard encodings into HardFloat's recoded format,
uses Berkeley HardFloat Release 1 for every arithmetic result, and converts
back only at the service boundary.  Addition, multiplication, FMA,
comparisons, and conversions are captured after one request cycle.  The
Release 1 `_small` divider/square-root unit is iterative and holds the service
busy until its result is available.  The service always retains a completed
response until its consumer accepts it.

## Memory-mapped ABI

`j_fpu_mmio.sv` maps the service onto ten words at the target-selected base
address (default `0xfff00`).  This is a fabric adapter, not part of the MDP
core, so an FPGA target can instantiate one FPU per node, arbitrate several
nodes onto a shared FPU, or route requests to a dedicated service node without
changing compiler-visible semantics.

| Offset | Access | Meaning |
| --- | --- | --- |
| `0` | R/W | control/start |
| `1`, `2` | R/W | operand A low/high |
| `3`, `4` | R/W | operand B low/high |
| `5`, `6` | R/W | operand C low/high |
| `7`, `8` | R | result low/high |
| `9` | R/W | status / write-one-to-clear done |

Control bits are operation `[4:0]`, format `[5]`, rounding mode `[8:6]`,
tininess-after-rounding `[9]`, and start `[31]`.  Status bits are busy `[0]`,
done `[1]`, exception flags `[6:2]`, and comparison
`{unordered, greater, equal, less}` in `[10:7]`.  Every MMIO word must have the
architectural `INT` tag.  Invalid addresses, tags, operations, and rounding
encodings return the adapter's error response rather than silently changing
the request.

Binary64 words use little-word order: the low 32 bits are at the lower word
address.  The ABI intentionally transports bits rather than relying on an MDP
floating tag.  Compiler type checking retains the C distinction between
integer, `float`, and `double`; only the machine-level transport representation
is shared.

## 512-node FPGA topology

Instantiating 512 complete binary64 FMA/divide/square-root blocks is a valid
semantic configuration but is unlikely to be the best use of a single FPGA.
The service boundary keeps three implementation choices open:

1. a per-node binary32 unit, with binary64 or divide/square-root sent to a
   shared service;
2. one FPU per tile or mesh plane behind deterministic arbitration; or
3. dedicated FPU nodes reached with ordinary J-Machine messages.

These are area/latency placement choices, not alternate floating semantics.
The Verilator target first verifies one complete service.  FPGA synthesis and
resource measurements must choose a concrete device and topology before any
area claim is meaningful.
