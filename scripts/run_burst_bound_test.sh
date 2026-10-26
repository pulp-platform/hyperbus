#!/usr/bin/env bash
# Copyright 2026 ETH Zurich and University of Bologna.
# SPDX-License-Identifier: SHL-0.51
set -euo pipefail
ulimit -c 0
cd "$(dirname "$0")/.."

build_root=${1:-$(mktemp -d /tmp/hyperbus-burst-bound.XXXXXX)}
mkdir -p "$build_root"
build_root=$(realpath "$build_root")
cc=$(bender --local path common_cells)
for config in 256:32:1 0:32:1; do
  IFS=: read -r max_beats addr_width phys <<< "$config"
  name="max-$max_beats"
  if [[ $addr_width != 32 ]]; then name="addr-$addr_width-phys-$phys"; fi
  oseda -2026.09 verilator --binary --timing --assert +define+INC_ASSERT -Wno-fatal \
    --top-module hyperbus_burst_bound_tb "-GMaxHostBurstBeats=$max_beats" \
    "-GHostAddrWidth=$addr_width" "-GNumPhys=$phys" \
    --Mdir "$build_root/$name" -j 2 \
    -Iinclude "-I$cc/include" "$cc/src/cf_math_pkg.sv" \
    "$cc/src/addr_decode.sv" "$cc/src/addr_decode_dync.sv" \
    "$cc/src/fifo_v3.sv" "$cc/src/stream_fifo.sv" \
    "$cc/src/spill_register.sv" "$cc/src/spill_register_flushable.sv" \
    "$cc/src/stream_register.sv" src/hyperbus_pkg.sv \
    src/hyperbus_read_adapter.sv src/hyperbus_write_adapter.sv \
    src/hyperbus_atomic_handler.sv src/hyperbus_midend.sv \
    test/hyperbus_burst_bound_tb.sv > "$build_root/compile-$name.log" 2>&1
done

timeout 30s oseda -2026.09 "$build_root/max-256/Vhyperbus_burst_bound_tb" \
    > "$build_root/run.log" 2>&1
grep -Fq 'PASS: maximum burst rejected' "$build_root/run.log"
status=0
timeout 30s oseda -2026.09 "$build_root/max-256/Vhyperbus_burst_bound_tb" +out-of-bound \
    > "$build_root/out-of-bound.log" 2>&1 || status=$?
if [[ $status == 0 || $status == 124 ]] ||
   ! grep -Fq 'HostCommandBurstBound' "$build_root/out-of-bound.log"; then
    cat "$build_root/out-of-bound.log" >&2
    printf 'Out-of-bound request did not trigger the burst assertion\n' >&2
    exit 1
fi
timeout 30s oseda -2026.09 "$build_root/max-0/Vhyperbus_burst_bound_tb" +mapped-read \
    > "$build_root/mapped-read.log" 2>&1
grep -Fq 'PASS: generic mapped 32768-byte read' "$build_root/mapped-read.log"
status=0
timeout 30s oseda -2026.09 "$build_root/max-0/Vhyperbus_burst_bound_tb" +physical-overflow \
    > "$build_root/physical-overflow.log" 2>&1 || status=$?
if [[ $status == 0 || $status == 124 ]] ||
   ! grep -Fq 'HostPhysicalBurstFits' "$build_root/physical-overflow.log"; then
    cat "$build_root/physical-overflow.log" >&2
    printf 'Oversized physical span did not trigger its assertion\n' >&2
    exit 1
fi
printf 'PASS: host/physical bounds and mapped reads. Logs: %s\n' "$build_root"
