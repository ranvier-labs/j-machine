#include <lean/lean.h>

#include <array>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <string>

namespace {

constexpr std::size_t kSourceCapacity = 1024 * 1024;
constexpr std::size_t kMeshCapacity = 256;

std::array<std::uint8_t, kSourceCapacity> g_source{};
std::array<std::uint8_t, kMeshCapacity> g_mesh{};
std::string g_output;
std::uint32_t g_status = 1;

std::uint32_t pointer32(const void* pointer) {
  return static_cast<std::uint32_t>(
      reinterpret_cast<std::uintptr_t>(pointer));
}

}  // namespace

extern "C" {

LEAN_EXPORT std::uint32_t jmc_source_ptr() {
  return pointer32(g_source.data());
}

LEAN_EXPORT std::uint32_t jmc_source_capacity() {
  return static_cast<std::uint32_t>(g_source.size());
}

LEAN_EXPORT lean_object* jmc_source_string(std::uint32_t length) {
  if (length > g_source.size()) length = g_source.size();
  return lean_mk_string_from_bytes(
      reinterpret_cast<const char*>(g_source.data()), length);
}

LEAN_EXPORT std::uint32_t jmc_mesh_ptr() {
  return pointer32(g_mesh.data());
}

LEAN_EXPORT std::uint32_t jmc_mesh_capacity() {
  return static_cast<std::uint32_t>(g_mesh.size());
}

LEAN_EXPORT lean_object* jmc_mesh_string(std::uint32_t length) {
  if (length > g_mesh.size()) length = g_mesh.size();
  return lean_mk_string_from_bytes(
      reinterpret_cast<const char*>(g_mesh.data()), length);
}

LEAN_EXPORT std::uint32_t jmc_store_output(
    std::uint32_t world, std::uint32_t status, b_lean_obj_arg text) {
  g_output.assign(lean_string_cstr(text), lean_string_size(text) - 1);
  g_status = status;
  return world;
}

// Image text is streamed line by line: building a full-image string in Lean
// exhausts linear memory under the wasm backend.
LEAN_EXPORT std::uint32_t jmc_append_output(
    std::uint32_t world, b_lean_obj_arg text) {
  g_output.append(lean_string_cstr(text), lean_string_size(text) - 1);
  return world;
}

// Image text is streamed word by word: building image strings in Lean
// exhausts linear memory under the wasm backend, so formatting happens here.
// The 36-bit value arrives as two 32-bit halves (lean_uint64_of_nat is not
// linked into the wasm runtime).
LEAN_EXPORT std::uint32_t jmc_emit_word(
    std::uint32_t world, std::uint32_t node, std::uint32_t address,
    std::uint32_t value_low, std::uint32_t value_high,
    b_lean_obj_arg annotation) {
  char prefix[64];
  const int length = node == 0xffffffffu
      ? std::snprintf(prefix, sizeof prefix, "*  %05x  %x%08x  # ",
          address, value_high, value_low)
      : std::snprintf(prefix, sizeof prefix, "%u  %05x  %x%08x  # ",
          node, address, value_high, value_low);
  g_output.append(prefix, static_cast<std::size_t>(length));
  g_output.append(
      lean_string_cstr(annotation), lean_string_size(annotation) - 1);
  g_output.push_back('\n');
  return world;
}

LEAN_EXPORT std::uint32_t jmc_output_status() {
  return g_status;
}

LEAN_EXPORT std::uint32_t jmc_output_ptr() {
  return g_output.empty() ? 0 : pointer32(g_output.data());
}

LEAN_EXPORT std::uint32_t jmc_output_len() {
  return static_cast<std::uint32_t>(g_output.size());
}

}  // extern "C"
