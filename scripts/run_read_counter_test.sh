#!/usr/bin/env bash
# Copyright 2026 ETH Zurich and University of Bologna.
# SPDX-License-Identifier: SHL-0.51
set -euo pipefail
cd "$(dirname "$0")/.."

build_root=${1:-$(mktemp -d /tmp/hyperbus-read-counter.XXXXXX)}
mkdir -p "$build_root"
build_root=$(realpath "$build_root")
cc=$(bender path common_cells)
includes=(-Iinclude "-I$cc/include")
sources=(src/hyperbus_pkg.sv src/hyperbus_read_adapter.sv test/hyperbus_read_counter_tb.sv)

for max_beats in 0 256; do
  # Generic coverage stays at six cases; bounded coverage includes all wide host sizes.
  configs=(1:16 2:32 1:64 2:64)
  if [[ "$max_beats" == 0 ]]; then
    configs+=(1:1024 2:1024)
  else
    configs+=(1:128 2:128 1:256 2:256 1:512 2:512 1:1024 2:1024)
  fi
  for config in "${configs[@]}"; do
    IFS=: read -r phys width <<< "$config"
    name="max-$max_beats-phys-$phys-width-$width"
    dir="$build_root/$name"
    oseda -2026.09 verilator --binary --timing --assert +define+INC_ASSERT -Wno-fatal \
        --top-module hyperbus_read_counter_tb "-GNumPhys=$phys" "-GHostDataWidth=$width" \
        "-GMaxHostBurstBeats=$max_beats" \
        --Mdir "$dir" "${includes[@]}" "${sources[@]}" -j 2 \
        > "$build_root/$name.log" 2>&1
    oseda -2026.09 "$dir/Vhyperbus_read_counter_tb" | tee "$build_root/$name.run.log"
    rg -Fq "Read counter tests passed (NumPhys=$phys HostDataWidth=$width MaxHostBurstBeats=$max_beats)" \
        "$build_root/$name.run.log"
  done
done
printf 'Read counter test logs: %s\n' "$build_root"
