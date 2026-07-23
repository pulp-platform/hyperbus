// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

`include "common_cells/registers.svh"

module hyperbus_iso_bridge #(
    parameter int unsigned RxFifoLogDepth = 8,
    parameter int unsigned TxFifoLogDepth = 3,
    parameter type         hyper_rx_t     = logic,
    parameter type         hyper_tx_t     = logic,
    parameter type         hyper_wrsp_t   = logic,
    parameter type         hyper_cmd_t    = logic,
    parameter type         hyper_req_t    = logic,
    parameter type         hyper_rsp_t    = logic
) (
    input  logic                     clk_sys_i,
    input  logic                     rst_sys_ni,
    input  logic                     clk_phy_i,
    input  logic                     rst_phy_ni,

    input  hyperbus_pkg::phy_cfg_t   cfg_apply_i,
    input  logic                     frontend_cfg_apply_valid_i,
    output logic                     frontend_cfg_apply_ready_o,
    output logic                     frontend_cfg_apply_done_o,

    input  hyper_req_t               frontend_req_i,
    output hyper_rsp_t               frontend_rsp_o,
    output hyper_req_t               backend_req_o,
    input  hyper_rsp_t               backend_rsp_i,

    output hyperbus_pkg::phy_cfg_t   cfg_apply_o,
    output logic                     cfg_apply_valid_o,
    input  logic                     cfg_apply_ready_i
);

    hyperbus_pkg::phy_cfg_t      cfg_apply_data_q;
    logic                        cfg_apply_accepted;
    logic                        cfg_apply_pending_d;
    logic                        cfg_apply_pending_q;
    hyper_cmd_t                  cmd_data_q;
    logic                        cmd_accepted;
    hyper_wrsp_t                wrsp_data_q;
    logic                        wrsp_accepted;
    hyper_tx_t                   tx_fifo_data;
    logic                        tx_fifo_valid;
    logic                        tx_fifo_ready;
    hyper_rx_t                   rx_src_fifo_data;
    logic                        rx_src_fifo_valid;
    logic                        rx_src_fifo_ready;
    logic                        rx_iso_valid;
    logic                        rx_iso_ready;
    hyper_rx_t                   rx_iso_data;
    hyper_rx_t                   rx_fifo_data;
    logic                        rx_fifo_valid;
    logic                        rx_fifo_ready;

    assign cfg_apply_accepted = frontend_cfg_apply_valid_i && frontend_cfg_apply_ready_o;
    assign frontend_cfg_apply_done_o =
        cfg_apply_pending_q && frontend_cfg_apply_ready_o;
    assign cmd_accepted       = frontend_req_i.cmd_valid && frontend_rsp_o.cmd_ready;
    assign wrsp_accepted      = backend_rsp_i.wrsp_valid && backend_req_o.wrsp_ready;

    always_comb begin : proc_cfg_apply_pending
        cfg_apply_pending_d = cfg_apply_pending_q;

        if (cfg_apply_accepted) begin
            cfg_apply_pending_d = 1'b1;
        end else if (frontend_cfg_apply_done_o) begin
            cfg_apply_pending_d = 1'b0;
        end
    end

    `FFLARN(cfg_apply_data_q, cfg_apply_i, cfg_apply_accepted, '0, clk_sys_i, rst_sys_ni)
    `FFARN(cfg_apply_pending_q, cfg_apply_pending_d, 1'b0, clk_sys_i, rst_sys_ni)
    `FFLARN(cmd_data_q, frontend_req_i.cmd, cmd_accepted, '0, clk_sys_i, rst_sys_ni)
    `FFLARN(wrsp_data_q, backend_rsp_i.wrsp, wrsp_accepted, '0, clk_phy_i, rst_phy_ni)

    isochronous_4phase_handshake i_iso_cfg_apply (
        .src_clk_i   ( clk_sys_i                   ),
        .src_rst_ni  ( rst_sys_ni                  ),
        .src_valid_i ( frontend_cfg_apply_valid_i  ),
        .src_ready_o ( frontend_cfg_apply_ready_o  ),
        .dst_clk_i   ( clk_phy_i                   ),
        .dst_rst_ni  ( rst_phy_ni                  ),
        .dst_valid_o ( cfg_apply_valid_o           ),
        .dst_ready_i ( cfg_apply_ready_i           )
    );

    assign cfg_apply_o = cfg_apply_data_q;

    isochronous_4phase_handshake i_iso_cmd (
        .src_clk_i   ( clk_sys_i                ),
        .src_rst_ni  ( rst_sys_ni               ),
        .src_valid_i ( frontend_req_i.cmd_valid ),
        .src_ready_o ( frontend_rsp_o.cmd_ready ),
        .dst_clk_i   ( clk_phy_i                ),
        .dst_rst_ni  ( rst_phy_ni               ),
        .dst_valid_o ( backend_req_o.cmd_valid  ),
        .dst_ready_i ( backend_rsp_i.cmd_ready  )
    );

    assign backend_req_o.cmd = cmd_data_q;

    isochronous_4phase_handshake i_iso_wrsp (
        .src_clk_i   ( clk_phy_i                   ),
        .src_rst_ni  ( rst_phy_ni                  ),
        .src_valid_i ( backend_rsp_i.wrsp_valid    ),
        .src_ready_o ( backend_req_o.wrsp_ready    ),
        .dst_clk_i   ( clk_sys_i                   ),
        .dst_rst_ni  ( rst_sys_ni                  ),
        .dst_valid_o ( frontend_rsp_o.wrsp_valid   ),
        .dst_ready_i ( frontend_req_i.wrsp_ready   )
    );

    assign frontend_rsp_o.wrsp = wrsp_data_q;

    stream_fifo #(
        .FALL_THROUGH ( 1'b0                  ),
        .DEPTH        ( 1 << TxFifoLogDepth   ),
        .T            ( hyper_tx_t            )
    ) i_tx_fifo (
        .clk_i      ( clk_sys_i                ),
        .rst_ni     ( rst_sys_ni               ),
        .flush_i    ( 1'b0                     ),
        .testmode_i ( 1'b0                     ),
        .usage_o    (                          ),
        .data_i     ( frontend_req_i.tx          ),
        .valid_i    ( frontend_req_i.tx_valid    ),
        .ready_o    ( frontend_rsp_o.tx_ready    ),
        .data_o     ( tx_fifo_data             ),
        .valid_o    ( tx_fifo_valid            ),
        .ready_i    ( tx_fifo_ready            )
    );

    isochronous_spill_register #(
        .T ( hyper_tx_t )
    ) i_iso_tx (
        .src_clk_i   ( clk_sys_i              ),
        .src_rst_ni  ( rst_sys_ni             ),
        .src_valid_i ( tx_fifo_valid          ),
        .src_ready_o ( tx_fifo_ready          ),
        .src_data_i  ( tx_fifo_data           ),
        .dst_clk_i   ( clk_phy_i              ),
        .dst_rst_ni  ( rst_phy_ni             ),
        .dst_valid_o ( backend_req_o.tx_valid  ),
        .dst_ready_i ( backend_rsp_i.tx_ready  ),
        .dst_data_o  ( backend_req_o.tx        )
    );

    stream_fifo #(
        .FALL_THROUGH ( 1'b0                  ),
        .DEPTH        ( 1 << RxFifoLogDepth   ),
        .T            ( hyper_rx_t            )
    ) i_rx_src_fifo (
        .clk_i      ( clk_phy_i                ),
        .rst_ni     ( rst_phy_ni               ),
        .flush_i    ( 1'b0                     ),
        .testmode_i ( 1'b0                     ),
        .usage_o    (                          ),
        .data_i     ( backend_rsp_i.rx           ),
        .valid_i    ( backend_rsp_i.rx_valid     ),
        .ready_o    ( backend_req_o.rx_ready     ),
        .data_o     ( rx_src_fifo_data         ),
        .valid_o    ( rx_src_fifo_valid        ),
        .ready_i    ( rx_src_fifo_ready        )
    );

    isochronous_spill_register #(
        .T ( hyper_rx_t )
    ) i_iso_rx (
        .src_clk_i   ( clk_phy_i              ),
        .src_rst_ni  ( rst_phy_ni             ),
        .src_valid_i ( rx_src_fifo_valid      ),
        .src_ready_o ( rx_src_fifo_ready      ),
        .src_data_i  ( rx_src_fifo_data       ),
        .dst_clk_i   ( clk_sys_i              ),
        .dst_rst_ni  ( rst_sys_ni             ),
        .dst_valid_o ( rx_iso_valid           ),
        .dst_ready_i ( rx_iso_ready           ),
        .dst_data_o  ( rx_iso_data            )
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
        .usage_o    (                       ),
        .data_i     ( rx_iso_data           ),
        .valid_i    ( rx_iso_valid          ),
        .ready_o    ( rx_iso_ready          ),
        .data_o     ( rx_fifo_data          ),
        .valid_o    ( rx_fifo_valid         ),
        .ready_i    ( rx_fifo_ready         )
    );

    assign frontend_rsp_o.rx       = rx_fifo_data;
    assign frontend_rsp_o.rx_valid = rx_fifo_valid;
    assign rx_fifo_ready           = frontend_req_i.rx_ready;

endmodule
