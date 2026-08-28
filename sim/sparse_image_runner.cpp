#include <verilated.h>
#include "Vj_machine_verilator_sparse_top.h"

#include <cerrno>
#include <cstdint>
#include <cstdlib>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <vector>

namespace {
constexpr std::uint64_t kWordMask = 0x0000000fffffffffull;
constexpr std::uint32_t kAddressMask = 0x000fffffu;
#ifndef J_MACHINE_SIM_NODES
#define J_MACHINE_SIM_NODES 512
#endif
constexpr unsigned kNodes = J_MACHINE_SIM_NODES;
static_assert(kNodes > 0, "the sparse runner requires at least one node");

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

struct Location {
  unsigned node = 0;
  std::uint32_t address = 0;
};

struct Expectation {
  Location location;
  std::uint64_t value = 0;
};

Location parseLocation(const std::string& text) {
  const std::size_t separator = text.find(':');
  if (separator == std::string::npos || separator == 0
      || separator + 1 == text.size()) {
    throw std::runtime_error("expected NODE:HEX_ADDRESS: " + text);
  }
  const std::uint64_t node = parseUnsigned(text.substr(0, separator), 0, "node");
  const std::uint64_t address = parseUnsigned(
      text.substr(separator + 1), 16, "address");
  if (node >= kNodes || address > kAddressMask) {
    throw std::runtime_error("location out of range: " + text);
  }
  return Location{static_cast<unsigned>(node), static_cast<std::uint32_t>(address)};
}

Expectation parseExpectation(const std::string& text) {
  const std::size_t last = text.rfind(':');
  if (last == std::string::npos || last + 1 == text.size()) {
    throw std::runtime_error("expected NODE:HEX_ADDRESS:HEX_WORD: " + text);
  }
  const Location location = parseLocation(text.substr(0, last));
  const std::uint64_t value = parseUnsigned(text.substr(last + 1), 16, "word");
  if (value > kWordMask) throw std::runtime_error("word out of range: " + text);
  return Expectation{location, value};
}

class SparseMemory {
 public:
  SparseMemory() : perNode_(kNodes) {}

  std::uint64_t read(unsigned node, std::uint32_t address) const {
    const auto& local = perNode_.at(node);
    const auto localEntry = local.find(address & kAddressMask);
    if (localEntry != local.end()) return localEntry->second;
    const auto commonEntry = common_.find(address & kAddressMask);
    return commonEntry == common_.end() ? 0 : commonEntry->second;
  }

  void write(unsigned node, std::uint32_t address, std::uint64_t value) {
    address &= kAddressMask;
    value &= kWordMask;
    const auto commonEntry = common_.find(address);
    const std::uint64_t inherited
        = commonEntry == common_.end() ? 0 : commonEntry->second;
    auto& local = perNode_.at(node);
    if (value == inherited) local.erase(address);
    else local[address] = value;
  }

  void writeCommon(std::uint32_t address, std::uint64_t value) {
    address &= kAddressMask;
    value &= kWordMask;
    if (value == 0) common_.erase(address);
    else common_[address] = value;
    // Wildcard rows are ordered image writes and therefore replace an earlier
    // node override at the same address if a hand-written image contains one.
    for (auto& local : perNode_) local.erase(address);
  }

  std::size_t commonWords() const { return common_.size(); }

  std::size_t overrideWords() const {
    std::size_t total = 0;
    for (const auto& local : perNode_) total += local.size();
    return total;
  }

 private:
  std::unordered_map<std::uint32_t, std::uint64_t> common_;
  std::vector<std::unordered_map<std::uint32_t, std::uint64_t>> perNode_;
};

SparseMemory memory;

struct Simulator {
  Vj_machine_verilator_sparse_top top;

  void halfCycle(bool clock) {
    top.clk = clock;
    top.eval();
  }

  void cycle() {
    halfCycle(false);
    halfCycle(true);
  }

  void select(unsigned node) {
    top.debug_node = node;
    top.eval();
  }
};

void loadImage(const std::string& path) {
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
    const std::uint64_t address = parseUnsigned(addressText, 16, "image address");
    const std::uint64_t value = parseUnsigned(wordText, 16, "image word");
    if (address > kAddressMask || value > kWordMask) {
      throw std::runtime_error(path + ":" + std::to_string(lineNumber)
                               + ": architectural value out of range");
    }
    if (nodeText == "*") {
      memory.writeCommon(static_cast<std::uint32_t>(address), value);
      continue;
    }
    const std::uint64_t node = parseUnsigned(nodeText, 0, "image node");
    if (node >= kNodes) {
      throw std::runtime_error(path + ":" + std::to_string(lineNumber)
                               + ": image node out of range");
    }
    memory.write(static_cast<unsigned>(node),
                 static_cast<std::uint32_t>(address), value);
  }
}

void printUsage(const char* program) {
  std::cerr << "usage: " << program
            << " --image FILE [--cycles N] [--status NODE]"
               " [--peek NODE:HEX_ADDRESS]"
               " [--stop-when NODE:HEX_ADDRESS:HEX_WORD]"
               " [--expect NODE:HEX_ADDRESS:HEX_WORD]\n";
}

