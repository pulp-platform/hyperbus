#!/usr/bin/env zsh
# Copyright 2026. SPDX-License-Identifier: SHL-0.51
#
# Generate a single flat Verilog-2005 file for the FULL PULP hyperbus
# controller (AXI4 + RegBus + dual PHY) for open-source ASIC synthesis.
#
# Pipeline:  bender (resolve deps + file list)  ->  sv2v (SV -> Verilog)
# Output:    openlane/hyperbus/build/hyperbus_full.v   (top: hyperbus_lint_wrap)
#
# Requirements on PATH: bender, sv2v.  Run from the repo root.
#
# Notes / gotchas baked in here (learned the hard way):
#  * zsh does NOT word-split unquoted $var -> use ${(f)VAR} to split on lines.
#  * sv2v resolves `include search dirs only via RELATIVE -I paths here, so we
#    strip the repo-root prefix from bender's absolute include dirs.
#  * -DVERILATOR -DXSIM strip the sim-only SVA (`default disable iff`, etc.)
#    that sv2v 0.0.13 cannot parse; -DSYNTHESIS drops other sim-only blocks.
#  * -DSKY130_NATIVE_CELLS selects the hard sky130 delay/ICG cells.
#  * The bender source list has no `configurable_delay` body (behav/fpga are
#    target-gated out), so we append target/sky130/configurable_delay.sky130.sv.
#  * src/hyperbus_synth_wrap.sv (hyperbus_lint_wrap) binds concrete AXI/Reg
#    types and flat ports -> it is the synthesis top.
set -e

ROOT="${0:A:h}/../.."
cd "$ROOT"
OUT=openlane/hyperbus/build
mkdir -p "$OUT"

command -v bender >/dev/null || { echo "ERROR: bender not on PATH" >&2; exit 1; }
command -v sv2v   >/dev/null || { echo "ERROR: sv2v not on PATH"   >&2; exit 1; }

# Resolve dependencies from the committed Bender.lock (no re-resolve).
bender script verilator > "$OUT/bender.vlt.f"

INCS="$(grep '+incdir+' "$OUT/bender.vlt.f" | sed "s/+incdir+//; s#$PWD/##; s/^/-I/" | sort -u)"
FILES="$(grep -E '\.sv$|\.v$' "$OUT/bender.vlt.f" | sed "s#$PWD/##")"

# --top elaborates from hyperbus_lint_wrap and emits ONLY reachable modules
# (prunes unused apb/reg/axi modules that carry SV constructs yosys can't
# parse, and binds concrete parameters).
sv2v --top=hyperbus_lint_wrap \
     -DSYNTHESIS -DVERILATOR -DXSIM -DSKY130_NATIVE_CELLS \
     ${(f)INCS} ${(f)FILES} \
     target/sky130/configurable_delay.sky130.sv \
     src/hyperbus_synth_wrap.sv \
     > "$OUT/hyperbus_full.v"

# --- Post-process: pin the "-1 must-override" parameter defaults --------------
# The hyperbus RTL uses `parameter X = -1` as a "must override" idiom (flagged
# in AUDIT.md). sv2v's --top specialization decomposes AXI *type* parameters and
# in doing so leaves some of these scalar defaults unbound, so they resolve to
# -1 (0xFFFFFFFF) and blow up part-select widths in Yosys. This design is used in
# exactly ONE configuration (the hyperbus_lint_wrap defaults), so we pin the
# defaults to those concrete values. A real instantiation still overrides them;
# only the otherwise-garbage unbound cases change.
FV="$OUT/hyperbus_full.v"
# sv2v mis-sizes the width-parameter it extracts from `parameter type T` for the
# HyperBurstWidth field as [0:0] (1 bit), so passing HyperBurstWidth=15 truncates
# to 1 and the transaction CDC data ports become 38 bits instead of 52 -> 14 MSBs
# (write flag + burst[14:2]) silently dropped across the AXI<->PHY CDC. Widen the
# extracted width param to 32 bits so the value survives.
sed -i '' \
  -e 's/parameter \[0:0\] \([A-Za-z0-9_]*HyperBurstWidth\)/parameter [31:0] \1/g' \
  "$FV"
sed -i '' \
  -e 's/\(parameter \[31:0\] AxiDataWidth\) = -1;/\1 = 128;/' \
  -e 's/\(parameter \[31:0\] AxiAddrWidth\) = -1;/\1 = 48;/' \
  -e 's/\(parameter \[31:0\] AxiIdWidth\) = -1;/\1 = 6;/' \
  -e 's/\(parameter \[31:0\] AxiUserWidth\) = -1;/\1 = 1;/' \
  -e 's/\(parameter \[31:0\] NumChips\) = -1;/\1 = 2;/' \
  -e 's/\(parameter \[31:0\] NumPhys\) = -1;/\1 = 2;/' \
  -e 's/\(parameter \[31:0\] RegAddrWidth\) = -1;/\1 = 32;/' \
  -e 's/\(parameter \[31:0\] RegDataWidth\) = -1;/\1 = 32;/' \
  -e 's/\(parameter \[31:0\] BurstLength\) = -1;/\1 = 15;/' \
  -e 's/\(parameter \[RegDataWidth - 1:0\] RstChipBase\) = -1;/\1 = 0;/' \
  -e "s/\(parameter \[RegDataWidth - 1:0\] RstChipSpace\) = -1;/\1 = 'h10000;/" \
  "$FV"

echo "Wrote $OUT/hyperbus_full.v ($(grep -c '^module ' "$OUT/hyperbus_full.v") modules)"
