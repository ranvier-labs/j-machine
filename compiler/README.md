# `jmc`: a Lean 4 C compiler for the J-Machine

`jmc` is a clean-room compiler written in Lean 4. It parses a deliberately
specified C subset, emits exact MDP Architecture Version 11 words, resolves
branches and CALL-vector entries, and writes the same text image format
consumed by the independent C++ golden model and the Verilator target.

This is new work, not recovered Message-Driven C source. The surviving GNU C
port and its original examples are described in
[`historical/PROVENANCE.md`](../historical/PROVENANCE.md).

## Build and run

From `j_machine/`:

```sh
bazel build //compiler:jmc

bazel run //compiler:jmc -- compiler/examples/factorial.c \
  -o /tmp/factorial.image --listing /tmp/factorial.lst

bazel run //compiler:jmc -- compiler/examples/multi_main.c \
  compiler/examples/multi_library.c -o /tmp/multi_file.image

bazel run //:mdp-golden -- --image /tmp/factorial.image --events 10000 \
  --expect 0:300:1000002d0

bazel run //sim:image_runner -- --image /tmp/factorial.image --cycles 10000 \
  --expect 0:300:1000002d0
```

The shorter complete regression is:

```sh
bazel test //compiler:generated_tests
```

It builds the compiler and both simulators, compiles all examples, runs every
compiler unit test, and checks the generated images in both execution models.

## Accepted source language

The lexer and recursive-descent/precedence parser currently accept:

- `_Bool`, distinct plain/signed/unsigned `char`, signed/unsigned `short`,
  `int`, and `long`, plus `void`, named `struct`/`union`, pointers, arrays, recursive C
  declarators, file- and block-scope function prototypes and function types,
  file- and block-scope `extern` object declarations, file-scope `static` functions and objects,
  tentative object definitions, and scoped object/pointer/array/function/
  aggregate `typedef` names with the C ordinary-identifier shadowing rules;
- named and anonymous enum types, scoped enumerator constants, and signed
  32-bit integer constant expressions for enumerator values, array bounds,
  global initializers, switch labels, and file- or block-scope `_Static_assert`;
- recursive `const`, `volatile`, and `restrict` qualification at declaration
  and pointer levels; const-qualified lvalues and qualifier-dropping pointer
  conversions are rejected, volatile accesses remain explicit, and restrict
  is constrained to pointer types;
- decimal, octal, and hexadecimal 32-bit integer constants with `U`/`L`/`UL`
  suffixes; ordinary, `L`, `u`, and `U` character constants; ordinary,
  `u8`, `L`, `u`, and `U` string literals; universal character names,
  adjacent literal concatenation, escaped code units, comments, and
  object-like integer `#define` directives;
- default or explicit `auto` block-local objects, `register` locals and
  parameters (including the required address-taking constraint), multiple
  declarators with optional scalar, recursively nested brace-list,
  designated, or aggregate-copy initialization, plus persistent block-scope `static` objects
  with zero, integer-constant, null-pointer, function-designator, object-address,
  or narrow-string initialization;
- C11 `_Thread_local` objects at file scope and in the required block-scope
  `static`/`extern` forms, including combinations with internal or external
  linkage and consistency checks across every declaration of one object;
- bounded multidimensional arrays, typed pointers, array decay, `&`, `*`,
  subscripting, initializer-inferred one-dimensional array bounds, `.`/`->`,
  struct/union layout and copy assignment, self-referential pointer members,
  C99 flexible array members with omitted `sizeof` storage, recursive
  structure/union containment constraints, and bounds-preserving access
  through caller-provided backing storage,
  C99 block-scope scalar/array/struct/union compound literals with automatic
  storage duration and lvalue identity, word-based `sizeof`, and C11
  `_Alignof(type-name)`/`_Alignas(type-name-or-constant)` with aligned
  members, aggregates, parameters, compound literals, automatic objects, and
  static-duration objects, plus C11 `_Atomic(type-name)` and `_Atomic`
  qualifiers for integer, pointer, structure, and union objects; packed `_Bool`, signed
  `int`, and unsigned `int` bit-fields with unnamed padding and zero-width
  allocation boundaries;
