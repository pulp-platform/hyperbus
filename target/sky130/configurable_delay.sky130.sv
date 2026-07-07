// Copyright 2026.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Synthesizable standard-cell delay line for ASIC (sky130) targets.
//
// This replaces, for a real ASIC build, the two non-ASIC bodies of
// `configurable_delay`:
//   * models/configurable_delay.behav.sv  -- transport `#delay`, sim only
//   * models/configurable_delay.fpga.sv   -- Xilinx IBUF, no real delay
// and stands in for the absent proprietary `generic_delay_*` macro that
// models/README.md references but does not ship (see AUDIT.md, blocker #1).
//
// Structure: a chain of delay cells with a tap multiplexer. `delay_i`
// selects how many stages the signal passes through.
//
//   * `SKY130_NATIVE_CELLS` : each stage is a hard sky130_fd_sc_hd delay
//     cell (dlygate4sd3_1, A->X). Instantiated cells survive synthesis and
//     CTS optimisation, so the delay line is real in the netlist.
//   * default               : keep-marked generic buffers (RTL-simulatable,
//     but NOTE plain synthesis/opt will collapse these -- use the native
//     path for an ASIC netlist).
//
// IMPORTANT (per AUDIT.md): the *absolute* per-tap delay is the delay-cell
// propagation (~hundreds of ps on sky130 HD, i.e. coarser than the ~78 ps
// /tap the Xilinx IDELAY path assumes) and is PVT-dependent. For timing
// signoff this element must be characterised and pinned with SDC, or
// replaced with a calibrated delay / DLL. It is provided so the PHY
// *elaborates and synthesizes* on sky130 with a real, non-collapsing chain.

`timescale 1ps/1ps

module configurable_delay #(
    parameter  int unsigned NUM_STEPS       = 32,           // power of two
    localparam int unsigned DELAY_SEL_WIDTH = $clog2(NUM_STEPS)
) (
    input  logic                        clk_i,
    input  logic [DELAY_SEL_WIDTH-1:0]  delay_i,
    output logic                        clk_o
);

    // Tap 0 is the undelayed input; tap k has passed through k delay cells.
    (* keep = "true" *) wire [NUM_STEPS:0] tap;
    assign tap[0] = clk_i;

    for (genvar i = 0; i < NUM_STEPS; i++) begin : gen_tap
`ifdef SKY130_NATIVE_CELLS
        // Hard sky130 delay cell; not removed by synthesis/CTS optimisation.
        (* keep = "true" *) sky130_fd_sc_hd__dlygate4sd3_1 i_dly (
            .A (tap[i]),
            .X (tap[i+1])
        );
`else
        // Generic buffer element (simulatable; collapses under plain opt).
        (* keep = "true" *) wire buf_stage;
        assign buf_stage = tap[i];
        assign tap[i+1]  = buf_stage;
`endif
    end

    // Select the requested tap.
    assign clk_o = tap[delay_i];

endmodule
