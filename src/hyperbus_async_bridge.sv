// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

module hyperbus_async_bridge #(
    parameter int unsigned RxFifoLogDepth = 3,
    parameter int unsigned TxFifoLogDepth = 3,
    parameter type         hyper_rx_t     = logic,
    parameter type         hyper_tx_t     = logic,
    parameter type         tf_cdc_t       = logic,
    parameter hyperbus_pkg::hyper_cfg_t RstCfg = '0
) (
    input  logic                     clk_sys_i,
    input  logic                     rst_sys_ni,
    input  logic                     clk_phy_i,
    input  logic                     rst_phy_ni,

    input  hyperbus_pkg::hyper_cfg_t cfg_i,
    output logic                     cfg_apply_busy_o,

    output hyper_rx_t                frontend_rx_o,
    output logic                     frontend_rx_valid_o,
    input  logic                     frontend_rx_ready_i,
    input  hyper_tx_t                frontend_tx_i,
    input  logic                     frontend_tx_valid_i,
    output logic                     frontend_tx_ready_o,
    output logic                     frontend_b_error_o,
    output logic                     frontend_b_valid_o,
    input  logic                     frontend_b_ready_i,
    input  tf_cdc_t                  frontend_trans_i,
    input  logic                     frontend_trans_valid_i,
    output logic                     frontend_trans_ready_o,

    input  hyper_rx_t                backend_rx_i,
    input  logic                     backend_rx_valid_i,
    output logic                     backend_rx_ready_o,
    output hyper_tx_t                backend_tx_o,
    output logic                     backend_tx_valid_o,
    input  logic                     backend_tx_ready_i,
    input  logic                     backend_b_error_i,
    input  logic                     backend_b_valid_i,
    output logic                     backend_b_ready_o,
    output tf_cdc_t                  backend_trans_o,
    output logic                     backend_trans_valid_o,
    input  logic                     backend_trans_ready_i,

    output hyperbus_pkg::hyper_cfg_t cfg_apply_o,
    output logic                     cfg_apply_valid_o,
    input  logic                     cfg_apply_ready_i
);

    typedef enum logic [1:0] {
        CfgIdle,
        CfgSend,
        CfgWaitAck
    } cfg_state_e;

    cfg_state_e                  cfg_state_d, cfg_state_q;
    hyperbus_pkg::hyper_cfg_t    cfg_applied_d, cfg_applied_q;
    hyperbus_pkg::hyper_cfg_t    cfg_pending_d, cfg_pending_q;
    logic                        cfg_src_valid;
    logic                        cfg_src_ready;
    logic                        cfg_changed;

    assign cfg_changed      = cfg_i != cfg_applied_q;
    assign cfg_src_valid    = cfg_state_q == CfgSend;
    assign cfg_apply_busy_o = (cfg_state_q != CfgIdle) | cfg_changed;

    always_comb begin
        cfg_state_d   = cfg_state_q;
        cfg_applied_d = cfg_applied_q;
        cfg_pending_d = cfg_pending_q;

        unique case (cfg_state_q)
            CfgIdle: begin
                if (cfg_changed) begin
                    cfg_pending_d = cfg_i;
                    cfg_state_d   = CfgSend;
                end
            end
            CfgSend: begin
                if (cfg_src_ready) begin
                    cfg_state_d = CfgWaitAck;
                end
            end
            CfgWaitAck: begin
                if (cfg_src_ready) begin
                    cfg_applied_d = cfg_pending_q;
                    cfg_state_d   = CfgIdle;
                end
            end
            default: cfg_state_d = CfgIdle;
        endcase
    end

    always_ff @(posedge clk_sys_i or negedge rst_sys_ni) begin
        if (!rst_sys_ni) begin
            cfg_state_q   <= CfgIdle;
            cfg_applied_q <= RstCfg;
            cfg_pending_q <= RstCfg;
        end else begin
            cfg_state_q   <= cfg_state_d;
            cfg_applied_q <= cfg_applied_d;
            cfg_pending_q <= cfg_pending_d;
        end
    end

    cdc_2phase #(
        .T ( hyperbus_pkg::hyper_cfg_t )
    ) i_cdc_2phase_cfg (
        .src_rst_ni   ( rst_sys_ni        ),
        .src_clk_i    ( clk_sys_i         ),
        .src_data_i   ( cfg_pending_q     ),
        .src_valid_i  ( cfg_src_valid     ),
        .src_ready_o  ( cfg_src_ready     ),
        .dst_rst_ni   ( rst_phy_ni        ),
        .dst_clk_i    ( clk_phy_i         ),
        .dst_data_o   ( cfg_apply_o       ),
        .dst_valid_o  ( cfg_apply_valid_o ),
        .dst_ready_i  ( cfg_apply_ready_i )
    );

    cdc_2phase #(
        .T ( tf_cdc_t )
    ) i_cdc_2phase_trans (
        .src_rst_ni     ( rst_sys_ni               ),
        .src_clk_i      ( clk_sys_i                ),
        .src_data_i     ( frontend_trans_i         ),
        .src_valid_i    ( frontend_trans_valid_i   ),
        .src_ready_o    ( frontend_trans_ready_o   ),
        .dst_rst_ni     ( rst_phy_ni               ),
        .dst_clk_i      ( clk_phy_i                ),
        .dst_data_o     ( backend_trans_o          ),
        .dst_valid_o    ( backend_trans_valid_o    ),
        .dst_ready_i    ( backend_trans_ready_i    )
    );

    cdc_2phase #(
        .T ( logic )
    ) i_cdc_2phase_b (
        .src_rst_ni     ( rst_phy_ni             ),
        .src_clk_i      ( clk_phy_i              ),
        .src_data_i     ( backend_b_error_i      ),
        .src_valid_i    ( backend_b_valid_i      ),
        .src_ready_o    ( backend_b_ready_o      ),
        .dst_rst_ni     ( rst_sys_ni             ),
        .dst_clk_i      ( clk_sys_i              ),
        .dst_data_o     ( frontend_b_error_o     ),
        .dst_valid_o    ( frontend_b_valid_o     ),
        .dst_ready_i    ( frontend_b_ready_i     )
    );

    cdc_fifo_gray #(
        .T         ( hyper_tx_t     ),
        .LOG_DEPTH ( TxFifoLogDepth )
    ) i_cdc_fifo_tx (
        .src_rst_ni     ( rst_sys_ni              ),
        .src_clk_i      ( clk_sys_i               ),
        .src_data_i     ( frontend_tx_i           ),
        .src_valid_i    ( frontend_tx_valid_i     ),
        .src_ready_o    ( frontend_tx_ready_o     ),
        .dst_rst_ni     ( rst_phy_ni              ),
        .dst_clk_i      ( clk_phy_i               ),
        .dst_data_o     ( backend_tx_o            ),
        .dst_valid_o    ( backend_tx_valid_o      ),
        .dst_ready_i    ( backend_tx_ready_i      )
    );

    cdc_fifo_gray #(
        .T         ( hyper_rx_t     ),
        .LOG_DEPTH ( RxFifoLogDepth )
    ) i_cdc_fifo_rx (
        .src_rst_ni     ( rst_phy_ni              ),
        .src_clk_i      ( clk_phy_i               ),
        .src_data_i     ( backend_rx_i            ),
        .src_valid_i    ( backend_rx_valid_i      ),
        .src_ready_o    ( backend_rx_ready_o      ),
        .dst_rst_ni     ( rst_sys_ni              ),
        .dst_clk_i      ( clk_sys_i               ),
        .dst_data_o     ( frontend_rx_o           ),
        .dst_valid_o    ( frontend_rx_valid_o     ),
        .dst_ready_i    ( frontend_rx_ready_i     )
    );

endmodule
