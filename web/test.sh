#!/usr/bin/env bash
set -euo pipefail
if [[ -n "${BUILD_WORKSPACE_DIRECTORY:-}" ]]; then
  root="$BUILD_WORKSPACE_DIRECTORY"
else
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  root="$(cd "$script_dir/.." && pwd)"
fi
node_binary="${NODE:-node}"
if [[ "$("$node_binary" -p 'Number(process.versions.node.split(".")[0])')" -lt 20 \
    && -x /opt/homebrew/bin/node ]]; then
  node_binary=/opt/homebrew/bin/node
fi
"$node_binary" --test "$root/web/tests/compiler.test.mjs" \
  "$root/web/tests/lsp.test.mjs" "$root/web/tests/debugger.test.mjs" \
  "$root/web/tests/workspace.test.mjs" "$root/web/tests/ide.test.mjs" \
  "$root/web/tests/build.test.mjs" "$root/web/tests/network.test.mjs" \
  "$root/web/tests/keyboard.test.mjs" "$root/web/tests/graphics.test.mjs" \
  "$root/web/tests/documentation.test.mjs"
"$node_binary" "$root/web/tests/compiler_mesh.mjs"
"$node_binary" "$root/web/tests/simulator_variants.mjs"
"$node_binary" "$root/web/tests/compiler_examples.mjs" "$@"
"$node_binary" "$root/web/tests/network_mesh.mjs"
