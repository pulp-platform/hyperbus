#!/usr/bin/env bash
# Copyright 2026 ETH Zurich and University of Bologna.
# SPDX-License-Identifier: SHL-0.51
# Run the focused atomic operation/protocol matrix without a device model.
set -euo pipefail
cd "$(dirname "$0")/.."
build_root=${1:-$(mktemp -d /tmp/hyperbus-atomic.XXXXXX)}
mkdir -p "$build_root"
build_root=$(realpath "$build_root")
bender=${BENDER:-bender}
verilator=${VERILATOR:-verilator}
cc=$("$bender" path common_cells)
sources=(src/regs/hyperbus_cfg_regblock_pkg.sv src/hyperbus_pkg.sv
         src/hyperbus_atomic_handler.sv test/hyperbus_atomic_handler_tb.sv)
for width in 16 32 64 128 256 512 1024; do
    dir="$build_root/unit-$width"
    "$verilator" --binary --timing --assert +define+INC_ASSERT -Wno-fatal \
        --top-module hyperbus_atomic_handler_tb "-GHostDataWidth=$width" --Mdir "$dir" \
        -Iinclude "-I$cc/include" "${sources[@]}" -j 2 > "$build_root/unit-$width.log" 2>&1
    "$dir/Vhyperbus_atomic_handler_tb" | tee "$build_root/unit-$width.run.log"
    grep -q 'Atomic handler operation and protocol tests passed' "$build_root/unit-$width.run.log"
done
printf 'Atomic build logs: %s\n' "$build_root"