- `if`/`else`, `while`, `do`/`while`, expression- or declaration-form `for`,
  arbitrary `switch` bodies with nested `case`/`default` labels and fallthrough,
  function-scoped labels and `goto`, `return`, `break`, and `continue`;
- direct and function-pointer calls, recursion, full-width struct/union
  parameters and results by value, function designator decay, global/static
  function-pointer relocations, native indirect MDP `CALL`, and repeated C11
  `inline`/`_Noreturn` function specifiers in arbitrary declaration-specifier
  order;
- variable/member assignment, prefix and postfix integer or pointer `++`/`--`,
  every integer compound assignment, pointer `+=`/`-=`, and exact single
  evaluation of each updating lvalue; exact scalar-to-`_Bool` normalization,
  explicit integer/pointer casts, unary `+`, `-`, `!`, and `~`, plus the
  left-associative comma operator; C11 `_Generic` selection with compatible-
  type/default diagnostics, non-evaluated controlling and unselected
  expressions, and preservation of the selected expression's type, value, and
  lvalue category; and
- signed and unsigned multiplication, division/remainder, addition,
  subtraction, shifts, comparisons, equality, integer promotions and usual
  arithmetic conversions, bitwise operations, typed/scaled pointer arithmetic
  and difference, pointer comparison and scalar pointer conditions,
  short-circuit `&&`/`||`, and the
  right-associative conditional operator with selected-arm execution and C
  integer/pointer/aggregate result compatibility.

The command accepts multiple input files. It merges compatible aggregate
layouts, validates prototypes against definitions, resolves external functions,
coalesces `extern` and tentative global declarations with one definition, and
assigns translation-unit-local identities to internal-linkage functions and
objects before emitting one linked MDP image.

`--broadcast-image` emits target-neutral loader rows of the form
`* ADDRESS WORD` for code and identical initial data, followed by explicit
per-node identity overrides. Both current loaders expand this contract. The
result is about one common image plus per-node state overrides instead of
textually replicating every word; an FPGA configuration controller can
implement the same broadcast operation directly. Replicated placement marks
the application ready on every node; no software cache request is generated.

All application functions are linked directly into the writable external-code
section beginning at `0x30000`; bootstrap and the MDC handlers occupy the
protected `0x1000..0x1fff` region. `--distributed-code` broadcasts only that
resident bootstrap/runtime image and common data, while placing the linked
application section on code-home node zero. Remote nodes begin with an
unwritten application cache and a clear ready flag, then fetch the exact linked
words over the J-network before their first spawn can invoke a function. CALL
vectors therefore have one address on every node and never require per-node
relocation. This option and `--broadcast-image` are mutually exclusive.

The arithmetic representation is the MDP's tagged 32-bit `INT`. Following the
word-addressed ABI documented by Maskit, every integer scalar object—including
`_Bool` and `char`—occupies one addressable word, so `sizeof(_Bool)`,
`sizeof(char)`, `sizeof(short)`,
`sizeof(int)`, and `sizeof(long)` are all one and `CHAR_BIT` is 32. Plain
`char`, signed `char`, and unsigned `char` nevertheless remain distinct C
types. `_Bool` conversion from any integer, object pointer, or function pointer
stores exactly zero or one. Function pointers are stored as CALL-vector index
plus one so entry zero remains distinct from the null pointer, then decoded at
the local or remote indirect-call boundary. Signed arithmetic stays checked,
so invalid tags and signed overflow
enter the architectural fault mechanism. Unsigned add/subtract/multiply,
negation, and left shift bracket the exact operation with the MDP `U` flag to
obtain modulo-2^32 behavior; unsigned division and comparison have dedicated
lowerings and right shift uses `LSH`.

A narrow string literal has type array of plain `char` and is emitted as one
32-bit word per decoded character followed by a zero word, matching the MDP's
word-addressed memory instead of inventing byte addressing. Adjacent literals
are concatenated before allocation. Direct character-array initialization
copies the literal words and infers an omitted bound; an exact explicit bound
may omit the trailing zero as in ISO C. Brace initializers likewise infer an
omitted one-dimensional array bound. Global and static string pointers and
explicit object-address constants are relocated as bounded `ADDR` words. A string can therefore cross the
historical MDC bulk-data convention after an explicit cast to its word-pointer
parameter type, with the existing `(int length, int *data)` envelope carrying
its characters unchanged.

