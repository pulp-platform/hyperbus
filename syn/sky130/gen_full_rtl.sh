#!/usr/bin/env zsh
# Copyright 2026. SPDX-License-Identifier: SHL-0.51
#
# Generate a single flat Verilog-2005 file for the FULL PULP hyperbus
# controller (AXI4 + RegBus + PHY) for open-source ASIC synthesis.
#
# Pipeline:  bender (resolve deps + file list)  ->  sv2v (SV -> Verilog)
# Output:    openlane/hyperbus/build/$OUT_NAME   (top: hyperbus_lint_wrap)
#
# Config knobs (env vars; defaults = the documented 128b / dual-PHY build):
#   AXIW=128   AxiDataWidth
#   NPHYS=2    NumPhys (1 or 2)
#   OUT_NAME=hyperbus_full.v   output filename under the build dir
# e.g. small variant:  AXIW=32 NPHYS=1 OUT_NAME=hyperbus_full_small.v zsh gen_full_rtl.sh
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
#  * sv2v --top bakes the wrapper's DEFAULT params, so to vary AxiDataWidth/
#    NumPhys we feed sv2v a build-local copy of the wrapper with the defaults
#    patched (src/ stays pristine).
set -e

AXIW=${AXIW:-128}
NPHYS=${NPHYS:-2}
OUT_NAME=${OUT_NAME:-hyperbus_full.v}

ROOT="${0:A:h}/../.."
cd "$ROOT"
OUT=openlane/hyperbus/build
mkdir -p "$OUT"

command -v bender >/dev/null || { echo "ERROR: bender not on PATH" >&2; exit 1; }
command -v sv2v   >/dev/null || { echo "ERROR: sv2v not on PATH"   >&2; exit 1; }

# Build-local wrapper with AxiDataWidth / NumPhys defaults patched for this run.
WRAP="$OUT/wrap_gen.sv"
sed -E "s/(AxiDataWidth *= *)128/\1${AXIW}/; s/(NumPhys +)= 2/\1= ${NPHYS}/" \
    src/hyperbus_synth_wrap.sv > "$WRAP"

# Resolve dependencies from the committed Bender.lock (no re-resolve).
bender script verilator > "$OUT/bender.vlt.f"

INCS="$(grep '+incdir+' "$OUT/bender.vlt.f" | sed "s/+incdir+//; s#$PWD/##; s/^/-I/" | sort -u)"
FILES="$(grep -E '\.sv$|\.v$' "$OUT/bender.vlt.f" | sed "s#$PWD/##")"

# --top elaborates from hyperbus_lint_wrap and emits ONLY reachable modules
# (prunes unused apb/reg/axi modules that carry SV constructs yosys can't
# parse, and binds concrete parameters).
FV="$OUT/$OUT_NAME"
sv2v --top=hyperbus_lint_wrap \
     -DSYNTHESIS -DVERILATOR -DXSIM -DSKY130_NATIVE_CELLS \
     ${(f)INCS} ${(f)FILES} \
     target/sky130/configurable_delay.sky130.sv \
     "$WRAP" \
     > "$FV"

# --- Post-process: pin the "-1 must-override" parameter defaults --------------
# The hyperbus RTL uses `parameter X = -1` as a "must override" idiom (flagged
# in AUDIT.md). sv2v's --top specialization decomposes AXI *type* parameters and
# in doing so leaves some scalar defaults unbound, so they resolve to -1
# (0xFFFFFFFF) and blow up part-select widths in Yosys. This design is used in
# exactly ONE configuration per generation, so we pin the defaults to those
# concrete values. A real instantiation still overrides them; only the
# otherwise-garbage unbound cases change.
#
# Also: sv2v mis-sizes the HyperBurstWidth width-param it extracts from
# `parameter type T` as [0:0] (1 bit), truncating 15->1 and shrinking the
# transaction CDC data ports from 52 to 38 bits (dropping the write flag +
# burst MSBs). Widen it back to 32 bits.
sed -i '' \
  -e 's/parameter \[0:0\] \([A-Za-z0-9_]*HyperBurstWidth\)/parameter [31:0] \1/g' \
  "$FV"
sed -i '' \
  -e "s/\(parameter \[31:0\] AxiDataWidth\) = -1;/\1 = ${AXIW};/" \
  -e 's/\(parameter \[31:0\] AxiAddrWidth\) = -1;/\1 = 48;/' \
  -e 's/\(parameter \[31:0\] AxiIdWidth\) = -1;/\1 = 6;/' \
  -e 's/\(parameter \[31:0\] AxiUserWidth\) = -1;/\1 = 1;/' \
  -e 's/\(parameter \[31:0\] NumChips\) = -1;/\1 = 2;/' \
  -e "s/\(parameter \[31:0\] NumPhys\) = -1;/\1 = ${NPHYS};/" \
  -e 's/\(parameter \[31:0\] RegAddrWidth\) = -1;/\1 = 32;/' \
  -e 's/\(parameter \[31:0\] RegDataWidth\) = -1;/\1 = 32;/' \
  -e 's/\(parameter \[31:0\] BurstLength\) = -1;/\1 = 15;/' \
  -e 's/\(parameter \[RegDataWidth - 1:0\] RstChipBase\) = -1;/\1 = 0;/' \
  -e "s/\(parameter \[RegDataWidth - 1:0\] RstChipSpace\) = -1;/\1 = 'h10000;/" \
  "$FV"

echo "Wrote $FV  (AxiDataWidth=${AXIW}, NumPhys=${NPHYS}, $(grep -c '^module ' "$FV") modules)"
