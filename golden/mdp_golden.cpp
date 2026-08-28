#include "mdp_golden.hpp"

#include <algorithm>
#include <stdexcept>
#include <unordered_map>
#include <utility>

namespace jmachine {
namespace golden {
namespace {

constexpr std::size_t kContexts = 3;
constexpr std::size_t kPriorities = 2;
constexpr std::size_t kBackground = 2;
constexpr std::size_t kMemoryWords = std::size_t{1} << 20;
constexpr std::size_t kMemoryPageWords = 256;

class PagedMemory {
 public:
  using Page = std::array<Word, kMemoryPageWords>;

  Word operator[](std::uint32_t addressValue) const {
    return read(addressValue);
  }

  Word& operator[](std::uint32_t addressValue) {
    return writeReference(addressValue);
  }

  Word at(std::uint32_t addressValue) const {
    checkAddress(addressValue);
    return read(addressValue);
  }

  Word& at(std::uint32_t addressValue) {
    checkAddress(addressValue);
    return writeReference(addressValue);
  }

 private:
  static void checkAddress(std::uint32_t addressValue) {
    if (addressValue >= kMemoryWords) {
      throw std::out_of_range("MDP memory address exceeds 20 bits");
    }
  }

  Word read(std::uint32_t addressValue) const {
    const auto page = pages_.find(addressValue / kMemoryPageWords);
    if (page == pages_.end()) return nil();
    return page->second[addressValue % kMemoryPageWords];
  }

  Word& writeReference(std::uint32_t addressValue) {
    checkAddress(addressValue);
    return pages_[addressValue / kMemoryPageWords][addressValue % kMemoryPageWords];
  }

  std::unordered_map<std::uint32_t, Page> pages_;
};

constexpr bool bit(std::uint32_t value, unsigned index) {
  return ((value >> index) & 1u) != 0;
}

constexpr std::uint32_t base(Word value) {
  return (data(value) >> 10) & kAddressMask;
}

constexpr std::uint16_t length(Word value) {
  return data(value) & 0x3ffu;
}

constexpr bool unchecked(Word ip) { return bit(data(ip), 31); }
constexpr bool faultMode(Word ip) { return bit(data(ip), 30); }
constexpr bool phase(Word ip) { return bit(data(ip), 9); }
constexpr bool absoluteA0(Word ip) { return bit(data(ip), 8); }

constexpr bool instructionWord(Word value) {
  return ((value >> 34) & 3u) == 3u;
}

constexpr Instruction highInstruction(Word value) {
  return static_cast<Instruction>((((value >> 32) & 3u) << 15)
                                | ((value >> 17) & 0x7fffu));
}

constexpr Instruction lowInstruction(Word value) {
  return static_cast<Instruction>(value & 0x1ffffu);
}

constexpr std::uint32_t priorityMap(std::uint32_t addressValue,
                                    bool priority) {
  addressValue &= kAddressMask;
  if (addressValue < 0x40u) addressValue ^= std::uint32_t{priority} << 5;
  return addressValue;
}

constexpr std::uint32_t align4(std::uint32_t value) {
  return (value + 3u) & ~3u;
}

constexpr Word updateAddressFields(Word original, std::uint32_t newBase,
                                   std::uint16_t newLength) {
  const std::uint32_t preserved = data(original) & 0xc000'0000u;
  return word(tag(original), preserved | ((newBase & kAddressMask) << 10)
                                  | (newLength & 0x3ffu));
}

constexpr std::int32_t signExtend(std::uint32_t value, unsigned bits) {
  const std::uint32_t sign = std::uint32_t{1} << (bits - 1);
  return static_cast<std::int32_t>((value ^ sign) - sign);
}

constexpr Fault typeFaultFor(Word value) {
  switch (tag(value)) {
    case Tag::CFuture: return Fault::CFuture;
    case Tag::Future: return Fault::Future;
    case Tag::Tag8: return Fault::Tag8;
    case Tag::Tag9: return Fault::Tag9;
    case Tag::TagA: return Fault::TagA;
    case Tag::TagB: return Fault::TagB;
    default: return Fault::Type;
  }
}

constexpr std::uint32_t arithmeticShift(std::uint32_t value,
                                        std::int32_t amount) {
  if (amount >= 32 || amount <= -32) {
    return (value & 0x8000'0000u) ? 0xffff'ffffu : 0u;
  }
  if (amount < 0) {
    return static_cast<std::uint32_t>(static_cast<std::int32_t>(value)
                                     >> -amount);
  }
  return value << amount;
}

constexpr std::uint32_t logicalShift(std::uint32_t value,
                                     std::int32_t amount) {
  if (amount >= 32 || amount <= -32) return 0;
  if (amount < 0) return value >> -amount;
  return value << amount;
}

constexpr std::uint32_t rotateLeft(std::uint32_t value,
                                   std::uint32_t amount) {
  amount &= 31u;
  if (amount == 0) return value;
  return (value << amount) | (value >> (32u - amount));
}

std::uint32_t findFirstBit(std::uint32_t value) {
  const bool sign = bit(value, 31);
  for (int index = 30; index >= 0; --index) {
    if (bit(value, static_cast<unsigned>(index)) != sign) {
      return static_cast<std::uint32_t>(30 - index);
    }
  }
  return 31;
}

constexpr bool addOverflow(std::uint32_t left, std::uint32_t right,
                           std::uint32_t result) {
  return bit(left, 31) == bit(right, 31) && bit(result, 31) != bit(left, 31);
}

constexpr bool subOverflow(std::uint32_t left, std::uint32_t right,
                           std::uint32_t result) {
  return bit(left, 31) != bit(right, 31) && bit(result, 31) != bit(left, 31);
}

}  // namespace

struct Machine::Impl {
  struct Context {
    std::array<Word, 4> r{};
    std::array<Word, 4> a{};
    Word ip = nil();
    Word fip = nil();
  };

  struct SendBuilder {
    bool active = false;
    std::uint16_t destination = 0;
    bool priority = false;
    std::vector<Word> words;
  };

  struct Node {
    PagedMemory memory;
    std::array<Context, kContexts> context{};
    std::array<std::array<Word, 4>, kPriorities> id{};
    std::array<Word, kPriorities> fir{};
    std::array<Word, kPriorities> fop0{};
    std::array<Word, kPriorities> fop1{};
    std::array<Word, kPriorities> qbm{};
    std::array<Word, kPriorities> qhl{};
    std::array<bool, kPriorities> queueAddressing{};
    std::array<bool, kPriorities> activeMessage{};
    Word tbm = nil();
    std::uint32_t nnr = 0;
    std::uint32_t mar = 0;
    bool priority = false;
    bool background = true;
    bool interruptMask = true;
    bool externalInterrupt = false;
    bool dramErrorEnabled = false;
    std::uint32_t dramErrorAddress = 0;
    Fault lastFault = Fault::Catastrophe;
    bool catastrophe = false;
    std::uint64_t retired = 0;
    bool replacementWay = false;
    SendBuilder send;

