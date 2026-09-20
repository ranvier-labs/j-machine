// Passive simulator observations. Nothing here drives an RTL input.
#pragma once
#include <array>
#include <cstdint>
#include <vector>

namespace jmc_trace {
constexpr std::size_t width = 12;
constexpr std::size_t capacity = 131072;
using Record = std::array<std::uint32_t, width>;
inline std::vector<Record> records;
inline std::uint64_t cycle = 0;
inline std::uint32_t dropped = 0;
inline bool enabled = true, loaded = false, candidate = false;
inline unsigned break_mask = 0;
inline void reset() { records.clear(); dropped = 0; cycle = 0; loaded = false; records.reserve(capacity); }
inline void emit(unsigned kind, unsigned node, unsigned port, unsigned priority,
                 unsigned aux, std::uint64_t value, unsigned flags = 0,
                 unsigned ip = 0, unsigned extra = 0) {
  if (!enabled || !loaded) return;
  const unsigned event_mask = (kind == 1 && port == 0 ? 1u : 0u)
      | (kind == 2 && port == 0 && (flags & 1) ? 2u : 0u)
      | (kind == 2 ? 4u : 0u) | (kind == 8 ? 8u : 0u)
      | (kind == 4 || kind == 5 ? 16u : 0u);
  candidate |= (break_mask & event_mask) != 0;
  if (records.size() == capacity) { ++dropped; return; }
  records.push_back({static_cast<unsigned>(cycle), static_cast<unsigned>(cycle >> 32),
    kind, node, port, priority, aux, static_cast<unsigned>(value),
    static_cast<unsigned>(value >> 32), flags, ip, extra});
}
}

// Node arguments use the architectural coordinate encoding, not flat IDs.
extern "C" void jmc_trace_router(unsigned node, unsigned kind, unsigned port,
    unsigned priority, unsigned aux, unsigned flit, unsigned flags) {
  jmc_trace::emit(kind, node, port, priority, aux, flit, flags);
}
extern "C" void jmc_trace_endpoint(unsigned node, unsigned kind, unsigned priority,
    unsigned aux, unsigned long long value, unsigned flags, unsigned ip) {
  jmc_trace::emit(kind, node, 0, priority, aux, value, flags, ip);
}

extern "C" {
EMSCRIPTEN_KEEPALIVE void sim_trace_break_mask(unsigned mask) { jmc_trace::break_mask = mask; }
EMSCRIPTEN_KEEPALIVE void sim_trace_enable(unsigned enabled) { jmc_trace::enabled = enabled != 0; }
EMSCRIPTEN_KEEPALIVE const std::uint32_t* sim_trace_ptr() {
  return jmc_trace::records.empty() ? nullptr : jmc_trace::records.front().data();
}
EMSCRIPTEN_KEEPALIVE unsigned sim_trace_count() { return jmc_trace::records.size(); }
EMSCRIPTEN_KEEPALIVE unsigned sim_trace_dropped() { return jmc_trace::dropped; }
EMSCRIPTEN_KEEPALIVE void sim_trace_clear() { jmc_trace::records.clear(); jmc_trace::dropped = 0; }
}