The encoded-literal ABI follows the target's 32-bit word-addressed character
model. `wchar_t` is signed `int`, `char16_t` is `unsigned short`, and
`char32_t` is `unsigned int`; all three therefore occupy one word. Ordinary,
`L`, `u`, and `U` source characters use the target execution mapping of one
Unicode scalar per word. A `u8` literal instead contains its exact UTF-8 byte
sequence, with each byte held in one `char` word. Octal and hexadecimal
escapes insert one direct code unit and may use the full 32-bit range;
universal character names are checked for Unicode scalar validity and the C11
below-U+00A0 restrictions before execution encoding.

Adjacent unprefixed tokens adopt the encoding of the prefixed token before
conversion, so `"\u03a9" u8""` contains `0xce, 0xa9, 0`. C11 forbids mixing
`u8` with a wide prefix. For the implementation-defined case of differing
wide prefixes (`L`, `u`, or `U`), this target chooses not to concatenate and
issues a diagnostic. A multi-character constant uses the documented target
rule common to historical C implementations: fold left by eight bits, append
the low byte of each character, and retain the low 32 bits; the result then
has the signedness of its prefixed character type.

Every block-scope compound literal owns a statically reserved region in the
function frame and is reinitialized whenever execution reaches its syntactic
occurrence. Repeated evaluation of one occurrence therefore preserves object
identity while distinct occurrences remain distinct. Array literals decay to
bounded `ADDR` values, aggregate literals participate in member access and
by-value calls, and scalar or aggregate literals remain addressable lvalues.
Recursive implicit initialization is type-directed: an omitted object-pointer
subobject receives the MDP invalid-`ADDR` null representation rather than an
integer-tagged zero. `sizeof` retains an array compound literal's complete
object type without allocating or evaluating its initializer.

Initializer lists preserve their recursive C99 structure rather than being
flattened. Array `[index]` and structure/union `.member` designators may be
chained, later clauses override earlier clauses in source order, and the next
positional clause continues after the designated subobject. Brace elision,
nested strings, aggregate-valued expressions, omitted-subobject zeroing, union
active-member selection, and incomplete outer-array bound inference all use
the selected subobject's exact type. The same resolver is used for automatic,
static, global, and compound-literal storage.

Function specifiers follow the C11 linkage model. A pure external `inline`
definition is retained as a translation-unit-local alternative and does not
provide the program's external definition; `extern inline`, or any non-inline
file-scope declaration in that translation unit, makes the definition an
external definition. The linker permits multiple compatible inline definitions
but requires at most one corresponding external definition. This backend makes
the implementation-defined choice to dispatch calls through that ordinary
external definition rather than substitute an inline body, preserving the
single function address and the MDP CALL-vector ABI. It enforces the same-unit
definition rule and the restrictions on modifiable static objects and
internal-linkage references. `_Noreturn` propagates across compatible
declarations, rejects explicit returns, and lowers any otherwise reachable
closing brace to a non-returning trap loop.

Alignment is expressed in addressed 32-bit MDP words. Scalar and pointer types
have fundamental alignment one; arrays inherit their element alignment, and a
struct or union inherits the strictest member alignment with real internal and
trailing padding. This implementation supports power-of-two extended
alignments through 64 words, plus the standard no-op value zero. Multiple
specifiers select the strictest requirement, type-name operands use the same
layout engine as `_Alignof`, and declarations/definitions are checked for the
C11 equivalence rules. Function frames are rounded to the program's strictest
alignment so direct, indirect, and message-delivered by-value aggregate
parameters remain aligned; the 64-word ceiling matches the aligned MDC runtime
frame boundary.