    Node() = default;
  };

  enum class OperandKind { None, DataRegister, AddressRegister, Memory, RegisterMode };

  struct Operand {
    OperandKind kind = OperandKind::None;
    Word value = nil();
    std::uint8_t registerNumber = 0;
    std::uint32_t address = 0;
    bool memory = false;
    bool faulted = false;
    Fault fault = Fault::IllegalInstruction;
  };

  struct Execution {
    std::size_t context = kBackground;
    bool priority = false;
    bool background = true;
    Word instructionIp = nil();
    std::uint32_t instructionWordOffset = 0;
    Instruction instruction = 0;
    Opcode opcode = Opcode::Nop;
    std::uint8_t op2 = 0;
    std::uint8_t op1 = 0;
    std::uint8_t op0 = 0;
    Word rs = nil();
    Operand operand;
    bool checked = false;
  };

  explicit Impl(std::size_t count) : nodes(count) {
    if (count == 0 || count > 65536) {
      throw std::invalid_argument("golden MDP machine requires 1..65536 nodes");
    }
    reset();
  }

  std::vector<Node> nodes;
  std::vector<TraceEvent> trace;
  std::size_t roundRobin = 0;
  std::uint64_t sequence = 0;

  void resetNode(Node& node) {
    for (std::size_t context = 0; context < kContexts; ++context) {
      node.context[context] = {};
      for (auto& value : node.context[context].r) value = nil();
      for (auto& value : node.context[context].a) {
        value = address(false, false, 0, 0);
      }
      node.context[context].ip = instructionPointer(
          true, false, context == kBackground ? 0x1000u : 0u, false,
          context == kBackground);
      node.context[context].fip = instructionPointer(true, false, 0, false, true);
    }
    for (std::size_t priority = 0; priority < kPriorities; ++priority) {
      node.id[priority].fill(nil());
      node.fir[priority] = nil();
      node.fop0[priority] = nil();
      node.fop1[priority] = nil();
      node.qbm[priority] = address(false, true, 0, 0);
      node.qhl[priority] = address(false, false, 0, 0);
      node.queueAddressing[priority] = false;
      node.activeMessage[priority] = false;
    }
    node.tbm = address(false, false, 0, 0);
    node.nnr = 0;
    node.mar = 0;
    node.priority = false;
    node.background = true;
    node.interruptMask = true;
    node.externalInterrupt = false;
    node.dramErrorEnabled = false;
    node.dramErrorAddress = 0;
    node.lastFault = Fault::Catastrophe;
    node.catastrophe = false;
    node.retired = 0;
    node.replacementWay = false;
    node.send = {};
  }

  void reset() {
    for (auto& node : nodes) resetNode(node);
    roundRobin = 0;
    sequence = 0;
    trace.clear();
  }

  std::size_t currentContext(const Node& node) const {
    return node.background ? kBackground : std::size_t{node.priority};
  }

  bool queuePending(const Node& node, bool priority) const {
    return length(node.qhl[priority]) >= 4;
  }

  bool queueFull(const Node& node, bool priority) const {
    return std::uint32_t{length(node.qhl[priority])}
        >= std::uint32_t{length(node.qbm[priority])} + 1u;
  }

  bool dramError(const Node& node, std::uint32_t addressValue) const {
    return node.dramErrorEnabled && addressValue == node.dramErrorAddress
        && addressValue >= 0x2000u;
  }

  void appendTrace(std::size_t nodeIndex, TraceKind kind, Word ipValue,
                   Instruction instructionValue = 0,
                   Fault faultValue = Fault::Catastrophe,
                   std::uint32_t addressValue = 0, Word value = nil(),
                   std::string detail = {}) {
    trace.push_back(TraceEvent{++sequence, nodeIndex, kind, ipValue,
                               instructionValue, faultValue, addressValue,
                               value, std::move(detail)});
  }

  std::uint32_t fetchAddress(const Node& node, std::size_t context,
                             bool priority, Fault& fault) const {
    const Word ipValue = node.context[context].ip;
    const std::uint32_t offset = base(ipValue);
    if (absoluteA0(ipValue)) return priorityMap(offset, priority);
    const Word a0 = node.context[context].a[0];
    if (bit(data(a0), 30)) {
      fault = Fault::InvalidAddress;
      return 0;
    }
    if (length(a0) != 0 && offset >= length(a0)) {
      fault = Fault::Limit;
      return 0;
    }
    return priorityMap(base(a0) + offset, priority);
  }

  static Word incrementIp(Word value) {
    std::uint32_t d = data(value);
    if (!bit(d, 9)) {
      d |= 1u << 9;
    } else {
      d = (d & ~((kAddressMask << 10) | (1u << 9)))
        | (((base(value) + 1u) & kAddressMask) << 10);
    }
    return word(tag(value), d);
  }

  static Word branchIp(Word oldIp, std::uint32_t instructionWordOffset,
                       std::int32_t displacement) {
    return instructionPointer(unchecked(oldIp), faultMode(oldIp),
                              (instructionWordOffset + 1u
                               + static_cast<std::uint32_t>(displacement))
                                  & kAddressMask,
                              false, absoluteA0(oldIp));
  }

  void raiseFault(std::size_t nodeIndex, const Execution& execution,
                  Fault requested, Word operand0, Word operand1,
                  bool instructionSpecific) {
    Node& node = nodes[nodeIndex];
    Fault selected = requested;
    if (faultMode(node.context[execution.context].ip)) {
      selected = Fault::Catastrophe;
    }
    node.lastFault = selected;
    node.context[execution.context].fip = node.context[execution.context].ip;
    node.fir[execution.priority] = instructionSpecific
        ? instructionPair(0, execution.instruction) : nil();
    node.fop0[execution.priority] = operand0;
    node.fop1[execution.priority] = operand1;
    appendTrace(nodeIndex, TraceKind::Fault, execution.instructionIp,
                execution.instruction, selected, 0, operand0);

    const std::uint32_t vectorAddress = 0x40u
        + (std::uint32_t{execution.priority} << 5)
        + static_cast<std::uint8_t>(selected);
    const Word vector = node.memory.at(vectorAddress);
    if (dramError(node, vectorAddress) || tag(vector) != Tag::Ip) {
      if (selected == Fault::Catastrophe) {
        node.catastrophe = true;
        appendTrace(nodeIndex, TraceKind::Catastrophe,
                    node.context[execution.context].ip, execution.instruction,
                    selected, vectorAddress, vector,
                    "invalid catastrophe vector");
        return;
      }
      Execution catastropheExecution = execution;
      catastropheExecution.instructionIp = node.context[execution.context].ip;
      raiseFault(nodeIndex, catastropheExecution, Fault::Catastrophe,
                 operand0, operand1, instructionSpecific);
      return;
    }
    node.context[execution.context].ip = vector;
    node.background = execution.context == kBackground;
    node.priority = execution.priority;
  }

