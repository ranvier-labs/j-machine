#include <verilated.h>
#include "Vj_node_backpressure_top.h"

#include <cerrno>
#include <cstdint>
#include <cstdlib>
#include <fstream>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include <string>

namespace {
constexpr std::uint64_t kWordMask = 0x0000000fffffffffull;
constexpr std::uint32_t kAddressMask = 0x000fffffu;
constexpr std::uint32_t kResultAddress = 0x00300u;
constexpr std::uint32_t kSendFaultCountAddress = 0x00709u;
constexpr std::uint32_t kBackgroundRetryBase = 0x00720u;
constexpr std::uint64_t kIntZero = 0x100000000ull;
constexpr std::uint64_t kExpectedResult = 0x10000004dull;

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

struct Simulator {
  Vj_node_backpressure_top top;

  void cycle() {
    top.clk = 0;
    top.eval();
    top.clk = 1;
    top.eval();
  }

  void write(std::uint32_t address, std::uint64_t value) {
    top.debug_address = address;
    top.debug_wdata = value;
    top.debug_write = 1;
    cycle();
    top.debug_write = 0;
  }

  std::uint64_t read(std::uint32_t address) {
    top.debug_address = address;
    top.eval();
    return top.debug_rdata & kWordMask;
  }
};

void loadNodeZeroImage(Simulator& simulator, const std::string& path) {
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
    if (nodeText == "*" || parseUnsigned(nodeText, 0, "image node") == 0) {
      simulator.write(static_cast<std::uint32_t>(address), value);
    }
  }
}
}  // namespace

int main(int argc, char** argv) {
  try {
    Verilated::commandArgs(argc, argv);
    if (argc != 2) {
      std::cerr << "usage: " << argv[0] << " IMAGE\n";
      return 2;
    }

    Simulator simulator;
    simulator.top.reset = 1;
    simulator.top.run_enable = 0;
    simulator.top.block_network = 1;
    simulator.top.debug_write = 0;
    simulator.cycle();
    loadNodeZeroImage(simulator, argv[1]);
    simulator.top.reset = 0;
    simulator.top.run_enable = 1;

    constexpr std::uint64_t maxCycles = 500000;
    bool sawBlockedFlit = false;
    bool releasedNetwork = false;
    std::uint64_t releaseCycle = 0;
    std::uint64_t completionCycle = 0;
    for (std::uint64_t cycle = 1; cycle <= maxCycles; ++cycle) {
      simulator.cycle();
      if (simulator.top.block_network && simulator.top.network_tx_valid != 0) {
        sawBlockedFlit = true;
      }
      if (simulator.top.catastrophe != 0) {
        throw std::runtime_error("processor entered catastrophe during SEND retry");
      }
      const std::uint64_t faultCount = simulator.read(kSendFaultCountAddress);
      if (!releasedNetwork && (faultCount >> 32) == 1
          && (faultCount & 0xffffffffu) >= 2) {
        simulator.top.block_network = 0;
        releasedNetwork = true;
        releaseCycle = cycle;
      }
      if (simulator.read(kResultAddress) == kExpectedResult) {
        completionCycle = cycle;
        break;
      }
    }
    simulator.top.run_enable = 0;
    simulator.top.eval();

    const std::uint64_t result = simulator.read(kResultAddress);
    const std::uint64_t faultCount = simulator.read(kSendFaultCountAddress);
    const std::uint64_t active = simulator.read(kBackgroundRetryBase);
    std::cout << "SEND backpressure: release_cycle=" << releaseCycle
              << " completion_cycle=" << completionCycle
              << " retired=" << simulator.top.retired_instructions
              << " fault_count=" << std::dec << (faultCount & 0xffffffffu)
              << " last_fault=" << static_cast<unsigned>(simulator.top.last_fault)
              << " result=0x" << std::hex << result << '\n';

    if (!sawBlockedFlit) throw std::runtime_error("backpressure never blocked an offered flit");
    if (!releasedNetwork) throw std::runtime_error("SEND handler did not re-enter twice");
    if (completionCycle == 0 || result != kExpectedResult) {
      throw std::runtime_error("main did not resume with INT(77)");
    }
    if ((faultCount >> 32) != 1 || (faultCount & 0xffffffffu) < 2) {
      throw std::runtime_error("architectural SEND-fault counter is invalid");
    }
    if (simulator.top.last_fault != 3) {
      throw std::runtime_error("last architectural fault was not SEND (3)");
    }
    if (active != kIntZero) {
      throw std::runtime_error("background SEND retry frame remained active");
    }
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "send-fault-verilator: " << error.what() << '\n';
    return 1;
  }
}
