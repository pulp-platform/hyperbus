#!/usr/bin/env bash
# Copyright 2026 ETH Zurich and University of Bologna.
# SPDX-License-Identifier: SHL-0.51
# Run with: bash scripts/run_axi_barrier_test.sh [build-log-directory] [frontend-source]
set -euo pipefail
cd "$(dirname "$0")/.."

build_root=${1:-$(mktemp -d /tmp/hyperbus-axi-barrier.XXXXXX)}
frontend_source=${2:-src/hyperbus_axi_frontend.sv}
mkdir -p "$build_root"
build_root=$(realpath "$build_root")
profiles=()
line=0
while read -r reads writes beats extra || [[ -n ${reads:-} ]]; do
    line=$((line + 1))
    [[ -z $reads || $reads == \#* ]] && continue
    if [[ -n $extra || ! $reads =~ ^[1-9][0-9]*$ ||
          ! $writes =~ ^[1-9][0-9]*$ || ! $beats =~ ^[1-9][0-9]*$ ]]; then
        printf 'Malformed AXI queue profile at test/axi_queue_profiles.txt:%d\n' "$line" >&2
        exit 2
    fi
    profiles+=("$reads $writes $beats")
done < test/axi_queue_profiles.txt
if [[ ${#profiles[@]} == 0 ]]; then
    printf 'No AXI queue profiles in test/axi_queue_profiles.txt\n' >&2
    exit 2
fi

cc=$(bender path common_cells)
axi=$(bender path axi)
reg_if=$(bender path register_interface)
includes=(-Iinclude "-I$cc/include" "-I$axi/include" "-I$reg_if/include")
sources=("$cc/src/cf_math_pkg.sv" "$axi/src/axi_pkg.sv"
    "$cc/src/fifo_v3.sv" "$cc/src/stream_fifo.sv" "$cc/src/spill_register.sv"
    "$cc/src/spill_register_flushable.sv" "$cc/src/stream_register.sv"
    "$cc/src/lzc.sv" "$cc/src/rr_arb_tree.sv" "$cc/src/sync.sv"
    "$axi/src/axi_serializer.sv" "$reg_if/src/reg_to_apb.sv"
    src/regs/hyperbus_cfg_regblock_pkg.sv src/hyperbus_pkg.sv
    src/regs/hyperbus_cfg_regblock.sv src/hyperbus_cfg_regs.sv src/hyperbus_cfg_frontend.sv
    src/hyperbus_atomic_handler.sv "$frontend_source"
    src/hyperbus_read_adapter.sv src/hyperbus_write_adapter.sv src/hyperbus_midend.sv
    test/hyperbus_axi_barrier_tb.sv)

for profile in "${profiles[@]}"; do
    read -r reads writes beats <<< "$profile"
    dir="$build_root/r${reads}-w${writes}-b${beats}"
    mkdir -p "$dir"
    printf 'AXI queue profile: read=%s write=%s buffer-beats=%s\n' "$reads" "$writes" "$beats"
    if ! oseda -2026.09 verilator --binary --timing --assert +define+INC_ASSERT -Wno-fatal \
            --top-module hyperbus_axi_barrier_tb --Mdir "$dir/obj_dir" \
            "-GAxiMaxReadTxns=$reads" "-GAxiMaxWriteTxns=$writes" \
            "-GHostWriteBufferBytes=$((8 * beats))" \
            "${includes[@]}" "${sources[@]}" -j 2 > "$dir/compile.log" 2>&1; then
        cat "$dir/compile.log" >&2
        exit 1
    fi
    if ! oseda -2026.09 "$dir/obj_dir/Vhyperbus_axi_barrier_tb" > "$dir/run.log" 2>&1; then
        cat "$dir/run.log" >&2
        exit 1
    fi
    cat "$dir/run.log"
    rg -q 'AXI CSR barrier integration tests passed' "$dir/run.log"
done
printf 'AXI barrier build logs: %s\n' "$build_root"
