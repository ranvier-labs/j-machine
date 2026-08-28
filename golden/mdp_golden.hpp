#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <memory>
#include <string>
#include <vector>

namespace jmachine {
namespace golden {

using Word = std::uint64_t;
using Instruction = std::uint32_t;

constexpr std::uint32_t kAddressMask = 0x000f'ffffu;
constexpr Word kWordMask = 0x0000'000f'ffff'ffffull;

enum class Tag : std::uint8_t {
  Sym = 0x0,
  Int = 0x1,
  Bool = 0x2,
  Addr = 0x3,
  Ip = 0x4,
  Msg = 0x5,
  CFuture = 0x6,
  Future = 0x7,
  Tag8 = 0x8,
  Tag9 = 0x9,
  TagA = 0xa,
  TagB = 0xb,
  Inst0 = 0xc,
  Inst1 = 0xd,
  Inst2 = 0xe,
  Inst3 = 0xf,
};

enum class Opcode : std::uint8_t {
  Nop = 0x00,
  Read = 0x01,
  Write = 0x02,
  ReadR = 0x03,
  WriteR = 0x04,
  ReadTag = 0x05,
  WriteTag = 0x06,
  LoadIp = 0x07,
  LoadIpR = 0x08,
  Check = 0x09,
  Carry = 0x0a,
  Add = 0x0b,
  Sub = 0x0c,
  MulHigh = 0x0e,
  Mul = 0x0f,
  ArithmeticShift = 0x10,
  LogicalShift = 0x11,
  Rotate = 0x12,
  And = 0x18,
  Or = 0x19,
  Xor = 0x1a,
  FindFirstBit = 0x1b,
  Not = 0x1c,
  Negate = 0x1d,
  Less = 0x20,
  LessEqual = 0x21,
  GreaterEqual = 0x22,
  Greater = 0x23,
  EqualData = 0x24,
  NotEqualData = 0x25,
  Equal = 0x26,
  NotEqual = 0x27,
  Translate = 0x28,
  Enter = 0x29,
  Invalidate = 0x2a,
  Probe = 0x2d,
  Suspend = 0x30,
  Call = 0x31,
  Send = 0x34,
  SendEnd = 0x35,
  Send2 = 0x36,
  Send2End = 0x37,
  Branch = 0x38,
  BranchNil = 0x3a,
  BranchNotNil = 0x3b,
  BranchFalse = 0x3c,
  BranchTrue = 0x3d,
  BranchZero = 0x3e,
  BranchNotZero = 0x3f,
};

enum class Fault : std::uint8_t {
  Catastrophe = 0x00,
  Interrupt = 0x01,
  Queue = 0x02,
  Send = 0x03,
  IllegalInstruction = 0x04,
  DramError = 0x05,
  InvalidAddress = 0x06,
  Limit = 0x07,
  Early = 0x08,
  Message = 0x09,
  Translate = 0x0a,
  Overflow = 0x0b,
  CFuture = 0x0c,
  Future = 0x0d,
  Tag8 = 0x0e,
  Tag9 = 0x0f,
  TagA = 0x10,
  TagB = 0x11,
  Type = 0x12,
};

constexpr Word word(Tag tag, std::uint32_t data) {
  return ((Word{static_cast<std::uint8_t>(tag)} << 32) | data) & kWordMask;
}

constexpr Tag tag(Word value) {
  return static_cast<Tag>((value >> 32) & 0xfu);
}

constexpr std::uint32_t data(Word value) {
  return static_cast<std::uint32_t>(value);
}

constexpr Word integer(std::uint32_t value) { return word(Tag::Int, value); }
constexpr Word boolean(bool value) { return word(Tag::Bool, value ? 1u : 0u); }
constexpr Word nil() { return word(Tag::Sym, 0); }

constexpr Word address(bool relocatable, bool invalid, std::uint32_t base,
                       std::uint16_t length) {
  return word(Tag::Addr, (std::uint32_t{relocatable} << 31)
                             | (std::uint32_t{invalid} << 30)
                             | ((base & kAddressMask) << 10)
                             | (length & 0x3ffu));
}

constexpr Word instructionPointer(bool unchecked, bool fault,
                                  std::uint32_t offset, bool phase,
                                  bool absoluteA0) {
  return word(Tag::Ip, (std::uint32_t{unchecked} << 31)
                           | (std::uint32_t{fault} << 30)
                           | ((offset & kAddressMask) << 10)
                           | (std::uint32_t{phase} << 9)
                           | (std::uint32_t{absoluteA0} << 8));
}

constexpr Word message(bool unchecked, bool fault, std::uint32_t handler,
                       std::uint16_t length) {
  return word(Tag::Msg, (std::uint32_t{unchecked} << 31)
                            | (std::uint32_t{fault} << 30)
                            | ((handler & kAddressMask) << 10)
                            | (length & 0x3ffu));
}

constexpr Instruction instruction(Opcode opcode, std::uint8_t op2,
                                  std::uint8_t op1, std::uint8_t op0) {
  return ((static_cast<Instruction>(opcode) & 0x3fu) << 11)
       | ((op2 & 3u) << 9) | ((op1 & 3u) << 7) | (op0 & 0x7fu);
}

constexpr Word instructionPair(Instruction high, Instruction low = 0) {
  return (Word{3} << 34) | (Word{high & 0x1ffffu} << 17)
       | Word{low & 0x1ffffu};
}

constexpr std::uint8_t operandR(unsigned number) { return number & 3u; }
constexpr std::uint8_t operandA(unsigned number) {
  return 0x04u | (number & 3u);
}
constexpr std::uint8_t operandMemoryRegister(unsigned offsetRegister,
                                             unsigned addressRegister) {
  return 0x10u | ((offsetRegister & 3u) << 2) | (addressRegister & 3u);
}
constexpr std::uint8_t operandImmediate(int value) {
  return 0x20u | (static_cast<unsigned>(value) & 0x1fu);
}
constexpr std::uint8_t operandMemoryImmediate(unsigned offset,
                                              unsigned addressRegister) {
  return 0x40u | ((offset & 0xfu) << 2) | (addressRegister & 3u);
}
constexpr std::uint8_t registerOperand(bool backgroundRelative,
                                       bool priorityRelative,
                                       std::uint8_t number) {
  return (std::uint8_t{backgroundRelative} << 6)
       | (std::uint8_t{priorityRelative} << 5) | (number & 0x1fu);
}

enum class TraceKind {
  Constant,
  Instruction,
  Dispatch,
  Send,
  Suspend,
  Fault,
  Catastrophe,
};

struct TraceEvent {
  std::uint64_t sequence = 0;
  std::size_t node = 0;
  TraceKind kind = TraceKind::Instruction;
  Word ip = nil();
  Instruction instruction = 0;
  Fault fault = Fault::Catastrophe;
  std::uint32_t address = 0;
  Word value = nil();
  std::string detail;
};

struct ContextView {
  std::array<Word, 4> registers{};
  std::array<Word, 4> addresses{};
  Word ip = nil();
  Word faultIp = nil();
};

struct NodeView {
  std::array<ContextView, 3> contexts{};
  std::array<std::array<Word, 4>, 2> identifiers{};
  std::array<Word, 2> faultInstructions{};
  std::array<Word, 2> faultOperand0{};
  std::array<Word, 2> faultOperand1{};
  std::array<Word, 2> queueBaseMask{};
  std::array<Word, 2> queueHeadLength{};
  std::array<bool, 2> queueAddressing{};
  std::array<bool, 2> activeMessage{};
  Word tableBaseMask = nil();
  std::uint32_t memoryAddress = 0;

