// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

`include "hyperbus/typedef.svh"
`include "common_cells/assertions.svh"

module hyperbus_asynchronous #(
    parameter int unsigned  NumPhys               = 2,
    parameter int unsigned  AxiAddrWidth          = -1,
    parameter int unsigned  AxiDataWidth          = -1,
    parameter int unsigned  AxiIdWidth            = -1,
    parameter int unsigned  AxiUserWidth          = -1,
    parameter type          axi_req_t             = logic,
    parameter type          axi_rsp_t             = logic,
    parameter int unsigned  RegDataWidth          = -1,
    parameter int unsigned  RegAddrWidth          = 32,
    parameter type          reg_req_t             = logic,
    parameter type          reg_rsp_t             = logic,
    parameter type          axi_rule_t            = logic,
    parameter int unsigned  AxiMaxReadTxns        = 4,
    parameter int unsigned  AxiMaxWriteTxns       = 4,
    parameter int unsigned  HostWriteBufferBytes  = 64,
    parameter int unsigned  RxFifoLogDepth        = 3,
    parameter int unsigned  TxFifoLogDepth        = 3,
    parameter int unsigned  PhyStartupCycles      = 300 * 200,
    parameter int unsigned  SyncStages            = 2,
    parameter int unsigned  CdcSyncStages         = 3
) (
    input  logic                        clk_sys_i,
    input  logic                        rst_sys_ni,
    input  logic                        clk_phy_i,
    input  logic                        rst_phy_ni,
`ifdef TARGET_XILINX
    input  logic                        clk_ref200_i,
`endif
    input  logic                        test_mode_i,

    input  axi_req_t                    axi_req_i,
    output axi_rsp_t                    axi_rsp_o,

    input  reg_req_t                    reg_req_i,
    output reg_rsp_t                    reg_rsp_o,

    output logic [NumPhys-1:0][hyperbus_pkg::HyperNumChips-1:0] hyper_cs_no,
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

    `ASSERT_INIT(AxiAddrWidthValid, AxiAddrWidth >= $clog2(AxiDataWidth / 8))
    `ASSERT_INIT(AxiMaxReadTxnsValid, AxiMaxReadTxns >= 1)
    `ASSERT_INIT(AxiMaxWriteTxnsValid, AxiMaxWriteTxns >= 1)

    typedef logic [AxiAddrWidth-1:0]   host_addr_t;
    typedef logic [AxiDataWidth-1:0]   host_data_t;
    typedef logic [AxiDataWidth/8-1:0] host_strb_t;
    localparam int unsigned AxiDataBytes = AxiDataWidth / 8;
    `HYPERBUS_TYPEDEF_HOST_ALL_CT(host, host_addr_t, host_data_t, host_strb_t)
    `HYPERBUS_TYPEDEF_LINK_ALL_CT(hyper, NumPhys)

    /////////////////////
    // Clock and reset //
    /////////////////////

    logic clk_backend;
    logic rst_backend_n;
    logic rst_phy_async_n;

    ////////////////////////
    // Configuration path //
    ////////////////////////

    hyperbus_pkg::phy_cfg_t    frontend_cfg_apply;
    logic                      frontend_cfg_apply_valid;
    logic                      frontend_cfg_apply_ready;
    logic                      frontend_cfg_apply_done;
    logic                      frontend_clock_div_apply_valid;
    logic                      frontend_drain;
    logic                      host_idle;
    hyperbus_pkg::phy_cfg_t    backend_cfg_apply;
    logic                      backend_cfg_apply_valid;
    logic                      backend_cfg_apply_ready;

    hyperbus_pkg::frontend_cfg_t frontend_cfg;
    axi_rule_t [hyperbus_pkg::HyperNumChips-1:0] frontend_chip_rules;

    ////////////////////
    // Dataflow links //
    ////////////////////

    host_req_t                host_req;
    host_rsp_t                host_rsp;
    hyper_req_t               midend_req;
    hyper_rsp_t               midend_rsp;
    logic                     midend_trans_active;
    logic                     midend_decode_error;
    hyper_req_t               backend_req;
    hyper_rsp_t               backend_rsp;

    // Clearable CDCs permit an independent PHY reset without creating phantom
    // transfers. Such a reset can discard a pending transfer and is therefore
    // only a supported software operation while the controller is idle.
    assign rst_phy_async_n = rst_sys_ni & rst_phy_ni;

    assign clk_backend = clk_phy_i;

    rstgen i_rstgen_phy (
        .clk_i       ( clk_backend     ),
        .rst_ni      ( rst_phy_async_n ),
        .test_mode_i ( test_mode_i     ),
        .rst_no      ( rst_backend_n   ),
        .init_no     (                 )
    );

    ////////////////////////////
    // Configuration frontend //
    ////////////////////////////

    hyperbus_cfg_frontend #(
        .NumPhys       ( NumPhys       ),
        .reg_req_t     ( reg_req_t     ),
        .reg_rsp_t     ( reg_rsp_t     ),
        .host_rule_t   ( axi_rule_t    ),
        .RegDataWidth  ( RegDataWidth  ),
        .RegAddrWidth  ( RegAddrWidth  )
    ) i_cfg_frontend (
        .clk_i              ( clk_sys_i              ),
        .rst_ni             ( rst_sys_ni             ),
        .reg_req_i          ( reg_req_i              ),
        .reg_rsp_o          ( reg_rsp_o              ),
        .drain_o            ( frontend_drain         ),
        .host_idle_i        ( host_idle              ),
        .trans_active_i     ( midend_trans_active    ),
        .cfg_apply_o        ( frontend_cfg_apply       ),
        .cfg_apply_valid_o  ( frontend_cfg_apply_valid ),
        .cfg_apply_ready_i  ( frontend_cfg_apply_ready ),
        .cfg_apply_done_i   ( frontend_cfg_apply_done  ),
        .clock_div_apply_o       (                                ),
        .clock_div_apply_valid_o ( frontend_clock_div_apply_valid ),
        .clock_div_apply_ready_i ( 1'b1                           ),
        .clock_div_apply_done_i  ( frontend_clock_div_apply_valid ),
        .frontend_cfg_o     ( frontend_cfg           ),
        .chip_rules_o       ( frontend_chip_rules    ),
        .decode_error_i     ( midend_decode_error    )
    );

    //////////////////
    // AXI frontend //
    //////////////////

    hyperbus_axi_frontend #(
        .AxiDataWidth      ( AxiDataWidth                          ),
        .AxiAddrWidth      ( AxiAddrWidth                          ),
        .AxiIdWidth        ( AxiIdWidth                            ),
        .AxiUserWidth      ( AxiUserWidth                          ),
        .AxiMaxReadTxns    ( AxiMaxReadTxns                        ),
        .AxiMaxWriteTxns   ( AxiMaxWriteTxns                       ),
        .MaxWriteDataBeats ( HostWriteBufferBytes / AxiDataBytes  ),
        .axi_req_t         ( axi_req_t                              ),
        .axi_rsp_t         ( axi_rsp_t                              ),
        .host_req_t        ( host_req_t                             ),
        .host_rsp_t        ( host_rsp_t                             )
    ) i_axi_frontend (
        .clk_i             ( clk_sys_i      ),
        .rst_ni            ( rst_sys_ni     ),
        .drain_i           ( frontend_drain ),
        .idle_o            ( host_idle      ),
        .axi_req_i         ( axi_req_i      ),
        .axi_rsp_o         ( axi_rsp_o      ),
        .host_req_o         ( host_req       ),
        .host_rsp_i         ( host_rsp       )
    );

    ////////////
    // Midend //
    ////////////

    hyperbus_midend #(
        .HostAddrWidth        ( AxiAddrWidth        ),
        .HostDataWidth        ( AxiDataWidth        ),
        .NumPhys              ( NumPhys             ),
        .HostWriteBufferBytes ( HostWriteBufferBytes ),
        .host_cmd_t            ( host_cmd_t          ),
        .host_w_t              ( host_w_t            ),
        .host_r_t              ( host_r_t            ),
        .host_wrsp_t           ( host_wrsp_t         ),
        .host_req_t            ( host_req_t          ),
        .host_rsp_t            ( host_rsp_t          ),
        .hyper_rx_t            ( hyper_rx_t          ),
        .hyper_tx_t            ( hyper_tx_t          ),
        .hyper_cmd_t           ( hyper_cmd_t         ),
        .hyper_req_t           ( hyper_req_t         ),
        .hyper_rsp_t           ( hyper_rsp_t         ),
        .rule_t                ( axi_rule_t          )
    ) i_midend (
        .clk_i             ( clk_sys_i              ),
        .rst_ni            ( rst_sys_ni             ),
        .host_link_req_i   ( host_req               ),
        .host_link_rsp_o   ( host_rsp               ),
        .frontend_cfg_i    ( frontend_cfg           ),
        .chip_rules_i      ( frontend_chip_rules    ),
        .trans_active_o    ( midend_trans_active    ),
        .decode_error_o    ( midend_decode_error    ),
        .hyper_link_req_o  ( midend_req             ),
        .hyper_link_rsp_i  ( midend_rsp             )
    );

    /////////////////////////
    // Asynchronous bridge //
    /////////////////////////

    hyperbus_async_bridge #(
        .RxFifoLogDepth ( RxFifoLogDepth ),
        .TxFifoLogDepth ( TxFifoLogDepth ),
        .CdcSyncStages  ( CdcSyncStages  ),
        .hyper_rx_t     ( hyper_rx_t     ),
        .hyper_tx_t     ( hyper_tx_t     ),
        .hyper_wrsp_t   ( hyper_wrsp_t   ),
        .hyper_cmd_t    ( hyper_cmd_t    ),
        .hyper_req_t    ( hyper_req_t    ),
        .hyper_rsp_t    ( hyper_rsp_t    )
    ) i_bridge (
        .clk_sys_i                ( clk_sys_i                 ),
        .rst_sys_ni               ( rst_sys_ni                ),
        .clk_phy_i                ( clk_backend               ),
        .rst_phy_ni               ( rst_backend_n             ),
        .cfg_apply_i              ( frontend_cfg_apply        ),
        .frontend_cfg_apply_valid_i ( frontend_cfg_apply_valid ),
        .frontend_cfg_apply_ready_o ( frontend_cfg_apply_ready ),
        .frontend_cfg_apply_done_o  ( frontend_cfg_apply_done  ),
        .frontend_req_i           ( midend_req                ),
        .frontend_rsp_o           ( midend_rsp                ),
        .backend_req_o            ( backend_req               ),
        .backend_rsp_i            ( backend_rsp               ),
        .cfg_apply_o              ( backend_cfg_apply         ),
        .cfg_apply_valid_o        ( backend_cfg_apply_valid   ),
        .cfg_apply_ready_i        ( backend_cfg_apply_ready   )
    );

    /////////////
    // Backend //
    /////////////

    hyperbus_backend #(
        .NumPhys          ( NumPhys           ),
        .StartupCycles    ( PhyStartupCycles  ),
        .SyncStages       ( SyncStages        ),
        .hyper_rx_t       ( hyper_rx_t        ),
        .hyper_tx_t       ( hyper_tx_t        ),
        .hyper_req_t      ( hyper_req_t       ),
        .hyper_rsp_t      ( hyper_rsp_t       )
    ) i_backend (
        .clk_i                  ( clk_backend               ),
        .rst_ni                 ( rst_backend_n             ),
`ifdef TARGET_XILINX
        .clk_ref200_i           ( clk_ref200_i              ),
`endif
        .test_mode_i            ( test_mode_i               ),
        .cfg_apply_i            ( backend_cfg_apply         ),
        .cfg_apply_valid_i      ( backend_cfg_apply_valid   ),
        .cfg_apply_ready_o      ( backend_cfg_apply_ready   ),
        .busy_o                 (                           ),
        .req_i                  ( backend_req               ),
        .rsp_o                  ( backend_rsp               ),
        .hyper_cs_no            ( hyper_cs_no               ),
        .hyper_ck_o             ( hyper_ck_o                ),
        .hyper_ck_no            ( hyper_ck_no               ),
        .hyper_rwds_o           ( hyper_rwds_o              ),
        .hyper_rwds_i           ( hyper_rwds_i              ),
        .hyper_rwds_oe_o        ( hyper_rwds_oe_o           ),
        .hyper_dq_i             ( hyper_dq_i                ),
        .hyper_dq_o             ( hyper_dq_o                ),
        .hyper_dq_oe_o          ( hyper_dq_oe_o             ),
        .hyper_reset_no         ( hyper_reset_no            )
    );

    `ASSERT(PhyResetOnlyWhenIdle, !rst_phy_ni |-> !midend_trans_active,
        clk_sys_i, !rst_sys_ni)

endmodule
