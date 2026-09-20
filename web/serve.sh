#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${BUILD_WORKSPACE_DIRECTORY:-}" ]]; then
  root="$BUILD_WORKSPACE_DIRECTORY"
else
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  root="$(cd "$script_dir/.." && pwd)"
fi

port="${1:-8000}"
[[ -f "$root/web/dist/index.html" ]] || {
  echo "web/dist is missing; run bazel run //web:build first" >&2
  exit 1
}

exec python3 -m http.server "$port" --directory "$root/web/dist"
