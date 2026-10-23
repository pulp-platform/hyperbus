#!/usr/bin/env bash
set -euo pipefail

# Invoke this entire runner through heavy so compilation and simulation are constrained.
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
build=${1:?Usage: heavy bash scripts/run_iso_clock_div_test.sh BUILD_DIR [PHY_SYNC_STAGES] [--negative-control]}
phy_sync_stages=${2:-2}
latency_oracle_offset=0
if [[ ${3:-} == --negative-control ]]; then
    latency_oracle_offset=4
elif [[ $# -gt 2 ]]; then
    printf 'Usage: %s BUILD_DIR [PHY_SYNC_STAGES] [--negative-control]\n' "$0" >&2
    exit 2
fi
mkdir -p "$build"
build=$(cd "$build" && pwd)
cd "$root"
"${BENDER:-bender-0.31.0}" --local script verilator --no-default-target \
    -t rtl -t verilator -t synthesis \
    > "$build/sources.f"
if ! oseda -2026.09 verilator --binary --timing --assert +define+INC_ASSERT -j 2 -Wno-fatal \
    --top-module hyperbus_iso_clock_div_tb -GPhySyncStages="$phy_sync_stages" \
    -GLatencyOracleOffsetCycles="$latency_oracle_offset" \
    --Mdir "$build/obj_dir" \
    -f "$build/sources.f" "$root/models/configurable_delay.behav.sv" \
    "$root/test/hyperbus_iso_clock_div_tb.sv" \
    > "$build/compile.log" 2>&1; then
    tail -80 "$build/compile.log" >&2
    exit 1
fi
if [[ $latency_oracle_offset != 0 ]]; then
    if oseda -2026.09 "$build/obj_dir/Vhyperbus_iso_clock_div_tb" \
        > "$build/simulation.log" 2>&1; then
        cat "$build/simulation.log"
        printf 'Latency negative control unexpectedly passed\n' >&2
        exit 1
    fi
    if ! grep -Fq 'BVALID latency/phase mismatch' "$build/simulation.log"; then
        cat "$build/simulation.log" >&2
        printf 'Latency negative control failed for an unexpected reason\n' >&2
        exit 1
    fi
    printf 'PASS: injected latency-oracle offset trips the comparison (checker sensitivity only)\n'
else
    if ! oseda -2026.09 "$build/obj_dir/Vhyperbus_iso_clock_div_tb" \
        > "$build/simulation.log" 2>&1; then
        cat "$build/simulation.log" >&2
        exit 1
    fi
    cat "$build/simulation.log"
    grep -q '\[ISO-DIV\] all checks passed' "$build/simulation.log"
fi
