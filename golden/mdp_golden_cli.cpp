#include "mdp_golden.hpp"

#include <algorithm>
#include <cerrno>
#include <cstdint>
#include <cstdlib>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

namespace {
using namespace jmachine::golden;

const char* traceKindName(TraceKind kind) {
  switch (kind) {
    case TraceKind::Constant: return "constant";
    case TraceKind::Instruction: return "instruction";
    case TraceKind::Dispatch: return "dispatch";
    case TraceKind::Send: return "send";
    case TraceKind::Suspend: return "suspend";
    case TraceKind::Fault: return "fault";
    case TraceKind::Catastrophe: return "catastrophe";
  }
  return "unknown";
}

std::uint64_t parseUnsigned(const std::string& text, int base,
                            const char* description) {
  if (text.empty() || text.front() == '-') {
    throw std::runtime_error(std::string("invalid ") + description + ": " + text);
  }
  errno = 0;
  char* end = nullptr;
  const unsigned long long value = std::strtoull(text.c_str(), &end, base);
  if (errno != 0 || end == text.c_str() || *end != '\0') {
    throw std::runtime_error(std::string("invalid ") + description + ": " + text);
  }
  return value;
}

void loadImage(Machine& machine, const std::string& path) {
  std::ifstream input(path);
  if (!input) throw std::runtime_error("cannot open image: " + path);
  std::string line;
  std::uint64_t lineNumber = 0;
  while (std::getline(input, line)) {
    ++lineNumber;
    const std::size_t comment = line.find('#');
    if (comment != std::string::npos) line.erase(comment);
    std::istringstream fields(line);
    std::string nodeText;
    std::string addressText;
    std::string wordText;
    if (!(fields >> nodeText)) continue;
    if (!(fields >> addressText >> wordText)) {
      throw std::runtime_error(path + ":" + std::to_string(lineNumber)
                               + ": expected NODE ADDRESS WORD");
    }
    std::string extra;
    if (fields >> extra) {
      throw std::runtime_error(path + ":" + std::to_string(lineNumber)
                               + ": trailing field " + extra);
    }
    const std::uint64_t addressValue = parseUnsigned(addressText, 16, "address");
    const std::uint64_t value = parseUnsigned(wordText, 16, "word");
    if (addressValue > kAddressMask || value > kWordMask) {
      throw std::runtime_error(path + ":" + std::to_string(lineNumber)
                               + ": architectural value out of range");
    }
    if (nodeText == "*") {
      for (std::size_t node = 0; node < machine.nodeCount(); ++node) {
        machine.loaderWrite(node, static_cast<std::uint32_t>(addressValue), value);
      }
      continue;
    }
    const std::uint64_t node = parseUnsigned(nodeText, 0, "node");
    if (node >= machine.nodeCount()) {
      throw std::runtime_error(path + ":" + std::to_string(lineNumber)
                               + ": node out of range");
    }
    machine.loaderWrite(static_cast<std::size_t>(node),
                        static_cast<std::uint32_t>(addressValue), value);
  }
}

void printUsage(const char* program) {
  std::cerr << "usage: " << program
            << " --image FILE [--nodes N] [--events N] [--trace]"
               " [--status NODE]"
               " [--peek NODE:HEX_ADDRESS]"
               " [--expect NODE:HEX_ADDRESS:HEX_WORD]\n"
               "image rows are: NODE|* HEX_ADDRESS HEX_36_BIT_WORD\n";
}

struct Peek {
  std::size_t node = 0;
  std::uint32_t address = 0;
};

Peek parsePeek(const std::string& text) {
  const std::size_t separator = text.find(':');
  if (separator == std::string::npos || separator == 0
      || separator + 1 == text.size()) {
    throw std::runtime_error("invalid peek; expected NODE:HEX_ADDRESS: " + text);
  }
  const std::uint64_t node = parseUnsigned(text.substr(0, separator), 0, "peek node");
  const std::uint64_t addressValue = parseUnsigned(
      text.substr(separator + 1), 16, "peek address");
  if (addressValue > kAddressMask) {
    throw std::runtime_error("peek address out of range: " + text);
  }
  return Peek{static_cast<std::size_t>(node),
              static_cast<std::uint32_t>(addressValue)};
}

struct Expectation {
  Peek location;
  std::uint64_t value = 0;
};

Expectation parseExpectation(const std::string& text) {
  const std::size_t separator = text.rfind(':');
  if (separator == std::string::npos || separator + 1 == text.size()) {
    throw std::runtime_error(
        "invalid expectation; expected NODE:HEX_ADDRESS:HEX_WORD: " + text);
  }
  const Peek location = parsePeek(text.substr(0, separator));
  const std::uint64_t value = parseUnsigned(
      text.substr(separator + 1), 16, "expected word");
  if (value > kWordMask) {
    throw std::runtime_error("expected word out of range: " + text);
  }
  return Expectation{location, value};
}

}  // namespace

