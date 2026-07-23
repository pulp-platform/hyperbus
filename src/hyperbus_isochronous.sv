// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

module hyperbus_isochronous #(
    parameter int unsigned  NumChips         = -1,
    parameter int unsigned  NumPhys          = 2,
    parameter int unsigned  AxiAddrWidth     = -1,
    parameter int unsigned  AxiDataWidth     = -1,
    parameter int unsigned  AxiIdWidth       = -1,
    parameter int unsigned  AxiUserWidth     = -1,
    parameter type          axi_req_t        = logic,
    parameter type          axi_rsp_t        = logic,
    parameter type          axi_w_chan_t     = logic,
    parameter type          axi_b_chan_t     = logic,
    parameter type          axi_ar_chan_t    = logic,
    parameter type          axi_r_chan_t     = logic,
    parameter type          axi_aw_chan_t    = logic,
    parameter int unsigned  RegAddrWidth     = -1,
    parameter int unsigned  RegDataWidth     = -1,
    parameter int unsigned  MinFreqMHz       = 100,
    parameter type          reg_req_t        = logic,
    parameter type          reg_rsp_t        = logic,
    parameter type          axi_rule_t       = logic,
    parameter int unsigned  RxFifoLogDepth   = 8,
    parameter int unsigned  TxFifoLogDepth   = 3,
    parameter logic [RegDataWidth-1:0]  RstChipBase  = 'h0,
    parameter logic [RegDataWidth-1:0]  RstChipSpace = 'h1_0000,
    parameter hyperbus_pkg::hyper_cfg_t RstCfg       = hyperbus_pkg::gen_RstCfg(NumPhys, MinFreqMHz),
    parameter int unsigned  PhyStartupCycles = 300 * 200,
    parameter int unsigned  SyncStages       = 2
) (
    input  logic                        clk_sys_i,
    input  logic                        rst_sys_ni,
`ifdef TARGET_XILINX
    input  logic                        clk_ref200_i,
`endif
    input  logic                        test_mode_i,

    input  axi_req_t                    axi_req_i,
    output axi_rsp_t                    axi_rsp_o,

    input  reg_req_t                    reg_req_i,
    output reg_rsp_t                    reg_rsp_o,

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

    typedef struct packed {
        logic [(16*NumPhys)-1:0] data;
        logic                    last;
        logic [(2*NumPhys)-1:0]  strb;
    } hyper_tx_t;

    typedef struct packed {
        logic [(16*NumPhys)-1:0] data;
        logic                    last;
        logic                    error;
    } hyper_rx_t;

    typedef struct packed {
        hyperbus_pkg::hyper_tf_t trans;
        logic [NumChips-1:0]     cs;
    } tf_cdc_t;

    logic                      clk_backend;
    logic                      clk_backend_90;
    logic                      rst_backend_n;
    hyperbus_pkg::hyper_cfg_t  cfg_frontend_apply;
    logic                      cfg_frontend_apply_valid;
    logic                      cfg_frontend_apply_ready;
    hyperbus_pkg::hyper_cfg_t  cfg_backend_apply;
    logic                      cfg_backend_apply_valid;
    logic                      cfg_backend_apply_ready;
    logic                      rst_backend_async_n;

    hyper_rx_t                 frontend_rx;
    logic                      frontend_rx_valid;
    logic                      frontend_rx_ready;
    hyper_tx_t                 frontend_tx;
    logic                      frontend_tx_valid;
    logic                      frontend_tx_ready;
    logic                      frontend_b_error;
    logic                      frontend_b_valid;
    logic                      frontend_b_ready;
    tf_cdc_t                   frontend_trans;
    logic                      frontend_trans_valid;
    logic                      frontend_trans_ready;

    hyper_rx_t                 backend_rx;
    logic                      backend_rx_valid;
    logic                      backend_rx_ready;
    hyper_tx_t                 backend_tx;
    logic                      backend_tx_valid;
    logic                      backend_tx_ready;
    logic                      backend_b_error;
    logic                      backend_b_valid;
    logic                      backend_b_ready;
    tf_cdc_t                   backend_trans;
    logic                      backend_trans_valid;
    logic                      backend_trans_ready;

    hyperbus_clk_gen i_clk_gen (
        .clk_i    ( clk_sys_i        ),
        .rst_ni   ( rst_sys_ni       ),
        .clk0_o   ( clk_backend      ),
        .clk90_o  ( clk_backend_90   ),
        .clk180_o (                  ),
        .clk270_o (                  ),
        .rst_no   ( rst_backend_async_n )
    );

    rstgen i_rstgen_backend (
        .clk_i       ( clk_backend         ),
        .rst_ni      ( rst_backend_async_n ),
        .test_mode_i ( test_mode_i         ),
        .rst_no      ( rst_backend_n       ),
        .init_no     (                     )
    );

    hyperbus_frontend #(
        .NumChips      ( NumChips      ),
        .NumPhys       ( NumPhys       ),
        .AxiAddrWidth  ( AxiAddrWidth  ),
        .AxiDataWidth  ( AxiDataWidth  ),
        .AxiIdWidth    ( AxiIdWidth    ),
        .AxiUserWidth  ( AxiUserWidth  ),
        .axi_req_t     ( axi_req_t     ),
        .axi_rsp_t     ( axi_rsp_t     ),
        .reg_req_t     ( reg_req_t     ),
        .reg_rsp_t     ( reg_rsp_t     ),
        .axi_rule_t    ( axi_rule_t    ),
        .hyper_rx_t    ( hyper_rx_t    ),
        .hyper_tx_t    ( hyper_tx_t    ),
        .tf_cdc_t      ( tf_cdc_t      ),
        .RegAddrWidth  ( RegAddrWidth  ),
        .RegDataWidth  ( RegDataWidth  ),
        .RstChipBase   ( RstChipBase   ),
        .RstChipSpace  ( RstChipSpace  ),
        .RstCfg        ( RstCfg        )
    ) i_frontend (
        .clk_i              ( clk_sys_i              ),
        .rst_ni             ( rst_sys_ni             ),
        .axi_req_i          ( axi_req_i              ),
        .axi_rsp_o          ( axi_rsp_o              ),
        .reg_req_i          ( reg_req_i              ),
        .reg_rsp_o          ( reg_rsp_o              ),
        .cfg_o              (                        ),
        .cfg_apply_o        ( cfg_frontend_apply     ),
        .cfg_apply_valid_o  ( cfg_frontend_apply_valid ),
        .cfg_apply_ready_i  ( cfg_frontend_apply_ready ),
        .rx_i               ( frontend_rx            ),
        .rx_valid_i         ( frontend_rx_valid      ),
        .rx_ready_o         ( frontend_rx_ready      ),
        .tx_o               ( frontend_tx            ),
        .tx_valid_o         ( frontend_tx_valid      ),
        .tx_ready_i         ( frontend_tx_ready      ),
        .b_error_i          ( frontend_b_error       ),
        .b_valid_i          ( frontend_b_valid       ),
        .b_ready_o          ( frontend_b_ready       ),
        .trans_o            ( frontend_trans         ),
        .trans_valid_o      ( frontend_trans_valid   ),
        .trans_ready_i      ( frontend_trans_ready   )
    );

    hyperbus_iso_bridge #(
        .RxFifoLogDepth ( RxFifoLogDepth ),
        .TxFifoLogDepth ( TxFifoLogDepth ),
        .hyper_rx_t     ( hyper_rx_t     ),
        .hyper_tx_t     ( hyper_tx_t     ),
        .tf_cdc_t       ( tf_cdc_t       )
    ) i_bridge (
        .clk_sys_i                ( clk_sys_i                 ),
        .rst_sys_ni               ( rst_sys_ni                ),
        .clk_phy_i                ( clk_backend               ),
        .rst_phy_ni               ( rst_backend_n             ),
        .cfg_apply_i              ( cfg_frontend_apply        ),
        .frontend_cfg_apply_valid_i ( cfg_frontend_apply_valid ),
        .frontend_cfg_apply_ready_o ( cfg_frontend_apply_ready ),
        .frontend_rx_o            ( frontend_rx               ),
        .frontend_rx_valid_o      ( frontend_rx_valid         ),
        .frontend_rx_ready_i      ( frontend_rx_ready         ),
        .frontend_tx_i            ( frontend_tx               ),
        .frontend_tx_valid_i      ( frontend_tx_valid         ),
        .frontend_tx_ready_o      ( frontend_tx_ready         ),
        .frontend_b_error_o       ( frontend_b_error          ),
        .frontend_b_valid_o       ( frontend_b_valid          ),
        .frontend_b_ready_i       ( frontend_b_ready          ),
        .frontend_trans_i         ( frontend_trans            ),
        .frontend_trans_valid_i   ( frontend_trans_valid      ),
        .frontend_trans_ready_o   ( frontend_trans_ready      ),
        .backend_rx_i             ( backend_rx                ),
        .backend_rx_valid_i       ( backend_rx_valid          ),
        .backend_rx_ready_o       ( backend_rx_ready          ),
        .backend_tx_o             ( backend_tx                ),
        .backend_tx_valid_o       ( backend_tx_valid          ),
        .backend_tx_ready_i       ( backend_tx_ready          ),
        .backend_b_error_i        ( backend_b_error           ),
        .backend_b_valid_i        ( backend_b_valid           ),
        .backend_b_ready_o        ( backend_b_ready           ),
        .backend_trans_o          ( backend_trans             ),
        .backend_trans_valid_o    ( backend_trans_valid       ),
        .backend_trans_ready_i    ( backend_trans_ready       ),
        .cfg_apply_o              ( cfg_backend_apply         ),
        .cfg_apply_valid_o        ( cfg_backend_apply_valid   ),
        .cfg_apply_ready_i        ( cfg_backend_apply_ready   )
    );

    hyperbus_backend #(
        .NumChips         ( NumChips          ),
        .NumPhys          ( NumPhys           ),
        .StartupCycles    ( PhyStartupCycles  ),
        .SyncStages       ( SyncStages        ),
        .hyper_rx_t       ( hyper_rx_t        ),
        .hyper_tx_t       ( hyper_tx_t        ),
        .tf_cdc_t         ( tf_cdc_t          ),
        .RstCfg           ( RstCfg            )
    ) i_backend (
        .clk_i                  ( clk_backend               ),
        .clk_90_i               ( clk_backend_90            ),
        .rst_ni                 ( rst_backend_n             ),
        .test_mode_i            ( test_mode_i               ),
        .cfg_apply_i            ( cfg_backend_apply         ),
        .cfg_apply_valid_i      ( cfg_backend_apply_valid   ),
        .cfg_apply_ready_o      ( cfg_backend_apply_ready   ),
        .busy_o                 (                           ),
        .tx_clk_delay_o         (                           ),
        .rx_o                   ( backend_rx                ),
        .rx_valid_o             ( backend_rx_valid          ),
        .rx_ready_i             ( backend_rx_ready          ),
        .tx_i                   ( backend_tx                ),
        .tx_valid_i             ( backend_tx_valid          ),
        .tx_ready_o             ( backend_tx_ready          ),
        .b_error_o              ( backend_b_error           ),
        .b_valid_o              ( backend_b_valid           ),
        .b_ready_i              ( backend_b_ready           ),
        .trans_i                ( backend_trans             ),
        .trans_valid_i          ( backend_trans_valid       ),
        .trans_ready_o          ( backend_trans_ready       ),
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

endmodule
