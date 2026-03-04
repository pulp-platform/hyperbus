// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Thomas Benz <paulsc@iis.ee.ethz.ch>
// Paul Scheffler <paulsc@iis.ee.ethz.ch>

(* no_ungroup *)
(* no_boundary_optimization *)
(* keep_hierarchy = "yes" *)
module hyperbus_delay (
    input  logic        in_i,
    input  logic [4:0]  delay_i,
    output logic        out_o
);

    // The standard delay line is expected to have 32 taps with ~78ps per tap
    // This conforms to the Xilinx IDELAYE2 with a 200MHz reference clock
    // The total delay range is thus ~2.5ns
    // Additional delay can be added for debug purposes,
    // the upper 3 bits are reserved for this optional additional delay
    configurable_delay #(
      .NUM_STEPS(32)
    ) i_delay (
        .clk_i      ( in_i         ),
        .delay_i    ( delay_i[4:0] ),
        .clk_o      ( out_o        )
    );

endmodule : hyperbus_delay
