#include "mdp_golden.hpp"

#include <cstdint>
#include <cstdlib>
#include <iomanip>
#include <iostream>
#include <string>

namespace {
using namespace jmachine::golden;

[[noreturn]] void fail(const std::string& name, Word expected, Word actual) {
  std::cerr << "GOLDEN TEST FAIL: " << name << " expected=0x" << std::hex
            << expected << " actual=0x" << actual << '\n';
  std::exit(1);
}

void expect(const std::string& name, Word expected, Word actual) {
  if (expected != actual) fail(name, expected, actual);
}

void loadInstruction(Machine& machine, std::uint32_t location,
                     Instruction encoded) {
  machine.loaderWrite(0, location,
      instructionPair(encoded, instruction(Opcode::Nop, 0, 0, 0)));
}

Word runBinary(const std::string& name, Opcode opcode, Word left, Word right,
               bool checked = true) {
  Machine machine(1);
  std::uint32_t pc = 0x1000;
  if (checked) {
    machine.loaderWrite(0, pc++, boolean(false));
    loadInstruction(machine, pc++, instruction(
        Opcode::WriteR, 0, 0, registerOperand(false, false, 0x1c)));
  }
  machine.loaderWrite(0, pc++, left);
  loadInstruction(machine, pc++, instruction(
      Opcode::Read, 1, 0, operandR(0)));
  machine.loaderWrite(0, pc++, right);
  loadInstruction(machine, pc++, instruction(opcode, 2, 1, operandR(0)));
  loadInstruction(machine, pc, instruction(
      Opcode::Branch, 3, 0, operandImmediate(-1)));
  machine.run(64);
  const NodeView view = machine.view(0);
  if (view.catastrophe) {
    std::cerr << "GOLDEN TEST FAIL: " << name << " caused catastrophe\n";
    std::exit(1);
  }
  return view.registers[2];
}

Word runUnary(const std::string& name, Opcode opcode, Word operand,
              bool checked = true) {
  Machine machine(1);
  std::uint32_t pc = 0x1000;
  if (checked) {
    machine.loaderWrite(0, pc++, boolean(false));
    loadInstruction(machine, pc++, instruction(
        Opcode::WriteR, 0, 0, registerOperand(false, false, 0x1c)));
  }
  machine.loaderWrite(0, pc++, operand);
  loadInstruction(machine, pc++, instruction(opcode, 2, 0, operandR(0)));
  loadInstruction(machine, pc, instruction(
      Opcode::Branch, 3, 0, operandImmediate(-1)));
  machine.run(48);
  const NodeView view = machine.view(0);
  if (view.catastrophe) {
    std::cerr << "GOLDEN TEST FAIL: " << name << " caused catastrophe\n";
    std::exit(1);
  }
  return view.registers[2];
}

void testEncoding() {
  expect("INT encoding", 0x1'12345678ull, integer(0x12345678));
  expect("ADDR encoding", 0x3'80140008ull,
         address(true, false, 0x500, 8));
  expect("MSG encoding", 0x5'00440002ull,
         message(false, false, 0x1100, 2));
  const Instruction encoded = instruction(Opcode::Add, 2, 1, operandR(0));
  if (encoded != 0x5c80u) {
    std::cerr << "GOLDEN TEST FAIL: instruction encoding expected=0x5c80 actual=0x"
              << std::hex << encoded << '\n';
    std::exit(1);
  }
  expect("instruction pair", (Word{3} << 34) | (Word{encoded} << 17),
         instructionPair(encoded));
}

void testArithmetic() {
  expect("ADD", integer(12),
         runBinary("ADD", Opcode::Add, integer(7), integer(5)));
  expect("SUB", integer(2),
         runBinary("SUB", Opcode::Sub, integer(7), integer(5)));
  expect("CARRY", integer(1),
         runBinary("CARRY", Opcode::Carry, integer(0xffff'ffffu), integer(1)));
  expect("MUL", integer(42),
         runBinary("MUL", Opcode::Mul, integer(7), integer(6)));
  expect("MULH unchecked", integer(0xffff'ffffu),
         runBinary("MULH", Opcode::MulHigh, integer(0xffff'ffffu), integer(2),
                   false));
  expect("ASH right", integer(0xffff'fffeu),
         runBinary("ASH", Opcode::ArithmeticShift, integer(0xffff'fff8u),
                   integer(0xffff'fffeu)));
  expect("LSH right", integer(2),
         runBinary("LSH", Opcode::LogicalShift, integer(8),
                   integer(0xffff'fffeu)));
  expect("ROT", integer(3),
         runBinary("ROT", Opcode::Rotate, integer(0x8000'0001u), integer(1)));
  expect("NEG", integer(0xffff'fff9u),
         runUnary("NEG", Opcode::Negate, integer(7)));
}

void testLogicalAndTags() {
  expect("AND", integer(0x00f0'0000u),
         runBinary("AND", Opcode::And, integer(0x0ff0'0000u),
                   integer(0x00ff'0000u)));
  expect("OR", integer(0x0fff'0000u),
         runBinary("OR", Opcode::Or, integer(0x0ff0'0000u),
                   integer(0x00ff'0000u)));
  expect("XOR bool", boolean(true),
         runBinary("XOR", Opcode::Xor, boolean(true), boolean(false)));
  expect("NOT bool", boolean(true),
         runUnary("NOT", Opcode::Not, boolean(false)));
  expect("FFB", integer(0),
         runUnary("FFB", Opcode::FindFirstBit, integer(0x4000'0000u)));
  expect("RTAG", integer(static_cast<std::uint8_t>(Tag::Addr)),
         runUnary("RTAG", Opcode::ReadTag, address(false, false, 0x123, 7)));
  expect("WTAG", word(Tag::Bool, 0x1234),
         runBinary("WTAG", Opcode::WriteTag, word(Tag::Sym, 0x1234),
                   integer(static_cast<std::uint8_t>(Tag::Bool))));
  expect("CHECK", boolean(true),
         runBinary("CHECK", Opcode::Check, boolean(false),
                   integer(static_cast<std::uint8_t>(Tag::Bool))));
}

void testComparisons() {
  expect("LT", boolean(true),
         runBinary("LT", Opcode::Less, integer(0xffff'ffffu), integer(1)));
  expect("LE", boolean(true),
         runBinary("LE", Opcode::LessEqual, integer(4), integer(4)));
  expect("GE", boolean(true),
         runBinary("GE", Opcode::GreaterEqual, integer(4), integer(4)));
  expect("GT", boolean(true),
         runBinary("GT", Opcode::Greater, integer(5), integer(4)));
  expect("EQUAL", boolean(true),
         runBinary("EQUAL", Opcode::EqualData, integer(5), integer(5)));
  expect("NEQUAL", boolean(true),
         runBinary("NEQUAL", Opcode::NotEqualData, integer(5), integer(4)));
  expect("EQ tagged", boolean(false),
         runBinary("EQ", Opcode::Equal, integer(1), boolean(true)));
  expect("NEQ tagged", boolean(true),
         runBinary("NEQ", Opcode::NotEqual, integer(1), boolean(true)));
}

void testTypeFault() {
  Machine machine(1);
  machine.loaderWrite(0, 0x40 + static_cast<std::uint8_t>(Fault::Type),
      instructionPointer(false, true, 0x1200, false, true));
  std::uint32_t pc = 0x1000;
  machine.loaderWrite(0, pc++, boolean(false));
  loadInstruction(machine, pc++, instruction(
      Opcode::WriteR, 0, 0, registerOperand(false, false, 0x1c)));
  machine.loaderWrite(0, pc++, boolean(true));
  loadInstruction(machine, pc++, instruction(Opcode::Read, 1, 0, operandR(0)));
  machine.loaderWrite(0, pc++, integer(1));
  loadInstruction(machine, pc, instruction(Opcode::Add, 2, 1, operandR(0)));
  loadInstruction(machine, 0x1200, instruction(
      Opcode::Branch, 3, 0, operandImmediate(-1)));
  machine.run(32);
  const NodeView view = machine.view(0);
  if (view.lastFault != static_cast<std::uint8_t>(Fault::Type)
      || view.catastrophe || !view.faultMode) {
    std::cerr << "GOLDEN TEST FAIL: TYPE fault/vector state\n";
    std::exit(1);
  }
}

}  // namespace

int main() {
  testEncoding();
  testArithmetic();
  testLogicalAndTags();
  testComparisons();
  testTypeFault();
  std::cout << "PASS: standalone MDP v11 golden encoding, ALU, tags, "
               "comparisons, and fault-vector tests\n";
  return 0;
}
