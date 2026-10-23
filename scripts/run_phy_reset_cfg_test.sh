#!/usr/bin/env bash
# Copyright 2026 ETH Zurich and University of Bologna.
# SPDX-License-Identifier: SHL-0.51
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
build_dir=${BUILD_DIR:-"$root/build/phy_reset_cfg"}
mkdir -p "$build_dir"
cd "$root"
bender-0.31.0 --local script verilator --no-default-target \
    -t rtl -t verilator -t synthesis > "$build_dir/sources.f"
if [[ ${1:-} == --negative-control ]]; then
    # Disable replay after startup, reproducing the original missing replay.
    if [[ $(grep -Fc 'if (!phy_ready_sync) begin' src/hyperbus_cfg_frontend.sv) != 1 ]]; then
        printf 'Negative-control mutation point was not unique; refusing to run\n' >&2
        exit 2
    fi
    sed "s/if (!phy_ready_sync) begin/if (1'b0) begin/" \
        src/hyperbus_cfg_frontend.sv > "$build_dir/hyperbus_cfg_frontend.sv"
    if cmp -s src/hyperbus_cfg_frontend.sv "$build_dir/hyperbus_cfg_frontend.sv" ||
       ! grep -Fq "if (1'b0) begin" "$build_dir/hyperbus_cfg_frontend.sv"; then
        printf 'Negative-control mutation did not apply; refusing to run\n' >&2
        exit 2
    fi
    sed -i "s|$root/src/hyperbus_cfg_frontend.sv|$build_dir/hyperbus_cfg_frontend.sv|" "$build_dir/sources.f"
elif [[ $# != 0 ]]; then
    printf 'Usage: %s [--negative-control]\n' "$0" >&2
    exit 2
fi
oseda -2026.09 verilator --binary --timing --assert +define+INC_ASSERT -j 2 -Wno-fatal \
    --top-module hyperbus_phy_reset_cfg_tb --Mdir "$build_dir/obj_dir" \
    -GCdcSyncStages="${CDC_SYNC_STAGES:-3}" \
    -f "$build_dir/sources.f" models/configurable_delay.behav.sv \
    test/hyperbus_phy_reset_cfg_tb.sv \
    > "$build_dir/compile.log" 2>&1
if [[ ${1:-} == --negative-control ]]; then
    if oseda -2026.09 "$build_dir/obj_dir/Vhyperbus_phy_reset_cfg_tb" > "$build_dir/run.log" 2>&1; then
        cat "$build_dir/run.log"
        printf 'Negative control unexpectedly passed\n' >&2
        exit 1
    fi
    if ! grep -Fq 'admission reopened before PHY-reset replay completion' "$build_dir/run.log"; then
        cat "$build_dir/run.log" >&2
        printf 'Negative control failed for an unexpected reason\n' >&2
        exit 1
    fi
    printf 'PASS: negative control detected missing PHY-reset replay\n'
else
    oseda -2026.09 "$build_dir/obj_dir/Vhyperbus_phy_reset_cfg_tb" > "$build_dir/run.log" 2>&1
    cat "$build_dir/run.log"
    grep -q 'PASS: defaults, applied replay' "$build_dir/run.log"
    grep -q '^HELD_RESET_W1C time_ns=' "$build_dir/run.log"
fi
