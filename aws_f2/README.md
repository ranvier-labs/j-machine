# AWS EC2 F2 target

This directory is the AWS EC2 F2 Hardware Development Kit (HDK) target for the
J-Machine. It follows the official F2 Small Shell customer-logic layout and
keeps AWS/Vivado integration outside the target-independent `rtl/` tree.

The implemented baseline instantiates the complete `8 x 8 x 8` mesh and uses:

- `clk_main_a0` and `rst_main_n` from the Small Shell;
- the OCL AXI-Lite interface on AppPF BAR0 for control and architectural debug;
- the CL-to-host PCIM AXI4 interface for node memory; and
- AWS's standard unused-interface templates for DDR, SDA, interrupts, and
  inbound PCIS.

The wrapper top is `cl_j_machine`. No J-Machine opcode, tag, address, node
number, queue, or routing behavior is changed for F2.

## Bazel targets

The module pins the official `aws/aws-fpga` `f2` branch at commit
`b603a81f65666e0cf7a67ee5cf18b148eb6b08c3`, verified by SHA-256. The external
repository is exposed without copying the AWS kit into this source tree.

```sh
bazel build //aws_f2:hdk
bazel build //aws_f2:platform_rtl
bazel build //aws_f2:cl_bundle
bazel test //aws_f2:tests
```

`//aws_f2:cl_bundle` produces
`bazel-bin/aws_f2/cl_bundle.tar`. Its `cl_j_machine/` root contains the
HDK-compatible `design/`, `build/scripts/`, and `build/constraints/`
directories plus a private copy of the target-independent J-Machine RTL needed
for the DCP build. `//aws_f2:hdk` resolves the pinned upstream development kit;
it does not run `hdk_setup.sh` or download shell checkpoints as a Bazel action.

## Memory organization

Each 36-bit MDP word is stored in the low bits of one 64-bit lane. Eight
consecutive words share one 512-bit PCIM beat. The byte address is:

```text
host_memory_base + (node_index << 23) + ((physical_word_address >> 3) << 6)
```

The word lane is `physical_word_address[2:0]`. Each node therefore occupies
8 MiB and all 512 complete 20-bit word spaces occupy exactly 4 GiB. The host
base must be 64-byte aligned. A four-word queue-row commit updates either the
lower or upper half of one PCIM beat with byte strobes, preserving the same
atomic acceptance contract as the simulation memories.

The memory adapter allows one outstanding PCIM transaction. It arbitrates
queue-row commits before processor accesses and uses round-robin selection
among nodes. This is a functionally complete initial memory binding, but it is
not presented as the final throughput architecture. A later striping target
can replace it with 32 HBM channels without changing the mesh or compiler image
format.

## OCL register map

All registers are 32-bit and naturally aligned.

| Offset | Access | Meaning |
| --- | --- | --- |
| `0x00` | R | ID, `0x4a4d4632` (`JMF2`) |
| `0x04` | R | target ABI version, `0x00010000` |
| `0x08` | R/W | control: run `[0]`, soft-reset pulse `[1]` |
| `0x0c` | R | run, memory busy/errors, catastrophe, base alignment |
| `0x10`, `0x14` | R/W | PCIM host-memory base low/high |
| `0x18`, `0x1c` | R | aperture size low/high, exactly 4 GiB |
| `0x20` | R/W | debug node index, `0..511` |
| `0x24` | R | selected node state, fault, and queue flags |
| `0x28`, `0x2c` | R | selected node retired-instruction count |
| `0x30`, `0x34` | R | selected node IP payload/tag |
| `0x38`, `0x3c` | R | selected node R0 payload/tag |
| `0x40` | R/W1C | sticky PCIM write/read errors `[0]`/`[1]` |

Writes honor AXI byte strobes. Invalid or read-only writes and invalid reads
return AXI-Lite `SLVERR`; an invalid read also returns `0xdeadbeef`.

## Building a DCP

The routed DCP build must run in the AWS-supported x86 environment with a
supported Vivado installation and the shell artifacts installed by the HDK.
Bazel deliberately prepares and verifies the customer-logic inputs but does
not pretend that this external licensed toolchain is locally available.

```sh
bazel build //aws_f2:cl_bundle
mkdir -p /path/to/f2-work
tar -xf bazel-bin/aws_f2/cl_bundle.tar -C /path/to/f2-work

cd /path/to/aws-fpga
source hdk_setup.sh

export CL_DIR=/path/to/f2-work/cl_j_machine
cd "$CL_DIR/build/scripts"
./aws_build_dcp_from_cl.py --no-encrypt
```

The wrapper invokes the HDK's own `aws_build_dcp_from_cl.py` with
`-c cl_j_machine --mode small_shell`. Remove `--no-encrypt` for an encrypted
production build.

## Explicit remaining platform work

- The F2 runtime allocator/loader that reserves the host PCIM aperture, applies
  broadcast and per-node sparse image rows, and writes the OCL controls is not
  implemented yet.
- The existing HardFloat service is verified as a separate target-neutral RTL
  service but is not yet inserted into the F2 memory path. The intended mapping
  remains a shared/tiled service rather than 512 binary64 divider instances.
- No Vivado synthesis, place-and-route, timing, or F2 resource claim has been
  made on this non-x86 development host. The generated HDK bundle and the
  Verilated memory/control boundary are the locally verified artifacts.
