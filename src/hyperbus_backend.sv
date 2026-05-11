// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

module hyperbus_backend #(
    parameter int unsigned  NumChips         = -1,
    parameter int unsigned  NumPhys          = 2,
    parameter bit           UsePhyClkDivider = 1,
    parameter int unsigned  StartupCycles    = 60000,
    parameter int unsigned  SyncStages       = 2,
    parameter type          hyper_rx_t       = logic,
    parameter type          hyper_tx_t       = logic,
    parameter type          tf_cdc_t         = logic,
    parameter hyperbus_pkg::hyper_cfg_t RstCfg = '0
) (
    input  logic                       clk_i,
    input  logic                       clk_90_i,
`ifdef TARGET_XILINX
    input  logic                       clk_ref200_i,
`endif
    input  logic                       rst_ni,
    input  logic                       test_mode_i,

    input  hyperbus_pkg::hyper_cfg_t   cfg_apply_i,
    input  logic                       cfg_apply_valid_i,
    output logic                       cfg_apply_ready_o,

    output logic                       busy_o,

    output hyper_rx_t                  rx_o,
    output logic                       rx_valid_o,
    input  logic                       rx_ready_i,
    input  hyper_tx_t                  tx_i,
    input  logic                       tx_valid_i,
    output logic                       tx_ready_o,
    output logic                       b_error_o,
    output logic                       b_valid_o,
    input  logic                       b_ready_i,
    input  tf_cdc_t                    trans_i,
    input  logic                       trans_valid_i,
    output logic                       trans_ready_o,

    output logic [NumPhys-1:0][NumChips-1:0] hyper_cs_no,
    output logic [NumPhys-1:0]               hyper_ck_o,
    output logic [NumPhys-1:0]               hyper_ck_no,
    output logic [NumPhys-1:0]               hyper_rwds_o,
    input  logic [NumPhys-1:0]               hyper_rwds_i,
    output logic [NumPhys-1:0]               hyper_rwds_oe_o,
    input  logic [NumPhys-1:0][7:0]          hyper_dq_i,
    output logic [NumPhys-1:0][7:0]          hyper_dq_o,
    output logic [NumPhys-1:0]               hyper_dq_oe_o,
    output logic [NumPhys-1:0]               hyper_reset_no
);

    hyperbus_pkg::hyper_cfg_t cfg_q, cfg_d;
    logic                     phy_busy;
    logic                     cfg_apply_fire;

    assign cfg_apply_ready_o = ~phy_busy;
    assign cfg_apply_fire    = cfg_apply_valid_i & cfg_apply_ready_o;
    assign cfg_d             = cfg_apply_fire ? cfg_apply_i : cfg_q;
    assign busy_o            = phy_busy | cfg_apply_valid_i;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) cfg_q <= RstCfg;
        else         cfg_q <= cfg_d;
    end

    hyperbus_phy_if #(
        .UsePhyClkDivider ( UsePhyClkDivider ),
        .NumChips         ( NumChips         ),
        .NumPhys          ( NumPhys          ),
        .StartupCycles    ( StartupCycles    ),
        .hyper_rx_t       ( hyper_rx_t       ),
        .hyper_tx_t       ( hyper_tx_t       ),
        .SyncStages       ( SyncStages       )
    ) i_phy (
        .clk_phy_i       ( clk_i          ),
        .clk_phy_i_90    ( clk_90_i       ),
`ifdef TARGET_XILINX
        .clk_ref200_i    ( clk_ref200_i   ),
`endif
        .rst_phy_ni      ( rst_ni         ),
        .test_mode_i     ( test_mode_i    ),
        .cfg_i           ( cfg_q          ),
        .busy_o          ( phy_busy       ),
        .rx_o            ( rx_o           ),
        .rx_valid_o      ( rx_valid_o     ),
        .rx_ready_i      ( rx_ready_i     ),
        .tx_i            ( tx_i           ),
        .tx_valid_i      ( tx_valid_i     ),
        .tx_ready_o      ( tx_ready_o     ),
        .b_error_o       ( b_error_o      ),
        .b_valid_o       ( b_valid_o      ),
        .b_ready_i       ( b_ready_i      ),
        .trans_i         ( trans_i.trans  ),
        .trans_cs_i      ( trans_i.cs     ),
        .trans_valid_i   ( trans_valid_i  ),
        .trans_ready_o   ( trans_ready_o  ),
        .hyper_cs_no     ( hyper_cs_no    ),
        .hyper_ck_o      ( hyper_ck_o     ),
        .hyper_ck_no     ( hyper_ck_no    ),
        .hyper_rwds_o    ( hyper_rwds_o   ),
        .hyper_rwds_i    ( hyper_rwds_i   ),
        .hyper_rwds_oe_o ( hyper_rwds_oe_o ),
        .hyper_dq_i      ( hyper_dq_i     ),
        .hyper_dq_o      ( hyper_dq_o     ),
        .hyper_dq_oe_o   ( hyper_dq_oe_o  ),
        .hyper_reset_no  ( hyper_reset_no )
    );

endmodule
