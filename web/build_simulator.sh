#!/usr/bin/env bash
# Builds the WebAssembly simulator variants for the web workbench.
#
# Every variant verilates sim/j_machine_verilator_sparse_top.sv with its own
# mesh geometry and links web/simulator/sim_bridge_sparse.cpp with the node
# count baked in as -DJ_MACHINE_SIM_NODES. Artifacts land in web/dist as
# simulator_N.js / simulator_N.wasm. The two-node build is additionally
# emitted under the historical names simulator.js / simulator.wasm, which
# web/site/runtime.js and web/tests/smoke.mjs reference.
#
#   ./build_simulator.sh          build all variants and write dist/variants.json
#   ./build_simulator.sh 4 [16..] build only the listed node counts
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$script_dir/.." && pwd)"
build_root="$script_dir/build/simulator"
cache_dir="$script_dir/build/em_cache"
dist_dir="$script_dir/dist"
top="j_machine_verilator_sparse_top"
prefix="Vj_machine_verilator_sparse_top"

verilator_root="${VERILATOR_ROOT:-$(verilator -V | awk -F'= ' '/VERILATOR_ROOT/ {print $2; exit}')}"
[[ -n "$verilator_root" ]] || { echo "Unable to determine VERILATOR_ROOT" >&2; exit 1; }

mkdir -p "$dist_dir" "$cache_dir"
export EM_CACHE="$cache_dir"

rtl_sources=(
  "$root/rtl/j_machine_pkg.sv"
  "$root/rtl/mdp_network_input.sv"
  "$root/rtl/mdp_network_output.sv"
  "$root/rtl/mdp_message_unit.sv"
  "$root/rtl/j_mdp_core.sv"
  "$root/rtl/j_mesh_router.sv"
  "$root/rtl/j_node.sv"
  "$root/rtl/j_machine_mesh.sv"
  "$root/sim/mdp_sparse_memory_dpi.sv"
  "$root/sim/j_machine_verilator_sparse_top.sv"
)

mesh_dims() {
  case "$1" in
    2) echo "2 1 1" ;;
    4) echo "2 2 1" ;;
    16) echo "4 4 1" ;;
    512) echo "8 8 8" ;;
    *) echo "unsupported node count: $1" >&2; return 1 ;;
  esac
}

verilate_variant() {
  local nodes="$1" x="$2" y="$3" z="$4"
  local object_dir="$build_root/obj_${nodes}"
  rm -rf "$object_dir"
  mkdir -p "$object_dir"
  (
    cd "$root/sim"
    verilator --cc "${rtl_sources[@]}" \
      --top-module "$top" \
      --prefix "$prefix" \
      --Mdir "$object_dir" \
      -GX_SIZE="$x" -GY_SIZE="$y" -GZ_SIZE="$z" \
      +define+J_MACHINE_NETWORK_TRACE \
      --assert \
      --no-timing \
      -Wall \
      -Wno-DECLFILENAME \
      -Wno-MODDUP \
      -Wno-fatal
  )
}

# The fixed 8x8x8 top (sim/j_machine_verilator_sparse512_top.sv) verilates
# hierarchically, compiling j_node once as a DPI protectlib child. The root
# model alone is ~640 C++ files, so objects are compiled in parallel and
# linked in a second step instead of a single em++ invocation.
verilate_variant_512() {
  local object_dir="$build_root/obj_512"
  rm -rf "$object_dir"
  mkdir -p "$object_dir"
  (
    cd "$root/sim"
    verilator --cc \
      "$root/rtl/j_machine_pkg.sv" \
      "$root/rtl/mdp_network_input.sv" \
      "$root/rtl/mdp_network_output.sv" \
      "$root/rtl/mdp_message_unit.sv" \
      "$root/rtl/j_mdp_core.sv" \
      "$root/rtl/j_mesh_router.sv" \
      "$root/rtl/j_node.sv" \
      "$root/rtl/j_machine_mesh.sv" \
      "$root/rtl/j_machine_mesh_512.sv" \
      "$root/sim/mdp_sparse_memory_dpi.sv" \
      "$root/sim/j_machine_verilator_sparse512_top.sv" \
      --top-module "$top" \
      --prefix "$prefix" \
      --Mdir "$object_dir" \
      --hierarchical \
      +define+J_MACHINE_NETWORK_TRACE \
      --assert \
      --no-timing \
      -Wall \
      -Wno-DECLFILENAME \
      -Wno-MODDUP \
      -Wno-fatal
  )
}

