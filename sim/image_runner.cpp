#include <verilated.h>
#include "Vj_machine_verilator_top.h"

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
constexpr std::uint64_t kWordMask = 0x0000000fffffffffull;
constexpr std::uint32_t kAddressMask = 0x000fffffu;
constexpr unsigned kNodes = 2;

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

struct Simulator {
  Vj_machine_verilator_top top;

  void halfCycle(bool clock) {
    top.clk = clock;
    top.eval();
  }

  void cycle() {
    halfCycle(false);
    halfCycle(true);
  }

  void write(unsigned node, std::uint32_t address, std::uint64_t value) {
    top.debug_node = node;
    top.debug_address = address;
    top.debug_wdata = value;
    top.debug_write = 1;
    cycle();
    top.debug_write = 0;
  }

  std::uint64_t read(Location location) {
    top.debug_node = location.node;
    top.debug_address = location.address;
    top.eval();
    return top.debug_rdata & kWordMask;
  }
};

void loadImage(Simulator& simulator, const std::string& path) {
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
      for (unsigned node = 0; node < kNodes; ++node) {
        simulator.write(node, static_cast<std::uint32_t>(address), value);
      }
      continue;
    }
    const std::uint64_t node = parseUnsigned(nodeText, 0, "image node");
    if (node >= kNodes) {
      throw std::runtime_error(path + ":" + std::to_string(lineNumber)
                               + ": image node out of range");
    }
    simulator.write(static_cast<unsigned>(node),
                    static_cast<std::uint32_t>(address), value);
  }
}

void printUsage(const char* program) {
  std::cerr << "usage: " << program
            << " --image FILE [--cycles N] [--peek NODE:HEX_ADDRESS]"
               " [--expect NODE:HEX_ADDRESS:HEX_WORD]\n";
}
}  // namespace

int main(int argc, char** argv) {
  try {
    Verilated::commandArgs(argc, argv);
    std::string imagePath;
    std::uint64_t cycles = 10000;
    std::vector<Location> peeks;
    std::vector<Expectation> expectations;
    for (int index = 1; index < argc; ++index) {
      const std::string argument = argv[index];
      if (argument == "--image" && index + 1 < argc) {
        imagePath = argv[++index];
      } else if (argument == "--cycles" && index + 1 < argc) {
        cycles = parseUnsigned(argv[++index], 0, "cycle count");
      } else if (argument == "--peek" && index + 1 < argc) {
        peeks.push_back(parseLocation(argv[++index]));
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

    Simulator simulator;
    simulator.top.reset = 1;
    simulator.top.run_enable = 0;
    simulator.top.external_interrupt = 0;
    simulator.top.dram_error_inject = 0;
    simulator.top.dram_error_address = 0;
    simulator.top.debug_write = 0;
    simulator.cycle();
    loadImage(simulator, imagePath);
    simulator.top.reset = 0;
    simulator.top.run_enable = 1;
    for (std::uint64_t cycle = 0; cycle < cycles; ++cycle) simulator.cycle();
    simulator.top.run_enable = 0;
    simulator.top.eval();

    std::cout << "cycles=" << cycles;
    for (unsigned node = 0; node < 2; ++node) {
      const std::uint64_t retired = node == 0 ? simulator.top.node0_retired
                                               : simulator.top.node1_retired;
      const unsigned fault = node == 0 ? simulator.top.node0_last_fault
                                        : simulator.top.node1_last_fault;
      const unsigned catastrophe = node == 0 ? simulator.top.node0_catastrophe
                                              : simulator.top.node1_catastrophe;
      const std::uint64_t ip = node == 0 ? simulator.top.node0_ip
                                         : simulator.top.node1_ip;
      const unsigned background = node == 0 ? simulator.top.node0_background
                                             : simulator.top.node1_background;
      const unsigned priority = node == 0 ? simulator.top.node0_priority
                                           : simulator.top.node1_priority;
      const unsigned pending = node == 0 ? simulator.top.node0_queue_pending
                                          : simulator.top.node1_queue_pending;
      std::cout << " node" << node << "_retired=" << std::dec << retired
                << " fault=0x" << std::hex << fault
                << " catastrophe=" << std::dec << catastrophe
                << " ip=0x" << std::hex << ip
                << " background=" << std::dec << background
                << " priority=" << priority
                << " pending=0x" << std::hex << pending;
    }
    std::cout << '\n';
    for (const Location location : peeks) {
      std::cout << "peek node=" << location.node << " address=0x" << std::hex
                << std::setw(5) << std::setfill('0') << location.address
                << " value=0x" << std::setw(9) << simulator.read(location) << '\n';
    }
    bool failed = simulator.top.node0_catastrophe != 0
               || simulator.top.node1_catastrophe != 0;
    for (const Expectation& expectation : expectations) {
      const std::uint64_t actual = simulator.read(expectation.location);
      if (actual != expectation.value) {
        std::cerr << "EXPECTATION FAIL node=" << expectation.location.node
                  << " address=0x" << std::hex << expectation.location.address
                  << " expected=0x" << expectation.value
                  << " actual=0x" << actual << '\n';
        failed = true;
      }
    }
    return failed ? 1 : 0;
  } catch (const std::exception& error) {
    std::cerr << "mdp-verilator: " << error.what() << '\n';
    return 2;
  }
}
