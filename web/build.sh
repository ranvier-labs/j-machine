#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${BUILD_WORKSPACE_DIRECTORY:-}" ]]; then
  root="$BUILD_WORKSPACE_DIRECTORY"
else
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  root="$(cd "$script_dir/.." && pwd)"
fi

web="$root/web"
dist="$web/dist"

"$web/build_compiler.sh"
"$web/build_simulator.sh"

node_binary="${NODE:-node}"
if [[ "$("$node_binary" -p 'Number(process.versions.node.split(".")[0])')" -lt 20 \
    && -x /opt/homebrew/bin/node ]]; then
  node_binary=/opt/homebrew/bin/node
fi
if [[ ! -d "$web/node_modules/monaco-editor" || ! -d "$web/node_modules/esbuild" ]]; then
  (cd "$web" && PATH="$(dirname "$node_binary"):$PATH" npm ci --no-audit --no-fund)
fi
"$node_binary" "$web/build_frontend.mjs"

if [[ "${SKIP_WEB_SMOKE:-0}" != "1" ]]; then
  node_binary="${NODE:-node}"
  if [[ "$("$node_binary" -p 'Number(process.versions.node.split(".")[0])')" -lt 20 \
      && -x /opt/homebrew/bin/node ]]; then
    node_binary=/opt/homebrew/bin/node
  fi
  "$node_binary" "$web/tests/smoke.mjs"
fi

echo "standalone site: $dist"
