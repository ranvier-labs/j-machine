#!/usr/bin/env bash
set -euo pipefail

output="$1"
shift
staging="$(mktemp -d)"
trap 'rm -rf "${staging}"' EXIT

root="${staging}/cl_j_machine"
mkdir -p "${root}"

while (( "$#" )); do
  destination="$1"
  source="$2"
  shift 2
  mkdir -p "${root}/$(dirname "${destination}")"
  cp "${source}" "${root}/${destination}"
done

tar -cf "${output}" -C "${staging}" cl_j_machine