Atomic objects use the C11 type-specifier and type-qualifier grammar, including
their required distinction at `_Atomic (`. Integer and pointer atomic loads or
stores are indivisible MDP memory transactions. A structure or union atomic
lvalue conversion masks dispatch while copying every word into a stable frame
snapshot; whole-object assignment first snapshots the converted right operand,
then masks dispatch around the complete target store. The assignment expression
retains the stable snapshot as its non-atomic result. Atomic `++`/`--` and
compound assignments are sequentially consistent read-modify-write operations:
code generation saves the
architectural `I` message-dispatch mask, masks message dispatch around the
load/operation/store sequence, and restores the exact prior mask afterward.
This works both in ordinary code and inside an already masked priority message
handler. Atomic qualification participates in pointer compatibility, so a
conversion cannot silently discard it. C11 makes member access through an
atomic structure or union undefined; the target therefore guarantees only
whole-object atomic access.

`#include <stdatomic.h>` selects a compiler-owned C11 header with an idempotent
include guard. It defines `memory_order`, `atomic_flag`, all standard atomic
aliases representable by the target's `char`/`short`/`int`/`long` word ABI,
the corresponding `ATOMIC_*_LOCK_FREE` macros, `ATOMIC_VAR_INIT`, and
`ATOMIC_FLAG_INIT`. The generic functions cover initialization, load, store,
exchange, strong and weak compare-exchange, integer and pointer fetch
operations, flag operations, lock-free queries, dependency suppression, and
thread/signal fences, including every `_explicit` form. A weak compare-exchange
currently takes the permitted no-spurious-failure path. Compile-time memory
orders are checked against each operation's C11 constraints, including the
failure-order restrictions of compare-exchange. The in-order MDP memory path is
the ordering boundary; fences remain explicit `NOP` markers in the image, and
read-modify-write operations mask message dispatch across their complete
critical region. `atomic_is_lock_free` reports true for native one-word objects
and false for multiword aggregates. The `long long` atomic aliases remain tied
to the separately diagnosed, unimplemented `long long` scalar type.

Generic selection performs no runtime type dispatch. The compiler checks the
controlling expression and every association for semantic constraints, selects
exactly one compatible type or the single default at translation time, and
emits only the selected expression. Because the AST and code generator retain
the selected expression rather than prematurely replacing it with a value,
constructs such as assignment through `_Generic(...)` and
`&_Generic(...)` preserve the C11 lvalue rules.

Bit-field allocation is an explicit target ABI rule: each allocation unit is
one addressed 32-bit MDP word, fields are assigned from least-significant to
most-significant bit in declaration order, and a field that does not fit starts
the next word rather than straddling it. An unnamed zero-width field forces the
next allocation unit. Plain and explicitly signed `int` fields are signed;
unsigned and `_Bool` fields retain their respective semantics. Reads mask and
sign-extend as required, while assignment, prefix/postfix updates, and compound
assignments use a masked read-modify-write that preserves adjacent fields.
Positional/designated, static/automatic initialization merges all fields that
share a word in source order. The compiler enforces the C constraints on field
type and width and rejects address-taking, `sizeof`, `_Alignas`, and atomic
qualification on bit-fields.

Flexible array members use their element alignment and occupy no words in the
containing structure's `sizeof`; any padding required to reach the flexible
member's offset remains part of the prefix. They must be the named last member
of a structure with another named member. A structure containing one, and a
union containing such a structure recursively, cannot be embedded in another
structure or used as an array element. The incomplete member itself cannot be
initialized or passed to `sizeof`. Access through a cast from a larger backing
array preserves that array's MDP capability bounds, so subscripting the
trailing member checks the real allocated storage rather than inventing an
unbounded pointer.

The target threading ABI maps one C abstract thread to one physical MDP node.
File-scope and block-scope static `_Thread_local` objects therefore use the
same initialized node-local data placement as other static-duration objects,
but retain their distinct C storage-duration metadata and redeclaration rules.
All message-driven activations executing on one node belong to that node's C
thread and observe the same thread-local instances; an activation sent with
`function(args)@rank` observes the instances belonging to the destination
node. The current runtime does not provide a library API for creating multiple
C threads within a node.

The compiler diagnoses, rather than approximates, features that are outside
this source-language boundary. Notable remaining ISO C work includes floating
point, `long long`, variadic and old-style calls, variable-length arrays, and
preprocessing beyond object-like integer `#define` directives plus the
compiler-owned `<stdatomic.h>` include.