  void asynchronousFault(std::size_t nodeIndex, Fault fault) {
    Node& node = nodes[nodeIndex];
    Execution execution;
    execution.context = currentContext(node);
    execution.priority = node.priority;
    execution.background = node.background;
    execution.instructionIp = node.context[execution.context].ip;
    raiseFault(nodeIndex, execution, fault, nil(), nil(), false);
  }

  std::size_t registerModeContext(const Execution& execution,
                                  bool backgroundSelect,
                                  bool prioritySelect) const {
    const bool useBackground = backgroundSelect ^ execution.background;
    if (useBackground) return kBackground;
    return static_cast<std::size_t>(execution.priority ^ prioritySelect);
  }

  Word readSpecial(Node& node, const Execution& execution,
                   std::uint8_t encoded, bool& valid) {
    const std::size_t selectedContext = registerModeContext(
        execution, bit(encoded, 6), bit(encoded, 5));
    const std::uint8_t number = encoded & 0x1fu;
    const bool selectedPriority = execution.priority ^ bit(encoded, 5);
    valid = true;
    if (number <= 0x03) return node.context[selectedContext].r[number];
    if (number <= 0x07) return node.context[selectedContext].a[number & 3u];
    if (number <= 0x0b) {
      return selectedContext == kBackground ? nil()
          : node.id[selectedContext & 1u][number & 3u];
    }
    switch (number) {
      case 0x0c: return node.context[selectedContext].fip;
      case 0x0d: return selectedContext == kBackground
          ? nil() : node.fir[selectedContext & 1u];
      case 0x0e: return selectedContext == kBackground
          ? nil() : node.fop0[selectedContext & 1u];
      case 0x0f: return selectedContext == kBackground
          ? nil() : node.fop1[selectedContext & 1u];
      case 0x10: return node.qbm[selectedPriority];
      case 0x11: return node.qhl[selectedPriority];
      case 0x12: return node.context[selectedContext].ip;
      case 0x13: return node.tbm;
      case 0x14: return integer(node.nnr);
      case 0x15: return integer(node.mar);
      case 0x18: return boolean(node.priority);
      case 0x19: return boolean(node.background);
      case 0x1a: return boolean(node.interruptMask);
      case 0x1b: return boolean(faultMode(node.context[selectedContext].ip));
      case 0x1c: return boolean(unchecked(node.context[selectedContext].ip));
      case 0x1d: return boolean(node.queueAddressing[selectedPriority]);
      default:
        valid = false;
        return nil();
    }
  }

  bool writeSpecial(Node& node, const Execution& execution,
                    std::uint8_t encoded, Word value) {
    const std::size_t selectedContext = registerModeContext(
        execution, bit(encoded, 6), bit(encoded, 5));
    const std::uint8_t number = encoded & 0x1fu;
    const bool selectedPriority = execution.priority ^ bit(encoded, 5);
    if (number <= 0x03) {
      node.context[selectedContext].r[number] = value;
      return true;
    }
    if (number <= 0x07) {
      node.context[selectedContext].a[number & 3u] = value;
      return true;
    }
    if (number <= 0x0b) {
      if (selectedContext != kBackground) {
        node.id[selectedContext & 1u][number & 3u] = value;
      }
      return true;
    }
    switch (number) {
      case 0x0c: node.context[selectedContext].fip = value; return true;
      case 0x0d:
        if (selectedContext != kBackground) node.fir[selectedContext & 1u] = value;
        return true;
      case 0x0e:
        if (selectedContext != kBackground) node.fop0[selectedContext & 1u] = value;
        return true;
      case 0x0f:
        if (selectedContext != kBackground) node.fop1[selectedContext & 1u] = value;
        return true;
      case 0x10: node.qbm[selectedPriority] = value; return true;
      case 0x11: node.qhl[selectedPriority] = value; return true;
      case 0x12: node.context[selectedContext].ip = value; return true;
      case 0x13: node.tbm = value; return true;
      case 0x14: node.nnr = data(value); return true;
      case 0x15: return false;
      case 0x18: node.priority = bit(data(value), 0); return true;
      case 0x19: node.background = bit(data(value), 0); return true;
      case 0x1a: node.interruptMask = bit(data(value), 0); return true;
      case 0x1b: {
        std::uint32_t d = data(node.context[selectedContext].ip);
        d = (d & ~(1u << 30)) | (std::uint32_t{bit(data(value), 0)} << 30);
        node.context[selectedContext].ip
            = word(tag(node.context[selectedContext].ip), d);
        return true;
      }
      case 0x1c: {
        std::uint32_t d = data(node.context[selectedContext].ip);
        d = (d & ~(1u << 31)) | (std::uint32_t{bit(data(value), 0)} << 31);
        node.context[selectedContext].ip
            = word(tag(node.context[selectedContext].ip), d);
        return true;
      }
      case 0x1d:
        node.queueAddressing[selectedPriority] = bit(data(value), 0);
        return true;
      default: return false;
    }
  }

