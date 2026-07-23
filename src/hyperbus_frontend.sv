// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

module hyperbus_frontend #(
    parameter int unsigned  NumChips         = -1,
    parameter int unsigned  NumPhys          = 2,
    parameter int unsigned  AxiAddrWidth     = -1,
    parameter int unsigned  AxiDataWidth     = -1,
    parameter int unsigned  AxiIdWidth       = -1,
    parameter int unsigned  AxiUserWidth     = -1,
    parameter type          axi_req_t        = logic,
    parameter type          axi_rsp_t        = logic,
    parameter type          reg_req_t        = logic,
    parameter type          reg_rsp_t        = logic,
    parameter type          axi_rule_t       = logic,
    parameter type          hyper_rx_t       = logic,
    parameter type          hyper_tx_t       = logic,
    parameter type          tf_cdc_t         = logic,
    parameter int unsigned  RegAddrWidth     = -1,
    parameter int unsigned  RegDataWidth     = -1,
    parameter logic [RegDataWidth-1:0]  RstChipBase  = 'h0,
    parameter logic [RegDataWidth-1:0]  RstChipSpace = 'h1_0000,
    parameter hyperbus_pkg::hyper_cfg_t RstCfg       = '0
) (
    input  logic                       clk_i,
    input  logic                       rst_ni,

    input  axi_req_t                   axi_req_i,
    output axi_rsp_t                   axi_rsp_o,

    input  reg_req_t                   reg_req_i,
    output reg_rsp_t                   reg_rsp_o,

    output hyperbus_pkg::hyper_cfg_t   cfg_o,
    output hyperbus_pkg::hyper_cfg_t   cfg_apply_o,
    output logic                       cfg_apply_valid_o,
    input  logic                       cfg_apply_ready_i,

    input  hyper_rx_t                  rx_i,
    input  logic                       rx_valid_i,
    output logic                       rx_ready_o,
    output hyper_tx_t                  tx_o,
    output logic                       tx_valid_o,
    input  logic                       tx_ready_i,
    input  logic                       b_error_i,
    input  logic                       b_valid_i,
    output logic                       b_ready_o,
    output tf_cdc_t                    trans_o,
    output logic                       trans_valid_o,
    input  logic                       trans_ready_i
);

    typedef enum logic [1:0] {
        CfgIdle,
        CfgSend,
        CfgWaitAck
    } cfg_state_e;

    axi_rule_t [NumChips-1:0] chip_rules;
    logic                     trans_active;
    logic                     axi_trans_valid;
    logic                     axi_trans_ready;
    cfg_state_e               cfg_state_d, cfg_state_q;
    hyperbus_pkg::hyper_cfg_t cfg_applied_d, cfg_applied_q;
    hyperbus_pkg::hyper_cfg_t cfg_pending_d, cfg_pending_q;
    logic                     cfg_changed;
    logic                     cfg_apply_busy;

    assign cfg_changed       = cfg_o != cfg_applied_q;
    assign cfg_apply_busy    = (cfg_state_q != CfgIdle) | cfg_changed;
    assign cfg_apply_valid_o = cfg_state_q == CfgSend;
    assign cfg_apply_o       = cfg_pending_q;

    always_comb begin
        cfg_state_d   = cfg_state_q;
        cfg_applied_d = cfg_applied_q;
        cfg_pending_d = cfg_pending_q;

        unique case (cfg_state_q)
            CfgIdle: begin
                if (cfg_changed) begin
                    cfg_pending_d = cfg_o;
                    cfg_state_d   = CfgSend;
                end
            end
            CfgSend: begin
                if (cfg_apply_ready_i) begin
                    cfg_state_d = CfgWaitAck;
                end
            end
            CfgWaitAck: begin
                if (cfg_apply_ready_i) begin
                    cfg_applied_d = cfg_pending_q;
                    cfg_state_d   = CfgIdle;
                end
            end
            default: cfg_state_d = CfgIdle;
        endcase
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            cfg_state_q   <= CfgIdle;
            cfg_applied_q <= RstCfg;
            cfg_pending_q <= RstCfg;
        end else begin
            cfg_state_q   <= cfg_state_d;
            cfg_applied_q <= cfg_applied_d;
            cfg_pending_q <= cfg_pending_d;
        end
    end

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
        .clk_i          ( clk_i         ),
        .rst_ni         ( rst_ni        ),
        .reg_req_i      ( reg_req_i     ),
        .reg_rsp_o      ( reg_rsp_o     ),
        .cfg_o          ( cfg_o         ),
        .chip_rules_o   ( chip_rules    ),
        .trans_active_i ( trans_active  )
    );

    hyperbus_axi #(
        .AxiDataWidth   ( AxiDataWidth  ),
        .AxiAddrWidth   ( AxiAddrWidth  ),
        .AxiIdWidth     ( AxiIdWidth    ),
        .AxiUserWidth   ( AxiUserWidth  ),
        .axi_req_t      ( axi_req_t     ),
        .axi_rsp_t      ( axi_rsp_t     ),
        .NumChips       ( NumChips      ),
        .NumPhys        ( NumPhys       ),
        .hyper_rx_t     ( hyper_rx_t    ),
        .hyper_tx_t     ( hyper_tx_t    ),
        .rule_t         ( axi_rule_t    )
    ) i_axi_slave (
        .clk_i           ( clk_i                ),
        .rst_ni          ( rst_ni               ),
        .axi_req_i       ( axi_req_i            ),
        .axi_rsp_o       ( axi_rsp_o            ),
        .rx_i            ( rx_i                 ),
        .rx_valid_i      ( rx_valid_i           ),
        .rx_ready_o      ( rx_ready_o           ),
        .tx_o            ( tx_o                 ),
        .tx_valid_o      ( tx_valid_o           ),
        .tx_ready_i      ( tx_ready_i           ),
        .b_error_i       ( b_error_i            ),
        .b_valid_i       ( b_valid_i            ),
        .b_ready_o       ( b_ready_o            ),
        .trans_o         ( trans_o.trans        ),
        .trans_cs_o      ( trans_o.cs           ),
        .trans_valid_o   ( axi_trans_valid      ),
        .trans_ready_i   ( axi_trans_ready      ),
        .chip_rules_i    ( chip_rules           ),
        .which_phy_i     ( cfg_o.which_phy      ),
        .phys_in_use_i   ( cfg_o.phys_in_use    ),
        .addr_mask_msb_i ( cfg_o.address_mask_msb ),
        .addr_space_i    ( cfg_o.address_space  ),
        .trans_active_o  ( trans_active         )
    );

    assign trans_valid_o  = axi_trans_valid & ~cfg_apply_busy;
    assign axi_trans_ready = trans_ready_i & ~cfg_apply_busy;

endmodule