## Message-Driven C extension

Calls accept the historical placement suffix `function(arguments)@computer`.
The callee may be a direct function name or a runtime function-pointer value;
the latter decodes its non-null stored representation and sends the native
CALL-vector index in the same historical MDC function-identifier field.
Local aggregate calls use the complete ABI below. Remote aggregate parameters
are one logical MDC argument whose length is the complete object width and
whose data words preserve the tagged representation in order. Aggregate
results use caller-owned multiword FUT storage and a distinct multiword SET
handler. Packed bit-field aggregates use that same path: allocation-unit words
are transported unchanged, then field extraction and masked updates use the
declared layout on the receiver. Pointer-containing aggregates are rejected
because an MDP `ADDR` names node-local storage; explicit
`(int length, int *data)` marshalling remains the pointer-bearing transport
contract.

`--nodes N` emits a node-aware image with initialized priority queues and
bootstrap execution of `main` only on logical rank zero. Meshes larger than a
single 32-node X dimension also require `--mesh XxYxZ`; each dimension is
checked against the architectural NNR widths (5-bit X, 5-bit Y, 6-bit Z), and
the product must equal `N`. For example, the executable 512-node target uses
`--nodes 512 --mesh 8x8x8`.

The source language deliberately presents dense logical ranks: `computer()`
returns `x + X * (y + Y * z)`, and the operand of `call(...)@rank` uses that
same numbering. At the SEND boundary the compiler packs the destination as
`x | (y << 5) | (z << 10)`. Return routes carried inside MDC messages remain
physical NNR values, as required by the hardware network. This distinction
lets historical rank-arithmetic programs run unchanged while preserving the
published router encoding. Unless `--distributed-code` is selected, code and
initial data are replicated. The runtime uses the published MDC spawn envelope:

```text
0  MSG(spawn-handler, total-length)
1  function identifier
2  receiver temporary
3  return length (-1 for void)
4  return computer
5  return address
6  logical argument count
7  first argument length
8  first argument data...
```

Scalar arguments have length one. An aggregate argument has its exact
`wordSize`, followed by that many object-representation words. The historical `(int length, int *data)`
parameter pair is one logical argument: the sender emits its run-time length
and reads that many bounds-checked words directly from the source object, while
the receiving handler reconstructs the two C parameters and a bounds-tagged
node-local copy. Thus the eight-word example in Figures 4.2-4.3 is exactly a
sixteen-word message, including the header.

For a run-time bulk length, the caller computes the complete spawn-envelope
length before allocating a result mailbox or emitting any header or payload.
A negative bulk length or a total above QHL's 1020-word message limit enters
the resident `__mdc_argument_error` fail-stop handler: it stores `INT(1)` at
node-local address `0x0070d` and loops. No partial message is routed and the
remote callee is not entered. `remote_bulk_limit.c` checks this boundary in
both execution models; message fragmentation remains a distinct transport
feature rather than silently truncating the architectural ten-bit length.

A non-void scalar call allocates a tagged `FUT` mailbox in node-local memory; the
remote priority-0 spawn handler invokes the function through the architectural
CALL vector, and a priority-1 SET handler resolves the mailbox. Void calls
continue without waiting. A remote call assigned directly to an `int` object,
including an array element, initializes that object as `FUT` and continues;
generated reads force it only at its first use. Remote calls embedded in a
larger expression still materialize at the call boundary. Background `main`
uses a priority-preemptible poll. A message-driven process instead takes the
architectural FUT fault: the runtime saves its FIP, data/address registers,
stack offset, active message, and waiter link in its heap process header, links
that header into the future, and executes `SUSPEND`. The priority-1 SET handler
resolves the mailbox and emits priority-0 wake messages; the wake handler
restores the process and re-enters the faulting access. Distributed code
transport uses a priority-0 request to code-home node zero and priority-1
install messages back to the requester. Application words retain their linked
addresses as they are written into the node-local cache, and readiness is
published only after the final chunk and before the waiting spawn continues.
Chunks carry at
most 1016 code words: with the four-word install envelope this is the largest
four-word-aligned message representable by QHL's ten occupancy bits. The
installer waits for complete wormhole arrival before reading a chunk, and each
chunk is acknowledged before code home begins the next tail-delimited message.
Completed processes return their fixed 512-word stack blocks to a node-local
intrusive free list. Each copied bulk argument owns a fixed 1024-word block and
is returned through a separate free list only after the process finishes; a
suspended process retains both kinds of storage until wakeup and completion.

