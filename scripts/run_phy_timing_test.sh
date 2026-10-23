#!/usr/bin/env bash
# Copyright 2026 ETH Zurich and University of Bologna.
# SPDX-License-Identifier: SHL-0.51
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
build=${1:?Usage: heavy bash scripts/run_phy_timing_test.sh BUILD_DIR}
mkdir -p "$build"
build=$(cd "$build" && pwd)
cd "$root"
bender-0.31.0 --local script verilator --no-default-target \
    -t rtl -t verilator -t synthesis > "$build/sources.f"
if ! oseda -2026.09 verilator --binary --timing --assert +define+INC_ASSERT -j 2 -Wno-fatal \
    --top-module hyperbus_phy_timing_tb --Mdir "$build/obj_dir" \
    -f "$build/sources.f" "$root/models/configurable_delay.behav.sv" \
    "$root/test/hyperbus_phy_timing_tb.sv" > "$build/compile.log" 2>&1; then
    tail -80 "$build/compile.log" >&2
    exit 1
fi
if ! oseda -2026.09 "$build/obj_dir/Vhyperbus_phy_timing_tb" > "$build/simulation.log" 2>&1; then
    cat "$build/simulation.log" >&2
    exit 1
fi
cat "$build/simulation.log"
grep -q '\[PHY-TIMING\] all checks passed' "$build/simulation.log"
