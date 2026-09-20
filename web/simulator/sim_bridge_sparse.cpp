// Emscripten bridge for the parameterized sparse J-Machine simulation top
// (sim/j_machine_verilator_sparse_top.sv). The node count is fixed per build
// through -DJ_MACHINE_SIM_NODES and must match the -GX_SIZE/-GY_SIZE/-GZ_SIZE
// product the model was verilated with. Node state is read through the top's
// debug_node mux; memory lives in this file behind the DPI-C store used by
// mdp_sparse_memory_dpi, so image loading and peeking touch the same words
// the RTL reads and writes.
//
// Exported C API (identical to the original two-node bridge, so
// web/site/runtime.js keeps working): sim_init, sim_destroy, sim_reset,
// sim_write_word, sim_finish_load, sim_set_running, sim_step,
// sim_snapshot_ptr, sim_snapshot_words, sim_peek.

#include "Vj_machine_verilator_sparse_top.h"
#include "verilated.h"

#ifdef __EMSCRIPTEN__
#include <emscripten/emscripten.h>
#else
#define EMSCRIPTEN_KEEPALIVE
#endif

#include <array>
#include <cstdint>
#include <memory>
#include <unordered_map>
#include <vector>
#include "network_trace.h"

namespace {

constexpr std::uint32_t kSnapshotMagic = 0x4a4d5331;
constexpr std::size_t kHeaderWords = 4;
constexpr std::size_t kNodeWords = 32;
#ifndef J_MACHINE_SIM_NODES
#define J_MACHINE_SIM_NODES 2
#endif
constexpr std::size_t kNodes = J_MACHINE_SIM_NODES;
constexpr std::size_t kSnapshotWords = kHeaderWords + kNodes * kNodeWords;
constexpr std::uint64_t kWordMask = 0x0000000fffffffffull;
constexpr std::uint32_t kAddressMask = 0x000fffffu;

std::unique_ptr<VerilatedContext> g_context;
std::unique_ptr<Vj_machine_verilator_sparse_top> g_top;
std::array<std::uint32_t, kSnapshotWords> g_snapshot{};
std::array<std::uint32_t, 2> g_peek{};
std::uint64_t g_cycle = 0;
bool g_loaded = false;
bool g_snapshot_dirty = true;

// One sparse store per node, mirroring sim/sparse_image_runner.cpp.
using SparseMemory = std::vector<std::unordered_map<std::uint32_t, std::uint64_t>>;
SparseMemory g_memory(kNodes);

std::uint64_t memoryRead(unsigned node, std::uint32_t address) {
  if (node >= kNodes) return 0;
  const auto& local = g_memory[node];
  const auto entry = local.find(address & kAddressMask);
  return entry == local.end() ? 0 : entry->second;
}

void memoryWrite(unsigned node, std::uint32_t address, std::uint64_t value) {
  if (node >= kNodes) return;
  address &= kAddressMask;
  value &= kWordMask;
  auto& local = g_memory[node];
  g_snapshot_dirty = true;
  const auto before = memoryRead(node, address);
  if (before != value && ((before >> 32) == 6 || (before >> 32) == 7
      || (value >> 32) == 6 || (value >> 32) == 7)) {
    // Memory uses flat IDs; bit 31 distinguishes them from coordinate IDs.
    jmc_trace::emit(10, node | 0x80000000u, 0, 0, address, value,
        static_cast<unsigned>(before >> 32), 0, static_cast<unsigned>(before));
  }
  if (value == 0) local.erase(address);
  else local[address] = value;
}

void ensureModel() {
  if (g_top) return;
  g_context = std::make_unique<VerilatedContext>();
  g_context->threads(1);
  g_context->randReset(0);
  g_top = std::make_unique<Vj_machine_verilator_sparse_top>(g_context.get());
  g_snapshot_dirty = true;
  g_top->clk = 0;
  g_top->reset = 1;
  g_top->run_enable = 0;
  g_top->debug_node = 0;
  g_top->eval();
}

void clockCycle() {
  ensureModel();
  g_snapshot_dirty = true;
  g_top->clk = 0;
  g_top->eval();
  jmc_trace::cycle = g_cycle + 1;
  g_top->clk = 1;
  g_top->eval();
  g_top->clk = 0;
  g_top->eval();
}

void write64(std::size_t offset, std::uint64_t value) {
  g_snapshot[offset] = static_cast<std::uint32_t>(value);
  g_snapshot[offset + 1] = static_cast<std::uint32_t>(value >> 32);
}

void captureNode(std::size_t node, std::size_t offset) {
  g_top->debug_node = static_cast<std::uint32_t>(node);
  g_top->eval();
  g_snapshot[offset + 0] = g_top->debug_node_number;
  g_snapshot[offset + 1] = g_top->debug_catastrophe;
  g_snapshot[offset + 2] = g_top->debug_last_fault;
  write64(offset + 3, g_top->debug_retired);
  write64(offset + 5, g_top->debug_ip);
  write64(offset + 7, g_top->debug_r0);
  g_snapshot[offset + 9] = g_top->debug_background | (g_top->debug_fetch << 1);
  g_snapshot[offset + 10] = g_top->debug_priority;
  g_snapshot[offset + 11] = g_top->debug_interrupt_mask;
  g_snapshot[offset + 12] = g_top->debug_fault_mode;
  g_snapshot[offset + 13] = g_top->debug_unchecked_mode;
  g_snapshot[offset + 14] = g_top->debug_queue_pending;
  g_snapshot[offset + 15] = g_top->debug_queue_full;
  for (std::size_t reg = 0; reg < 8; ++reg) {
    const std::size_t bit = reg * 36;
    const std::size_t word = bit / 32;
    const unsigned shift = bit % 32;
    const std::uint64_t pair = static_cast<std::uint64_t>(g_top->debug_registers[word])
        | (static_cast<std::uint64_t>(g_top->debug_registers[word + 1]) << 32);
    write64(offset + 16 + reg * 2, (pair >> shift) & kWordMask);
  }
}

void captureSnapshot() {
  ensureModel();
  if (!g_snapshot_dirty) return;
  g_snapshot[0] = kSnapshotMagic;
  g_snapshot[1] = 2;
  write64(2, g_cycle);
  for (std::size_t node = 0; node < kNodes; ++node) {
    captureNode(node, kHeaderWords + node * kNodeWords);
  }
  g_top->debug_node = 0;
  g_top->eval();
  g_snapshot_dirty = false;
}

void resetInternal() {
  g_top.reset();
  g_context.reset();
  for (auto& local : g_memory) local.clear();
  g_cycle = 0;
  g_loaded = false;
  jmc_trace::reset();
  ensureModel();
  clockCycle();
  captureSnapshot();
}

}  // namespace