int main(int argc, char** argv) {
  try {
    std::size_t nodes = 1;
    std::uint64_t events = 1000;
    std::string imagePath;
    std::vector<Peek> peeks;
    std::vector<Expectation> expectations;
    std::vector<std::size_t> statusNodes;
    bool printTrace = false;
    for (int index = 1; index < argc; ++index) {
      const std::string argument = argv[index];
      if (argument == "--nodes" && index + 1 < argc) {
        nodes = static_cast<std::size_t>(parseUnsigned(argv[++index], 0, "node count"));
      } else if (argument == "--events" && index + 1 < argc) {
        events = parseUnsigned(argv[++index], 0, "event count");
      } else if (argument == "--image" && index + 1 < argc) {
        imagePath = argv[++index];
      } else if (argument == "--peek" && index + 1 < argc) {
        peeks.push_back(parsePeek(argv[++index]));
      } else if (argument == "--status" && index + 1 < argc) {
        statusNodes.push_back(static_cast<std::size_t>(
            parseUnsigned(argv[++index], 0, "status node")));
      } else if (argument == "--expect" && index + 1 < argc) {
        expectations.push_back(parseExpectation(argv[++index]));
      } else if (argument == "--trace") {
        printTrace = true;
      } else if (argument == "--help" || argument == "-h") {
        printUsage(argv[0]);
        return 0;
      } else {
        printUsage(argv[0]);
        return 2;
      }
    }
    if (imagePath.empty()) {
      printUsage(argv[0]);
      return 2;
    }

    Machine machine(nodes);
    loadImage(machine, imagePath);
    machine.run(events);

    if (printTrace) {
      for (const TraceEvent& event : machine.trace()) {
        std::cout << std::dec << event.sequence << '\t' << event.node << '\t'
                  << traceKindName(event.kind) << "\tip=" << std::hex
                  << std::setw(9) << std::setfill('0') << event.ip
                  << "\tinsn=" << std::setw(5) << event.instruction
                  << "\tfault=" << std::setw(2)
                  << unsigned(static_cast<std::uint8_t>(event.fault))
                  << "\taddress=" << std::setw(5) << event.address
                  << "\tvalue=" << std::setw(9) << event.value;
        if (!event.detail.empty()) std::cout << '\t' << event.detail;
        std::cout << '\n';
      }
    }

    bool anyCatastrophe = false;
    for (std::size_t node = 0; node < machine.nodeCount(); ++node) {
      const NodeView state = machine.view(node);
      anyCatastrophe |= state.catastrophe;
      if (!statusNodes.empty()
          && std::find(statusNodes.begin(), statusNodes.end(), node)
              == statusNodes.end()) {
        continue;
      }
      std::cout << "node=" << std::dec << node << " nnr=" << state.nodeNumber
                << " retired=" << state.retiredInstructions << " ip=0x"
                << std::hex << std::setw(9) << std::setfill('0') << state.ip
                << " fault=0x" << std::setw(2) << unsigned(state.lastFault)
                << " catastrophe=" << std::dec << state.catastrophe
                << " q0=" << state.queuePending[0]
                << " q1=" << state.queuePending[1];
      for (std::size_t reg = 0; reg < state.registers.size(); ++reg) {
        std::cout << " r" << reg << "=0x" << std::hex << std::setw(9)
                  << state.registers[reg];
      }
      for (std::size_t reg = 0; reg < state.addresses.size(); ++reg) {
        std::cout << " a" << reg << "=0x" << std::hex << std::setw(9)
                  << state.addresses[reg];
      }
      std::cout << '\n';
    }
    for (const Peek& peek : peeks) {
      if (peek.node >= machine.nodeCount()) {
        throw std::runtime_error("peek node out of range");
      }
      std::cout << "peek node=" << std::dec << peek.node << " address=0x"
                << std::hex << std::setw(5) << std::setfill('0') << peek.address
                << " value=0x" << std::setw(9)
                << machine.readMemory(peek.node, peek.address) << '\n';
    }
    bool failed = anyCatastrophe;
    for (const Expectation& expectation : expectations) {
      if (expectation.location.node >= machine.nodeCount()) {
        throw std::runtime_error("expectation node out of range");
      }
      const std::uint64_t actual = machine.readMemory(
          expectation.location.node, expectation.location.address);
      if (actual != expectation.value) {
        std::cerr << "EXPECTATION FAIL node=" << std::dec
                  << expectation.location.node << " address=0x" << std::hex
                  << expectation.location.address << " expected=0x"
                  << expectation.value << " actual=0x" << actual << '\n';
        failed = true;
      }
    }
    return failed ? 1 : 0;
  } catch (const std::exception& error) {
    std::cerr << "mdp-golden: " << error.what() << '\n';
    return 2;
  }
}
