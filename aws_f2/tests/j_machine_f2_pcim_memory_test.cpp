#include "Vj_machine_f2_pcim_memory_test_top.h"
#include "verilated.h"

#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <string>

double sc_time_stamp() { return 0.0; }

namespace {

using Top = Vj_machine_f2_pcim_memory_test_top;

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

void clearInputs(Top& top) {
  top.cpu_request_valid = 0;
  top.cpu_request_write = 0;
  top.cpu_request_address = 0;
  top.cpu_request_wdata = 0;
  top.qrb_write = 0;
  top.qrb_row_address = 0;
  for (int word = 0; word < 5; ++word) top.qrb_write_data[word] = 0;
  top.qrb_write_enable = 0;
  top.pcim_awready = 0;
  top.pcim_wready = 0;
  top.pcim_bresp = 0;
  top.pcim_bvalid = 0;
  top.pcim_arready = 0;
  for (int word = 0; word < 16; ++word) top.pcim_rdata[word] = 0;
  top.pcim_rresp = 0;
  top.pcim_rlast = 1;
  top.pcim_rvalid = 0;
  top.clear_errors = 0;
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

void setWideBits(WData* words, int lowBit, int width, std::uint64_t value) {
  for (int bit = 0; bit < width; ++bit) {
    const int destination = lowBit + bit;
    const WData mask = WData{1} << (destination % 32);
    if ((value >> bit) & 1u) {
      words[destination / 32] |= mask;
    } else {
      words[destination / 32] &= ~mask;
    }
  }
}

void finishWrite(Top& top, std::uint8_t response = 0) {
  top.pcim_awready = 1;
  top.pcim_wready = 1;
  tick(top);
  top.pcim_awready = 0;
  top.pcim_wready = 0;
  expect(top.pcim_bready, "write response channel was not ready");
  top.pcim_bresp = response;
  top.pcim_bvalid = 1;
  tick(top);
  top.pcim_bvalid = 0;
  top.pcim_bresp = 0;
}

}  // namespace

int main(int argc, char** argv) {
  Verilated::commandArgs(argc, argv);
  Top top;
  clearInputs(top);
  top.host_memory_base = 0x0000001000000000ull;
  top.reset = 1;
  tick(top);
  tick(top);
  top.reset = 0;
  tick(top);

  // A processor write from node 2 selects one 64-bit lane in node 2's 8 MiB
  // aperture and remains stable while AW and W are independently stalled.
  top.cpu_request_valid = 0b0100;
  top.cpu_request_write = 0b0100;
  top.cpu_request_address = 0x123;
  top.cpu_request_wdata = 0xabcde;
  top.eval();
  expect(top.cpu_request_ready == 0b0100, "node 2 write was not selected");
  tick(top);
  top.cpu_request_valid = 0;
  top.cpu_request_write = 0;
  const std::uint64_t expectedWriteAddress = top.host_memory_base
      + (std::uint64_t{2} << 23) + (std::uint64_t{0x123 >> 3} << 6);
  expect(top.pcim_awvalid && top.pcim_wvalid, "write channels not issued");
  expect(top.pcim_awaddr == expectedWriteAddress, "processor write address");
  expect(top.pcim_wstrb == (std::uint64_t{0xff} << (3 * 8)),
         "processor write strobes");
  expect(wideBits(top.pcim_wdata, 3 * 64, 36) == 0xabcde,
         "processor write payload");
  tick(top);
  expect(top.pcim_awaddr == expectedWriteAddress,
         "stalled write address changed");
  finishWrite(top);
  expect(!top.busy, "write did not return to idle");

  // Architectural ROM ignores processor writes and emits no external cycle.
  top.cpu_request_valid = 0b0001;
  top.cpu_request_write = 0b0001;
  top.cpu_request_address = 0x1000;
  top.eval();
  expect(top.cpu_request_ready == 0b0001, "ROM write was not acknowledged");
  tick(top);
  top.cpu_request_valid = 0;
  top.cpu_request_write = 0;
  top.eval();
  expect(!top.busy && !top.pcim_awvalid, "ROM write escaped to PCIM");

  // A queue-row commit wins over simultaneous CPU traffic and fills four lanes
  // in the upper half of a 512-bit beat.
  top.cpu_request_valid = 0b0010;
  top.qrb_write = 0b1000;
  top.qrb_row_address = 1;
  top.qrb_write_enable = 0b1111;
  setWideBits(top.qrb_write_data, 0, 36, 0x100000001ull);
  setWideBits(top.qrb_write_data, 36, 36, 0x200000002ull);
  setWideBits(top.qrb_write_data, 72, 36, 0x300000003ull);
  setWideBits(top.qrb_write_data, 108, 36, 0x400000004ull);
  top.eval();
  expect(top.qrb_ready == 0b1000 && top.cpu_request_ready == 0,
         "queue-row priority");
  tick(top);
  top.qrb_write = 0;
  top.cpu_request_valid = 0;
  expect(top.pcim_wstrb == 0xffffffff00000000ull,
         "queue-row upper-half strobes");
  for (int lane = 0; lane < 4; ++lane) {
    const auto laneValue = static_cast<std::uint64_t>(lane + 1);
    const std::uint64_t expected = (laneValue << 32) | laneValue;
    expect(wideBits(top.pcim_wdata, (lane + 4) * 64, 36) == expected,
           "queue-row lane " + std::to_string(lane));
  }
  finishWrite(top, 2);
  expect(top.write_error, "write error was not sticky");

  // A read returns the selected 36-bit word and maps AXI response failures to
  // the MDP DRAM-error input for the requesting node.
  top.cpu_request_valid = 0b0010;
  top.cpu_request_address = 9;
  top.eval();
  expect(top.cpu_request_ready == 0b0010, "node 1 read was not selected");
  tick(top);
  top.cpu_request_valid = 0;
  expect(top.pcim_arvalid, "read address not issued");
  expect(top.pcim_araddr == top.host_memory_base
             + (std::uint64_t{1} << 23) + (std::uint64_t{1} << 6),
         "processor read address");
  top.pcim_arready = 1;
  tick(top);
  top.pcim_arready = 0;
  expect(top.pcim_rready, "read data channel was not ready");
  setWideBits(top.pcim_rdata, 64, 36, 0xf12345678ull);
  top.pcim_rresp = 2;
  top.pcim_rvalid = 1;
  tick(top);
  top.pcim_rvalid = 0;
  top.pcim_rresp = 0;
  expect(top.cpu_response_valid == 0b0010, "read response node identity");
  expect(top.cpu_response_rdata1 == 0xf12345678ull, "read response data");
  expect(top.cpu_response_dram_error == 0b0010, "read DRAM error mapping");
  expect(top.read_error, "read error was not sticky");

  top.clear_errors = 1;
  tick(top);
  top.clear_errors = 0;
  expect(!top.write_error && !top.read_error, "error clear failed");

  std::cout << "PASS: AWS F2 PCIM memory aperture, queue-row backpressure, "
               "AXI stalls, and error propagation\n";
  return 0;
}