bool allMatch(const std::vector<Expectation>& conditions) {
  for (const Expectation& condition : conditions) {
    if (memory.read(condition.location.node, condition.location.address)
        != condition.value) {
      return false;
    }
  }
  return true;
}
}  // namespace

extern "C" unsigned long long mdp_sparse_memory_read(
    unsigned int node, unsigned int address) {
  return memory.read(node, address);
}

extern "C" void mdp_sparse_memory_write(
    unsigned int node, unsigned int address, unsigned long long value) {
  memory.write(node, address, value);
}

int main(int argc, char** argv) {
  try {
    Verilated::commandArgs(argc, argv);
    std::string imagePath;
    std::uint64_t cycles = 10000;
    std::vector<unsigned> statusNodes;
    std::vector<Location> peeks;
    std::vector<Expectation> stopConditions;
    std::vector<Expectation> expectations;
    for (int index = 1; index < argc; ++index) {
      const std::string argument = argv[index];
      if (argument == "--image" && index + 1 < argc) {
        imagePath = argv[++index];
      } else if (argument == "--cycles" && index + 1 < argc) {
        cycles = parseUnsigned(argv[++index], 0, "cycle count");
      } else if (argument == "--status" && index + 1 < argc) {
        const std::uint64_t node = parseUnsigned(argv[++index], 0, "status node");
        if (node >= kNodes) throw std::runtime_error("status node out of range");
        statusNodes.push_back(static_cast<unsigned>(node));
      } else if (argument == "--peek" && index + 1 < argc) {
        peeks.push_back(parseLocation(argv[++index]));
      } else if (argument == "--stop-when" && index + 1 < argc) {
        stopConditions.push_back(parseExpectation(argv[++index]));
      } else if (argument == "--expect" && index + 1 < argc) {
        expectations.push_back(parseExpectation(argv[++index]));
      } else if (argument == "-h" || argument == "--help") {
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

    loadImage(imagePath);
    Simulator simulator;
    simulator.top.reset = 1;
    simulator.top.run_enable = 0;
    simulator.top.debug_node = 0;
    simulator.cycle();
    simulator.top.reset = 0;
    simulator.top.run_enable = 1;
    std::uint64_t executedCycles = 0;
    bool stopped = false;
    while (executedCycles < cycles) {
      simulator.cycle();
      ++executedCycles;
      if (simulator.top.any_catastrophe) {
        std::cerr << "CATASTROPHE at cycle " << std::dec << executedCycles << '\n';
        break;
      }
      if (!stopConditions.empty() && allMatch(stopConditions)) {
        stopped = true;
        break;
      }
    }
    simulator.top.run_enable = 0;
    simulator.top.eval();

    std::cout << "cycles=" << executedCycles
              << " max_cycles=" << cycles
              << " stopped=" << std::dec << unsigned(stopped)
              << " common_words=" << memory.commonWords()
              << " override_words=" << memory.overrideWords() << '\n';
    for (const unsigned node : statusNodes) {
      simulator.select(node);
      std::cout << "node=" << std::dec << node
                << " nnr=" << std::dec << simulator.top.debug_node_number
                << " retired=" << simulator.top.debug_retired
                << " fault=0x" << std::hex << unsigned(simulator.top.debug_last_fault)
                << " catastrophe=" << std::dec
                << unsigned(simulator.top.debug_catastrophe)
                << " ip=0x" << std::hex << simulator.top.debug_ip
                << " r0=0x" << simulator.top.debug_r0
                << " background=" << std::dec
                << unsigned(simulator.top.debug_background)
                << " priority=" << unsigned(simulator.top.debug_priority)
                << " pending=0x" << std::hex
                << unsigned(simulator.top.debug_queue_pending) << '\n';
    }
    for (const Location location : peeks) {
      std::cout << "peek node=" << std::dec << location.node
                << " address=0x" << std::hex
                << std::setw(5) << std::setfill('0') << location.address
                << " value=0x" << std::setw(9)
                << memory.read(location.node, location.address) << '\n';
    }

    bool failed = simulator.top.any_catastrophe != 0;
    if (!stopConditions.empty() && !stopped) {
      std::cerr << "STOP CONDITION NOT REACHED within " << std::dec << cycles
                << " cycles\n";
      failed = true;
    }
    for (const Expectation& expectation : expectations) {
      const std::uint64_t actual
          = memory.read(expectation.location.node, expectation.location.address);
      if (actual != expectation.value) {
        std::cerr << "EXPECTATION FAIL node=" << std::dec
                  << expectation.location.node
                  << " address=0x" << std::hex << expectation.location.address
                  << " expected=0x" << expectation.value
                  << " actual=0x" << actual << '\n';
        failed = true;
      }
    }
    simulator.top.final();
    return failed ? 1 : 0;
  } catch (const std::exception& error) {
    std::cerr << "mdp-verilator-512: " << error.what() << '\n';
    return 2;
  }
}