// DPI-C store backing every mdp_sparse_memory_dpi instance in the model.
extern "C" unsigned long long mdp_sparse_memory_read(
    unsigned int node, unsigned int address) {
  return memoryRead(node, address);
}

extern "C" void mdp_sparse_memory_write(
    unsigned int node, unsigned int address, unsigned long long value) {
  memoryWrite(node, address, value);
}

extern "C" {

EMSCRIPTEN_KEEPALIVE void sim_init() {
  resetInternal();
}

EMSCRIPTEN_KEEPALIVE void sim_destroy() {
  g_top.reset();
  g_context.reset();
  for (auto& local : g_memory) local.clear();
  g_snapshot.fill(0);
  g_peek.fill(0);
  g_cycle = 0;
  g_loaded = false;
  jmc_trace::reset();
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
  // Host image load: writes the DPI store directly, which is also what
  // populates the architectural ROM at $01000-$01fff.
  memoryWrite(node, address,
              (static_cast<std::uint64_t>(high) << 32) | low);
  return 0;
}

EMSCRIPTEN_KEEPALIVE void sim_finish_load() {
  ensureModel();
  g_snapshot_dirty = true;
  g_top->reset = 0;
  g_top->run_enable = 1;
  g_top->eval();
  g_loaded = true;
  jmc_trace::loaded = true;
  g_cycle = 0;
  captureSnapshot();
}

EMSCRIPTEN_KEEPALIVE void sim_set_running(std::uint32_t running) {
  ensureModel();
  g_snapshot_dirty = true;
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

// Batch instruction execution, stopping on the exact result/fatal edge or a
// candidate network event. JS checks the full network predicate at that edge;
// instruction breakpoints and watchpoints use one-cycle stepping. The cached
// snapshot avoids a second debug-mux scan when JS reads the completed batch.
EMSCRIPTEN_KEEPALIVE unsigned sim_run(unsigned cycles) {
  ensureModel(); if (!g_loaded) sim_finish_load();
  const auto result = memoryRead(0, 0x300);
  unsigned elapsed = 0;
  jmc_trace::candidate = false;
  while (elapsed < cycles) {
    clockCycle(); ++g_cycle; ++elapsed;
    if (g_top->any_catastrophe || memoryRead(0, 0x300) != result || jmc_trace::candidate) break;
  }
  captureSnapshot(); return elapsed;
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
  ensureModel();
  const std::uint64_t value = memoryRead(node, address);
  g_peek[0] = static_cast<std::uint32_t>(value);
  g_peek[1] = static_cast<std::uint32_t>(value >> 32);
  return g_peek.data();
}

}  // extern "C"
