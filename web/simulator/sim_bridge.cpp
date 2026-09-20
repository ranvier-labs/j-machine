#include "Vj_machine_verilator_top.h"
#include "verilated.h"

#ifdef __EMSCRIPTEN__
#include <emscripten/emscripten.h>
#else
#define EMSCRIPTEN_KEEPALIVE
#endif

#include <array>
#include <cstdint>
#include <memory>

namespace {

constexpr std::uint32_t kSnapshotMagic = 0x4a4d5331;
constexpr std::size_t kHeaderWords = 4;
constexpr std::size_t kNodeWords = 16;
constexpr std::size_t kNodes = 2;
constexpr std::size_t kSnapshotWords = kHeaderWords + kNodes * kNodeWords;
constexpr std::uint64_t kWordMask = 0x0000000fffffffffull;
constexpr std::uint32_t kAddressMask = 0x000fffffu;

std::unique_ptr<VerilatedContext> g_context;
std::unique_ptr<Vj_machine_verilator_top> g_top;
std::array<std::uint32_t, kSnapshotWords> g_snapshot{};
std::array<std::uint32_t, 2> g_peek{};
std::uint64_t g_cycle = 0;
bool g_loaded = false;

void ensureModel() {
  if (g_top) return;
  g_context = std::make_unique<VerilatedContext>();
  g_context->threads(1);
  g_context->randReset(0);
  g_top = std::make_unique<Vj_machine_verilator_top>(g_context.get());
  g_top->clk = 0;
  g_top->reset = 1;
  g_top->run_enable = 0;
  g_top->external_interrupt = 0;
  g_top->dram_error_inject = 0;
  g_top->dram_error_address = 0;
  g_top->debug_write = 0;
  g_top->debug_node = 0;
  g_top->debug_address = 0;
  g_top->debug_wdata = 0;
  g_top->eval();
}

void clockCycle() {
  ensureModel();
  g_top->clk = 0;
  g_top->eval();
  g_top->clk = 1;
  g_top->eval();
  g_top->clk = 0;
  g_top->eval();
}

std::uint64_t readWord(std::uint32_t node, std::uint32_t address) {
  ensureModel();
  g_top->debug_node = static_cast<CData>(node & 1u);
  g_top->debug_address = address & kAddressMask;
  g_top->eval();
  return static_cast<std::uint64_t>(g_top->debug_rdata) & kWordMask;
}

void write64(std::size_t offset, std::uint64_t value) {
  g_snapshot[offset] = static_cast<std::uint32_t>(value);
  g_snapshot[offset + 1] = static_cast<std::uint32_t>(value >> 32);
}

void captureNode(std::size_t node, std::size_t offset) {
  const bool first = node == 0;
  const std::uint64_t retired = first ? g_top->node0_retired : g_top->node1_retired;
  const std::uint64_t ip = first ? g_top->node0_ip : g_top->node1_ip;
  const std::uint64_t r0 = first ? g_top->node0_r0 : g_top->node1_r0;

  g_snapshot[offset + 0] = first ? g_top->node0_number : g_top->node1_number;
  g_snapshot[offset + 1] = first ? g_top->node0_catastrophe : g_top->node1_catastrophe;
  g_snapshot[offset + 2] = first ? g_top->node0_last_fault : g_top->node1_last_fault;
  write64(offset + 3, retired);
  write64(offset + 5, ip);
  write64(offset + 7, r0);
  g_snapshot[offset + 9] = first ? g_top->node0_background : g_top->node1_background;
  g_snapshot[offset + 10] = first ? g_top->node0_priority : g_top->node1_priority;
  g_snapshot[offset + 11] = first ? g_top->node0_interrupt_mask : g_top->node1_interrupt_mask;
  g_snapshot[offset + 12] = first ? g_top->node0_fault_mode : g_top->node1_fault_mode;
  g_snapshot[offset + 13] = first ? g_top->node0_unchecked_mode : g_top->node1_unchecked_mode;
  g_snapshot[offset + 14] = first ? g_top->node0_queue_pending : g_top->node1_queue_pending;
  g_snapshot[offset + 15] = first ? g_top->node0_queue_full : g_top->node1_queue_full;
}

void captureSnapshot() {
  ensureModel();
  g_snapshot[0] = kSnapshotMagic;
  g_snapshot[1] = 1;
  write64(2, g_cycle);
  captureNode(0, kHeaderWords);
  captureNode(1, kHeaderWords + kNodeWords);
}

void resetInternal() {
  g_top.reset();
  g_context.reset();
  g_cycle = 0;
  g_loaded = false;
  ensureModel();
  clockCycle();
  captureSnapshot();
}

}  // namespace

extern "C" {

EMSCRIPTEN_KEEPALIVE void sim_init() {
  resetInternal();
}

EMSCRIPTEN_KEEPALIVE void sim_destroy() {
  g_top.reset();
  g_context.reset();
  g_snapshot.fill(0);
  g_peek.fill(0);
  g_cycle = 0;
  g_loaded = false;
}

EMSCRIPTEN_KEEPALIVE void sim_reset() {
  resetInternal();
}

EMSCRIPTEN_KEEPALIVE std::uint32_t sim_write_word(
    std::uint32_t node, std::uint32_t address,
    std::uint32_t low, std::uint32_t high) {
  ensureModel();
  if (g_loaded || node >= kNodes || address > kAddressMask || high > 0xfu) {
    return 1;
  }
  g_top->debug_node = static_cast<CData>(node);
  g_top->debug_address = address;
  g_top->debug_wdata =
      (static_cast<std::uint64_t>(high) << 32) | low;
  g_top->debug_write = 1;
  clockCycle();
  g_top->debug_write = 0;
  g_top->eval();
  return 0;
}

EMSCRIPTEN_KEEPALIVE void sim_finish_load() {
  ensureModel();
  g_top->debug_write = 0;
  g_top->reset = 0;
  g_top->run_enable = 1;
  g_top->eval();
  g_loaded = true;
  g_cycle = 0;
  captureSnapshot();
}

EMSCRIPTEN_KEEPALIVE void sim_set_running(std::uint32_t running) {
  ensureModel();
  g_top->run_enable = running ? 1 : 0;
  g_top->eval();
  captureSnapshot();
}

EMSCRIPTEN_KEEPALIVE void sim_step(std::uint32_t cycles) {
  ensureModel();
  if (!g_loaded) sim_finish_load();
  for (std::uint32_t i = 0; i < cycles; ++i) {
    clockCycle();
    ++g_cycle;
  }
  captureSnapshot();
}

EMSCRIPTEN_KEEPALIVE const std::uint32_t* sim_snapshot_ptr() {
  captureSnapshot();
  return g_snapshot.data();
}

EMSCRIPTEN_KEEPALIVE std::uint32_t sim_snapshot_words() {
  return static_cast<std::uint32_t>(g_snapshot.size());
}

EMSCRIPTEN_KEEPALIVE const std::uint32_t* sim_peek(
    std::uint32_t node, std::uint32_t address) {
  const std::uint64_t value = readWord(node, address);
  g_peek[0] = static_cast<std::uint32_t>(value);
  g_peek[1] = static_cast<std::uint32_t>(value >> 32);
  return g_peek.data();
}

}  // extern "C"