An aggregate result reserves one FUT word per result word in the caller's
destination or temporary buffer. The callee receives a bounded pointer to a
reclaimable result block through the same hidden slot-one convention as a
local aggregate call. It replies with this multiword envelope:

```text
0  MSG(aggregate-SET-handler, 3 + result-length)
1  return address
2  result length
3  first result word...
```

The priority-1 aggregate SET handler resolves every destination word and walks
each prior waiter list before any priority-0 process resumes. Consequently a
member access may suspend on one FUT while the eventual wake observes the
entire aggregate as resolved. The result payload is limited to 1017 words so
the header, destination, count, and payload fit the queue's 1020-word maximum.

Version 11 `READ` is legal on `FUT` (only `CFUT` faults on `READ`). Generated
forcing therefore first moves the tagged `FUT` and then executes exact `EQ`,
which architecturally faults on either future tag. The fault handler captures
MAR before its first memory access, saves FIP and the complete process context,
and records the event at `0x00708`. Maskit's recursive factorial example gives
a directed five-fault cascade rather than relying on a scheduling race.

The output FIFO retains the published SEND fault rather than turning a full
buffer into an invisible processor stall. Physical vector words `0x00043` and
`0x00063` enter the same unchecked, absolute-A0 handler for priority mappings
zero and one. On first entry it saves the original FIP, FIR, FOP0/FOP1, R0-R3,
and A1-A3 in a context-private frame; subsequent full-buffer faults preserve
that original image. The handler decodes the faulting instruction and retries
all four send opcodes at either output priority. A successful retry restores
the register image and continues at the instruction after the original send
with `LDIPR FIP`. Because `SENDE` and `SEND2E` clear the interrupt mask before
cleanup, background, priority-0, and priority-1 frames are deliberately
disjoint. `send_fault.c` and `bazel test //compiler:send_fault_rtl_test` force two retries in the
cycle-accurate RTL before releasing the blocked egress link.

## MDP ABI and image layout

| Resource | Compiler convention |
| --- | --- |
| `R0` | expression value and function result |
| `R1` | preserved temporary while evaluating operations and calls |
| `R2` | synthesized memory address or saved return IP |
| `R3` | current software-frame offset |
| `A0` | reserved runtime scratch; generated IPs use absolute-A0 addressing |
| `A1` | background stack at `0x04000`, or bounds-tagged heap process stack |
| `A2` | result mailbox, based at `0x00300` |
| `A3` | global arena, based at `0x00800` |
| `0x00700` | node-local process, bulk-data, and result heap bump pointer |
| `0x00701` | image-assigned packed X/Y/Z architectural NNR |
| `0x00702` | node-local free-list head for 512-word process blocks |
| `0x00703` | node-local free-list head for 1024-word bulk blocks |
| `0x00704` | node-local application-code cache-ready flag |
| `0x00705` | code-home request counter |
| `0x00706` | node-local installed-code-chunk counter |
| `0x00707` | code-home acknowledged-code-chunk counter |
| `0x00708` | node-local architectural FUT-fault counter |
| `0x00709` | node-local architectural SEND-fault entry/retry counter |
| `0x0070a..0x0070c` | priority-1 multiword SET destination/count/index scratch |
| `0x0070d` | node-local MDC argument-envelope runtime-error status |
| `0x00720..0x0072f` | background SEND retry frame |
| `0x00740..0x0074f` | priority-0 SEND retry frame |
| `0x00760..0x0076f` | priority-1 SEND retry frame |
| `0x080 + function-id` | architectural CALL-vector IP word |
| `0x01000..0x01fff` | compiler-protected instruction-image region |
| `0x20000..0x203ff` | priority-0 process-message queue |
| `0x21000..0x213ff` | priority-1 SET/reply queue |
| `0x30000...` | writable, node-local linked application-code section/cache |

