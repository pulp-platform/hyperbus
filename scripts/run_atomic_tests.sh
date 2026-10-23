#!/usr/bin/env bash
# Copyright 2026 ETH Zurich and University of Bologna.
# SPDX-License-Identifier: SHL-0.51
# Run with: bash scripts/run_atomic_tests.sh [build-log-directory]
set -euo pipefail
cd "$(dirname "$0")/.."

build_root=${1:-$(mktemp -d /tmp/hyperbus-atomic.XXXXXX)}
mkdir -p "$build_root"
build_root=$(realpath "$build_root")
cc=$(bender path common_cells)
axi=$(bender path axi)
includes=(-Iinclude "-I$cc/include" "-I$axi/include")
unit_sources=(src/regs/hyperbus_cfg_regblock_pkg.sv src/hyperbus_pkg.sv
              src/hyperbus_atomic_handler.sv test/hyperbus_atomic_handler_tb.sv)
integration_sources=("$cc/src/cf_math_pkg.sv" "$axi/src/axi_pkg.sv"
    "$cc/src/fifo_v3.sv" "$cc/src/stream_fifo.sv" "$cc/src/spill_register.sv"
    "$cc/src/spill_register_flushable.sv" "$cc/src/stream_register.sv"
    "$cc/src/lzc.sv" "$cc/src/rr_arb_tree.sv" "$axi/src/axi_serializer.sv"
    src/regs/hyperbus_cfg_regblock_pkg.sv src/hyperbus_pkg.sv
    src/hyperbus_atomic_handler.sv src/hyperbus_axi_frontend.sv
    src/hyperbus_read_adapter.sv src/hyperbus_write_adapter.sv src/hyperbus_midend.sv
    test/hyperbus_axi_atomic_tb.sv)

for width in 16 32 64 128 256 512 1024; do
    dir="$build_root/unit-$width"
    oseda -2026.09 verilator --binary --timing --assert +define+INC_ASSERT -Wno-fatal \
        --top-module hyperbus_atomic_handler_tb "-GHostDataWidth=$width" --Mdir "$dir" \
        "${includes[@]}" "${unit_sources[@]}" -j 2 > "$build_root/unit-$width.log" 2>&1
    oseda -2026.09 "$dir/Vhyperbus_atomic_handler_tb" | tee "$build_root/unit-$width.run.log"
    rg -q 'Atomic handler operation and protocol tests passed' "$build_root/unit-$width.run.log"
done
for width in 16 32 64 128 256; do
    dir="$build_root/axi-$width"
    oseda -2026.09 verilator --binary --timing --assert +define+INC_ASSERT -Wno-fatal \
        --top-module hyperbus_axi_atomic_tb "-GHostDataWidth=$width" --Mdir "$dir" \
        "${includes[@]}" "${integration_sources[@]}" -j 2 > "$build_root/axi-$width.log" 2>&1
    oseda -2026.09 "$dir/Vhyperbus_axi_atomic_tb" | tee "$build_root/axi-$width.run.log"
    rg -q 'AXI atomic frontend/midend tests passed' "$build_root/axi-$width.run.log"
done
if oseda -2026.09 "$build_root/axi-64/Vhyperbus_axi_atomic_tb" +inject_backend_write_fault \
        > "$build_root/axi-64-negative-control.log" 2>&1; then
    echo "Atomic backend write-fault negative control unexpectedly passed" >&2
    exit 1
fi
rg -q 'Compare failed at byte 0' "$build_root/axi-64-negative-control.log"
printf 'Atomic build logs: %s\n' "$build_root"
