// Copyright 2026.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// SkyWater 130nm technology-cell shim for the PULP HyperBus PHY.
//
// The HyperBus RTL instantiates the pulp-platform `tech_cells_generic`
// clock cells (tc_clk_inverter / tc_clk_gating / tc_clk_mux2). For an
// ASIC (sky130) build we provide synthesizable definitions here so the
// design maps to sky130_fd_sc_hd standard cells WITHOUT pulling in the
// external tech_cells_generic dependency.
//
// Two flavours:
//   * default            : generic, RTL-simulatable behaviour.
//   * `SKY130_NATIVE_CELLS`: instantiate real sky130_fd_sc_hd cells
//     (resolved from the Liberty blackbox during synthesis). This gives
//     the most accurate netlist and a proper integrated clock gate.
//
// See target/sky130/README.md and AUDIT.md for context.

// ---------------------------------------------------------------------------
// Clock inverter
// ---------------------------------------------------------------------------
module tc_clk_inverter (
    input  logic clk_i,
    output logic clk_o
);
`ifdef SKY130_NATIVE_CELLS
    sky130_fd_sc_hd__clkinv_1 i_inv (.A (clk_i), .Y (clk_o));
`else
    assign clk_o = ~clk_i;
`endif
endmodule

// ---------------------------------------------------------------------------
// 2:1 clock multiplexer (clk_sel_i == 1 -> clk1_i)
// ---------------------------------------------------------------------------
module tc_clk_mux2 (
    input  logic clk0_i,
    input  logic clk1_i,
    input  logic clk_sel_i,
    output logic clk_o
);
`ifdef SKY130_NATIVE_CELLS
    // sky130 has no dedicated clock mux; mux2_1 is the conventional choice.
    sky130_fd_sc_hd__mux2_1 i_mux (.A0 (clk0_i), .A1 (clk1_i), .S (clk_sel_i), .X (clk_o));
`else
    assign clk_o = clk_sel_i ? clk1_i : clk0_i;
`endif
endmodule

// ---------------------------------------------------------------------------
// Integrated clock gate (active-high enable, test-enable ORed in)
// ---------------------------------------------------------------------------
module tc_clk_gating (
    input  logic clk_i,
    input  logic en_i,
    input  logic test_en_i,
    output logic clk_o
);
`ifdef SKY130_NATIVE_CELLS
    // Real latch-based integrated clock gate. Avoids inferring a latch in
    // the generic path and gives a glitch-free enable.
    sky130_fd_sc_hd__dlclkp_1 i_icg (
        .CLK  (clk_i),
        .GATE (en_i | test_en_i),
        .GCLK (clk_o)
    );
`else
    // Generic latch-based ICG (simulatable). For synthesis prefer the
    // native cell; a bare AND would glitch (see AUDIT.md finding on gating).
    logic en_latched;
    always_latch begin
        if (!clk_i) en_latched = en_i | test_en_i;
    end
    assign clk_o = clk_i & en_latched;
`endif
endmodule
