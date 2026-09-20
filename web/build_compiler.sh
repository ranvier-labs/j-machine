#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$script_dir/.." && pwd)"
lean_root="${LEAN_WASM_ROOT:-$script_dir/build/lean4-wasm}"
wasi_sdk="${WASI_SDK_PATH:-/Users/pehle/opt/wasi-sdk-33.0-arm64-macos}"
stage1="${LEAN_BUILD_DIR:-$lean_root/build/release/stage1}"
lean="${LEAN:-$stage1/bin/lean}"
leanc="${LEANC:-$stage1/bin/leanc}"
lake="${LAKE:-$stage1/bin/lake}"
build_dir="$script_dir/build/compiler"
source_dir="$build_dir/src"
object_dir="$build_dir/objects"
dist_dir="$script_dir/dist"

[[ -x "$lean" ]] || {
  echo "Lean with --wasm support was not found at $lean" >&2
  echo "Set LEAN_WASM_ROOT to a built feat/wasm-backend checkout." >&2
  exit 1
}
[[ -x "$leanc" ]] || { echo "leanc was not found at $leanc" >&2; exit 1; }
[[ -x "$lake" ]] || { echo "lake was not found at $lake" >&2; exit 1; }
[[ -d "$wasi_sdk" ]] || { echo "Set WASI_SDK_PATH to wasi-sdk." >&2; exit 1; }

if ! "$lean" --help 2>&1 | grep -q -- '--wasm-whole'; then
  echo "$lean does not expose the whole-program WebAssembly backend" >&2
  exit 1
fi

rm -rf "$build_dir"
mkdir -p "$source_dir/JMachineC" "$object_dir" "$dist_dir"
cp "$root/compiler/JMachineC.lean" "$source_dir/JMachineC.lean"
cp "$root/compiler/JMachineC/"*.lean "$source_dir/JMachineC/"
cp "$root/compiler/lakefile.toml" "$source_dir/lakefile.toml"
cp "$script_dir/compiler/WebCompiler.lean" "$source_dir/WebCompiler.lean"

export WASI_SDK_PATH="$wasi_sdk"
export LEAN_BUILD_DIR="$stage1"
export PATH="$(dirname "$lean"):$PATH"

libleanrt="$stage1/wasm32-wasip1/libleanrt.a"
libleanrt_stale=0
if [[ ! -f "$libleanrt" ]]; then
  libleanrt_stale=1
else
  for src in "$lean_root/src/runtime/"*.cpp; do
    if [[ "$src" -nt "$libleanrt" ]]; then
      libleanrt_stale=1
      break
    fi
  done
fi
if [[ "$libleanrt_stale" == 1 ]]; then
  "$lean_root/script/build_wasm_runtime.sh" "$lean_root/build/release/wasm32-wasip1"
fi

(
  cd "$source_dir"
  "$lake" build JMachineC
)

export LEAN_PATH="$source_dir/.lake/build/lib/lean"
"$lean" --run "$script_dir/compiler/EmitBrowser.lean" \
  "$source_dir/WebCompiler.lean" "$object_dir/WebCompiler.wasm"

"$wasi_sdk/bin/clang++" -std=c++20 -O2 -DNDEBUG -DLEAN_WASI \
  -fwasm-exceptions \
  -I "$stage1/include" -I "$lean_root/src/include" -I "$lean_root/src" \
  -c "$script_dir/compiler/compiler_bridge.cpp" \
  -o "$object_dir/compiler_bridge.o"

objects=(
  "$object_dir/WebCompiler.wasm"
  "$object_dir/compiler_bridge.o"
)

# The C++ exception tag is supplied by the host (runtime.js / WebAssembly.Tag);
# everything else must resolve at link time.
printf '__cpp_exception\n' > "$object_dir/allowed_undefined.txt"

"$leanc" --target=wasm32-wasip1 \
  -Wl,--export=jmc_compile \
  -Wl,--export=jmc_source_ptr \
  -Wl,--export=jmc_source_capacity \
  -Wl,--export=jmc_mesh_ptr \
  -Wl,--export=jmc_mesh_capacity \
  -Wl,--export=jmc_output_status \
  -Wl,--export=jmc_output_ptr \
  -Wl,--export=jmc_output_len \
  -Wl,--initial-memory=67108864 \
  -Wl,--max-memory=536870912 \
  -Wl,-z,stack-size=4194304 \
  -Wl,--allow-undefined-file="$object_dir/allowed_undefined.txt" \
  -o "$object_dir/compiler.wasm" "${objects[@]}"

wasm-validate --enable-exceptions --enable-tail-call "$object_dir/compiler.wasm"
node_binary="${NODE:-node}"
if [[ "$("$node_binary" -p 'Number(process.versions.node.split(".")[0])')" -lt 20 \
    && -x /opt/homebrew/bin/node ]]; then
  node_binary=/opt/homebrew/bin/node
fi
"$node_binary" "$script_dir/tests/compiler_smoke.mjs" "$object_dir/compiler.wasm"
cp "$object_dir/compiler.wasm" "$dist_dir/compiler.wasm"
echo "wrote $dist_dir/compiler.wasm"
