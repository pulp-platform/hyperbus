// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Thomas Benz <paulsc@iis.ee.ethz.ch>
// Paul Scheffler <paulsc@iis.ee.ethz.ch>
// Luca Valente <luca.valente@unibo.it>

module hyperbus #(
    parameter int unsigned  NumChips         = -1,
    parameter int unsigned  NumPhys          = 2,
    parameter bit           UsePhyClkDivider = 1,
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
    parameter int unsigned  MinFreqMHz      = 100,
    parameter type          reg_req_t        = logic,
    parameter type          reg_rsp_t        = logic,
    parameter type          axi_rule_t       = logic,
    // The below have sensible defaults, but should be set on integration!
    parameter int unsigned  RxFifoLogDepth   = 3,
    parameter int unsigned  TxFifoLogDepth   = 3,
    parameter logic [RegDataWidth-1:0]  RstChipBase  = 'h0,      // Base address for all chips
    parameter logic [RegDataWidth-1:0]  RstChipSpace = 'h1_0000, // 64 KiB: Current maximum HyperBus device size
    parameter hyperbus_pkg::hyper_cfg_t RstCfg       = hyperbus_pkg::gen_RstCfg(NumPhys,MinFreqMHz),
    parameter int unsigned  PhyStartupCycles = 300 * 200, /* us*MHz */ // Conservative maximum frequency estimate
    parameter int unsigned  SyncStages  = 2
) (
    input  logic                        clk_phy_x2_i,
`ifdef TARGET_XILINX
    input  logic                        clk_ref200_i, // only used for Xilinx delay lines
`endif
    input  logic                        clk_phy_i,
    input  logic                        rst_ni,
    input  logic                        ph_phy_i,
    input  logic                        test_mode_i,
    // AXI bus
    input  axi_req_t                    axi_req_i,
    output axi_rsp_t                    axi_rsp_o,
    // Reg bus
    input  reg_req_t                    reg_req_i,
    output reg_rsp_t                    reg_rsp_o,
    // Physical interace: facing HyperBus PADs
    output logic [NumPhys-1:0][NumChips-1:0] hyper_cs_no,
    output logic [NumPhys-1:0]               hyper_ck_o,
    output logic [NumPhys-1:0]               hyper_ck_no,
    output logic [NumPhys-1:0]               hyper_rwds_o,
    input  logic [NumPhys-1:0]               hyper_rwds_i,
    output logic [NumPhys-1:0]               hyper_rwds_oe_o,
    input  logic [NumPhys-1:0][7:0]          hyper_dq_i,
    output logic [NumPhys-1:0][7:0]          hyper_dq_o,
    output logic [NumPhys-1:0][7:0]          hyper_dq_oe_o,
    output logic [NumPhys-1:0]               hyper_reset_no,
    output logic [NumPhys-1:0][7:0]          hyper_pad_cfg_o
);

   typedef struct packed {
        logic [(16*NumPhys)-1:0]    data;
        logic                       last;
        logic [(2*NumPhys)-1:0]     strb;   // mask data
    } hyper_tx_t;

    typedef struct packed {
        logic [(16*NumPhys)-1:0]    data;
        logic                       last;
        logic                       error;
    } hyper_rx_t;

    // Combined transfer type for CDC
    typedef struct packed {
        hyperbus_pkg::hyper_tf_t    trans;
        logic [NumChips-1:0]        cs;
    } tf_cdc_t;

    // Register file
    hyperbus_pkg::hyper_cfg_t   cfg;
    axi_rule_t [NumChips-1:0]   chip_rules;
    logic                       trans_active;

    // AXI slave
    hyper_rx_t                  axi_rx;
    logic                       axi_rx_valid;
    logic                       axi_rx_ready;
    hyper_tx_t                  axi_tx;
    logic                       axi_tx_valid;
    logic                       axi_tx_ready;
    logic                       axi_b_error;
    logic                       axi_b_valid;
    logic                       axi_b_ready;
    tf_cdc_t                    axi_tf_cdc;
    logic                       axi_trans_valid;
    logic                       axi_trans_ready;

    // PHY
    hyper_rx_t                  phy_rx;
    logic                       phy_rx_valid;
    logic                       phy_rx_ready;
    hyper_tx_t                  phy_tx;
    logic                       phy_tx_valid;
    logic                       phy_tx_ready;
    logic                       phy_b_error;
    logic                       phy_b_valid;
    logic                       phy_b_ready;
    tf_cdc_t                    phy_tf_cdc;
    logic                       phy_trans_valid;
    logic                       phy_trans_ready;

    // Config register File
    hyperbus_cfg_regs #(
        .NumChips       ( NumChips      ),
        .NumPhys        ( NumPhys       ),
        .RegAddrWidth   ( RegAddrWidth  ),
        .RegDataWidth   ( RegDataWidth  ),
        .reg_req_t      ( reg_req_t     ),
        .reg_rsp_t      ( reg_rsp_t     ),
        .rule_t         ( axi_rule_t    ),
        .RstChipBase    ( RstChipBase   ),
        .RstChipSpace   ( RstChipSpace  ),
        .RstCfg         ( RstCfg        )
    ) i_cfg_regs (
        .clk_i          ( clk_phy_i     ),
        .rst_ni         ( rst_ni        ),
        .reg_req_i      ( reg_req_i     ),
        .reg_rsp_o      ( reg_rsp_o     ),
        .cfg_o          ( cfg           ),
        .chip_rules_o   ( chip_rules    ),
        .trans_active_i ( trans_active  )
    );

    // AXI slave interfacing PHY
    hyperbus_axi #(
        .AxiDataWidth   ( AxiDataWidth      ),
        .AxiAddrWidth   ( AxiAddrWidth      ),
        .AxiIdWidth     ( AxiIdWidth        ),
        .AxiUserWidth   ( AxiUserWidth      ),
        .axi_req_t      ( axi_req_t         ),
        .axi_rsp_t      ( axi_rsp_t         ),
        .NumChips       ( NumChips          ),
        .NumPhys        ( NumPhys           ),
        .hyper_rx_t     ( hyper_rx_t        ),
        .hyper_tx_t     ( hyper_tx_t        ),
        .rule_t         ( axi_rule_t        )
    ) i_axi_slave (
        .clk_i           ( clk_phy_i           ),
        .rst_ni          ( rst_ni              ),

        .axi_req_i       ( axi_req_i            ),
        .axi_rsp_o       ( axi_rsp_o            ),

        .rx_i            ( axi_rx               ),
        .rx_valid_i      ( axi_rx_valid         ),
        .rx_ready_o      ( axi_rx_ready         ),
        .tx_o            ( axi_tx               ),
        .tx_valid_o      ( axi_tx_valid         ),
        .tx_ready_i      ( axi_tx_ready         ),
        .b_error_i       ( axi_b_error          ),
        .b_valid_i       ( axi_b_valid          ),
        .b_ready_o       ( axi_b_ready          ),
        .trans_o         ( axi_tf_cdc.trans     ),
        .trans_cs_o      ( axi_tf_cdc.cs        ),
        .trans_valid_o   ( axi_trans_valid      ),
        .trans_ready_i   ( axi_trans_ready      ),

        .chip_rules_i    ( chip_rules           ),
        .which_phy_i     ( cfg.which_phy        ),
        .phys_in_use_i   ( cfg.phys_in_use      ),
        .addr_mask_msb_i ( cfg.address_mask_msb ),
        .addr_space_i    ( cfg.address_space    ),
        .trans_active_o  ( trans_active         )
    );

    hyperbus_phy_if #(
        .UsePhyClkDivider    ( UsePhyClkDivider    ),
        .NumChips            ( NumChips            ),
        .NumPhys             ( NumPhys             ),
        .StartupCycles       ( PhyStartupCycles    ),
        .hyper_rx_t          ( hyper_rx_t          ),
        .hyper_tx_t          ( hyper_tx_t          ),
        .SyncStages          ( SyncStages          )
    ) i_phy (
        .clk_phy_x2_i   ( clk_phy_x2_i      ),
        .clk_phy_i      ( clk_phy_i         ),
`ifdef TARGET_XILINX
        .clk_ref200_i   ( clk_ref200_i      ),
`endif
        .rst_ni         ( rst_ni            ),
        .ph_phy_i       ( ph_phy_i          ),
        .test_mode_i    ( test_mode_i       ),

        .cfg_i          ( cfg               ),

        .rx_o           ( phy_rx            ),
        .rx_valid_o     ( phy_rx_valid      ),
        .rx_ready_i     ( phy_rx_ready      ),
        .tx_i           ( phy_tx            ),
        .tx_valid_i     ( phy_tx_valid      ),
        .tx_ready_o     ( phy_tx_ready      ),
        .b_error_o      ( phy_b_error       ),
        .b_valid_o      ( phy_b_valid       ),
        .b_ready_i      ( phy_b_ready       ),
        .trans_i        ( phy_tf_cdc.trans  ),
        .trans_cs_i     ( phy_tf_cdc.cs     ),
        .trans_valid_i  ( phy_trans_valid   ),
        .trans_ready_o  ( phy_trans_ready   ),

        .hyper_cs_no    ( hyper_cs_no       ),
        .hyper_ck_o     ( hyper_ck_o        ),
        .hyper_ck_no    ( hyper_ck_no       ),
        .hyper_rwds_o   ( hyper_rwds_o      ),
        .hyper_rwds_i   ( hyper_rwds_i      ),
        .hyper_rwds_oe_o( hyper_rwds_oe_o   ),
        .hyper_dq_i     ( hyper_dq_i        ),
        .hyper_dq_o     ( hyper_dq_o        ),
        .hyper_dq_oe_o  ( hyper_dq_oe_o     ),
        .hyper_reset_no ( hyper_reset_no    )
    );

    assign phy_tf_cdc = axi_tf_cdc;
    assign phy_trans_valid = axi_trans_valid;
    assign axi_trans_ready = phy_trans_ready;

    assign axi_b_error = phy_b_error;
    assign axi_b_valid = phy_b_valid;
    assign phy_b_ready = axi_b_ready;

    assign phy_tx = axi_tx;
    assign phy_tx_valid = axi_tx_valid;
    assign axi_tx_ready = phy_tx_ready;

    assign axi_rx = phy_rx;
    assign axi_rx_valid = phy_rx_valid;
    assign phy_rx_ready = axi_rx_ready;


    // PAD configuration
    for (genvar i = 0; i < NumPhys; i++)
      assign hyper_pad_cfg_o[i] = cfg.t_pad_cfg[8*i +: 8];
endmodule : hyperbus