Frame slot zero holds the architectural return IP. An aggregate-returning
function additionally receives an exact ADDR to caller-owned result storage in
slot one. Parameter objects then follow at their complete `wordSize`, followed
by lexical locals and compiler-proved scratch space. A call evaluates all
arguments into non-overlapping caller scratch objects before copying their full
representations into the callee's frame. Direct and indirect calls share this
layout; nested aggregate calls cannot alias a prior argument or return buffer.
The bootstrap
initializes the address registers, calls `main(void)`, and stores its tagged
result at physical word `0x00300` before entering a local halt loop.

Each incoming spawn receives an independent 512-word, bounds-tagged process
stack from the node heap or process free list. Process-header slots 32-41 hold
the precise suspended machine state and waiter linkage; slots 42 onward own the
bulk/input/result-block vector used by terminal reclamation. Low-memory vector `0x4d` points
to the priority-0 FUT fault handler; physical vectors `0x43` and `0x63` point
to the SEND retry handler for the two priority mappings. `reclamation.c` executes twenty sequential
bulk calls and checks in both simulators that the heap high-water mark remains
at the first call's `0x10600` endpoint.

`bazel test //compiler:mesh512_golden_test` compiles a 512-node image and runs a bulk remote call from
node 0 to node 511. The corresponding FPGA-facing structural configuration is
`rtl/j_machine_mesh_512.sv`, an 8 x 8 x 8 instance of the same parameterized
mesh used by smaller targets. Its distributed image deliberately leaves the
external application section unwritten and its ready flag clear on node 511;
the test checks that fetched code appears at `0x30000`, that
request/install/ack counters each advance once, and that the fetched function
returns the expected result. `bazel test //compiler:mesh512_rtl_test` runs the same image and end-state oracle on the complete
hierarchical 512-node RTL target; it currently stops at cycle 66,496.

`bazel test //compiler:historical_hop512_golden_test` compiles `historical_hop.c` as replicated broadcast
code and runs four complete tours of all 512 nodes (2,048 remote calls). It
checks four visits per node, the fifth terminal increment on node zero, and
representative observations at nodes 0, 256, and 511. The compact image has
2,051 common rows and 1,024 identity/state overrides, which the loader expands
to 1,051,136 writes. The two-node historical factorial, Hop, one-way producer,
two-way producer/future, and four-node Dirichlet images run in both the golden
model and Verilator as part of `bazel test //compiler:generated_tests`; the 512-node Hop oracle is
intentionally a separate long target.

Each generated instruction occupies the high 17-bit half of one tagged
instruction word and pairs with a low-half NOP. This is a valid Version 11
encoding and keeps source-level relocation and diagnostics one-to-one; packing
two scheduled instructions per word is a future optimization, not a different
ISA.

Signed division and non-power-of-two remainder use a fixed 32-step binary
long-division runtime. A positive, compile-time power-of-two remainder divisor
(including the pure `computers()` builtin) instead uses a sign-correct mask
lowering. Both paths handle the unsigned magnitude `0x80000000` in the MDP's
unchecked mode and restore checked execution, so `INT_MIN % 2^n` is implemented
without overflowing its signed magnitude. This avoids input-dependent repeated
subtraction and implements C truncation toward zero; division by zero and
`INT_MIN / -1` retain C's undefined behavior.

## Lean modules

| Module | Responsibility |
| --- | --- |
| `JMachineC/AST.lean` | source positions, diagnostics, and typed syntax tree |
| `JMachineC/Lexer.lean` | comments, literals, integer macros, and tokens |
| `JMachineC/Parser.lean` | declarations, statements, and precedence parser |
| `JMachineC/MDP.lean` | exact Version 11 tags, opcodes, operands, and words |
| `JMachineC/Codegen.lean` | validation, ABI lowering, relocation, image/listing output |
| `Main.lean` | `jmc` command-line driver |
| `Test.lean` | compiler-level encoding, recursion, control-flow, and diagnostic checks |
