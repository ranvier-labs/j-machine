#!/usr/bin/env python3
"""Run the pinned AWS HDK Small Shell DCP builder for cl_j_machine."""

import os
import sys


def main() -> None:
    shell_dir = os.environ.get("HDK_SHELL_DIR")
    if not shell_dir:
        raise SystemExit("HDK_SHELL_DIR is unset; source aws-fpga/hdk_setup.sh first")
    builder = os.path.join(shell_dir, "build", "scripts", "aws_build_dcp_from_cl.py")
    if not os.path.isfile(builder):
        raise SystemExit(f"AWS HDK builder not found: {builder}")
    os.execv(sys.executable, [sys.executable, builder, "-c", "cl_j_machine", "--mode", "small_shell", *sys.argv[1:]])


if __name__ == "__main__":
    main()
