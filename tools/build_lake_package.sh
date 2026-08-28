#!/usr/bin/env bash
set -euo pipefail

lake="$1"
package_prefix="$2"
output_count="$3"
shift 3

targets=()
outputs=()
for ((index = 0; index < output_count; index++)); do
  targets+=("$1")
  outputs+=("$2")
  shift 2
done

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/j-machine-lake.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT

for source in "$@"; do
  relative="${source#"${package_prefix}/"}"
  destination="$work_dir/$relative"
  mkdir -p "$(dirname "$destination")"
  cp "$source" "$destination"
done

"$lake" -d "$work_dir" build "${targets[@]}"

for ((index = 0; index < output_count; index++)); do
  cp "$work_dir/.lake/build/bin/${targets[$index]}" "${outputs[$index]}"
  chmod +x "${outputs[$index]}"
done
