import JMachineC

open JMachineC JMachineC.MDP

private def fail (message : String) : IO α := do
  IO.eprintln s!"JMC TEST FAIL: {message}"
  IO.Process.exit 1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do fail message

private def expectCompile (name source : String) : IO Compilation :=
  match compileC source name with
  | .ok compilation => pure compilation
  | .error error => fail s!"{name} did not compile: {error}"

private def factorialSource : String :=
  "int factorial(int n) {\n" ++
  "  if (n == 0) return 1;\n" ++
  "  return n * factorial(n - 1);\n" ++
  "}\n" ++
  "int main(void) { return factorial(6); }\n"

private def controlSource : String :=
  "#define LIMIT 10\n" ++
  "int total = 0;\n" ++
  "int main(void) {\n" ++
  "  int i = 0;\n" ++
  "  for (i = 0; i < LIMIT; i++) {\n" ++
  "    if (i == 5) continue;\n" ++
  "    total = total + i;\n" ++
  "  }\n" ++
  "  return total;\n" ++
  "}\n"

private def nestedCallsSource : String :=
  "int add2(int a, int b) { return a + b; }\n" ++
  "int main(void) { return add2(10, add2(20, 3)); }\n"

private def remoteSource : String :=
  "int remote_add(int a, int b) { return a + b + computer(); }\n" ++
  "int main(void) { return remote_add(20, 22)@1; }\n"

