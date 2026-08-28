#!/usr/bin/env bash
set -euo pipefail

archive="$1"
listing="$(tar -tf "${archive}")"

required=(
  cl_j_machine/design/cl_j_machine.sv
  cl_j_machine/design/j_machine_f2_core.sv
  cl_j_machine/design/rtl/j_machine_pkg.sv
  cl_j_machine/build/scripts/aws_build_dcp_from_cl.py
  cl_j_machine/build/scripts/synth_cl_j_machine.tcl
  cl_j_machine/build/constraints/cl_timing_user.xdc
  cl_j_machine/README.md
)

for path in "${required[@]}"; do
  if ! grep -Fqx "${path}" <<<"${listing}"; then
    echo "missing HDK bundle entry: ${path}" >&2
    exit 1
  fi
done

echo "PASS: AWS F2 HDK customer-logic bundle layout"