  // Convenience projection of the currently selected context.
  std::array<Word, 4> registers{};
  std::array<Word, 4> addresses{};
  Word ip = nil();
  std::uint32_t nodeNumber = 0;
  std::uint8_t lastFault = 0;
  std::uint64_t retiredInstructions = 0;
  std::array<bool, 2> queuePending{};
  std::array<bool, 2> queueFull{};
  bool background = true;
  bool priority = false;
  bool interruptMask = true;
  bool unchecked = true;
  bool faultMode = false;
  bool catastrophe = false;
};

class Machine {
 public:
  explicit Machine(std::size_t nodeCount);
  ~Machine();
  Machine(Machine&&) noexcept;
  Machine& operator=(Machine&&) noexcept;
  Machine(const Machine&) = delete;
  Machine& operator=(const Machine&) = delete;

  // Reset architectural registers and queues. Memory is intentionally retained,
  // matching a processor reset with an already-programmed ROM/DRAM image.
  void reset();

  void loaderWrite(std::size_t node, std::uint32_t address, Word value);
  Word readMemory(std::size_t node, std::uint32_t address) const;
  void writeMemory(std::size_t node, std::uint32_t address, Word value);
  void setExternalInterrupt(std::size_t node, bool asserted);
  void setDramError(std::size_t node, bool enabled, std::uint32_t address);

  // Advance one node by one architectural event, in round-robin node order.
  // Constants, instructions, message dispatches, faults, and suspends are each
  // observable events. This is deliberately not an RTL-cycle API.
  bool step();
  void run(std::uint64_t maximumEvents);

  std::size_t nodeCount() const;
  NodeView view(std::size_t node) const;
  const std::vector<TraceEvent>& trace() const;
  void clearTrace();

 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};

}  // namespace golden
}  // namespace jmachine