link_variant_512() {
  local output_js="$1"
  local object_dir="$build_root/obj_512"
  local support_dir="$build_root/obj_512_support"
  local jobs="${SIM_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 8)}"
  mkdir -p "$support_dir"

  local includes=(
    -I"$verilator_root/include"
    -I"$verilator_root/include/vltstd"
    -I"$object_dir"
  )
  local common_flags=(
    -std=c++20 -O2
    -DVL_IGNORE_UNKNOWN_ARCH
    -include stdint.h
  )

  if [[ "${SIM_RELINK_ONLY:-0}" != 1 ]]; then
  (
    cd "$object_dir"
    printf '%s\n' "$prefix"*.cpp | xargs -P "$jobs" -n 1 bash -c \
      'em++ -std=c++20 -O2 -DVL_IGNORE_UNKNOWN_ARCH -DJ_MACHINE_SIM_NODES=512 \
        -include stdint.h -I"$0/include" -I"$0/include/vltstd" -I. \
        -c "$1" -o "$1.o"' "$verilator_root"
  )
  # DPI protectlib children (e.g. Vj_node/) hold the hierarchical blocks.
  local child_dir
  while IFS= read -r child_dir; do
    (
      cd "$child_dir"
      printf '%s\n' *.cpp | xargs -P "$jobs" -n 1 bash -c \
        'em++ -std=c++20 -O2 -DVL_IGNORE_UNKNOWN_ARCH -DJ_MACHINE_SIM_NODES=512 \
          -include stdint.h -I"$0/include" -I"$0/include/vltstd" -I. -I.. \
          -c "$1" -o "$1.o"' "$verilator_root"
    )
  done < <(find "$object_dir" -mindepth 1 -maxdepth 1 -type d -name "V*" ! -name "*__hier.dir")

  fi

  em++ "${common_flags[@]}" -DJ_MACHINE_SIM_NODES=512 "${includes[@]}" \
    -c "$script_dir/simulator/sim_bridge_sparse.cpp" -o "$support_dir/bridge.o"
  em++ "${common_flags[@]}" "${includes[@]}" \
    -c "$script_dir/simulator/verilated_threads_stub.cpp" -o "$support_dir/stub.o"
  em++ "${common_flags[@]}" "${includes[@]}" \
    -c "$verilator_root/include/verilated.cpp" -o "$support_dir/verilated.o"
  em++ "${common_flags[@]}" "${includes[@]}" \
    -c "$verilator_root/include/verilated_dpi.cpp" -o "$support_dir/verilated_dpi.o"

  em++ -O2 \
    "$object_dir"/*.o \
    "$object_dir"/V*/*.o \
    "$support_dir"/*.o \
    -o "$output_js" \
    -s MODULARIZE=1 \
    -s EXPORT_ES6=1 \
    -s EXPORT_NAME=JMachineSimulatorModule \
    -s ENVIRONMENT=web,worker,node \
    -s ALLOW_MEMORY_GROWTH=1 \
    -s INITIAL_MEMORY=134217728 \
    -s MAXIMUM_MEMORY=2147483648 \
    -s FILESYSTEM=0 \
    -s EXPORTED_FUNCTIONS='["_sim_init","_sim_destroy","_sim_reset","_sim_write_word","_sim_finish_load","_sim_set_running","_sim_step","_sim_snapshot_ptr","_sim_snapshot_words","_sim_peek","_sim_run","_sim_trace_enable","_sim_trace_break_mask","_sim_trace_ptr","_sim_trace_count","_sim_trace_clear","_sim_trace_dropped"]'
  wasm-validate "${output_js%.js}.wasm"
  echo "wrote $output_js and ${output_js%.js}.wasm"
}

link_variant() {
  local nodes="$1" output_js="$2"
  local object_dir="$build_root/obj_${nodes}"
  local verilated_sources=()
  while IFS= read -r source_path; do
    verilated_sources+=("$source_path")
  done < <(find "$object_dir" -maxdepth 1 -name "$prefix*.cpp" -print | sort)
  [[ ${#verilated_sources[@]} -gt 0 ]] || { echo "No Verilator C++ sources generated for $nodes nodes" >&2; exit 1; }

  em++ -std=c++20 -O2 \
    -DVL_IGNORE_UNKNOWN_ARCH \
    -DJ_MACHINE_SIM_NODES="$nodes" \
    -include stdint.h \
    -I"$verilator_root/include" \
    -I"$verilator_root/include/vltstd" \
    -I"$object_dir" \
    "$script_dir/simulator/sim_bridge_sparse.cpp" \
    "$script_dir/simulator/verilated_threads_stub.cpp" \
    "$verilator_root/include/verilated.cpp" \
    "$verilator_root/include/verilated_dpi.cpp" \
    "${verilated_sources[@]}" \
    -o "$output_js" \
    -s MODULARIZE=1 \
    -s EXPORT_ES6=1 \
    -s EXPORT_NAME=JMachineSimulatorModule \
    -s ENVIRONMENT=web,worker,node \
    -s ALLOW_MEMORY_GROWTH=1 \
    -s INITIAL_MEMORY=67108864 \
    -s MAXIMUM_MEMORY=2147483648 \
    -s FILESYSTEM=0 \
    -s EXPORTED_FUNCTIONS='["_sim_init","_sim_destroy","_sim_reset","_sim_write_word","_sim_finish_load","_sim_set_running","_sim_step","_sim_snapshot_ptr","_sim_snapshot_words","_sim_peek","_sim_run","_sim_trace_enable","_sim_trace_break_mask","_sim_trace_ptr","_sim_trace_count","_sim_trace_clear","_sim_trace_dropped"]'
  wasm-validate "${output_js%.js}.wasm"
  echo "wrote $output_js and ${output_js%.js}.wasm"
}

build_variant() {
  local nodes="$1" x y z
  if [[ "$nodes" == "512" ]]; then
    echo "=== building 512-node variant (8x8x8, hierarchical) ==="
    if [[ "${SIM_RELINK_ONLY:-0}" != 1 ]]; then verilate_variant_512; fi
    link_variant_512 "$dist_dir/simulator_512.js"
    return
  fi
  read -r x y z <<< "$(mesh_dims "$nodes")"
  echo "=== building ${nodes}-node variant (${x}x${y}x${z}) ==="
  if [[ "${SIM_RELINK_ONLY:-0}" != 1 ]]; then verilate_variant "$nodes" "$x" "$y" "$z"; fi
  link_variant "$nodes" "$dist_dir/simulator_${nodes}.js"
  if [[ "$nodes" == "2" ]]; then
    link_variant "$nodes" "$dist_dir/simulator.js"
  fi
}

if [[ $# -gt 0 ]]; then
  for nodes in "$@"; do
    build_variant "$nodes"
  done
  echo "subset build complete; dist/variants.json left unchanged"
  exit 0
fi

rm -rf "$build_root"
variants=(2 4 16 512)
for nodes in "${variants[@]}"; do
  build_variant "$nodes"
done

{
  printf '{"variants":['
  separator=""
  for nodes in "${variants[@]}"; do
    read -r x y z <<< "$(mesh_dims "$nodes")"
    printf '%s{"nodes":%d,"mesh":"%dx%dx%d","js":"simulator_%d.js","wasm":"simulator_%d.wasm"}' \
      "$separator" "$nodes" "$x" "$y" "$z" "$nodes" "$nodes"
    separator=","
  done
  printf ']}\n'
} > "$dist_dir/variants.json"
echo "wrote $dist_dir/variants.json"
