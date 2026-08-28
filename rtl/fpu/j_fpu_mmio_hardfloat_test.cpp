#include "Vj_fpu_mmio_hardfloat.h"
#include "verilated.h"

#include <bit>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <memory>
#include <string>

double sc_time_stamp() { return 0.0; }

namespace {

constexpr std::uint32_t kBase = 0xfff00;
constexpr std::uint64_t kIntTag = std::uint64_t{1} << 32;
constexpr std::uint32_t kStart = std::uint32_t{1} << 31;
constexpr std::uint32_t kTininessAfter = std::uint32_t{1} << 9;

[[noreturn]] void fail(const std::string& message) {
  std::cerr << "FPU MMIO TEST FAIL: " << message << '\n';
  std::exit(1);
}

std::uint64_t intWord(std::uint32_t value) { return kIntTag | value; }

struct MemoryResponse {
  std::uint64_t word;
  bool error;
};

class Fixture {
 public:
  Fixture() : dut_{std::make_unique<Vj_fpu_mmio_hardfloat>(&context_)} {
    dut_->clk = 0;
    dut_->reset = 1;
    dut_->memory_request_valid = 0;
    for (int i = 0; i < 3; ++i) tick();
    dut_->reset = 0;
    tick();
  }

  MemoryResponse transact(bool write, std::uint32_t address,
                          std::uint64_t word = intWord(0)) {
    dut_->memory_request_write = write;
    dut_->memory_request_address = address;
    dut_->memory_request_wdata = word;
    dut_->memory_request_valid = 1;
    for (int cycles = 0; !dut_->memory_request_ready; ++cycles) {
      if (cycles == 512) fail("memory request remained stalled");
      tick();
    }
    tick();
    dut_->memory_request_valid = 0;
    for (int cycles = 0; !dut_->memory_response_valid; ++cycles) {
      if (cycles == 512) fail("memory response did not arrive");
      tick();
    }
    MemoryResponse response{dut_->memory_response_rdata,
                            static_cast<bool>(dut_->memory_response_error)};
    tick();
    return response;
  }

  void write(std::uint32_t offset, std::uint32_t value) {
    const MemoryResponse response = transact(true, kBase + offset, intWord(value));
    if (response.error) fail("valid MMIO write returned an error");
  }

  std::uint32_t read(std::uint32_t offset) {
    const MemoryResponse response = transact(false, kBase + offset);
    if (response.error) fail("valid MMIO read returned an error");
    if ((response.word >> 32) != 1) fail("MMIO read did not return an INT word");
    return static_cast<std::uint32_t>(response.word);
  }

  std::uint32_t waitDone() {
    for (int polls = 0; polls < 128; ++polls) {
      const std::uint32_t status = read(9);
      if (status & 2) return status;
    }
    fail("operation did not set done");
  }

 private:
  void tick() {
    dut_->clk = 0;
    dut_->eval();
    context_.timeInc(1);
    dut_->clk = 1;
    dut_->eval();
    context_.timeInc(1);
  }

  VerilatedContext context_;
  std::unique_ptr<Vj_fpu_mmio_hardfloat> dut_;
};

std::uint32_t f32Bits(float value) {
  return std::bit_cast<std::uint32_t>(value);
}

std::uint64_t f64Bits(double value) {
  return std::bit_cast<std::uint64_t>(value);
}

void runBinary32Add(Fixture& fixture) {
  fixture.write(1, f32Bits(12.5f));
  fixture.write(3, f32Bits(-2.25f));
  fixture.write(0, kStart | kTininessAfter);
  const std::uint32_t status = fixture.waitDone();
  if ((status & 1) || ((status >> 2) & 0x1f) != 0) {
    fail("binary32 add status is not done/exact");
  }
  if (fixture.read(7) != f32Bits(10.25f) || fixture.read(8) != 0) {
    fail("binary32 add MMIO result mismatch");
  }
  fixture.write(9, 2);
  if (fixture.read(9) & 2) fail("status write-one-to-clear failed");
}

void runBinary64Divide(Fixture& fixture) {
  const std::uint64_t a = f64Bits(7.0);
  const std::uint64_t b = f64Bits(2.0);
  fixture.write(1, static_cast<std::uint32_t>(a));
  fixture.write(2, static_cast<std::uint32_t>(a >> 32));
  fixture.write(3, static_cast<std::uint32_t>(b));
  fixture.write(4, static_cast<std::uint32_t>(b >> 32));
  fixture.write(0, kStart | kTininessAfter | (1u << 5) | 4u);
  const std::uint32_t status = fixture.waitDone();
  if (((status >> 2) & 0x1f) != 0) fail("binary64 divide raised flags");
  const std::uint64_t result = std::uint64_t{fixture.read(7)} |
      (std::uint64_t{fixture.read(8)} << 32);
  if (result != f64Bits(3.5)) fail("binary64 divide MMIO result mismatch");
}

void runErrorChecks(Fixture& fixture) {
  MemoryResponse response = fixture.transact(true, kBase + 1, 0x200000000ull);
  if (!response.error) fail("non-INT operand write was accepted");
  response = fixture.transact(false, kBase + 10);
  if (!response.error) fail("out-of-range MMIO read was accepted");
  response = fixture.transact(true, kBase, intWord(kStart | kTininessAfter | 31u));
  if (!response.error) fail("reserved operation was accepted");
  if (fixture.read(9) & 1) fail("invalid operation left the service busy");
}

}  // namespace

int main(int argc, char** argv) {
  Verilated::commandArgs(argc, argv);
  Fixture fixture;
  runBinary32Add(fixture);
  runBinary64Divide(fixture);
  runErrorChecks(fixture);
  std::cout << "PASS: tagged-word floating-point MMIO ABI and HardFloat backend\n";
  return 0;
}