def main : IO Unit := do
  expect (instruction .add 2 1 (operandR 0) == 0x5c80)
    "MDP v11 ADD encoding changed"
  let factorial ← expectCompile "factorial.c" factorialSource
  expect (factorial.symbols.any fun entry => entry.1 == "factorial")
    "factorial symbol missing"
  expect (factorial.words.any fun word => word.address == 0x80)
    "CALL vector zero missing"
  let control ← expectCompile "control.c" controlSource
  expect (control.words.any fun word => word.address == 0x800 && word.value == integer 0)
    "global initializer missing"
  let conditionalUpdates ← expectCompile "conditional_updates.c"
    "int trace; int select(int x) { trace = trace * 10 + x; return x; } int main(void) { int a[3] = {10, 20, 30}; int i = 0; int old = a[i++]++; int prefix = ++a[i++]; int chosen = 1 ? select(3) : select(7); int nested = 0 ? 1 : 1 ? 5 : 9; int loop = 0; do { ++loop; if (loop == 2) continue; if (loop == 4) break; } while (loop < 10); int *p = a; ++p; int *z = 1 ? 0 : p; return old + prefix + chosen + nested + loop + i + *p + (z == 0); }"
  expect (conditionalUpdates.broadcastWords.any fun word =>
      word.annotation == "save update lvalue capability")
    "prefix/postfix update did not preserve a single evaluated lvalue"
  let compoundAssignments ← expectCompile "compound_assignments.c"
    "int main(void) { int values[2] = {20, 7}; int i = 0; values[i++] += 5; values[0] -= 3; values[0] *= 2; values[0] /= 4; values[0] %= 6; values[0] <<= 3; values[0] >>= 2; values[0] |= 5; values[0] ^= 3; values[0] &= 10; int *p = values; p += 2; p -= 1; return values[0] + *p + i; }"
  expect (compoundAssignments.broadcastWords.any fun word =>
      word.annotation == "save compound-assignment lvalue capability")
    "compound assignment did not preserve a single evaluated lvalue"
  expect (compoundAssignments.broadcastWords.any fun word =>
      word.annotation == "store compound-assignment result")
    "compound assignment did not store its converted result"
  expect (conditionalUpdates.symbols.any fun entry => entry.1.contains ".conditional.else")
    "conditional operator did not emit control-flow selection"
  expect (conditionalUpdates.symbols.any fun entry => entry.1.contains ".do.condition")
    "do-while loop did not emit its post-body condition"
  let declarationControl ← expectCompile "declaration_control.c"
    "int left = 2, right = 3; struct Pair { int x, y; }; int add(int a, int b), identity(int x); int add(int a, int b) { return a + b; } int identity(int x) { return x; } int tick(void) { static int a = 1, b = 2; a++; b += 2; return a * 10 + b; } int main(void) { int trace = 0, total = 0; int outer = 9; trace = (trace += 1, trace += 2, 7); total += add((trace += 4, 5), 6); for (int i = 0, j = 4; i < 4; i++, j--) { total += i * j; } total += outer; goto count; skipped: total = 1000; count: total += 1; if (total < 23) goto count; goto done; goto skipped; done: return left + right + trace + total + tick() + tick() + identity(0); }"
  expect (declarationControl.symbols.any fun entry =>
      entry.1.contains ".user-label" && entry.1.endsWith ".count")
    "source label was not lowered to a function-scoped code label"
  expect ((declarationControl.broadcastWords.countP fun word =>
      word.annotation.contains "global __jmc.static") == 2)
    "a multiple static-local declaration did not allocate both backing objects"
  let blockDeclarations ← expectCompile "block_declarations.c"
    "_Static_assert(8 * 8 * 8 == 512, \"mesh\"); int value = 7; int helper(int x) { return x + 1; } int storage(register int x) { _Static_assert(2 > 0, \"loop\"); auto int total = x; for (register int i = 0; i < 2; i++) total += i; return total; } int main(void) { int value = 100; int (*helper)(int) = 0; { extern int value; int helper(int), local = 2; return helper(value) + local + storage(3); } }"
  expect (blockDeclarations.symbols.any fun entry => entry.1 == "helper")
    "a block-scope function prototype did not resolve its external definition"
  discard <| expectCompile "unused_extern.c"
    "extern int missing_file_object; int main(void) { extern int missing_block_object; return 0; }"
  let alignment ← expectCompile "alignment.c"
    "int prefix = 1; struct Aligned { int head; _Alignas(8) int tail; }; _Alignas(16) int aligned = 2; _Static_assert(_Alignof(struct Aligned) == 8, \"aggregate alignment\"); int pass(struct Aligned value) { return value.head + value.tail; } int main(void) { struct Aligned value = {3, 4}; _Alignas(0) _Alignas(16) int local = 5; return _Alignof(struct Aligned) + sizeof(struct Aligned) + pass(value) + local; }"
  expect (alignment.broadcastWords.any fun word =>
      word.address == 0x810 && word.value == integer 2)
    "_Alignas did not insert global-storage padding"
  expect (alignment.broadcastWords.any fun word =>
      word.annotation == "_Alignof(type)" && word.value == integer 8)
    "_Alignof did not preserve an aggregate member's extended alignment"
  let atomics ← expectCompile "atomics.c"
    "int values[2] = {3, 4}; _Atomic int counter = 1; volatile _Atomic(unsigned int) flags = 2U; int * _Atomic cursor; int main(void) { _Atomic(int) local = 5; counter += 2; local++; cursor = values; cursor += 1; flags |= 4U; return counter + local + *cursor + flags; }"
  expect (atomics.broadcastWords.any fun word =>
      word.annotation == "enter seq_cst atomic critical section")
    "atomic read-modify-write did not mask message dispatch"
  expect (atomics.broadcastWords.any fun word =>
      word.annotation == "restore message-dispatch mask after seq_cst atomic operation")
    "atomic read-modify-write did not restore the prior message-dispatch mask"
  let atomicAggregates ← expectCompile "atomic_aggregates.c"
    "struct Pair { int x; int y; }; union Cell { int value; unsigned int bits; }; typedef _Atomic(struct Pair) AtomicPair; _Atomic(struct Pair) pair = {1, 2}; _Atomic struct Pair slots[2]; _Atomic(union Cell) cell = {3}; int main(void) { struct Pair first = pair; pair = (struct Pair){4, 5}; AtomicPair local = {6, 7}; struct Pair second = local; slots[1] = (struct Pair){8, 9}; struct Pair third = slots[1]; AtomicPair *pointer = &pair; struct Pair assigned = (*pointer = (struct Pair){10, 11}); struct Pair fourth = *pointer; cell = (union Cell){12}; union Cell fifth = cell; return first.x + first.y + second.x + second.y + third.x + third.y + assigned.x + assigned.y + fourth.x + fourth.y + fifth.value; }"
  expect (atomicAggregates.broadcastWords.any fun word =>
      word.annotation == "load atomic aggregate snapshot word")
    "atomic aggregate lvalue conversion did not materialize a masked snapshot"
  expect (atomicAggregates.broadcastWords.any fun word =>
      word.annotation == "store atomic aggregate word")
    "atomic aggregate assignment did not emit a masked whole-object store"
  expect (atomicAggregates.broadcastWords.any fun word =>
      word.annotation == "atomic aggregate target := A2")
    "atomic aggregate assignment did not preserve the exact target capability"
  let stdatomic ← expectCompile "stdatomic.c"
    "#include <stdatomic.h>\n#include <stdatomic.h>\nstruct Pair { int x; int y; }; typedef _Atomic(struct Pair) AtomicPair; atomic_int counter = ATOMIC_VAR_INIT(1); AtomicPair pair = {2, 3}; int main(void) { const atomic_int *read_only = &counter; int expected = 1; int score = atomic_load_explicit(read_only, memory_order_acquire); score += atomic_compare_exchange_strong_explicit(&counter, &expected, 4, memory_order_acq_rel, memory_order_acquire); score += atomic_fetch_add_explicit(&counter, 2, memory_order_relaxed); struct Pair old = atomic_exchange(&pair, (struct Pair){5, 6}); atomic_thread_fence(memory_order_seq_cst); return score + old.x + old.y + ATOMIC_INT_LOCK_FREE; }"
  expect (stdatomic.broadcastWords.any fun word =>
      word.annotation == "compare-exchange scalar mismatch")
    "<stdatomic.h> compare-exchange did not emit an exact scalar comparison"
  expect (stdatomic.broadcastWords.any fun word =>
      word.annotation == "atomic_fetch arithmetic modulo 2^32")
    "<stdatomic.h> fetch-add did not emit an atomic read-modify-write"
  expect (stdatomic.broadcastWords.any fun word =>
      word.annotation == "atomic_exchange store aggregate word")
    "<stdatomic.h> aggregate exchange did not emit a whole-object update"
  expect (stdatomic.broadcastWords.any fun word =>
      word.annotation == "atomic thread fence")
    "<stdatomic.h> thread fence was not preserved in the instruction stream"
  let genericSelection ← expectCompile "generic_selection.c"
    "struct Pair { int x; int y; }; int effects; int observe(void) { effects++; return 9; } int main(void) { int value = 3; unsigned int other = 4U; struct Pair pair = {5, 6}; _Generic(value, int: value, default: pair.x) = 7; int *selected = &_Generic(other, unsigned int: value, default: pair.y); ++*selected; return value + _Generic(value, int: 1, default: observe()) + _Generic(pair, struct Pair: pair.y, default: observe()) + _Generic(observe(), int: 2, default: 0) + effects; }"
  expect (genericSelection.broadcastWords.any fun word =>
      word.annotation == "store through C lvalue")
    "generic selection did not preserve the selected expression's lvalue category"
  expect (!genericSelection.broadcastWords.any fun word =>
      word.annotation == "call observe")
    "a generic controlling or unselected expression was evaluated"
  let bitFields ← expectCompile "bit_fields.c"
    "struct Bits { unsigned int low : 3; signed int delta : 5; unsigned int : 0; _Bool ready : 1; }; struct Bits bits = {5, -3, 1}; int main(void) { int prior = bits.low++; bits.delta += 2; _Generic(bits.low, unsigned int: bits.low, default: bits.ready) = 6; return sizeof(struct Bits) + prior + bits.low + bits.delta + bits.ready; }"
  expect (bitFields.broadcastWords.any fun word =>
      word.address == 0x800 && word.value == integer 0xed)
    "packed bit-field constant initialization did not merge adjacent fields"
  expect (bitFields.broadcastWords.any fun word =>
      word.annotation.contains "extract bit-field delta")
    "signed bit-field access did not emit extraction/sign extension"
  expect (bitFields.broadcastWords.any fun word =>
      word.annotation == "store through C bit-field lvalue")
    "bit-field assignment did not emit a masked read-modify-write"
  let flexibleArrays ← expectCompile "flexible_arrays.c"
    "struct Packet { int length; int payload[]; }; union Carrier { struct Packet packet; int word; }; int backing[4]; int main(void) { struct Packet header = {2}; struct Packet *packet = (struct Packet *)backing; packet->length = 3; packet->payload[0] = 4; packet->payload[1] = 5; packet->payload[2] = 6; return sizeof(struct Packet) + header.length + packet->payload[2] + (packet->payload - backing); }"
  expect (flexibleArrays.broadcastWords.any fun word =>
      word.annotation == "sizeof(type)" && word.value == integer 1)
    "sizeof a structure with a flexible array did not omit the array storage"
  expect (flexibleArrays.broadcastWords.any fun word =>
      word.annotation == "array member base")
    "flexible array member access did not preserve the backing capability"
  let threadLocal ← match compileCWithOptions
      "_Thread_local int counter = 3; static _Thread_local int total = 4; extern _Thread_local int counter; int update(int amount) { extern _Thread_local int counter; _Thread_local static int calls = 1; counter += amount; return counter + ++calls + total + computer(); } int main(void) { return update(2) + update(5)@1; }"
      "thread_local.c" { nodeCount := 2 } with
    | .ok compilation => pure compilation
    | .error error => fail s!"thread_local.c did not compile: {error}"
  expect ((threadLocal.broadcastWords.countP fun word =>
      word.annotation.contains "global __jmc.static") == 1)
    "a block-scope static _Thread_local object did not receive persistent backing storage"
  expect (threadLocal.words.any fun word => word.node == 1 && word.address == 0x800 &&
      word.value == integer 3)
    "a _Thread_local object's initializer was not replicated into node-local storage"
  let nested ← expectCompile "nested_calls.c" nestedCallsSource
  expect (nested.symbols.any fun entry => entry.1 == "add2")
    "nested-call callee symbol missing"
  let remote ← match compileCWithOptions remoteSource "remote.c" { nodeCount := 2 } with
    | .ok compilation => pure compilation
    | .error error => fail s!"remote.c did not compile: {error}"
  expect (remote.words.any fun word => word.node == 1)
    "two-node image did not contain node 1"
  expect (remote.words.any fun word => (word.value >>> 32) == Tag.msg.encoding)
    "remote call did not emit an MDP MSG header"
  let remoteFunctionPointer ←
    match compileCWithOptions
        "typedef int (*binary_fn)(int, int); int unused(int lhs, int rhs) { return lhs - rhs; } int remote_add(int lhs, int rhs) { return lhs + rhs + computer(); } int main(void) { binary_fn operation = remote_add; int result = operation(20, 22)@1; return result; }"
        "remote_function_pointer.c" { nodeCount := 2 } with
    | .ok compilation => pure compilation
    | .error error => fail s!"remote_function_pointer.c did not compile: {error}"
  expect (remoteFunctionPointer.broadcastWords.any fun word =>
      word.annotation == "encoded CALL vector index for remote_add" && word.value == integer 2)
    "remote function designator did not preserve its nonzero CALL-vector index"
  expect (remoteFunctionPointer.broadcastWords.any fun word =>
      word.annotation == "MDC function id")
    "remote indirect call did not send a runtime-selected MDC function id"
  expect (remote.symbols.any fun entry => entry.1 == "__mdc_spawn")
    "MDC spawn handler missing"
  expect (remote.symbols.any fun entry => entry.1 == "__mdc_code_install")
    "MDC distributed-code install handler missing"
  expect (remote.symbols.any fun entry => entry.1 == "__mdc_code_ack")
    "MDC distributed-code acknowledgement handler missing"
  expect (remote.symbols.any fun entry => entry.1 == "__mdc_send_fault")
    "MDC SEND fault handler missing"
  for address in [0x43, 0x63] do
    expect (remote.words.any fun word => word.node == 0 && word.address == address &&
        (word.value >>> 32) == Tag.ip.encoding &&
        ((word.value >>> 31) &&& 1) == 1 &&
        ((word.value >>> 30) &&& 1) == 0 &&
        ((word.value >>> 8) &&& 1) == 1)
      s!"unchecked absolute-A0 SEND fault vector 0x{toHex 2 address} is missing"
  expect ((remote.broadcastWords.countP fun word =>
      word.annotation.contains "retry faulting") == 8)
    "SEND retry handler does not contain all four opcodes at both priorities"
  expect (remote.words.any fun word => word.node == 0 && word.address == 0x709 &&
      word.value == integer 0)
    "node-local SEND-fault counter is missing"
  for address in [0x720, 0x740, 0x760] do
    expect (remote.words.any fun word => word.node == 0 && word.address == address &&
        word.value == integer 0)
      s!"SEND retry frame at 0x{toHex 3 address} was not initialized"
  expect (remote.applicationStart < remote.applicationEnd)
    "application-code placement range is empty"
  expect (remote.applicationStart == 0x30000)
    "application code is not linked at the external code-cache base"
  let remoteAddAddress ← match remote.symbols.find? fun entry => entry.1 == "remote_add" with
    | some entry => pure entry.2
    | none => fail "remote_add symbol missing"
  let spawnAddress ← match remote.symbols.find? fun entry => entry.1 == "__mdc_spawn" with
    | some entry => pure entry.2
    | none => fail "MDC spawn symbol missing"
  expect (remoteAddAddress >= remote.applicationStart &&
      remoteAddAddress < remote.applicationEnd)
    "application function was not linked into the external code section"
  expect (spawnAddress >= 0x1000 && spawnAddress < 0x2000)
    "resident MDC runtime handler escaped the protected code region"
  expect (remote.broadcastWords.any fun word =>
      word.annotation == "CALL vector for remote_add" &&
      word.value == instructionPointer false false remoteAddAddress false true)
    "remote_add CALL vector does not point directly at its linked cache address"
  expect (remote.words.any fun word => word.node == 1 && word.address == 0x704 &&
      word.value == integer 1)
    "replicated application code was not marked ready on node 1"
  let meshRemote ←
    match compileCWithOptions remoteSource "mesh-remote.c" {
        nodeCount := 8, meshX := 2, meshY := 2, meshZ := 2 } with
    | .ok compilation => pure compilation
    | .error error => fail s!"2x2x2 topology did not compile: {error}"
  expect (meshRemote.words.any fun word => word.node == 7 && word.address == 0x701 &&
      word.value == integer 0x421)
    "logical rank 7 did not map to packed NNR (1,1,1)"
  expect (meshRemote.broadcastWords.any fun word =>
      word.annotation.contains "construct packed MDP destination NNR")
    "remote logical-rank to physical-NNR lowering is missing"
  expect (meshRemote.broadcastWords.any fun word =>
      word.annotation.contains "construct dense logical node rank")
    "computer() physical-NNR to logical-rank lowering is missing"
  match compileCWithOptions remoteSource "ambiguous-topology.c" { nodeCount := 512 } with
  | .ok _ => fail "512-node compilation without an explicit mesh was accepted"
  | .error error =>
      expect (error.message.contains "explicit --mesh")
        "wrong diagnostic for a large node count without topology"
  let remoteDistributed ←
    match compileCWithOptions remoteSource "remote-distributed.c"
        { nodeCount := 2, codePlacement := .distributedHome } with
    | .ok compilation => pure compilation
    | .error error => fail s!"remote-distributed.c did not compile: {error}"
  expect (remoteDistributed.words.any fun word => word.node == 1 &&
      word.address == 0x704 && word.value == integer 0)
    "distributed application cache did not start empty on node 1"
  let distributed := distributedCodeImageText remoteDistributed
  expect (distributed.contains s!"0  {toHex 5 remoteDistributed.applicationStart}")
    "distributed image omitted code-home application word"
  expect (!distributed.contains s!"*  {toHex 5 remoteDistributed.applicationStart}")
    "distributed image incorrectly broadcast an application word"
  expect (distributed.contains "*  01000")
    "distributed image did not broadcast the bootstrap/runtime image"
  let division ← expectCompile "division.c"
    "int main(void) { return (100 / 7) + (-100 % 7) + (-100 % 8) + (100 % 8) + ((-2147483647 - 1) % 8); }"
  expect (division.broadcastWords.any fun word =>
      word.annotation.contains "power-of-two remainder mask")
    "power-of-two signed remainder lowering is missing"
  let integerTypes ← expectCompile "integer_types.c"
    "_Bool global = 9; unsigned int add(unsigned int a, unsigned int b) { return a + b; } _Bool truth(_Bool value) { return value; } unsigned long divide(unsigned long a, unsigned long b) { return a / b; } int main(void) { unsigned char c = (unsigned char)-1; signed short s = -2; unsigned int u = 0xffffffffU; unsigned long l = 0xffffffffUL; char p = -1; _Bool b = u; int *q = (int *)0; b = q; return (add(u, 2U) == 1U) + (divide(l, 05UL) == 858993459UL) + (u > 7U) + (u >> 31U) + (c + 2U == 1U) + (s < 0) + (p < 0) + truth(u) + global + b + sizeof(_Bool) + sizeof(char) + sizeof(short) + sizeof(long); }"
  expect (integerTypes.broadcastWords.any fun word =>
      word.annotation == "unsigned add modulo 2^32")
    "unsigned addition was not lowered through unchecked modulo arithmetic"
  expect (integerTypes.broadcastWords.any fun word =>
      word.annotation.contains "unsigned remainder >= divisor")
    "unsigned restoring division was not emitted"
  expect (integerTypes.broadcastWords.any fun word =>
      word.annotation == "unsigned integer comparison")
    "unsigned relational comparison lowering is missing"
  expect (integerTypes.broadcastWords.any fun word =>
      word.annotation == "normalize scalar to _Bool")
    "_Bool scalar normalization lowering is missing"
  let strings ← expectCompile "string_literals.c"
    "char *global = \"ab\" \"cd\"; char array[] = \"xyz\"; int numbers[] = {1, 2, 3}; int matrix[][2] = {1, 2, 3, 4}; int object; int *object_pointer = &object; int main(void) { static char exact[3] = \"cat\"; static char inferred[] = \"q\"; char local[] = \"hi\"; int local_numbers[] = {4, 5}; return global[3] + array[2] + local[2] + exact[2] + inferred[1] + numbers[2] + matrix[1][1] + local_numbers[1] + sizeof(\"ok\") + sizeof(array) + sizeof(local); }"
  expect (strings.broadcastWords.any fun word =>
      word.annotation.contains "__jmc.string" && word.value == integer 97)
    "narrow string storage did not preserve one character per MDP word"
  expect (strings.broadcastWords.any fun word =>
      word.annotation == "global global[0]" && (word.value >>> 32) == Tag.addr.encoding)
    "string designator did not relocate to an ADDR global initializer"
  expect (strings.broadcastWords.any fun word =>
      word.annotation == "global object_pointer[0]" && (word.value >>> 32) == Tag.addr.encoding)
    "object address constant did not relocate to an ADDR global initializer"
  let wideLiterals ← match compileCWithOptions
      "typedef int wchar_t; typedef unsigned short char16_t; typedef unsigned int char32_t; wchar_t wide[] = L\"A\\u03a9\\U0001f600\"; char16_t u16[] = u\"B\\u03a9\"; char32_t u32[] = U\"C\\U0001f600\"; char utf8[] = \"\\u03a9\" u8\"\"; int remote(wchar_t a, char16_t b, char32_t c) { return a + b + c + computer(); } int main(void) { return sizeof(wide) + sizeof(u16) + sizeof(u32) + sizeof(utf8) + ('AB' == 0x4142) + _Generic(L'A', int: 1, default: 0) + _Generic(u'B', unsigned short: 1, default: 0) + _Generic(U'C', unsigned int: 1, default: 0) + remote(L'A', u'B', U'C')@1; }"
      "wide_literals.c" { nodeCount := 2 } with
    | .ok compilation => pure compilation
    | .error error => fail s!"wide_literals.c did not compile: {error}"
  expect (wideLiterals.broadcastWords.any fun word =>
      word.annotation == "global wide[1]" && word.value == integer 0x3a9)
    "wide literal storage did not preserve a Unicode scalar word"
  expect (wideLiterals.broadcastWords.any fun word =>
      word.annotation == "global utf8[0]" && word.value == integer 0xce)
    "ordinary-plus-u8 concatenation was not encoded after prefix promotion"
  discard <| expectCompile "literal_line_splice.c"
    "int main(void) { return L'\\\nA' == L'A'; }"
  discard <| expectCompile "integer_declaration_specifiers.c"
    "typedef unsigned long word_t; unsigned const short global = 3; int accepts_plain(char value) { return value; } int accepts_signed(signed char value) { return value; } int main(void) { word_t value = 0xffffffffUL; return accepts_plain('A') + accepts_signed((signed char)'\\x41') + global + ('\\101' == 'A'); }"
  let generalSwitch ← expectCompile "switch.c"
    "int main(void) { int x = 0; switch (2) { case 1: x = 4; break; if (x == 0) { case 2: x = 7; break; } while (0) { case 3: x = 9; break; } break; default: x = x + 1; } switch (4) case 4: x += 2; return x; }"
  expect ((generalSwitch.symbols.countP fun entry =>
      entry.1.contains ".switch.case") == 4)
    "case labels nested in arbitrary switch statements were not collected"
  discard <| expectCompile "pointers.c"
    "int first(int *p) { return p[0]; } int main(void) { int a[2] = {7, 9}; int *p = a; *p = first(a); return sizeof(a) + p[0]; }"
  discard <| expectCompile "pointer_arithmetic.c"
    "int main(void) { int a[4] = {2, 4, 6, 8}; int *p = a; int *q = p + 3; q--; return *q + (q - p) + *(1 + p) + ((int *)0 == (int *)0); }"
  let nullPointerConversions ← expectCompile "null_pointer_conversions.c"
    "int *make_null(void) { return 0; } int is_null(int *pointer) { return !pointer; } int main(void) { int *pointer = 0; pointer = 0; return is_null(0) + !make_null(); }"
  expect ((nullPointerConversions.broadcastWords.countP fun word =>
      word.annotation == "null C pointer (invalid ADDR)") >= 4)
    "null object pointers were not converted at return, initialization, assignment, and argument boundaries"
  discard <| expectCompile "aggregates.c"
    "struct P { int x; int y; }; struct N { int value; struct N *next; }; int main(void) { struct P a[2]; struct P b; struct N n[2]; a[1].x = 7; b = a[1]; n[0].next = &n[1]; n[0].next->value = 11; return b.x + n[1].value + sizeof(struct P); }"
  let aggregateByValue ← expectCompile "aggregate_by_value.c"
    "struct P { int x; int y; }; typedef struct P P; typedef P (*combine_fn)(P, P); P add(P left, P right) { left.x = left.x + right.x; left.y = left.y + right.y; return left; } int main(void) { P a = {2, 3}; P b = {5, 7}; combine_fn combine = add; P c = combine(a, b); return add(c, a).x + c.y + a.x; }"
  expect (aggregateByValue.broadcastWords.any fun word =>
      word.annotation == "load aggregate argument word")
    "aggregate parameter staging did not copy full object words"
  expect (aggregateByValue.broadcastWords.any fun word =>
      word.annotation == "store aggregate return word")
    "caller-owned aggregate result ABI was not emitted"
  let compoundLiterals ← expectCompile "compound_literals.c"
    "struct P { int x; int y; }; struct Box { int value; int *pointer; }; int sum(struct P p) { return p.x + p.y; } int main(void) { struct Box box = {7}; struct P *p = &(struct P){2, 3}; int *q = &(int){4}; return !box.pointer + p->x + p->y + *q + (int[]){5, 6}[1] + sum((struct P){7, 8}) + (char[]){\"hi\"}[1]; }"
  expect (compoundLiterals.broadcastWords.any fun word =>
      word.annotation == "compound-literal lvalue base := A2")
    "compound literal did not allocate an addressable automatic object"
  expect (compoundLiterals.broadcastWords.any fun word =>
      word.annotation == "null C pointer (invalid ADDR)")
    "implicit pointer-subobject initialization did not construct an invalid ADDR null"
  let unevaluatedCompound ← expectCompile "unevaluated_compound_literal.c"
    "int side; int main(void) { return sizeof((int[3]){++side, 2, 3}) + side; }"
  expect (!unevaluatedCompound.broadcastWords.any fun word =>
      word.annotation == "save update lvalue capability")
    "sizeof evaluated a compound-literal initializer"
  let designatedInitializers ← expectCompile "designated_initializers.c"
    "struct P { int x; int y; }; struct O { struct P p; int z; }; int global[4] = {[2] = 7, 8, [0] = 1}; struct O object = {.z = 5, .p = {.y = 3, .x = 2}}; int main(void) { struct P local[2] = {[1] = {.y = 11, .x = 10}, [0] = {8, 9}}; struct P *literal = &(struct P){.y = 13, .x = 12}; return global[0] + global[2] + global[3] + object.p.x + object.p.y + object.z + local[0].x + local[0].y + local[1].x + local[1].y + literal->x + literal->y; }"
  expect (designatedInitializers.broadcastWords.any fun word =>
      word.annotation == "global global[2]" && word.value == integer 7)
    "global array designator did not select its exact subobject"
  expect (designatedInitializers.broadcastWords.any fun word =>
      word.annotation == "global object[1]" && word.value == integer 3)
    "nested structure designator did not select its exact member"
  let functionSpecifiers ← match compileCSourcesWithOptions #[
      ("int inline advance(int value) { return value + 1; } int inline static inline local_twice(int value) { return value * 2; } void _Noreturn fail_forever(void); void fail_forever(void) { for (;;) { } } int main(void) { return advance(20) + local_twice(10); }", "function_specifiers_main.c"),
      ("int advance(int value) { return value + 1; }", "function_specifiers_external.c") ] {} with
    | .error error => fail s!"function specifiers did not compile: {error}"
    | .ok compilation => pure compilation
  expect (functionSpecifiers.symbols.any fun entry =>
      entry.1 == "__jmc.inline.tu0.advance")
    "external inline definition was not kept translation-unit-local"
  expect (functionSpecifiers.symbols.any fun entry => entry.1 == "advance")
    "external definition corresponding to an inline definition is missing"
  expect (functionSpecifiers.symbols.any fun entry =>
      entry.1 == "__jmc.tu0.local_twice")
    "static inline function lost internal linkage"
  expect (functionSpecifiers.symbols.any fun entry =>
      entry.1 == "fail_forever.noreturn.fallthrough")
    "_Noreturn definition omitted its non-returning fallthrough trap"
  discard <| expectCompile "typedefs.c"
    "typedef int word_t, word_array_t[2]; typedef word_t *word_ptr_t; struct Pair { word_t x; word_t y; }; typedef struct Pair Pair; int sum(Pair *p) { return p->x + p->y; } int main(void) { word_array_t values = {7, 9}; word_ptr_t cursor = values; Pair pair; pair.x = cursor[0]; pair.y = cursor[1]; return sum(&pair) + sizeof(word_t) + (word_t)3; }"
  let functionPointers ← expectCompile "function_pointers.c"
    "typedef int (*binary_fn)(int, int); int add(int lhs, int rhs) { return lhs + rhs; } int subtract(int lhs, int rhs) { return lhs - rhs; } binary_fn global_operation = add; int apply(binary_fn operation, int lhs, int rhs) { return operation(lhs, rhs); } int main(void) { static binary_fn persistent_operation = subtract; binary_fn operation = global_operation; int first = apply(operation, 40, 2); operation = &subtract; return first + (*operation)(50, 8) + persistent_operation(60, 18); }"
  expect ((functionPointers.broadcastWords.countP fun word =>
      word.annotation == "indirect call through CALL vector index") == 3)
    "function-pointer calls did not lower to native indirect MDP CALL instructions"
  expect (functionPointers.broadcastWords.any fun word =>
      word.annotation == "encoded CALL vector index for subtract" && word.value == integer 2)
    "function designator 'subtract' did not lower to its non-null encoded CALL-vector index"
  expect (functionPointers.broadcastWords.any fun word =>
      word.annotation == "global global_operation[0]" && word.value == integer 1)
    "global function-pointer relocation did not resolve add's CALL-vector index"
  expect (functionPointers.broadcastWords.any fun word =>
      word.annotation.contains "persistent_operation" && word.value == integer 2)
    "static-local function-pointer relocation did not resolve subtract's CALL-vector index"
  discard <| expectCompile "recursive_function_declarators.c"
    "typedef int unary(int); unary increment; int increment(int value) { return value + 1; } typedef unary *unary_ptr; int main(void) { unary_ptr table[2] = {increment, &increment}; return ((int (*)(int))table[0])(4) + table[1](5) + (table[0] != 0) + sizeof(int (*)(int)); }"
  discard <| expectCompile "typedef_scope.c"
    "typedef int T; int main(void) { int T = 7; { typedef int T; T inner = 5; inner = inner + 1; } return T; }"
  discard <| expectCompile "qualifiers.c"
    "struct Pair { int x; int y; }; int sum(const int * restrict values) { return values[0] + values[1]; } int main(void) { const int values[2] = {4, 6}; volatile int counter = 2; int mutable[1] = {1}; int * const cursor = mutable; const struct Pair pair = {7, 8}; cursor[0] = cursor[0] + 2; counter = counter + 1; return sum(values) + pair.x + pair.y + cursor[0] + counter; }"
  discard <| expectCompile "qualified_typedef.c"
    "typedef int *IntPointer; struct P { int x; }; int identity(const int value); int identity(int value) { return value; } int main(void) { int value = 4; IntPointer const pointer = &value; struct P source = {3}; const struct P copy = source; return identity(*pointer) + copy.x; }"
  discard <| expectCompile "enums.c"
    "enum Flag { FLAG_ZERO, FLAG_START = 3, FLAG_MASK = (FLAG_START << 2) | 1, FLAG_NEGATIVE = -5, FLAG_HALF = FLAG_NEGATIVE / 2, FLAG_REMAINDER = FLAG_NEGATIVE % 2, FLAG_TRUTH = (FLAG_MASK > 10) && (FLAG_ZERO == 0), FLAG_SHORT_AND = 0 && (1 / 0), FLAG_SHORT_OR = 1 || (1 << 99) }; typedef enum Flag Flag; int global_mask = FLAG_MASK; int select(Flag flag) { int values[FLAG_TRUTH + 1] = {2, 7}; switch (flag) { case FLAG_MASK: return global_mask + values[1] + sizeof(enum Flag) + FLAG_HALF - FLAG_REMAINDER; default: return 0; } } int main(void) { Flag flag = FLAG_MASK; return select(flag); }"
  discard <| expectCompile "enum_scope.c"
    "enum { VALUE = 1 }; int main(void) { int VALUE = 4; { enum { VALUE = 7 }; int inner = VALUE; inner = inner + 1; } return VALUE; }"
  match compileCSourcesWithOptions #[
      ("extern int shared; int helper(int value); int main(void) { return helper(shared); }", "main.c"),
      ("int shared = 7; int helper(int value) { return value + 5; }", "library.c") ] {} with
  | .error error => fail s!"cross-file declarations/linkage did not compile: {error}"
  | .ok compilation =>
      expect (compilation.symbols.any fun entry => entry.1 == "helper")
        "linked helper symbol is missing"
  match compileCSourcesWithOptions #[
      ("static int value = 3; static int bump(void) { static int count = 4; count = count + 1; return value + count; } int library(void); int main(void) { int value = 100; return bump() + bump() + library() + value; }", "static-main.c"),
      ("static int value = 20; static int bump(void) { static int count = 1; count = count + 1; return value + count; } int library(void) { return bump(); }", "static-library.c") ] {} with
  | .error error => fail s!"internal linkage/static duration did not compile: {error}"
  | .ok compilation =>
      expect (compilation.symbols.any fun entry => entry.1 == "__jmc.tu0.bump")
        "translation-unit zero static function symbol is missing"
      expect (compilation.symbols.any fun entry => entry.1 == "__jmc.tu1.bump")
        "translation-unit one static function symbol is missing"
      expect ((compilation.broadcastWords.countP fun word =>
          word.annotation == "CALL vector for bump") == 2)
        "same-spelling static functions did not receive distinct CALL vectors"
  let inheritedStaticFunction ← expectCompile "inherited_static_function.c"
    "static int helper(void); int helper(void) { return 7; } int main(void) { return helper(); }"
  expect (inheritedStaticFunction.symbols.any fun entry =>
      entry.1 == "__jmc.tu0.helper")
    "a function definition did not inherit internal linkage from its prototype"
  let inheritedStaticObject ← expectCompile "inherited_static_object.c"
    "static int value; extern int value; int main(void) { return value; }"
  expect ((inheritedStaticObject.broadcastWords.countP fun word =>
      word.annotation == "global value[0]") == 1)
    "an extern redeclaration did not coalesce with its prior internal-linkage object"
  let tentativeStatic ← expectCompile "tentative_static.c"
    "static int value = 9; static int value; static int value; int main(void) { return value; }"
  expect ((tentativeStatic.broadcastWords.countP fun word =>
      word.annotation == "global value[0]" && word.value == integer 9) == 1)
    "tentative static declarations did not coalesce with the initialized definition"
  match compileC "int main(void) { return missing; }" "bad.c" with
  | .ok _ => fail "undeclared identifier did not produce a diagnostic"
  | .error error => expect (error.pos.line == 1) "diagnostic lost source position"
  for (name, source, diagnostic) in [
      ("static_main.c", "static int main(void) { return 0; }", "external linkage"),
      ("linkage_conflict.c", "extern int value; static int value = 1; int main(void) { return value; }", "conflicting linkage"),
      ("duplicate_initialized_static.c", "static int value = 1; static int value = 2; int main(void) { return value; }", "duplicate initialized"),
      ("dynamic_static.c", "int seed = 1; int main(void) { static int value = seed; return value; }", "enumerator constant"),
      ("block_static_function.c", "int main(void) { static int helper(void); return 0; }", "static function") ] do
    match compileC source name with
    | .ok _ => fail s!"{name} accepted an invalid static declaration"
    | .error error =>
        expect (error.message.contains diagnostic)
          s!"{name} produced the wrong static/linkage diagnostic"
  for (name, source, diagnostic) in [
      ("call_object.c", "int main(void) { int value = 0; return value(); }", "not a function pointer"),
      ("function_pointer_arity.c", "typedef int (*unary_fn)(int); int identity(int value) { return value; } int main(void) { unary_fn fn = identity; return fn(1, 2); }", "expects 1 arguments"),
      ("function_pointer_assignment.c", "typedef int (*unary_fn)(int); int sum(int lhs, int rhs) { return lhs + rhs; } int main(void) { unary_fn fn = sum; return 0; }", "incompatible types"),
      ("global_function_pointer_assignment.c", "typedef int (*unary_fn)(int); int sum(int lhs, int rhs) { return lhs + rhs; } unary_fn fn = sum; int main(void) { return 0; }", "incompatible initializer"),
      ("function_pointer_arithmetic.c", "typedef int (*unary_fn)(int); int identity(int value) { return value; } int main(void) { unary_fn fn = identity; fn++; return 0; }", "pointer to an object type"),
      ("array_of_functions.c", "typedef int invalid_table[2](int); int main(void) { return 0; }", "array element type") ] do
    match compileC source name with
    | .ok _ => fail s!"{name} accepted an invalid function-pointer construct"
    | .error error =>
        expect (error.message.contains diagnostic)
          s!"{name} produced the wrong function-pointer diagnostic: {error.message}"
  for (name, source, diagnostic) in [
      ("prefix_rvalue.c", "int main(void) { return ++1; }", "not an lvalue"),
      ("compound_pointer.c", "int main(void) { int value = 1; int *p = &value; p *= 2; return 0; }", "integer operands"),
      ("compound_const.c", "int main(void) { const int value = 1; value += 2; return value; }", "const-qualified"),
      ("conditional_condition.c", "struct P { int x; }; int main(void) { struct P p; return p ? 1 : 2; }", "scalar condition"),
      ("conditional_aggregate.c", "struct P { int x; }; struct Q { int x; }; int main(void) { struct P p; struct Q q; return (1 ? p : q).x; }", "incompatible types") ] do
    match compileC source name with
    | .ok _ => fail s!"{name} accepted an invalid conditional/update construct"
    | .error error =>
        expect (error.message.contains diagnostic)
          s!"{name} produced the wrong conditional/update diagnostic: {error.message}"
  for (name, source, diagnostic) in [
      ("duplicate_label.c", "int main(void) { same: ; same: return 0; }", "duplicate label"),
      ("undefined_goto.c", "int main(void) { goto missing; return 0; }", "undefined label"),
      ("for_scope.c", "int main(void) { for (int i = 0; i < 1; i++) { } return i; }", "undeclared identifier"),
      ("comma_lvalue.c", "int main(void) { int a = 0, b = 0; (a, b) = 1; return b; }", "not an lvalue"),
      ("definition_list.c", "int first(void), second(void) { return 0; } int main(void) { return 0; }", "function definition"),
      ("case_outside_switch.c", "int main(void) { case 1: return 0; }", "not within a switch"),
      ("default_outside_switch.c", "int main(void) { default: return 0; }", "not within a switch"),
      ("duplicate_switch_case.c", "int main(void) { switch (0) { case 1: ; case 1: ; } return 0; }", "duplicate switch case"),
      ("duplicate_switch_default.c", "int main(void) { switch (0) { default: ; default: ; } return 0; }", "multiple default"),
      ("for_function_declaration.c", "int helper(void) { return 1; } int main(void) { for (int helper(void); 0; ) { } return 0; }", "only objects"),
      ("extern_initializer.c", "int value; int main(void) { extern int value = 2; return value; }", "cannot have an initializer"),
      ("conflicting_block_prototype.c", "int helper(int value) { return value; } int main(void) { int helper(unsigned int); return 0; }", "does not match its definition"),
      ("undefined_block_extern.c", "int main(void) { extern int missing; return missing; }", "undefined external global") ] do
    match compileC source name with
    | .ok _ => fail s!"{name} accepted an invalid declaration/control construct"
    | .error error =>
        expect (error.message.contains diagnostic)
          s!"{name} produced the wrong declaration/control diagnostic: {error.message}"
  for (name, source) in [
      ("register_address.c", "int main(void) { register int value = 1; return *&value; }"),
      ("register_parameter_address.c", "int read(register int value) { return *&value; } int main(void) { return read(1); }") ] do
    match compileC source name with
    | .ok _ => fail s!"{name} took the address of a register object"
    | .error error =>
        expect (error.message.contains "address of register object")
          s!"{name} produced the wrong register-address diagnostic"
  for (name, source, diagnostic) in [
      ("alignas_non_power.c", "_Alignas(3) int value; int main(void) { return 0; }", "power of two"),
      ("alignas_limit.c", "_Alignas(128) int value; int main(void) { return 0; }", "above 64 words"),
      ("alignas_function.c", "_Alignas(8) int helper(void); int main(void) { return 0; }", "function declaration"),
      ("alignas_typedef.c", "_Alignas(8) typedef int aligned_int; int main(void) { return 0; }", "typedef declaration"),
      ("alignas_register.c", "int main(void) { _Alignas(8) register int value; return 0; }", "register object"),
      ("alignas_parameter.c", "int helper(_Alignas(8) int value) { return value; } int main(void) { return 0; }", "parameter declaration"),
      ("alignas_missing_definition.c", "extern _Alignas(8) int value; int value = 1; int main(void) { return value; }", "has no alignment specifier"),
      ("alignas_conflict.c", "_Alignas(8) int value = 1; extern _Alignas(16) int value; int main(void) { return value; }", "conflicting alignment"),
      ("alignof_void.c", "int main(void) { return _Alignof(void); }", "complete object type") ] do
    match compileC source name with
    | .ok _ => fail s!"{name} accepted an invalid alignment construct"
    | .error error =>
        expect (error.message.contains diagnostic)
          s!"{name} produced the wrong alignment diagnostic: {error.message}"
  for (name, source, diagnostic) in [
      ("atomic_array.c", "_Atomic(int[2]) values; int main(void) { return 0; }", "unqualified non-array object type"),
      ("atomic_const.c", "_Atomic(const int) value; int main(void) { return 0; }", "unqualified non-array object type"),
      ("atomic_nested.c", "_Atomic(_Atomic int) value; int main(void) { return 0; }", "unqualified non-array object type"),
      ("atomic_void.c", "_Atomic(void) value; int main(void) { return 0; }", "complete object type"),
      ("atomic_function.c", "_Atomic(int (int)) function; int main(void) { return 0; }", "unqualified non-array object type"),
      ("atomic_qualifier_drop.c", "int main(void) { _Atomic int value = 1; int *pointer = &value; return *pointer; }", "incompatible"),
      ("atomic_store_acquire.c", "#include <stdatomic.h>\natomic_int value; int main(void) { atomic_store_explicit(&value, 1, 2); return 0; }", "invalid memory_order"),
      ("atomic_load_release.c", "#include <stdatomic.h>\natomic_int value; int main(void) { return atomic_load_explicit(&value, 3); }", "invalid memory_order"),
      ("atomic_compare_failure_release.c", "#include <stdatomic.h>\natomic_int value; int main(void) { int expected = 0; return atomic_compare_exchange_strong_explicit(&value, &expected, 1, 5, 3); }", "invalid memory_order"),
      ("atomic_compare_failure_stronger.c", "#include <stdatomic.h>\natomic_int value; int main(void) { int expected = 0; return atomic_compare_exchange_strong_explicit(&value, &expected, 1, 3, 2); }", "stronger than success"),
      ("atomic_fetch_bool.c", "#include <stdatomic.h>\natomic_bool value; int main(void) { return atomic_fetch_add(&value, 1); }", "non-_Bool integer or pointer"),
      ("atomic_flag_type.c", "#include <stdatomic.h>\natomic_int value; int main(void) { return atomic_flag_test_and_set(&value); }", "requires atomic_flag"),
      ("atomic_non_atomic_pointer.c", "#include <stdatomic.h>\nint value; int main(void) { return atomic_load(&value); }", "must point to an atomic object"),
      ("atomic_const_store.c", "#include <stdatomic.h>\nconst atomic_int value = 1; int main(void) { atomic_store(&value, 2); return 0; }", "const-qualified atomic object"),
      ("atomic_const_expected.c", "#include <stdatomic.h>\natomic_int value; int main(void) { const int expected = 0; return atomic_compare_exchange_strong(&value, &expected, 1); }", "const-qualified expected value"),
      ("unsupported_header.c", "#include <stddef.h>\nint main(void) { return 0; }", "unsupported system header") ] do
    match compileC source name with
    | .ok _ => fail s!"{name} accepted an invalid atomic construct"
    | .error error =>
        expect (error.message.contains diagnostic)
          s!"{name} produced the wrong atomic diagnostic: {error.message}"
  for (name, source, diagnostic) in [
      ("generic_duplicate_type.c", "int main(void) { return _Generic(1, int: 1, signed int: 2); }", "duplicate types"),
      ("generic_duplicate_default.c", "int main(void) { return _Generic(1, default: 1, default: 2); }", "only one default"),
      ("generic_void_type.c", "int main(void) { return _Generic(1, void: 1, default: 2); }", "complete object type"),
      ("generic_named_type.c", "int main(void) { return _Generic(1, int named: 1, default: 2); }", "type name, not a named declarator"),
      ("generic_no_match.c", "int main(void) { unsigned int value = 1U; return _Generic(value, int: 1); }", "not compatible with any generic association"),
      ("generic_unselected_constraint.c", "int main(void) { return _Generic(1, int: 2, default: missing); }", "undeclared identifier"),
      ("generic_unselected_call.c", "int helper(void) { return 1; } int main(void) { return _Generic(1, int: 2, default: helper(1)); }", "expects 0 arguments") ] do
    match compileC source name with
    | .ok _ => fail s!"{name} accepted an invalid generic selection"
    | .error error =>
        expect (error.message.contains diagnostic)
          s!"{name} produced the wrong generic-selection diagnostic: {error.message}"
  for (name, source, diagnostic) in [
      ("bitfield_negative_width.c", "struct Bits { int value : -1; }; int main(void) { return 0; }", "nonnegative"),
      ("bitfield_int_width.c", "struct Bits { int value : 33; }; int main(void) { return 0; }", "exceeds its 32-bit type"),
      ("bitfield_bool_width.c", "struct Bits { _Bool value : 2; }; int main(void) { return 0; }", "exceeds its 1-bit type"),
      ("bitfield_named_zero.c", "struct Bits { int value : 0; }; int main(void) { return 0; }", "must be unnamed"),
      ("bitfield_pointer.c", "struct Bits { int *value : 3; }; int main(void) { return 0; }", "must have type _Bool, signed int, or unsigned int"),
      ("bitfield_alignas.c", "struct Bits { _Alignas(2) int value : 3; }; int main(void) { return 0; }", "may not be applied to a bit-field"),
      ("bitfield_atomic.c", "struct Bits { _Atomic int value : 3; }; int main(void) { return 0; }", "atomic type may not be used"),
      ("bitfield_no_named_member.c", "struct Bits { unsigned int : 3; unsigned int : 0; }; int main(void) { return 0; }", "requires a named member"),
      ("bitfield_address.c", "struct Bits { unsigned int value : 3; }; int main(void) { struct Bits bits = {1}; return *&bits.value; }", "address of a bit-field"),
      ("bitfield_sizeof.c", "struct Bits { unsigned int value : 3; }; int main(void) { struct Bits bits = {1}; return sizeof(bits.value); }", "sizeof may not be applied to a bit-field") ] do
    match compileC source name with
    | .ok _ => fail s!"{name} accepted an invalid bit-field construct"
    | .error error =>
        expect (error.message.contains diagnostic)
          s!"{name} produced the wrong bit-field diagnostic: {error.message}"
  for (name, source, diagnostic) in [
      ("flexible_union.c", "union Bad { int data[]; int word; }; int main(void) { return 0; }", "only in a structure"),
      ("flexible_only_member.c", "struct Bad { int data[]; }; int main(void) { return 0; }", "requires another named member"),
      ("flexible_not_last.c", "struct Bad { int count; int data[]; int tail; }; int main(void) { return 0; }", "must be the last member"),
      ("flexible_same_declaration.c", "struct Bad { int count; int data[], tail; }; int main(void) { return 0; }", "must be the last member"),
      ("flexible_array_element.c", "struct Packet { int count; int data[]; }; struct Packet packets[2]; int main(void) { return 0; }", "array element type may not contain"),
      ("flexible_struct_member.c", "struct Packet { int count; int data[]; }; struct Bad { int tag; struct Packet packet; }; int main(void) { return 0; }", "structure member type may not contain"),
      ("flexible_recursive_union_member.c", "struct Packet { int count; int data[]; }; union Carrier { struct Packet packet; int word; }; struct Bad { int tag; union Carrier carrier; }; int main(void) { return 0; }", "structure member type may not contain"),
      ("flexible_initializer.c", "struct Packet { int count; int data[]; }; struct Packet packet = {1, 2}; int main(void) { return 0; }", "too many initializers"),
      ("flexible_sizeof_member.c", "struct Packet { int count; int data[]; }; int main(void) { int backing[2]; struct Packet *packet = (struct Packet *)backing; return sizeof(packet->data); }", "complete object type") ] do
    match compileC source name with
    | .ok _ => fail s!"{name} accepted an invalid flexible-array construct"
    | .error error =>
        expect (error.message.contains diagnostic)
          s!"{name} produced the wrong flexible-array diagnostic: {error.message}"
  for (name, source, diagnostic) in [
      ("thread_local_duplicate.c", "_Thread_local _Thread_local int value; int main(void) { return 0; }", "duplicate '_Thread_local'"),
      ("thread_local_typedef.c", "_Thread_local typedef int value_type; int main(void) { return 0; }", "may not be combined with 'typedef'"),
      ("thread_local_block.c", "int main(void) { _Thread_local int value; return 0; }", "requires 'static' or 'extern'"),
      ("thread_local_auto.c", "int main(void) { _Thread_local auto int value; return 0; }", "requires 'static' or 'extern'"),
      ("thread_local_register.c", "int main(void) { register _Thread_local int value; return 0; }", "requires 'static' or 'extern'"),
      ("thread_local_function.c", "_Thread_local int helper(void); int main(void) { return 0; }", "may not be applied to a function"),
      ("thread_local_member.c", "struct Bad { _Thread_local int value; }; int main(void) { return 0; }", "member may not be declared '_Thread_local'"),
      ("thread_local_parameter.c", "int helper(_Thread_local int value) { return value; } int main(void) { return 0; }", "parameter declaration"),
      ("thread_local_mismatch.c", "_Thread_local int value; extern int value; int main(void) { return value; }", "disagree on '_Thread_local'"),
      ("thread_local_block_mismatch.c", "int value; int main(void) { extern _Thread_local int value; return value; }", "disagree on '_Thread_local'") ] do
    match compileC source name with
    | .ok _ => fail s!"{name} accepted an invalid _Thread_local construct"
    | .error error =>
        expect (error.message.contains diagnostic)
          s!"{name} produced the wrong _Thread_local diagnostic: {error.message}"
  match compileC "_Static_assert(0, \"node count must be nonzero\"); int main(void) { return 0; }"
      "static_assert.c" with
  | .ok _ => fail "a failing _Static_assert was accepted"
  | .error error =>
      expect (error.message.contains "node count must be nonzero")
        "a failing _Static_assert lost its diagnostic message"
  for (name, source, diagnostic) in [
      ("conflicting_integer_prototype.c", "unsigned int f(unsigned int); int f(int); int main(void) { return 0; }", "conflicting declarations"),
      ("plain_signed_char_prototype.c", "int f(char); int f(signed char); int main(void) { return 0; }", "conflicting declarations"),
      ("bool_int_prototype.c", "int f(_Bool); int f(int); int main(void) { return 0; }", "conflicting declarations"),
      ("signed_bool.c", "signed _Bool value; int main(void) { return 0; }", "_Bool"),
      ("unsigned_bool.c", "_Bool unsigned value; int main(void) { return 0; }", "_Bool"),
      ("bool_int.c", "_Bool int value; int main(void) { return 0; }", "_Bool"),
      ("duplicate_signedness.c", "unsigned signed int value; int main(void) { return 0; }", "signedness"),
      ("char_int.c", "char int value; int main(void) { return 0; }", "cannot be combined"),
      ("long_long.c", "long long value; int main(void) { return 0; }", "long long"),
      ("long_long_literal.c", "int main(void) { return 1LL; }", "long long"),
      ("invalid_integer_suffix.c", "int main(void) { return 1ULU; }", "suffix"),
      ("invalid_octal.c", "int main(void) { return 09; }", "invalid digit"),
      ("wide_decimal_literal.c", "int main(void) { return 4294967295; }", "long long"),
      ("incompatible_integer_pointer.c", "int main(void) { int value = 0; unsigned int *pointer = &value; return 0; }", "incompatible types") ] do
    match compileC source name with
    | .ok _ => fail s!"{name} accepted an invalid integer-type construct"
    | .error error =>
        expect (error.message.contains diagnostic)
          s!"{name} produced the wrong integer-type diagnostic: {error.message}"
  for (name, source, diagnostic) in [
      ("unterminated_string.c", "int main(void) { char *p = \"missing; return 0; }", "unterminated string"),
      ("unknown_string_escape.c", "int main(void) { char *p = \"\\q\"; return 0; }", "unknown character escape"),
      ("long_string_initializer.c", "char value[2] = \"abc\"; int main(void) { return 0; }", "too long"),
      ("uninferred_array.c", "char value[]; int main(void) { return 0; }", "complete object type"),
      ("empty_inferred_array.c", "int value[] = {}; int main(void) { return 0; }", "cannot infer an array bound"),
      ("incompatible_string_pointer.c", "int *value = \"abc\"; int main(void) { return 0; }", "incompatible address initializer") ] do
    match compileC source name with
    | .ok _ => fail s!"{name} accepted an invalid string construct"
    | .error error =>
        expect (error.message.contains diagnostic)
          s!"{name} produced the wrong string diagnostic: {error.message}"
  for (name, source, diagnostic) in [
      ("utf8_character.c", "int main(void) { return u8'A'; }", "does not permit the u8 prefix"),
      ("ucn_basic_character.c", "int main(void) { return L'\\u0061'; }", "below U+00A0"),
      ("ucn_surrogate.c", "int main(void) { return U'\\uD800'; }", "Unicode scalar value"),
      ("ucn_out_of_range.c", "int main(void) { return U'\\U00110000'; }", "Unicode scalar value"),
      ("ucn_short.c", "int main(void) { int *p = L\"\\u123\"; return 0; }", "exactly 4 hexadecimal digits"),
      ("wide_utf8_concat.c", "int main(void) { return sizeof(L\"a\" u8\"b\"); }", "may not combine UTF-8 and wide"),
      ("different_wide_concat.c", "int main(void) { return sizeof(u\"a\" U\"b\"); }", "does not concatenate differently-prefixed"),
      ("wide_array_mismatch.c", "char value[] = L\"x\"; int main(void) { return 0; }", "requires an array with compatible element type"),
      ("utf16_array_mismatch.c", "unsigned int value[] = u\"x\"; int main(void) { return 0; }", "requires an array with compatible element type"),
      ("wide_pointer_mismatch.c", "char *value = L\"x\"; int main(void) { return 0; }", "incompatible"),
      ("wide_escape_overflow.c", "unsigned int value[] = U\"\\x100000000\"; int main(void) { return 0; }", "exceeds its 32-bit element type") ] do
    match compileC source name with
    | .ok _ => fail s!"{name} accepted an invalid encoded literal"
    | .error error =>
        expect (error.message.contains diagnostic)
          s!"{name} produced the wrong encoded-literal diagnostic: {error.message}"
  match compileCSourcesWithOptions #[
      ("int hidden(void); int main(void) { return hidden(); }", "caller.c"),
      ("static int hidden(void) { return 7; }", "owner.c") ] {} with
  | .ok _ => fail "a static function was resolved from another translation unit"
  | .error error =>
      expect (error.message.contains "undefined function")
        "wrong cross-translation-unit static visibility diagnostic"
  match compileC
      "int same(int value) { int value = 2; return value; } int main(void) { return 0; }"
      "scope.c" with
  | .ok _ => fail "outer block redeclaration of a parameter was accepted"
  | .error error => expect (error.message.contains "redeclaration") "wrong scope diagnostic"
  match compileC
      "int same(int value, int value) { return value; } int main(void) { return 0; }"
      "parameters.c" with
  | .ok _ => fail "duplicate parameter names were accepted"
  | .error error =>
      expect (error.message.contains "duplicate parameter")
        "wrong duplicate-parameter diagnostic"
  match compileC "typedef int T; int T; int main(void) { return 0; }"
      "typedef_conflict.c" with
  | .ok _ => fail "ordinary identifier redeclared a typedef in the same scope"
  | .error error =>
      expect (error.message.contains "ordinary identifier")
        "wrong typedef/ordinary namespace diagnostic"
  match compileC "typedef int T; typedef int *T; int main(void) { return 0; }"
      "typedef_redefinition.c" with
  | .ok _ => fail "conflicting typedef declarations were accepted"
  | .error error =>
      expect (error.message.contains "conflicting typedef")
        "wrong conflicting-typedef diagnostic"
  for (name, source) in [
      ("const_object.c", "int main(void) { const int value = 1; value = 2; return value; }"),
      ("const_element.c", "int main(void) { const int values[1] = {1}; values[0] = 2; return values[0]; }"),
      ("const_member.c", "struct P { int x; }; int main(void) { struct P value; const struct P *pointer = &value; pointer->x = 2; return 0; }"),
      ("const_compound_member.c", "struct P { int x; }; int main(void) { ((const struct P){1}).x = 2; return 0; }"),
      ("const_pointer.c", "int main(void) { int value = 1; int * const pointer = &value; pointer++; return value; }") ] do
    match compileC source name with
    | .ok _ => fail s!"{name} modified a const-qualified lvalue"
    | .error error =>
        expect (error.message.contains "const-qualified")
          s!"{name} produced the wrong const diagnostic"
  match compileC "int main(void) { return sizeof(void); }" "sizeof_void.c" with
  | .ok _ => fail "sizeof(void) was accepted"
  | .error error =>
      expect (error.message.contains "complete object type")
        "sizeof(void) produced the wrong diagnostic"
  for (name, source, diagnostic) in [
      ("negative_designator.c", "int a[2] = {[-1] = 1}; int main(void) { return 0; }", "nonnegative"),
      ("large_designator.c", "int a[2] = {[2] = 1}; int main(void) { return 0; }", "outside bound"),
      ("member_on_array.c", "int a[2] = {.x = 1}; int main(void) { return 0; }", "member access requires"),
      ("index_on_struct.c", "struct P { int x; }; struct P p = {[0] = 1}; int main(void) { return 0; }", "array designator requires"),
      ("excess_nested_initializer.c", "struct P { int x; }; struct P p = {1, 2}; int main(void) { return 0; }", "too many initializers") ] do
    match compileC source name with
    | .ok _ => fail s!"{name} accepted an invalid initializer designator"
    | .error error =>
        expect (error.message.contains diagnostic)
          s!"{name} produced the wrong initializer diagnostic: {error.message}"
  for (name, source, diagnostic) in [
      ("inline_object.c", "inline int value; int main(void) { return 0; }", "only in a function declaration"),
      ("inline_typedef.c", "inline typedef int value_t; int main(void) { return 0; }", "typedef declaration"),
      ("inline_main.c", "inline int main(void) { return 0; }", "not permitted on main"),
      ("inline_without_definition.c", "inline int helper(int); int main(void) { return 0; }", "same translation unit"),
      ("inline_internal_object.c", "static int hidden; inline int helper(void) { return hidden; } int main(void) { return 0; }", "internal-linkage object"),
      ("inline_internal_function.c", "static int hidden(void) { return 1; } inline int helper(void) { return hidden(); } int main(void) { return 0; }", "internal-linkage function"),
      ("inline_modifiable_static.c", "inline int helper(void) { static int state; return state; } int main(void) { return 0; }", "modifiable static object"),
      ("noreturn_return.c", "_Noreturn void stop(void) { return; } int main(void) { return 0; }", "contains a return statement") ] do
    match compileC source name with
    | .ok _ => fail s!"{name} accepted an invalid function specifier use"
    | .error error =>
        expect (error.message.contains diagnostic)
          s!"{name} produced the wrong function-specifier diagnostic: {error.message}"
  match compileCSourcesWithOptions #[
      ("inline int allowed(void) { static const int value = 7; return value; } int main(void) { return allowed(); }", "inline_const_main.c"),
      ("int allowed(void) { return 7; }", "inline_const_external.c") ] {} with
  | .error error => fail s!"const static object in inline definition was rejected: {error}"
  | .ok _ => pure ()
  match compileC "int main(void) { restrict int value = 1; return value; }"
      "invalid_restrict.c" with
  | .ok _ => fail "restrict-qualified non-pointer type was accepted"
  | .error error =>
      expect (error.message.contains "pointer type")
        "wrong restrict constraint diagnostic"
  for (name, source) in [
      ("drop_const_initializer.c", "int main(void) { int value = 1; const int *source = &value; int *target = source; return *target; }"),
      ("drop_const_argument.c", "void mutate(int *value) { *value = 2; } int main(void) { const int value = 1; mutate(&value); return value; }"),
      ("drop_const_return.c", "int *bad(const int *value) { return value; } int main(void) { int value = 1; return *bad(&value); }") ] do
    match compileC source name with
    | .ok _ => fail s!"{name} discarded a pointed-to const qualifier"
    | .error error =>
        expect (error.message.contains "incompatible types")
          s!"{name} produced the wrong pointer-qualification diagnostic"
  for (name, source, diagnostic) in [
      ("duplicate_enumerator.c", "enum E { A, A }; int main(void) { return 0; }", "redeclaration of enumerator"),
      ("nonconstant_enumerator.c", "enum E { A = missing }; int main(void) { return 0; }", "not an enumerator constant"),
      ("overflow_enumerator.c", "enum E { A = 2147483647 + 1 }; int main(void) { return 0; }", "signed 32-bit overflow"),
      ("zero_divisor_enumerator.c", "enum E { A = 1 / 0 }; int main(void) { return 0; }", "division by zero"),
      ("wide_enumerator.c", "enum E { A = 2147483647, B }; int main(void) { return 0; }", "outside the signed 32-bit"),
      ("undeclared_enum.c", "enum Missing value; int main(void) { return 0; }", "undeclared enum tag") ] do
    match compileC source name with
    | .ok _ => fail s!"{name} accepted an invalid enum declaration"
    | .error error =>
        expect (error.message.contains diagnostic)
          s!"{name} produced the wrong enum diagnostic"
  match compileCWithOptions
      "int remote_first(int *p) { return p[0]; } int main(void) { int a[1] = {7}; return remote_first(a)@1; }"
      "remote_pointer.c" { nodeCount := 2 } with
  | .ok _ => fail "remote pointer argument was silently compiled as scalar data"
  | .error error =>
      expect (error.message.contains "length, int *data")
        "wrong remote-pointer diagnostic"
  let remoteAggregates ← match compileCWithOptions
      "struct P { int x; int y; }; struct P make(struct P value) { value.x = value.x + 1; return value; } int main(void) { struct P value = {1, 2}; struct P result = make(value)@1; return result.x + result.y; }"
      "remote_aggregate.c" { nodeCount := 2 } with
  | .error error => fail s!"multiword remote aggregate ABI did not compile: {error}"
  | .ok compilation => pure compilation
  expect (remoteAggregates.broadcastWords.any fun word =>
      word.annotation == "add aggregate MDC envelope")
    "remote aggregate parameter did not use a multiword MDC envelope"
  expect (remoteAggregates.broadcastWords.any fun word =>
      word.annotation == "resolve aggregate MDC result future")
    "remote aggregate result did not use the multiword SET handler"
  match compileCWithOptions
      "struct Huge { int words[1018]; }; struct Huge make(void) { struct Huge value; return value; } int main(void) { struct Huge value = make()@1; return value.words[0]; }"
      "oversized_remote_aggregate.c" { nodeCount := 2 } with
  | .ok _ => fail "oversized remote aggregate result exceeded the queue envelope"
  | .error error =>
      expect (error.message.contains "queue message limit")
        "wrong oversized remote aggregate-result diagnostic"
  match compileCWithOptions
      "struct Box { int *pointer; }; void consume(struct Box value) { } int main(void) { int item = 1; struct Box box; box.pointer = &item; consume(box)@1; return 0; }"
      "remote_pointer_member.c" { nodeCount := 2 } with
  | .ok _ => fail "a node-local pointer escaped inside a remote aggregate"
  | .error error =>
      expect (error.message.contains "remote aggregate contains a pointer")
        "wrong remote aggregate pointer-member diagnostic"
  match compileCWithOptions
      "int remote_sum(int n, int *p) { int i = 0; int s = 0; while (i < n) { s = s + p[i]; i++; } return s; } int main(void) { int a[3] = {2, 3, 5}; return remote_sum(sizeof(a), a)@1; }"
      "remote_bulk.c" { nodeCount := 2 } with
  | .error error => fail s!"MDC length/pointer pair did not compile: {error}"
  | .ok compilation =>
      expect (compilation.words.any fun word => word.node == 1)
        "MDC bulk compilation omitted the receiving node image"
      expect (compilation.broadcastWords.any fun word =>
          word.annotation == "MDC bulk data length is negative")
        "dynamic MDC bulk length omitted its nonnegative guard"
      expect (compilation.broadcastWords.any fun word =>
          word.annotation == "MDC argument envelope exceeds queue limit")
        "dynamic MDC message length omitted its 1020-word guard"
      expect (compilation.symbols.any fun entry => entry.1 == "__mdc_argument_error")
        "dynamic MDC argument error handler is missing"
      expect (compilation.words.any fun word => word.node == 0 &&
          word.address == 0x70d && word.value == integer 0)
        "dynamic MDC argument error status was not initialized"
  let futures ← match compileCWithOptions
      "int work(int x) { return x + computer(); } int main(void) { int a; int b; a = work(10)@1; b = work(20)@1; return a + b; }"
      "futures.c" { nodeCount := 2 } with
    | .error error => fail s!"deferred futures did not compile: {error}"
    | .ok compilation => pure compilation
  expect ((futures.symbols.countP fun entry => entry.1.contains ".future.inspect") >= 2)
    "future consumption points were not emitted for deferred results"
  expect (futures.symbols.any fun entry => entry.1 == "__mdc_future_fault")
    "MDC FUT fault handler is missing"
  expect (futures.symbols.any fun entry => entry.1 == "__mdc_wakeup")
    "MDC wakeup handler is missing"
  expect (futures.words.any fun word => word.address == 0x4d &&
      (word.value >>> 32) == Tag.ip.encoding)
    "priority-0 FUT fault vector is missing"
  expect (futures.broadcastWords.any fun word =>
      word.annotation.contains "force unresolved" &&
      word.value == instructionPair (instruction .equal 0 0 (operandR 0)))
    "future forcing did not use the Version 11 exact-EQ FUT consumer"
  expect (futures.words.any fun word => word.address == 0x708 &&
      word.value == integer 0)
    "node-local FUT-fault counter is missing"
  IO.println "PASS: Lean 4 C front end, MDP v11 encoding, conditional/do-while/goto control flow, arbitrary switch labels, comma expressions, scoped declaration-form for and multiple declarators, block extern/function declarations, auto/register storage, C11 inline/_Noreturn/_Alignas/_Alignof/_Atomic/_Generic/_Thread_local, built-in C11 <stdatomic.h> generic operations and memory-order constraints, ordinary/wide/UTF-8/UTF-16/UTF-32 literals with universal character names and typed concatenation, implementation-defined multicharacter constants, packed signed/unsigned/_Bool bit-fields with initialization and masked lvalue updates, flexible array member layout/access/containment, per-node thread storage duration, seq_cst scalar/pointer atomic read-modify-write operations and masked aggregate snapshots/stores, non-evaluating generic selection with lvalue preservation, and static assertions, addressable compound literals, nested/designated initialization, and typed implicit initialization, single-evaluation prefix/postfix/compound updates, direct/indirect calls, _Bool and signed/unsigned word scalar types and promotions, word strings/address constants, local and multiword MDC aggregate parameters/results, guarded scalar/bulk MDC, division, arrays, typed object/function pointers and casts, scoped typedefs/enums, const/volatile/restrict qualifiers, aligned structs/unions, cross-file and internal linkage, static duration, and diagnostics"
