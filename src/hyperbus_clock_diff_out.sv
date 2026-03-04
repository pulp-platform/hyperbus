// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Armin Berger <bergerar@ethz.ch>
// Stephan Keck <kecks@ethz.ch>

/// A Hyperbus differential clock output generator.
(* no_ungroup *)
(* no_boundary_optimization *)
(* keep_hierarchy = "yes" *)
module hyperbus_clock_diff_out
(
    input  logic clk_phy_x2_i,
`ifdef TARGET_XILINX
    input  logic clk_phy_i,
    input  logic clk_ref200_i,
`endif
    input  logic rst_ni,
    input  logic ph_phy_i,
    input  logic cfg_tx_clk_delay_mode_i,
    input  logic [4:0] cfg_tx_clk_delay_i,
    input  logic en_i,
    output logic out_o,
    output logic out_no
);

    logic en_clk;

    // Shift clock by 90 degrees
    // Main idea for both options is to generate the CK output clock from an output of a FF.
    // This should prevent issue in STA and facilitate constraint development
    // Also this approach shold align as much as possible CK to other interface signals that are generated as output of FF as well

    // option 1: use the opposite edge of phy_x2 clock
    logic clk_phy_90_by_clk_g;
    always_ff @(negedge clk_phy_x2_i or negedge rst_ni) begin
        if (~rst_ni) begin
            clk_phy_90_by_clk_g <= '0;
            en_clk <= '0;
        end else begin
            clk_phy_90_by_clk_g <= ~cfg_tx_clk_delay_mode_i & ph_phy_i & en_clk;
            if(~ph_phy_i) begin
                en_clk <= en_i;
            end
        end
    end

    // option 2: generate a clock on same edge of phy clock and adding a delay line on the output of the flop
    logic clk_phy_0_g, clk_phy_90_by_delay_g, clk_phy_90_g;
    always_ff @(posedge clk_phy_x2_i or negedge rst_ni) begin
        if (~rst_ni) begin
            clk_phy_0_g <= '0;
        end else begin
            clk_phy_0_g <= cfg_tx_clk_delay_mode_i & ~ph_phy_i & en_clk;
        end
    end


`ifdef TARGET_XILINX
    hyperbus_clk_delay i_delay_tx_clk_90 (
        .rst_i         ( ~rst_ni ),
        .clk_ref200_i,
        .clk_i         ( clk_phy_i            ),
        .in_i          ( clk_phy_0_g          ),
        .delay_i       ( cfg_tx_clk_delay_i   ),
        .out_o         ( clk_phy_90_by_delay_g)
    );
`else
    hyperbus_delay i_delay_tx_clk_90 (
        .in_i          ( clk_phy_0_g          ),
        .delay_i       ( cfg_tx_clk_delay_i   ),
        .out_o         ( clk_phy_90_by_delay_g )
    );
`endif

    // option 1 and 2 muxed using a simple OR2 because the clocks are already gated
    tc_clk_or2 i_clk_phy_90_g ( // TODO to replace with NOR, inverting out_o and out_no to reduce propagation time
        .clk_o     ( out_o ),
        .clk0_i    ( clk_phy_90_by_clk_g ),
        .clk1_i    ( clk_phy_90_by_delay_g )
    );

    tc_clk_inverter i_hyper_ck_no_inv (
        .clk_i ( out_o  ),
        .clk_o ( out_no )
    );

endmodule
