// Copyright 2026.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Minimal synthesizable HyperBus PHY front-end for sky130.
//
// This gathers exactly the technology-dependent PHY building blocks of the
// PULP HyperBus controller -- the parts that must map to real sky130 clock
// and delay cells -- into one self-contained top so they can be synthesized
// against sky130_fd_sc_hd WITHOUT the pulp-platform common_cells / axi /
// register_interface dependencies (which the full controller needs and which
// are not vendored here).
//
// Included blocks:
//   * hyperbus_clk_gen        : divide-by-2 quadrature (0/90/180/270) clocks
//   * hyperbus_clock_diff_out : gated differential output clock CK / CK#
//   * hyperbus_ddr_out    x9  : DDR output cells for DQ[7:0] + RWDS (write)
//   * hyperbus_delay          : programmable RX delay on the incoming RWDS
//
// The tc_clk_* cells resolve via target/sky130/tech_cells_sky130.sv and the
// delay line via target/sky130/configurable_delay.sky130.sv.
//
// Bidirectional pads (DQ/RWDS) and the differential CK driver are the
// integrator's job (Caravel GPIO on sky130); this block only produces the
// core-side driver values and output-enable is handled upstream. See
// AUDIT.md and target/sky130/README.md.

module hyperbus_phy_sky130 #(
    parameter int unsigned NumDQ = 8
) (
    input  logic              clk_phy_i,     // PHY reference clock (2x interface rate)
    input  logic              rst_ni,        // async active-low reset

    input  logic              ck_en_i,       // enable the differential output clock
    input  logic [NumDQ-1:0]  tx_d0_i,       // DQ, data for the rising  half-cycle
    input  logic [NumDQ-1:0]  tx_d1_i,       // DQ, data for the falling half-cycle
    input  logic              rwds_d0_i,     // RWDS write mask, rising  half-cycle
    input  logic              rwds_d1_i,     // RWDS write mask, falling half-cycle

    input  logic              rwds_in_i,     // incoming RWDS (read strobe from device)
    input  logic [7:0]        rx_delay_i,    // RX RWDS delay tap select

    output logic              hyper_ck_o,    // differential output clock (P)
    output logic              hyper_ck_no,   // differential output clock (N)
    output logic [NumDQ-1:0]  hyper_dq_o,    // DDR data out to pads
    output logic              hyper_rwds_o,  // DDR RWDS out to pads (write mask)
    output logic              rwds_delayed_o // 90-deg delayed RWDS for read capture
);

    // ------------------------------------------------------------------
    // Quadrature clock generation (0/90/180/270 deg) from clk_phi_i
    // ------------------------------------------------------------------
    logic clk0, clk90, clk180, clk270, rst_no;

    hyperbus_clk_gen i_clk_gen (
        .clk_i    ( clk_phy_i ),
        .rst_ni   ( rst_ni    ),
        .clk0_o   ( clk0      ),
        .clk90_o  ( clk90     ),
        .clk180_o ( clk180    ),
        .clk270_o ( clk270    ),
        .rst_no   ( rst_no    )
    );

    // ------------------------------------------------------------------
    // Gated differential output clock CK / CK#
    // ------------------------------------------------------------------
    hyperbus_clock_diff_out i_ck_out (
        .in_i   ( clk0        ),
        .en_i   ( ck_en_i     ),
        .out_o  ( hyper_ck_o  ),
        .out_no ( hyper_ck_no )
    );

    // ------------------------------------------------------------------
    // DDR data outputs for DQ[7:0], launched on the 90-deg clock so data
    // is centred in the CK eye (source-synchronous write).
    // ------------------------------------------------------------------
    for (genvar i = 0; i < NumDQ; i++) begin : gen_dq
        hyperbus_ddr_out i_ddr_dq (
            .clk_i  ( clk90        ),
            .rst_ni ( rst_ni       ),
            .d0_i   ( tx_d0_i[i]   ),
            .d1_i   ( tx_d1_i[i]   ),
            .q_o    ( hyper_dq_o[i])
        );
    end

    // DDR RWDS output (write data mask)
    hyperbus_ddr_out i_ddr_rwds (
        .clk_i  ( clk90        ),
        .rst_ni ( rst_ni       ),
        .d0_i   ( rwds_d0_i    ),
        .d1_i   ( rwds_d1_i    ),
        .q_o    ( hyper_rwds_o )
    );

    // ------------------------------------------------------------------
    // Programmable delay on the incoming RWDS for read-data capture
    // (the sky130 std-cell delay line).
    // ------------------------------------------------------------------
    hyperbus_delay i_rx_delay (
        .in_i    ( rwds_in_i      ),
        .delay_i ( rx_delay_i     ),
        .out_o   ( rwds_delayed_o )
    );

endmodule
