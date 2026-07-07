#!/usr/bin/env bash
# Copyright 2026. SPDX-License-Identifier: SHL-0.51
#
# Minimal sky130 ASIC synthesis of the HyperBus PHY front-end using Yosys.
# Produces a gate-level netlist mapped to sky130_fd_sc_hd standard cells plus
# an area / cell-count report. This is a synthesis (STA-less) bring-up flow,
# not full P&R -- see target/sky130/README.md.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="${ROOT}/syn/sky130/out"
mkdir -p "${OUT}"

# Locate the sky130_fd_sc_hd typical-corner Liberty (installed via volare).
: "${SKY130_LIB:=$(ls "${HOME}"/.volare/volare/sky130/versions/*/sky130A/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib 2>/dev/null | head -1)}"
if [[ -z "${SKY130_LIB}" || ! -f "${SKY130_LIB}" ]]; then
  echo "ERROR: sky130_fd_sc_hd tt_025C_1v80 Liberty not found. Set SKY130_LIB." >&2
  exit 1
fi
echo "Using Liberty: ${SKY130_LIB}"

TOP=hyperbus_phy_sky130

yosys -q -p "
  read_liberty -lib ${SKY130_LIB}
  read_verilog -sv -DSKY130_NATIVE_CELLS ${ROOT}/target/sky130/tech_cells_sky130.sv
  read_verilog -sv -DSKY130_NATIVE_CELLS ${ROOT}/target/sky130/configurable_delay.sky130.sv
  read_verilog -sv                       ${ROOT}/src/hyperbus_clk_gen.sv \
                                         ${ROOT}/src/hyperbus_ddr_out.sv \
                                         ${ROOT}/src/hyperbus_clock_diff_out.sv \
                                         ${ROOT}/src/hyperbus_delay.sv \
                                         ${ROOT}/target/sky130/hyperbus_phy_sky130.sv
  hierarchy -check -top ${TOP}
  synth -top ${TOP} -flatten
  dfflibmap -liberty ${SKY130_LIB}
  abc -liberty ${SKY130_LIB}
  setundef -zero
  clean -purge
  write_verilog -noattr ${OUT}/${TOP}.netlist.v
  tee -o ${OUT}/${TOP}.area.rpt stat -liberty ${SKY130_LIB}
"

echo
echo "Netlist : ${OUT}/${TOP}.netlist.v"
echo "Area    : ${OUT}/${TOP}.area.rpt"
