// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

`include "hyperbus/typedef.svh"
`include "common_cells/assertions.svh"

module hyperbus_synchronous #(
    parameter int unsigned  NumChips         = -1,
    parameter int unsigned  NumPhys          = 2,
    parameter int unsigned  AxiAddrWidth     = -1,
    parameter int unsigned  AxiDataWidth     = -1,
    parameter int unsigned  AxiIdWidth       = -1,
    parameter int unsigned  AxiUserWidth     = -1,
    parameter type          axi_req_t        = logic,
    parameter type          axi_rsp_t        = logic,
    parameter int unsigned  RegDataWidth     = -1,
    parameter type          reg_req_t        = logic,
    parameter type          reg_rsp_t        = logic,
    parameter type          axi_rule_t       = logic,
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

    `ASSERT_INIT(AxiAddrWidthValid, AxiAddrWidth >= $clog2(AxiDataWidth / 8))

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
    } hyper_cmd_t;

    typedef logic [AxiAddrWidth-1:0]   host_addr_t;
    typedef logic [AxiDataWidth-1:0]   host_data_t;
    typedef logic [AxiDataWidth/8-1:0] host_strb_t;
    `HYPERBUS_TYPEDEF_HOST_ALL_CT(host, host_addr_t, host_data_t, host_strb_t)

    logic                      clk_backend;
    logic                      clk_backend_90;
    logic                      rst_backend_n;
    logic [7:0]                backend_tx_clk_delay;
    hyperbus_pkg::phy_cfg_t    frontend_cfg_apply;
    logic                      frontend_cfg_apply_valid;
    logic                      frontend_cfg_apply_ready;
    logic                      frontend_cfg_apply_done;
    logic                      frontend_drain;
    logic                      host_idle;
    hyperbus_pkg::phy_cfg_t    backend_cfg_apply;
    logic                      backend_cfg_apply_valid;
    logic                      backend_cfg_apply_ready;

    hyperbus_pkg::frontend_cfg_t frontend_cfg;
    axi_rule_t [NumChips-1:0]    frontend_chip_rules;

    host_req_t                host_req;
    logic                     host_req_valid;
    logic                     host_req_ready;
    host_w_t                  host_w;
    logic                     host_w_valid;
    logic                     host_w_ready;
    host_r_t                  host_r;
    logic                     host_r_valid;
    logic                     host_r_ready;
    host_wrsp_t               host_wrsp;
    logic                     host_wrsp_valid;
    logic                     host_wrsp_ready;

    hyper_rx_t                midend_rx;
    logic                     midend_rx_valid;
    logic                     midend_rx_ready;
    hyper_tx_t                midend_tx;
    logic                     midend_tx_valid;
    logic                     midend_tx_ready;
    logic                     midend_wrsp_error;
    logic                     midend_wrsp_valid;
    logic                     midend_wrsp_ready;
    hyper_cmd_t               midend_cmd;
    logic                     midend_cmd_valid;
    logic                     midend_cmd_ready;
    logic                     midend_trans_active;
    logic                     midend_decode_error;

    hyper_rx_t                 backend_rx;
    logic                      backend_rx_valid;
    logic                      backend_rx_ready;
    hyper_tx_t                 backend_tx;
    logic                      backend_tx_valid;
    logic                      backend_tx_ready;
    logic                      backend_wrsp_error;
    logic                      backend_wrsp_valid;
    logic                      backend_wrsp_ready;
    hyper_cmd_t                backend_cmd;
    logic                      backend_cmd_valid;
    logic                      backend_cmd_ready;

    assign clk_backend = clk_sys_i;
    assign rst_backend_n = rst_sys_ni;

    // The synchronous top keeps the frontend/backend boundary visible without a bridge module.
    assign backend_cfg_apply        = frontend_cfg_apply;
    assign backend_cfg_apply_valid  = frontend_cfg_apply_valid;
    assign frontend_cfg_apply_ready = backend_cfg_apply_ready;
    assign frontend_cfg_apply_done  = frontend_cfg_apply_valid && backend_cfg_apply_ready;

    assign midend_rx        = backend_rx;
    assign midend_rx_valid  = backend_rx_valid;
    assign backend_rx_ready = midend_rx_ready;

    assign backend_tx       = midend_tx;
    assign backend_tx_valid = midend_tx_valid;
    assign midend_tx_ready  = backend_tx_ready;

    assign midend_wrsp_error = backend_wrsp_error;
    assign midend_wrsp_valid = backend_wrsp_valid;
    assign backend_wrsp_ready = midend_wrsp_ready;

    assign backend_cmd        = midend_cmd;
    assign backend_cmd_valid  = midend_cmd_valid;
    assign midend_cmd_ready   = backend_cmd_ready;

    hyperbus_tx_clk_delay i_tx_clk_delay (
        .rst_ni        ( rst_backend_n        ),
`ifdef TARGET_XILINX
        .clk_ref200_i  ( clk_ref200_i         ),
`endif
        .clk_i         ( clk_backend          ),
        .in_i          ( clk_backend          ),
        .delay_i       ( backend_tx_clk_delay ),
        .out_o         ( clk_backend_90       )
    );

    hyperbus_cfg_frontend #(
        .NumChips      ( NumChips      ),
        .NumPhys       ( NumPhys       ),
        .reg_req_t     ( reg_req_t     ),
        .reg_rsp_t     ( reg_rsp_t     ),
        .host_rule_t   ( axi_rule_t    ),
        .RegDataWidth  ( RegDataWidth  )
    ) i_cfg_frontend (
        .clk_i              ( clk_sys_i                ),
        .rst_ni             ( rst_sys_ni               ),
        .reg_req_i          ( reg_req_i                ),
        .reg_rsp_o          ( reg_rsp_o                ),
        .drain_o            ( frontend_drain           ),
        .host_idle_i        ( host_idle                ),
        .trans_active_i     ( midend_trans_active      ),
        .cfg_apply_o        ( frontend_cfg_apply       ),
        .cfg_apply_valid_o  ( frontend_cfg_apply_valid ),
        .cfg_apply_ready_i  ( frontend_cfg_apply_ready ),
        .cfg_apply_done_i   ( frontend_cfg_apply_done  ),
        .frontend_cfg_o     ( frontend_cfg             ),
        .chip_rules_o       ( frontend_chip_rules      ),
        .decode_error_i     ( midend_decode_error      )
    );

    hyperbus_axi_frontend #(
        .AxiDataWidth ( AxiDataWidth ),
        .AxiAddrWidth ( AxiAddrWidth ),
        .AxiIdWidth   ( AxiIdWidth   ),
        .AxiUserWidth ( AxiUserWidth ),
        .axi_req_t    ( axi_req_t    ),
        .axi_rsp_t    ( axi_rsp_t    ),
        .host_req_t   ( host_req_t   ),
        .host_w_t     ( host_w_t     ),
        .host_r_t     ( host_r_t     ),
        .host_wrsp_t  ( host_wrsp_t  )
    ) i_axi_frontend (
        .clk_i             ( clk_sys_i       ),
        .rst_ni            ( rst_sys_ni      ),
        .drain_i           ( frontend_drain  ),
        .idle_o            ( host_idle       ),
        .axi_req_i         ( axi_req_i       ),
        .axi_rsp_o         ( axi_rsp_o       ),
        .host_req_o         ( host_req                 ),
        .host_req_valid_o   ( host_req_valid           ),
        .host_req_ready_i   ( host_req_ready           ),
        .host_w_o           ( host_w                   ),
        .host_w_valid_o     ( host_w_valid             ),
        .host_w_ready_i     ( host_w_ready             ),
        .host_r_i           ( host_r                   ),
        .host_r_valid_i     ( host_r_valid             ),
        .host_r_ready_o     ( host_r_ready             ),
        .host_wrsp_i        ( host_wrsp                ),
        .host_wrsp_valid_i  ( host_wrsp_valid          ),
        .host_wrsp_ready_o  ( host_wrsp_ready          )
    );

    hyperbus_midend #(
        .HostAddrWidth ( AxiAddrWidth        ),
        .HostDataWidth ( AxiDataWidth        ),
        .NumChips      ( NumChips            ),
        .NumPhys       ( NumPhys             ),
        .host_req_t    ( host_req_t          ),
        .host_w_t      ( host_w_t            ),
        .host_r_t      ( host_r_t            ),
        .host_wrsp_t   ( host_wrsp_t         ),
        .hyper_rx_t    ( hyper_rx_t          ),
        .hyper_tx_t    ( hyper_tx_t          ),
        .hyper_cmd_t   ( hyper_cmd_t         ),
        .rule_t        ( axi_rule_t          )
    ) i_midend (
        .clk_i             ( clk_sys_i              ),
        .rst_ni            ( rst_sys_ni             ),
        .host_req_i        ( host_req               ),
        .host_req_valid_i  ( host_req_valid         ),
        .host_req_ready_o  ( host_req_ready         ),
        .host_w_i          ( host_w                 ),
        .host_w_valid_i    ( host_w_valid           ),
        .host_w_ready_o    ( host_w_ready           ),
        .host_r_o          ( host_r                 ),
        .host_r_valid_o    ( host_r_valid           ),
        .host_r_ready_i    ( host_r_ready           ),
        .host_wrsp_o       ( host_wrsp              ),
        .host_wrsp_valid_o ( host_wrsp_valid        ),
        .host_wrsp_ready_i ( host_wrsp_ready        ),
        .frontend_cfg_i    ( frontend_cfg           ),
        .chip_rules_i      ( frontend_chip_rules    ),
        .trans_active_o    ( midend_trans_active    ),
        .decode_error_o    ( midend_decode_error    ),
        .rx_i              ( midend_rx              ),
        .rx_valid_i        ( midend_rx_valid        ),
        .rx_ready_o        ( midend_rx_ready        ),
        .tx_o              ( midend_tx              ),
        .tx_valid_o        ( midend_tx_valid        ),
        .tx_ready_i        ( midend_tx_ready        ),
        .wrsp_error_i      ( midend_wrsp_error      ),
        .wrsp_valid_i      ( midend_wrsp_valid      ),
        .wrsp_ready_o      ( midend_wrsp_ready      ),
        .cmd_o             ( midend_cmd             ),
        .cmd_valid_o       ( midend_cmd_valid       ),
        .cmd_ready_i       ( midend_cmd_ready       )
    );

    hyperbus_backend #(
        .NumChips         ( NumChips          ),
        .NumPhys          ( NumPhys           ),
        .StartupCycles    ( PhyStartupCycles  ),
        .SyncStages       ( SyncStages        ),
        .hyper_rx_t       ( hyper_rx_t        ),
        .hyper_tx_t       ( hyper_tx_t        ),
        .hyper_cmd_t      ( hyper_cmd_t       )
    ) i_backend (
        .clk_i                  ( clk_backend           ),
        .clk_90_i               ( clk_backend_90        ),
        .rst_ni                 ( rst_backend_n         ),
        .test_mode_i            ( test_mode_i           ),
        .cfg_apply_i            ( backend_cfg_apply     ),
        .cfg_apply_valid_i      ( backend_cfg_apply_valid ),
        .cfg_apply_ready_o      ( backend_cfg_apply_ready ),
        .busy_o                 (                       ),
        .tx_clk_delay_o         ( backend_tx_clk_delay  ),
        .rx_o                   ( backend_rx            ),
        .rx_valid_o             ( backend_rx_valid      ),
        .rx_ready_i             ( backend_rx_ready      ),
        .tx_i                   ( backend_tx            ),
        .tx_valid_i             ( backend_tx_valid      ),
        .tx_ready_o             ( backend_tx_ready      ),
        .wrsp_error_o           ( backend_wrsp_error    ),
        .wrsp_valid_o           ( backend_wrsp_valid    ),
        .wrsp_ready_i           ( backend_wrsp_ready    ),
        .cmd_i                  ( backend_cmd           ),
        .cmd_valid_i            ( backend_cmd_valid     ),
        .cmd_ready_o            ( backend_cmd_ready     ),
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
