#include "Vmdp_qrb_backpressure_test_top.h"
#include "verilated.h"

#include <array>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <string>

double sc_time_stamp() { return 0.0; }

namespace {

using Top = Vmdp_qrb_backpressure_test_top;

[[noreturn]] void fail(const std::string& message) {
  std::cerr << "FAIL: " << message << '\n';
  std::exit(1);
}

void expect(bool condition, const std::string& message) {
  if (!condition) fail(message);
}

void tick(Top& top) {
  top.clk = 0;
  top.eval();
  top.clk = 1;
  top.eval();
}

std::uint64_t wideBits(const WData* words, int lowBit, int width) {
  std::uint64_t result = 0;
  for (int bit = 0; bit < width; ++bit) {
    const int source = lowBit + bit;
    if ((words[source / 32] >> (source % 32)) & 1u) {
      result |= std::uint64_t{1} << bit;
    }
  }
  return result;
}

void driveWord(Top& top, std::uint64_t word) {
  top.receive_valid = 1;
  top.receive_word = word;
  top.receive_tail = 0;
  top.eval();
}

void acceptWord(Top& top, std::uint64_t word, const std::string& context) {
  driveWord(top, word);
  expect(top.receive_ready, context + " was not accepted");
  tick(top);
}

void expectRow(const Top& top, std::uint32_t address,
               const std::array<std::uint64_t, 4>& words,
               const std::string& context) {
  expect(top.qrb_write, context + " valid");
  expect(top.qrb_row_address == address, context + " address");
  expect(top.qrb_write_enable == 0xf, context + " enables");
  for (int lane = 0; lane < 4; ++lane) {
    expect(wideBits(top.qrb_write_data, lane * 36, 36) == words[lane],
           context + " lane " + std::to_string(lane));
  }
}

}  // namespace

int main(int argc, char** argv) {
  Verilated::commandArgs(argc, argv);
  Top top;
  top.configure_qbm = 0;
  top.qbm_value = 0;
  top.receive_valid = 0;
  top.receive_word = 0;
  top.receive_tail = 0;
  top.qrb_ready = 0;
  top.reset = 1;
  tick(top);
  tick(top);
  top.reset = 0;

  // Enable priority-zero queue storage at word address 0x100 with a 16-word
  // circular capacity. The encoding is {ADDR tag, relocatable, invalid,
  // 20-bit base, 10-bit length-minus-one}.
  top.configure_qbm = 1;
  top.qbm_value = (std::uint64_t{3} << 32)
                | (std::uint64_t{0x100} << 10) | 0xf;
  tick(top);
  top.configure_qbm = 0;

  const std::array<std::uint64_t, 4> first = {
      0x100000001ull, 0x200000002ull, 0x300000003ull, 0x400000004ull};
  for (int lane = 0; lane < 3; ++lane) {
    acceptWord(top, first[lane], "first row word " + std::to_string(lane));
  }

  // The fourth word completes a row. It is accepted into the elastic pending
  // register even though the shared PCIM arbiter is stalled.
  driveWord(top, first[3]);
  expect(top.receive_ready, "first committing word was not buffered");
  expectRow(top, 0x40, first, "first direct row");
  tick(top);
  top.receive_valid = 0;
  top.eval();
  expectRow(top, 0x40, first, "first pending row");
  tick(top);
  expectRow(top, 0x40, first, "first stalled row");

  const std::array<std::uint64_t, 4> second = {
      0x500000005ull, 0x600000006ull, 0x700000007ull, 0x800000008ull};
  for (int lane = 0; lane < 3; ++lane) {
    acceptWord(top, second[lane], "second row word " + std::to_string(lane));
    expectRow(top, 0x40, first, "first row while second accumulates");
  }

  // A second complete row cannot overwrite a stalled pending row.
  driveWord(top, second[3]);
  expect(!top.receive_ready, "second committing word escaped backpressure");
  expectRow(top, 0x40, first, "first row before replacement");
  tick(top);

  // When PCIM accepts the old row, the waiting commit is accepted in the same
  // cycle and atomically replaces it in the pending register.
  top.qrb_ready = 1;
  top.eval();
  expect(top.receive_ready, "replacement commit was not accepted");
  expectRow(top, 0x40, first, "first row at replacement handshake");
  tick(top);
  top.receive_valid = 0;
  top.qrb_ready = 0;
  top.eval();
  expectRow(top, 0x41, second, "second pending row");
  tick(top);
  expectRow(top, 0x41, second, "second stalled row");

  top.qrb_ready = 1;
  tick(top);
  top.qrb_ready = 0;
  top.eval();
  expect(!top.qrb_write, "pending row did not retire");

  std::cout << "PASS: MDP queue rows remain stable under PCIM backpressure "
               "and support lossless same-cycle replacement\n";
  return 0;
}
