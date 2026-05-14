// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

module hyperbus_synchronous #(
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
    } tf_t;

    logic                     clk_backend_90;
    logic [7:0]               backend_tx_clk_delay;
    hyperbus_pkg::hyper_cfg_t cfg_apply;
    logic                     cfg_apply_valid;
    logic                     cfg_apply_ready;

    hyper_rx_t                rx;
    logic                     rx_valid;
    logic                     rx_ready;
    hyper_tx_t                tx;
    logic                     tx_valid;
    logic                     tx_ready;
    tf_t                      frontend_trans;
    logic                     frontend_trans_valid;
    logic                     frontend_trans_ready;
    logic                     backend_trans_ready;
    logic                     b_error;
    logic                     b_valid;
    logic                     b_ready;

    hyperbus_tx_clk_delay i_tx_clk_delay (
        .rst_ni        ( rst_sys_ni           ),
`ifdef TARGET_XILINX
        .clk_ref200_i  ( clk_ref200_i         ),
`endif
        .clk_i         ( clk_sys_i            ),
        .in_i          ( clk_sys_i            ),
        .delay_i       ( backend_tx_clk_delay ),
        .out_o         ( clk_backend_90       )
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
        .tf_cdc_t      ( tf_t          ),
        .RegAddrWidth  ( RegAddrWidth  ),
        .RegDataWidth  ( RegDataWidth  ),
        .RstChipBase   ( RstChipBase   ),
        .RstChipSpace  ( RstChipSpace  ),
        .RstCfg        ( RstCfg        )
    ) i_frontend (
        .clk_i              ( clk_sys_i       ),
        .rst_ni             ( rst_sys_ni      ),
        .axi_req_i          ( axi_req_i       ),
        .axi_rsp_o          ( axi_rsp_o       ),
        .reg_req_i          ( reg_req_i       ),
        .reg_rsp_o          ( reg_rsp_o       ),
        .cfg_o              (                 ),
        .cfg_apply_o        ( cfg_apply       ),
        .cfg_apply_valid_o  ( cfg_apply_valid ),
        .cfg_apply_ready_i  ( cfg_apply_ready ),
        .rx_i               ( rx              ),
        .rx_valid_i         ( rx_valid        ),
        .rx_ready_o         ( rx_ready        ),
        .tx_o               ( tx              ),
        .tx_valid_o         ( tx_valid        ),
        .tx_ready_i         ( tx_ready        ),
        .b_error_i          ( b_error         ),
        .b_valid_i          ( b_valid         ),
        .b_ready_o          ( b_ready         ),
        .trans_o            ( frontend_trans        ),
        .trans_valid_o      ( frontend_trans_valid  ),
        .trans_ready_i      ( frontend_trans_ready  )
    );

    assign frontend_trans_ready = backend_trans_ready;

    hyperbus_backend #(
        .NumChips         ( NumChips          ),
        .NumPhys          ( NumPhys           ),
        .StartupCycles    ( PhyStartupCycles  ),
        .SyncStages       ( SyncStages        ),
        .hyper_rx_t       ( hyper_rx_t        ),
        .hyper_tx_t       ( hyper_tx_t        ),
        .tf_cdc_t         ( tf_t              ),
        .RstCfg           ( RstCfg            )
    ) i_backend (
        .clk_i                  ( clk_sys_i             ),
        .clk_90_i               ( clk_backend_90        ),
        .rst_ni                 ( rst_sys_ni            ),
        .test_mode_i            ( test_mode_i           ),
        .cfg_apply_i            ( cfg_apply             ),
        .cfg_apply_valid_i      ( cfg_apply_valid       ),
        .cfg_apply_ready_o      ( cfg_apply_ready       ),
        .busy_o                 (                       ),
        .tx_clk_delay_o         ( backend_tx_clk_delay  ),
        .rx_o                   ( rx                    ),
        .rx_valid_o             ( rx_valid              ),
        .rx_ready_i             ( rx_ready              ),
        .tx_i                   ( tx                    ),
        .tx_valid_i             ( tx_valid              ),
        .tx_ready_o             ( tx_ready              ),
        .b_error_o              ( b_error               ),
        .b_valid_o              ( b_valid               ),
        .b_ready_i              ( b_ready               ),
        .trans_i                ( frontend_trans        ),
        .trans_valid_i          ( frontend_trans_valid  ),
        .trans_ready_o          ( backend_trans_ready   ),
        .hyper_cs_no            ( hyper_cs_no           ),
        .hyper_ck_o             ( hyper_ck_o            ),
        .hyper_ck_no            ( hyper_ck_no           ),
        .hyper_rwds_o           ( hyper_rwds_o          ),
        .hyper_rwds_i           ( hyper_rwds_i          ),
        .hyper_rwds_oe_o        ( hyper_rwds_oe_o       ),
        .hyper_dq_i             ( hyper_dq_i            ),
        .hyper_dq_o             ( hyper_dq_o            ),
        .hyper_dq_oe_o          ( hyper_dq_oe_o         ),
        .hyper_reset_no         ( hyper_reset_no        )
    );

endmodule
