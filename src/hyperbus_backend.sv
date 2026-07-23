// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

`include "common_cells/assertions.svh"
`include "common_cells/registers.svh"

module hyperbus_backend #(
    parameter int unsigned  NumChips         = -1,
    parameter int unsigned  NumPhys          = 2,
    parameter int unsigned  StartupCycles    = 60000,
    parameter int unsigned  SyncStages       = 2,
    parameter type          hyper_rx_t       = logic,
    parameter type          hyper_tx_t       = logic,
    parameter type          hyper_cmd_t      = logic
) (
    input  logic                       clk_i,
    input  logic                       clk_90_i,
    input  logic                       rst_ni,
    input  logic                       test_mode_i,

    input  hyperbus_pkg::phy_cfg_t     cfg_apply_i,
    input  logic                       cfg_apply_valid_i,
    output logic                       cfg_apply_ready_o,

    output logic                       busy_o,
    output logic [7:0]                 tx_clk_delay_o,

    output hyper_rx_t                  rx_o,
    output logic                       rx_valid_o,
    input  logic                       rx_ready_i,
    input  hyper_tx_t                  tx_i,
    input  logic                       tx_valid_i,
    output logic                       tx_ready_o,
    output logic                       wrsp_error_o,
    output logic                       wrsp_valid_o,
    input  logic                       wrsp_ready_i,
    input  hyper_cmd_t                 cmd_i,
    input  logic                       cmd_valid_i,
    output logic                       cmd_ready_o,

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

    hyperbus_pkg::phy_cfg_t cfg_q, cfg_d;
    logic                     phy_busy;
    logic                     cfg_apply_fire;

    `ASSERT_INIT(NumChipsValid, NumChips >= 1 && NumChips <= 8)
    `ASSERT_INIT(NumPhysValid, NumPhys == 1 || NumPhys == 2)
    `ASSERT_INIT(SyncStagesValid, SyncStages >= 2)

    assign cfg_apply_ready_o = ~phy_busy;
    assign cfg_apply_fire    = cfg_apply_valid_i & cfg_apply_ready_o;
    assign cfg_d             = cfg_apply_fire ? cfg_apply_i : cfg_q;
    assign busy_o            = phy_busy | cfg_apply_valid_i;
    assign tx_clk_delay_o    = cfg_q.t_tx_clk_delay;

    `FFARN(cfg_q, cfg_d, '0, clk_i, rst_ni)

    hyperbus_phy_if #(
        .NumChips         ( NumChips         ),
        .NumPhys          ( NumPhys          ),
        .StartupCycles    ( StartupCycles    ),
        .hyper_rx_t       ( hyper_rx_t       ),
        .hyper_tx_t       ( hyper_tx_t       ),
        .SyncStages       ( SyncStages       )
    ) i_phy (
        .clk_phy_i       ( clk_i          ),
        .clk_phy_i_90    ( clk_90_i       ),
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
        .b_error_o       ( wrsp_error_o   ),
        .b_valid_o       ( wrsp_valid_o   ),
        .b_ready_i       ( wrsp_ready_i   ),
        .trans_i         ( cmd_i.trans    ),
        .trans_cs_i      ( cmd_i.cs       ),
        .trans_valid_i   ( cmd_valid_i    ),
        .trans_ready_o   ( cmd_ready_o    ),
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
