// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Hayate Okuhara <hayate.okuhara@unibo.it>

/// Generates 4 phase shifted clocks out of one faster clock
(* no_ungroup *)
(* no_boundary_optimization *)
(* keep_hierarchy = "yes" *)
module hyperbus_clk_gen (
    input  logic clk_i,     // input clock
    input  logic rst_ni,
    output logic clk_phy_o,
    output logic ph_phy_o
);

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (~rst_ni) begin
            ph_phy_o  <= 1'b0;
        end else begin
            ph_phy_o  <= ~ph_phy_o;
        end
    end

    // clock divider: using blocking assignment to prevent "hold" issue in simulation
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (~rst_ni) begin
            clk_phy_o  = 1'b0;
        end else begin
            clk_phy_o  = ~clk_phy_o;
        end
    end


// clk     ___-_-_-_-_-_-_-_-_-
// ph_phy  ___--__--__--__--__-
// clk_phy ___--__--__--__--__-

endmodule