  Operand decodeOperand(Node& node, const Execution& execution) {
    Operand result;
    const std::uint8_t op0 = execution.op0;
    std::uint8_t extension = 0;
    switch (execution.opcode) {
      case Opcode::Read:
      case Opcode::ReadTag:
      case Opcode::FindFirstBit:
      case Opcode::Not:
      case Opcode::Negate:
        extension = execution.op1;
        break;
      case Opcode::Write:
        extension = execution.op2;
        break;
      case Opcode::LoadIp:
      case Opcode::Call:
      case Opcode::Branch:
      case Opcode::BranchNil:
      case Opcode::BranchNotNil:
      case Opcode::BranchFalse:
      case Opcode::BranchTrue:
      case Opcode::BranchZero:
      case Opcode::BranchNotZero:
        extension = execution.op2;
        break;
      case Opcode::Send:
      case Opcode::SendEnd:
        extension = execution.op1;
        break;
      default: break;
    }

    if (execution.opcode == Opcode::ReadR
        || execution.opcode == Opcode::WriteR
        || execution.opcode == Opcode::LoadIpR) {
      result.kind = OperandKind::RegisterMode;
      return result;
    }

    std::uint32_t offset = 0;
    std::uint8_t addressRegister = op0 & 3u;
    if ((op0 >> 2) == 0) {
      result.kind = OperandKind::DataRegister;
      result.registerNumber = op0 & 3u;
      result.value = node.context[execution.context].r[result.registerNumber];
      return result;
    }
    if ((op0 >> 2) == 1) {
      result.kind = OperandKind::AddressRegister;
      result.registerNumber = op0 & 3u;
      result.value = node.context[execution.context].a[result.registerNumber];
      return result;
    }
    if (op0 >= 0x08u && op0 <= 0x0fu) {
      result.kind = OperandKind::None;
      switch (op0) {
        case 0x08: result.value = nil(); break;
        case 0x09: result.value = boolean(false); break;
        case 0x0a: result.value = boolean(true); break;
        case 0x0b: result.value = integer(0x8000'0000u); break;
        case 0x0c: result.value = integer(0x0000'00ffu); break;
        case 0x0d: result.value = integer(0x0000'03ffu); break;
        case 0x0e: result.value = integer(0x0000'ffffu); break;
        default: result.value = integer(0x000f'ffffu); break;
      }
      return result;
    }
    if ((op0 >> 4) == 1) {
      result.kind = OperandKind::Memory;
      result.memory = true;
      const Word offsetWord = node.context[execution.context].r[(op0 >> 2) & 3u];
      offset = data(offsetWord) & kAddressMask;
      if (execution.checked && tag(offsetWord) != Tag::Int) {
        result.faulted = true;
        result.fault = typeFaultFor(offsetWord);
        return result;
      }
    } else if ((op0 >> 5) == 1) {
      result.kind = OperandKind::None;
      const std::uint32_t immediate = ((extension & 3u) << 5) | (op0 & 0x1fu);
      result.value = integer(static_cast<std::uint32_t>(signExtend(immediate, 7)));
      return result;
    } else if (bit(op0, 6)) {
      result.kind = OperandKind::Memory;
      result.memory = true;
      offset = ((extension & 3u) << 4) | ((op0 >> 2) & 0xfu);
    } else {
      result.faulted = true;
      result.fault = Fault::IllegalInstruction;
      return result;
    }

    result.registerNumber = addressRegister;
    const Word selectedAddress = node.context[execution.context].a[addressRegister];
    if (addressRegister == 0 && absoluteA0(node.context[execution.context].ip)) {
      result.address = priorityMap(offset, execution.priority);
    } else if (bit(data(selectedAddress), 30)) {
      result.faulted = true;
      result.fault = Fault::InvalidAddress;
      return result;
    } else if (length(selectedAddress) != 0 && offset >= length(selectedAddress)) {
      result.faulted = true;
      result.fault = Fault::Limit;
      return result;
    } else if (!execution.background && node.queueAddressing[execution.priority]
               && addressRegister == 3) {
      if (execution.opcode != Opcode::Write
          && offset >= length(node.qhl[execution.priority])) {
        result.faulted = true;
        result.fault = Fault::Early;
        return result;
      }
      result.address = base(node.qbm[execution.priority])
          | ((base(selectedAddress) + offset)
             & std::uint32_t{length(node.qbm[execution.priority])});
    } else {
      result.address = priorityMap(base(selectedAddress) + offset,
                                   execution.priority);
    }
    result.address &= kAddressMask;
    node.mar = result.address;
    if (execution.opcode != Opcode::Write
        && execution.opcode != Opcode::Translate
        && execution.opcode != Opcode::Probe) {
      if (dramError(node, result.address)) {
        result.faulted = true;
        result.fault = Fault::DramError;
      } else {
        result.value = node.memory[result.address];
      }
    }
    return result;
  }

  bool checkedIntegerPair(std::size_t nodeIndex, const Execution& execution) {
    if (!execution.checked) return true;
    if (tag(execution.rs) == Tag::Int && tag(execution.operand.value) == Tag::Int) {
      return true;
    }
    raiseFault(nodeIndex, execution,
               tag(execution.rs) != Tag::Int ? typeFaultFor(execution.rs)
                                             : typeFaultFor(execution.operand.value),
               execution.operand.value, execution.rs, true);
    return false;
  }

  std::uint32_t tableRow(const Node& node, Word key) const {
    return (base(node.tbm)
            | ((data(key) & kAddressMask) & std::uint32_t{length(node.tbm)}))
        & 0xffffcu;
  }

  bool deliverMessage(std::size_t senderIndex, const Execution& execution,
                      SendBuilder& builder) {
    if (builder.words.empty()) return false;
    const auto destinationIterator = std::find_if(
        nodes.begin(), nodes.end(), [&](const Node& candidate) {
          return static_cast<std::uint16_t>(candidate.nnr) == builder.destination;
        });
    if (destinationIterator == nodes.end()) return false;
    const std::size_t destinationIndex = static_cast<std::size_t>(
        std::distance(nodes.begin(), destinationIterator));
    Node& destination = *destinationIterator;
    const bool priority = builder.priority;
    const std::uint32_t allocated = align4(
        static_cast<std::uint32_t>(builder.words.size()));
    const std::uint32_t capacity = std::uint32_t{length(destination.qbm[priority])} + 1u;
    const std::uint32_t occupancy = length(destination.qhl[priority]);
    if (occupancy + allocated > capacity) return false;
    const std::uint32_t queueBase = base(destination.qbm[priority]);
    const std::uint32_t mask = length(destination.qbm[priority]);
    const std::uint32_t tail = queueBase
        | ((base(destination.qhl[priority]) + occupancy) & mask);
    for (std::uint32_t index = 0; index < allocated; ++index) {
      const std::uint32_t location = queueBase | ((tail + index) & mask);
      destination.memory[location] = index < builder.words.size()
          ? builder.words[index] : nil();
    }
    destination.qhl[priority] = updateAddressFields(
        destination.qhl[priority], base(destination.qhl[priority]),
        static_cast<std::uint16_t>(occupancy + allocated));
    appendTrace(senderIndex, TraceKind::Send, execution.instructionIp,
                execution.instruction, Fault::Catastrophe,
                static_cast<std::uint32_t>(destinationIndex),
                builder.words.front(),
                "priority=" + std::to_string(priority)
                    + " words=" + std::to_string(builder.words.size()));
    return true;
  }

  bool offerSend(std::size_t nodeIndex, const Execution& execution) {
    Node& node = nodes[nodeIndex];
    const bool sendTwo = execution.opcode == Opcode::Send2
                      || execution.opcode == Opcode::Send2End;
    const bool sendEnd = execution.opcode == Opcode::SendEnd
                      || execution.opcode == Opcode::Send2End;
    const std::array<Word, 2> offered{execution.operand.value, execution.rs};
    const unsigned count = sendTwo ? 2u : 1u;
    for (unsigned index = 0; index < count; ++index) {
      if (!node.send.active) {
        node.send.active = true;
        node.send.destination = static_cast<std::uint16_t>(data(offered[index]));
        node.send.priority = (execution.op2 & 1u) != 0;
        node.send.words.clear();
        if (sendEnd && count == 1) return false;
      } else {
        node.send.words.push_back(offered[index]);
      }
    }
    if (sendEnd) {
      if (!deliverMessage(nodeIndex, execution, node.send)) return false;
      node.send = {};
    }
    node.interruptMask = !sendEnd;
    return true;
  }

  bool dispatch(std::size_t nodeIndex, bool priority) {
    Node& node = nodes[nodeIndex];
    const std::uint32_t head = base(node.qhl[priority]);
    const Word header = node.memory[head];
    Execution execution;
    execution.context = std::size_t{priority};
    execution.priority = priority;
    execution.background = false;
    execution.instructionIp = node.context[execution.context].ip;
    if (dramError(node, head)) {
      raiseFault(nodeIndex, execution, Fault::DramError, nil(), nil(), false);
      return true;
    }
    if (tag(header) != Tag::Msg || length(header) == 0) {
      raiseFault(nodeIndex, execution, Fault::Message, nil(), nil(), false);
      return true;
    }
    node.priority = priority;
    node.background = false;
    node.activeMessage[priority] = true;
    node.queueAddressing[priority] = true;
    node.context[priority].a[3] = address(false, false, head, length(header));
    node.context[priority].ip = instructionPointer(
        bit(data(header), 31), bit(data(header), 30), base(header), false, true);
    appendTrace(nodeIndex, TraceKind::Dispatch, node.context[priority].ip,
                0, Fault::Catastrophe, head, header,
                "priority=" + std::to_string(priority));
    return true;
  }

  bool suspend(std::size_t nodeIndex, const Execution& execution) {
    Node& node = nodes[nodeIndex];
    if (execution.background) {
      node.catastrophe = true;
      appendTrace(nodeIndex, TraceKind::Catastrophe, execution.instructionIp,
                  execution.instruction, Fault::Catastrophe, 0, nil(),
                  "SUSPEND in background context");
      return false;
    }
    const bool priority = execution.priority;
    const std::uint32_t allocated = align4(length(node.context[execution.context].a[3]));
    if (length(node.qhl[priority]) < allocated) {
      raiseFault(nodeIndex, execution, Fault::Early,
                 execution.operand.value, execution.rs, true);
      return false;
    }
    const std::uint32_t nextHead = base(node.qbm[priority])
        | ((base(node.qhl[priority]) + allocated)
           & std::uint32_t{length(node.qbm[priority])});
    node.qhl[priority] = updateAddressFields(node.qhl[priority], nextHead,
        static_cast<std::uint16_t>(length(node.qhl[priority]) - allocated));
    node.activeMessage[priority] = false;
    node.queueAddressing[priority] = false;
    if (priority && node.activeMessage[0]) {
      node.priority = false;
      node.background = false;
    } else {
      node.background = true;
    }
    ++node.retired;
    appendTrace(nodeIndex, TraceKind::Suspend, execution.instructionIp,
                execution.instruction);
    return true;
  }

  bool execute(std::size_t nodeIndex, Execution execution) {
    Node& node = nodes[nodeIndex];
    execution.operand = decodeOperand(node, execution);
    if (execution.operand.faulted) {
      raiseFault(nodeIndex, execution, execution.operand.fault,
                 execution.operand.value, execution.rs, true);
      return true;
    }

    const Word op0 = execution.operand.value;
    const std::uint32_t left = data(execution.rs);
    const std::uint32_t right = data(op0);
    auto fault = [&](Fault value) {
      raiseFault(nodeIndex, execution, value, op0, execution.rs, true);
    };
    auto finish = [&]() {
      ++node.retired;
      appendTrace(nodeIndex, TraceKind::Instruction, execution.instructionIp,
                  execution.instruction);
      return true;
    };

    switch (execution.opcode) {
      case Opcode::Nop:
        return finish();
      case Opcode::Read:
        if (execution.checked && tag(op0) == Tag::CFuture) {
          fault(Fault::CFuture);
          return true;
        }
        node.context[execution.context].r[execution.op2] = op0;
        return finish();
      case Opcode::Write:
        if (!execution.operand.memory) {
          fault(Fault::IllegalInstruction);
          return true;
        }
        if (!(execution.operand.address >= 0x1000u
              && execution.operand.address <= 0x1fffu)) {
          node.memory[execution.operand.address] = execution.rs;
        }
        return finish();
      case Opcode::ReadR:
      case Opcode::LoadIpR: {
        bool valid = false;
        const Word value = readSpecial(node, execution, execution.op0, valid);
        if (!valid) {
          fault(Fault::IllegalInstruction);
          return true;
        }
        if (execution.checked && tag(value) == Tag::CFuture) {
          fault(Fault::CFuture);
          return true;
        }
        if (execution.opcode == Opcode::LoadIpR) {
          if (execution.checked && tag(value) != Tag::Ip) {
            fault(typeFaultFor(value));
            return true;
          }
          node.context[execution.context].ip = value;
        } else {
          node.context[execution.context].r[execution.op2] = value;
        }
        return finish();
      }
      case Opcode::WriteR: {
        const std::uint8_t number = execution.op0 & 0x1fu;
        if (execution.checked && number >= 0x04 && number <= 0x07
            && tag(execution.rs) != Tag::Addr) {
          fault(typeFaultFor(execution.rs));
          return true;
        }
        if (execution.checked && number == 0x12 && tag(execution.rs) != Tag::Ip) {
          fault(typeFaultFor(execution.rs));
          return true;
        }
        if (!writeSpecial(node, execution, execution.op0, execution.rs)) {
          fault(Fault::IllegalInstruction);
          return true;
        }
        return finish();
      }
      case Opcode::ReadTag:
        if (execution.checked && tag(op0) == Tag::CFuture) {
          fault(Fault::CFuture);
          return true;
        }
        node.context[execution.context].r[execution.op2]
            = integer(static_cast<std::uint8_t>(tag(op0)));
        return finish();
      case Opcode::WriteTag:
        if (execution.checked && tag(op0) != Tag::Int) {
          fault(typeFaultFor(op0));
          return true;
        }
        if (right > 15) {
          fault(Fault::Type);
          return true;
        }
        node.context[execution.context].r[execution.op2]
            = word(static_cast<Tag>(right & 0xfu), left);
        return finish();
      case Opcode::LoadIp:
        if (execution.checked && tag(op0) != Tag::Ip) {
          fault(typeFaultFor(op0));
          return true;
        }
        node.context[execution.context].ip = op0;
        return finish();
      case Opcode::Check:
        if (execution.checked && tag(op0) != Tag::Int) {
          fault(typeFaultFor(op0));
          return true;
        }
        node.context[execution.context].r[execution.op2]
            = boolean(static_cast<std::uint8_t>(tag(execution.rs)) == (right & 0xfu));
        return finish();
      case Opcode::Carry:
      case Opcode::Add:
      case Opcode::Sub: {
        if (!checkedIntegerPair(nodeIndex, execution)) return true;
        const std::uint32_t result = execution.opcode == Opcode::Sub
            ? left - right : left + right;
        if (execution.checked
            && ((execution.opcode != Opcode::Sub && addOverflow(left, right, result))
                || (execution.opcode == Opcode::Sub
                    && subOverflow(left, right, result)))) {
          fault(Fault::Overflow);
          return true;
        }
        if (execution.opcode == Opcode::Carry) {
          node.context[execution.context].r[execution.op2]
              = integer(left > ~right ? 1u : 0u);
        } else {
          node.context[execution.context].r[execution.op2]
              = word(execution.checked ? Tag::Int : tag(execution.rs), result);
        }
        return finish();
      }
      case Opcode::Mul:
      case Opcode::MulHigh: {
        if (!checkedIntegerPair(nodeIndex, execution)) return true;
        const std::int64_t product = std::int64_t{static_cast<std::int32_t>(left)}
                                   * static_cast<std::int32_t>(right);
        const std::uint64_t bits = static_cast<std::uint64_t>(product);
        if (execution.checked
            && static_cast<std::int64_t>(static_cast<std::int32_t>(bits))
                   != product) {
          fault(Fault::Overflow);
          return true;
        }
        const std::uint32_t result = execution.opcode == Opcode::Mul
            ? static_cast<std::uint32_t>(bits)
            : static_cast<std::uint32_t>(bits >> 32);
        node.context[execution.context].r[execution.op2]
            = word(execution.checked ? Tag::Int : tag(execution.rs), result);
        return finish();
      }
      case Opcode::ArithmeticShift:
      case Opcode::LogicalShift: {
        if (!checkedIntegerPair(nodeIndex, execution)) return true;
        const auto amount = static_cast<std::int32_t>(right);
        const std::uint32_t shifted = execution.opcode == Opcode::ArithmeticShift
            ? arithmeticShift(left, amount) : logicalShift(left, amount);
        if (execution.checked && amount > 0) {
          const std::uint32_t restored = execution.opcode == Opcode::ArithmeticShift
              ? arithmeticShift(shifted, -amount) : logicalShift(shifted, -amount);
          if (restored != left) {
            fault(Fault::Overflow);
            return true;
          }
        }
        node.context[execution.context].r[execution.op2]
            = word(execution.checked ? Tag::Int : tag(execution.rs), shifted);
        return finish();
      }
      case Opcode::Rotate:
        if (!checkedIntegerPair(nodeIndex, execution)) return true;
        node.context[execution.context].r[execution.op2]
            = word(execution.checked ? Tag::Int : tag(execution.rs),
                   rotateLeft(left, right));
        return finish();
      case Opcode::And:
      case Opcode::Or:
      case Opcode::Xor: {
        const bool legal = (tag(execution.rs) == Tag::Int && tag(op0) == Tag::Int)
                        || (tag(execution.rs) == Tag::Bool && tag(op0) == Tag::Bool);
        if (execution.checked && !legal) {
          fault(tag(execution.rs) != Tag::Int && tag(execution.rs) != Tag::Bool
                    ? typeFaultFor(execution.rs)
                    : (tag(op0) != Tag::Int && tag(op0) != Tag::Bool)
                        ? typeFaultFor(op0) : Fault::Type);
          return true;
        }
        std::uint32_t result = left ^ right;
        if (execution.opcode == Opcode::And) result = left & right;
        if (execution.opcode == Opcode::Or) result = left | right;
        node.context[execution.context].r[execution.op2]
            = word(tag(execution.rs), result);
        return finish();
      }
      case Opcode::FindFirstBit:
        if (execution.checked && tag(op0) != Tag::Int) {
          fault(typeFaultFor(op0));
          return true;
        }
        node.context[execution.context].r[execution.op2]
            = integer(findFirstBit(right));
        return finish();
      case Opcode::Not:
        if (execution.checked && tag(op0) != Tag::Int && tag(op0) != Tag::Bool) {
          fault(typeFaultFor(op0));
          return true;
        }
        if (tag(op0) == Tag::Bool) {
          node.context[execution.context].r[execution.op2]
              = word(Tag::Bool, right ^ 1u);
        } else {
          node.context[execution.context].r[execution.op2]
              = word(execution.checked ? Tag::Int : tag(op0), ~right);
        }
        return finish();
      case Opcode::Negate:
        if (execution.checked && tag(op0) != Tag::Int) {
          fault(typeFaultFor(op0));
          return true;
        }
        if (execution.checked && right == 0x8000'0000u) {
          fault(Fault::Overflow);
          return true;
        }
        node.context[execution.context].r[execution.op2]
            = word(execution.checked ? Tag::Int : tag(op0), 0u - right);
        return finish();
      case Opcode::Less:
      case Opcode::LessEqual:
      case Opcode::GreaterEqual:
      case Opcode::Greater: {
        const bool legal = tag(execution.rs) == tag(op0)
            && (tag(execution.rs) == Tag::Int || tag(execution.rs) == Tag::Bool);
        if (execution.checked && !legal) {
          fault(typeFaultFor(tag(execution.rs) != Tag::Int
                             && tag(execution.rs) != Tag::Bool
                                 ? execution.rs : op0));
          return true;
        }
        bool result = false;
        const auto signedLeft = static_cast<std::int32_t>(left);
        const auto signedRight = static_cast<std::int32_t>(right);
        if (execution.opcode == Opcode::Less) result = signedLeft < signedRight;
        if (execution.opcode == Opcode::LessEqual) result = signedLeft <= signedRight;
        if (execution.opcode == Opcode::GreaterEqual) result = signedLeft >= signedRight;
        if (execution.opcode == Opcode::Greater) result = signedLeft > signedRight;
        node.context[execution.context].r[execution.op2] = boolean(result);
        return finish();
      }
      case Opcode::EqualData:
      case Opcode::NotEqualData: {
        const bool legal = tag(execution.rs) == tag(op0)
            && (tag(execution.rs) == Tag::Int || tag(execution.rs) == Tag::Bool
                || tag(execution.rs) == Tag::Sym);
        if (execution.checked && !legal) {
          fault(typeFaultFor(execution.rs));
          return true;
        }
        bool result = left == right;
        if (execution.opcode == Opcode::NotEqualData) result = !result;
        node.context[execution.context].r[execution.op2] = boolean(result);
        return finish();
      }
      case Opcode::Equal:
      case Opcode::NotEqual:
        if (execution.checked
            && (tag(execution.rs) == Tag::CFuture || tag(execution.rs) == Tag::Future
                || tag(op0) == Tag::CFuture || tag(op0) == Tag::Future)) {
          fault(tag(execution.rs) == Tag::CFuture || tag(op0) == Tag::CFuture
                    ? Fault::CFuture : Fault::Future);
          return true;
        }
        node.context[execution.context].r[execution.op2] = boolean(
            execution.opcode == Opcode::Equal ? execution.rs == op0
                                              : execution.rs != op0);
        return finish();
      case Opcode::Translate:
      case Opcode::Probe: {
        if (execution.operand.kind != OperandKind::DataRegister
            && execution.operand.kind != OperandKind::AddressRegister) {
          fault(Fault::IllegalInstruction);
          return true;
        }
        if (execution.checked && tag(execution.rs) == Tag::CFuture) {
          fault(Fault::CFuture);
          return true;
        }
        const std::uint32_t row = tableRow(node, execution.rs);
        for (std::uint32_t index = 0; index < 4; ++index) {
          if (dramError(node, row + index)) {
            fault(Fault::DramError);
            return true;
          }
        }
        const bool hit0 = node.memory[row + 1] == execution.rs;
        const bool hit1 = node.memory[row + 3] == execution.rs;
        const bool hit = hit0 || hit1;
        const Word result = hit1 ? node.memory[row + 2]
                                 : hit0 ? node.memory[row] : nil();
        if (execution.opcode == Opcode::Translate && (!hit || result == nil())) {
          fault(Fault::Translate);
          return true;
        }
        if (execution.operand.kind == OperandKind::DataRegister) {
          node.context[execution.context].r[execution.operand.registerNumber] = result;
        } else {
          node.context[execution.context].a[execution.operand.registerNumber] = result;
          if (!execution.background) {
            node.id[execution.priority][execution.operand.registerNumber] = execution.rs;
          }
        }
        return finish();
      }
      case Opcode::Enter: {
        if (execution.checked && tag(op0) == Tag::CFuture) {
          fault(Fault::CFuture);
          return true;
        }
        const std::uint32_t row = tableRow(node, op0);
        for (std::uint32_t index = 0; index < 4; ++index) {
          if (dramError(node, row + index)) {
            fault(Fault::DramError);
            return true;
          }
        }
        const bool hit0 = node.memory[row + 1] == op0;
        const bool hit1 = node.memory[row + 3] == op0;
        const bool way = hit1 || (!hit0 && node.replacementWay);
        node.memory[row + (way ? 2u : 0u)] = execution.rs;
        node.memory[row + (way ? 3u : 1u)] = op0;
        node.replacementWay = !node.replacementWay;
        return finish();
      }
      case Opcode::Invalidate:
        for (std::size_t context = 0; context < kPriorities; ++context) {
          for (Word& addressValue : node.context[context].a) {
            std::uint32_t d = data(addressValue);
            d = (d & ~(1u << 30)) | (std::uint32_t{bit(d, 31)} << 30);
            addressValue = word(tag(addressValue), d);
          }
        }
        return finish();
      case Opcode::Suspend:
        return suspend(nodeIndex, execution);
      case Opcode::Call: {
        if (execution.checked && tag(op0) != Tag::Int) {
          fault(typeFaultFor(op0));
          return true;
        }
        const std::uint32_t vectorAddress
            = (0x80u + (right & kAddressMask)) & kAddressMask;
        const Word vector = node.memory[vectorAddress];
        if (dramError(node, vectorAddress)) {
          fault(Fault::DramError);
          return true;
        }
        if (tag(vector) != Tag::Ip) {
          fault(typeFaultFor(vector));
          return true;
        }
        node.context[execution.context].fip = node.context[execution.context].ip;
        node.context[execution.context].ip = vector;
        return finish();
      }
      case Opcode::Send:
      case Opcode::SendEnd:
      case Opcode::Send2:
      case Opcode::Send2End:
        if (execution.checked && tag(op0) == Tag::CFuture) {
          fault(Fault::CFuture);
          return true;
        }
        if (!offerSend(nodeIndex, execution)) {
          fault(Fault::Send);
          return true;
        }
        return finish();
      case Opcode::Branch:
      case Opcode::BranchNil:
      case Opcode::BranchNotNil:
      case Opcode::BranchFalse:
      case Opcode::BranchTrue:
      case Opcode::BranchZero:
      case Opcode::BranchNotZero: {
        if (execution.checked && tag(op0) != Tag::Int) {
          fault(typeFaultFor(op0));
          return true;
        }
        bool take = execution.opcode == Opcode::Branch;
        if (execution.opcode == Opcode::BranchNil) take = execution.rs == nil();
        if (execution.opcode == Opcode::BranchNotNil) take = execution.rs != nil();
        if (execution.opcode == Opcode::BranchFalse) take = !bit(left, 0);
        if (execution.opcode == Opcode::BranchTrue) take = bit(left, 0);
        if (execution.opcode == Opcode::BranchZero) take = left == 0;
        if (execution.opcode == Opcode::BranchNotZero) take = left != 0;
        if (execution.checked
            && (execution.opcode == Opcode::BranchFalse
                || execution.opcode == Opcode::BranchTrue)
            && tag(execution.rs) != Tag::Bool) {
          fault(typeFaultFor(execution.rs));
          return true;
        }
        if (execution.checked
            && (execution.opcode == Opcode::BranchZero
                || execution.opcode == Opcode::BranchNotZero)
            && tag(execution.rs) != Tag::Int) {
          fault(typeFaultFor(execution.rs));
          return true;
        }
        if (execution.checked
            && (execution.opcode == Opcode::BranchNil
                || execution.opcode == Opcode::BranchNotNil)
            && (tag(execution.rs) == Tag::CFuture
                || tag(execution.rs) == Tag::Future)) {
          fault(typeFaultFor(execution.rs));
          return true;
        }
        if (take) {
          node.context[execution.context].ip = branchIp(
              node.context[execution.context].ip,
              execution.instructionWordOffset, signExtend(right & kAddressMask, 20));
        }
        return finish();
      }
      default:
        fault(Fault::IllegalInstruction);
        return true;
    }
  }

  bool stepNode(std::size_t nodeIndex) {
    Node& node = nodes[nodeIndex];
    if (node.catastrophe) return false;
    const std::size_t context = currentContext(node);
    const Word currentIp = node.context[context].ip;
    if (node.externalInterrupt && !node.interruptMask && !faultMode(currentIp)) {
      asynchronousFault(nodeIndex, Fault::Interrupt);
      return true;
    }
    if (!node.background && queueFull(node, node.priority)
        && !node.interruptMask && !faultMode(currentIp)) {
      asynchronousFault(nodeIndex, Fault::Queue);
      return true;
    }
    if (!node.interruptMask) {
      if (queuePending(node, true) && !node.activeMessage[1]
          && (node.background || !node.priority)) {
        return dispatch(nodeIndex, true);
      }
      if (queuePending(node, false) && !node.activeMessage[0]
          && node.background) {
        return dispatch(nodeIndex, false);
      }
    }

    Fault fetchFault = Fault::InvalidAddress;
    const std::uint32_t location = fetchAddress(node, context, node.priority,
                                                fetchFault);
    const Word fetchIp = node.context[context].ip;
    if ((!absoluteA0(fetchIp) && bit(data(node.context[context].a[0]), 30))
        || (!absoluteA0(fetchIp) && length(node.context[context].a[0]) != 0
            && base(fetchIp) >= length(node.context[context].a[0]))) {
      Execution execution;
      execution.context = context;
      execution.priority = node.priority;
      execution.background = node.background;
      execution.instructionIp = fetchIp;
      raiseFault(nodeIndex, execution, fetchFault, nil(), nil(), false);
      return true;
    }
    if (dramError(node, location)) {
      Execution execution;
      execution.context = context;
      execution.priority = node.priority;
      execution.background = node.background;
      execution.instructionIp = fetchIp;
      raiseFault(nodeIndex, execution, Fault::DramError, nil(), nil(), false);
      return true;
    }
    const Word fetched = node.memory[location];
    if (!instructionWord(fetched)) {
      node.context[context].r[0] = fetched;
      std::uint32_t nextData = data(fetchIp);
      nextData &= ~((kAddressMask << 10) | (1u << 9));
      nextData |= ((base(fetchIp) + 1u) & kAddressMask) << 10;
      node.context[context].ip = word(tag(fetchIp), nextData);
      appendTrace(nodeIndex, TraceKind::Constant, fetchIp, 0,
                  Fault::Catastrophe, location, fetched);
      return true;
    }

    Execution execution;
    execution.context = context;
    execution.priority = node.priority;
    execution.background = node.background;
    execution.instructionIp = fetchIp;
    execution.instructionWordOffset = base(fetchIp);
    execution.instruction = phase(fetchIp) ? lowInstruction(fetched)
                                           : highInstruction(fetched);
    execution.opcode = static_cast<Opcode>((execution.instruction >> 11) & 0x3fu);
    execution.op2 = (execution.instruction >> 9) & 3u;
    execution.op1 = (execution.instruction >> 7) & 3u;
    execution.op0 = execution.instruction & 0x7fu;
    execution.rs = node.context[context].r[execution.op1];
    execution.checked = !unchecked(fetchIp);
    node.context[context].ip = incrementIp(fetchIp);
    return execute(nodeIndex, execution);
  }
};

Machine::Machine(std::size_t nodeCount)
    : impl_(std::make_unique<Impl>(nodeCount)) {}
Machine::~Machine() = default;
Machine::Machine(Machine&&) noexcept = default;
Machine& Machine::operator=(Machine&&) noexcept = default;

void Machine::reset() { impl_->reset(); }

void Machine::loaderWrite(std::size_t node, std::uint32_t addressValue,
                          Word value) {
  impl_->nodes.at(node).memory.at(addressValue & kAddressMask) = value & kWordMask;
}

Word Machine::readMemory(std::size_t node, std::uint32_t addressValue) const {
  return impl_->nodes.at(node).memory.at(addressValue & kAddressMask);
}

void Machine::writeMemory(std::size_t node, std::uint32_t addressValue,
                          Word value) {
  impl_->nodes.at(node).memory.at(addressValue & kAddressMask) = value & kWordMask;
}

void Machine::setExternalInterrupt(std::size_t node, bool asserted) {
  impl_->nodes.at(node).externalInterrupt = asserted;
}

void Machine::setDramError(std::size_t node, bool enabled,
                           std::uint32_t addressValue) {
  Impl::Node& selected = impl_->nodes.at(node);
  selected.dramErrorEnabled = enabled;
  selected.dramErrorAddress = addressValue & kAddressMask;
}

bool Machine::step() {
  for (std::size_t attempt = 0; attempt < impl_->nodes.size(); ++attempt) {
    const std::size_t node = impl_->roundRobin;
    impl_->roundRobin = (impl_->roundRobin + 1) % impl_->nodes.size();
    if (impl_->stepNode(node)) return true;
  }
  return false;
}

void Machine::run(std::uint64_t maximumEvents) {
  for (std::uint64_t event = 0; event < maximumEvents; ++event) {
    if (!step()) return;
  }
}

std::size_t Machine::nodeCount() const { return impl_->nodes.size(); }

NodeView Machine::view(std::size_t nodeIndex) const {
  const Impl::Node& node = impl_->nodes.at(nodeIndex);
  const std::size_t context = impl_->currentContext(node);
  NodeView result;
  for (std::size_t index = 0; index < kContexts; ++index) {
    result.contexts[index].registers = node.context[index].r;
    result.contexts[index].addresses = node.context[index].a;
    result.contexts[index].ip = node.context[index].ip;
    result.contexts[index].faultIp = node.context[index].fip;
  }
  result.identifiers = node.id;
  result.faultInstructions = node.fir;
  result.faultOperand0 = node.fop0;
  result.faultOperand1 = node.fop1;
  result.queueBaseMask = node.qbm;
  result.queueHeadLength = node.qhl;
  result.queueAddressing = node.queueAddressing;
  result.activeMessage = node.activeMessage;
  result.tableBaseMask = node.tbm;
  result.memoryAddress = node.mar;
  result.registers = node.context[context].r;
  result.addresses = node.context[context].a;
  result.ip = node.context[context].ip;
  result.nodeNumber = node.nnr;
  result.lastFault = static_cast<std::uint8_t>(node.lastFault);
  result.retiredInstructions = node.retired;
  result.background = node.background;
  result.priority = node.priority;
  result.interruptMask = node.interruptMask;
  result.unchecked = unchecked(result.ip);
  result.faultMode = faultMode(result.ip);
  result.catastrophe = node.catastrophe;
  for (std::size_t priority = 0; priority < kPriorities; ++priority) {
    result.queuePending[priority] = impl_->queuePending(node, priority);
    result.queueFull[priority] = impl_->queueFull(node, priority);
  }
  return result;
}

const std::vector<TraceEvent>& Machine::trace() const { return impl_->trace; }
void Machine::clearTrace() { impl_->trace.clear(); }

}  // namespace golden
}  // namespace jmachine
