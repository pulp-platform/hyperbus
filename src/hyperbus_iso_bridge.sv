// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

module hyperbus_iso_bridge #(
    parameter int unsigned RxFifoLogDepth = 8,
    parameter int unsigned TxFifoLogDepth = 3,
    parameter type hyper_rx_t = logic,
    parameter type hyper_tx_t = logic,
    parameter type tf_cdc_t   = logic,
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
    hyperbus_pkg::hyper_cfg_t    cfg_apply_data_q;
    logic                        cfg_apply_src_fire;
    tf_cdc_t                     trans_data_q;
    logic                        trans_src_fire;
    logic                        b_error_q;
    logic                        b_src_fire;
    hyper_tx_t                   tx_fifo_data;
    logic                        tx_fifo_valid;
    logic                        tx_fifo_ready;
    logic [TxFifoLogDepth-1:0]   tx_fifo_usage;
    hyper_tx_t                   tx_data_q;
    logic                        tx_src_fire;
    hyper_rx_t                   rx_src_fifo_data;
    logic                        rx_src_fifo_valid;
    logic                        rx_src_fifo_ready;
    logic [RxFifoLogDepth-1:0]   rx_src_fifo_usage;
    hyper_rx_t                   rx_data_q;
    logic                        rx_iso_valid;
    logic                        rx_iso_ready;
    logic                        rx_src_fire;
    hyper_rx_t                   rx_fifo_data;
    logic                        rx_fifo_valid;
    logic                        rx_fifo_ready;
    logic [RxFifoLogDepth-1:0]   rx_fifo_usage;

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

    assign cfg_apply_src_fire = cfg_src_valid & cfg_src_ready;
    assign trans_src_fire     = frontend_trans_valid_i & frontend_trans_ready_o;
    assign tx_src_fire        = tx_fifo_valid & tx_fifo_ready;
    assign rx_src_fire        = rx_src_fifo_valid & rx_src_fifo_ready;
    assign b_src_fire         = backend_b_valid_i & backend_b_ready_o;

    always_ff @(posedge clk_sys_i or negedge rst_sys_ni) begin
        if (!rst_sys_ni) begin
            cfg_apply_data_q <= RstCfg;
            trans_data_q     <= '0;
            tx_data_q        <= '0;
        end else begin
            if (cfg_apply_src_fire) cfg_apply_data_q <= cfg_pending_q;
            if (trans_src_fire)     trans_data_q     <= frontend_trans_i;
            if (tx_src_fire)        tx_data_q        <= tx_fifo_data;
        end
    end

    always_ff @(posedge clk_phy_i or negedge rst_phy_ni) begin
        if (!rst_phy_ni) begin
            b_error_q  <= 1'b0;
            rx_data_q  <= '0;
        end else begin
            if (b_src_fire)  b_error_q <= backend_b_error_i;
            if (rx_src_fire) rx_data_q <= rx_src_fifo_data;
        end
    end

    isochronous_4phase_handshake i_iso_cfg_apply (
        .src_clk_i   ( clk_sys_i           ),
        .src_rst_ni  ( rst_sys_ni          ),
        .src_valid_i ( cfg_src_valid       ),
        .src_ready_o ( cfg_src_ready       ),
        .dst_clk_i   ( clk_phy_i           ),
        .dst_rst_ni  ( rst_phy_ni          ),
        .dst_valid_o ( cfg_apply_valid_o   ),
        .dst_ready_i ( cfg_apply_ready_i   )
    );

    assign cfg_apply_o = cfg_apply_data_q;

    isochronous_4phase_handshake i_iso_trans (
        .src_clk_i   ( clk_sys_i                ),
        .src_rst_ni  ( rst_sys_ni               ),
        .src_valid_i ( frontend_trans_valid_i   ),
        .src_ready_o ( frontend_trans_ready_o   ),
        .dst_clk_i   ( clk_phy_i                ),
        .dst_rst_ni  ( rst_phy_ni               ),
        .dst_valid_o ( backend_trans_valid_o    ),
        .dst_ready_i ( backend_trans_ready_i    )
    );

    assign backend_trans_o = trans_data_q;

    isochronous_4phase_handshake i_iso_b (
        .src_clk_i   ( clk_phy_i             ),
        .src_rst_ni  ( rst_phy_ni            ),
        .src_valid_i ( backend_b_valid_i     ),
        .src_ready_o ( backend_b_ready_o     ),
        .dst_clk_i   ( clk_sys_i             ),
        .dst_rst_ni  ( rst_sys_ni            ),
        .dst_valid_o ( frontend_b_valid_o    ),
        .dst_ready_i ( frontend_b_ready_i    )
    );

    assign frontend_b_error_o = b_error_q;

    stream_fifo #(
        .FALL_THROUGH ( 1'b0                  ),
        .DEPTH        ( 1 << TxFifoLogDepth   ),
        .T            ( hyper_tx_t            )
    ) i_tx_fifo (
        .clk_i      ( clk_sys_i             ),
        .rst_ni     ( rst_sys_ni            ),
        .flush_i    ( 1'b0                  ),
        .testmode_i ( 1'b0                  ),
        .usage_o    ( tx_fifo_usage         ),
        .data_i     ( frontend_tx_i         ),
        .valid_i    ( frontend_tx_valid_i   ),
        .ready_o    ( frontend_tx_ready_o   ),
        .data_o     ( tx_fifo_data          ),
        .valid_o    ( tx_fifo_valid         ),
        .ready_i    ( tx_fifo_ready         )
    );

    isochronous_4phase_handshake i_iso_tx (
        .src_clk_i   ( clk_sys_i              ),
        .src_rst_ni  ( rst_sys_ni             ),
        .src_valid_i ( tx_fifo_valid          ),
        .src_ready_o ( tx_fifo_ready          ),
        .dst_clk_i   ( clk_phy_i              ),
        .dst_rst_ni  ( rst_phy_ni             ),
        .dst_valid_o ( backend_tx_valid_o     ),
        .dst_ready_i ( backend_tx_ready_i     )
    );

    assign backend_tx_o = tx_data_q;

    stream_fifo #(
        .FALL_THROUGH ( 1'b0                  ),
        .DEPTH        ( 1 << RxFifoLogDepth   ),
        .T            ( hyper_rx_t            )
    ) i_rx_src_fifo (
        .clk_i      ( clk_phy_i             ),
        .rst_ni     ( rst_phy_ni            ),
        .flush_i    ( 1'b0                  ),
        .testmode_i ( 1'b0                  ),
        .usage_o    ( rx_src_fifo_usage     ),
        .data_i     ( backend_rx_i          ),
        .valid_i    ( backend_rx_valid_i    ),
        .ready_o    ( backend_rx_ready_o    ),
        .data_o     ( rx_src_fifo_data      ),
        .valid_o    ( rx_src_fifo_valid     ),
        .ready_i    ( rx_src_fifo_ready     )
    );

    isochronous_4phase_handshake i_iso_rx (
        .src_clk_i   ( clk_phy_i              ),
        .src_rst_ni  ( rst_phy_ni             ),
        .src_valid_i ( rx_src_fifo_valid      ),
        .src_ready_o ( rx_src_fifo_ready      ),
        .dst_clk_i   ( clk_sys_i              ),
        .dst_rst_ni  ( rst_sys_ni             ),
        .dst_valid_o ( rx_iso_valid           ),
        .dst_ready_i ( rx_iso_ready           )
    );

    stream_fifo #(
        .FALL_THROUGH ( 1'b0                  ),
        .DEPTH        ( 1 << RxFifoLogDepth   ),
        .T            ( hyper_rx_t            )
    ) i_rx_fifo (
        .clk_i      ( clk_sys_i             ),
        .rst_ni     ( rst_sys_ni            ),
        .flush_i    ( 1'b0                  ),
        .testmode_i ( 1'b0                  ),
        .usage_o    ( rx_fifo_usage         ),
        .data_i     ( rx_data_q             ),
        .valid_i    ( rx_iso_valid          ),
        .ready_o    ( rx_iso_ready          ),
        .data_o     ( rx_fifo_data          ),
        .valid_o    ( rx_fifo_valid         ),
        .ready_i    ( rx_fifo_ready         )
    );

    assign frontend_rx_o       = rx_fifo_data;
    assign frontend_rx_valid_o = rx_fifo_valid;
    assign rx_fifo_ready       = frontend_rx_ready_i;

endmodule
