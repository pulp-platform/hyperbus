// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

`include "common_cells/assertions.svh"
`include "common_cells/registers.svh"

module hyperbus_async_bridge #(
    parameter int unsigned RxFifoLogDepth = 3,
    parameter int unsigned TxFifoLogDepth = 3,
    parameter int unsigned CdcSyncStages  = 3,
    parameter type         hyper_rx_t     = logic,
    parameter type         hyper_tx_t     = logic,
    parameter type         hyper_cmd_t    = logic
) (
    input  logic                     clk_sys_i,
    input  logic                     rst_sys_ni,
    input  logic                     clk_phy_i,
    input  logic                     rst_phy_ni,

    input  hyperbus_pkg::phy_cfg_t   cfg_apply_i,
    input  logic                     frontend_cfg_apply_valid_i,
    output logic                     frontend_cfg_apply_ready_o,
    output logic                     frontend_cfg_apply_done_o,

    output hyper_rx_t                frontend_rx_o,
    output logic                     frontend_rx_valid_o,
    input  logic                     frontend_rx_ready_i,
    input  hyper_tx_t                frontend_tx_i,
    input  logic                     frontend_tx_valid_i,
    output logic                     frontend_tx_ready_o,
    output logic                     frontend_wrsp_error_o,
    output logic                     frontend_wrsp_valid_o,
    input  logic                     frontend_wrsp_ready_i,
    input  hyper_cmd_t               frontend_cmd_i,
    input  logic                     frontend_cmd_valid_i,
    output logic                     frontend_cmd_ready_o,

    input  hyper_rx_t                backend_rx_i,
    input  logic                     backend_rx_valid_i,
    output logic                     backend_rx_ready_o,
    output hyper_tx_t                backend_tx_o,
    output logic                     backend_tx_valid_o,
    input  logic                     backend_tx_ready_i,
    input  logic                     backend_wrsp_error_i,
    input  logic                     backend_wrsp_valid_i,
    output logic                     backend_wrsp_ready_o,
    output hyper_cmd_t               backend_cmd_o,
    output logic                     backend_cmd_valid_o,
    input  logic                     backend_cmd_ready_i,

    output hyperbus_pkg::phy_cfg_t   cfg_apply_o,
    output logic                     cfg_apply_valid_o,
    input  logic                     cfg_apply_ready_i
);

    logic cfg_apply_src_fire;
    logic cfg_apply_pending_d, cfg_apply_pending_q;

    `ASSERT_INIT(CdcSyncStagesValid, CdcSyncStages >= 3)
    // Preserve FIFO elasticity beyond the round-trip pointer synchronization latency.
    `ASSERT_INIT(TxCdcFifoDepthValid, (1 << TxFifoLogDepth) > (2 * CdcSyncStages))
    `ASSERT_INIT(RxCdcFifoDepthValid, (1 << RxFifoLogDepth) > (2 * CdcSyncStages))

    assign cfg_apply_src_fire =
        frontend_cfg_apply_valid_i && frontend_cfg_apply_ready_o;
    assign frontend_cfg_apply_done_o =
        cfg_apply_pending_q && frontend_cfg_apply_ready_o;

    always_comb begin
        cfg_apply_pending_d = cfg_apply_pending_q;

        if (cfg_apply_src_fire) begin
            cfg_apply_pending_d = 1'b1;
        end else if (frontend_cfg_apply_done_o) begin
            cfg_apply_pending_d = 1'b0;
        end
    end

    `FFARN(cfg_apply_pending_q, cfg_apply_pending_d, 1'b0, clk_sys_i, rst_sys_ni)

    cdc_2phase_clearable #(
        .T           ( hyperbus_pkg::phy_cfg_t ),
        .SYNC_STAGES ( CdcSyncStages           )
    ) i_cdc_cfg (
        .src_rst_ni           ( rst_sys_ni                   ),
        .src_clk_i            ( clk_sys_i                    ),
        .src_clear_i          ( 1'b0                         ),
        .src_clear_pending_o  (                              ),
        .src_data_i           ( cfg_apply_i                  ),
        .src_valid_i          ( frontend_cfg_apply_valid_i   ),
        .src_ready_o          ( frontend_cfg_apply_ready_o   ),
        .dst_rst_ni           ( rst_phy_ni                   ),
        .dst_clk_i            ( clk_phy_i                    ),
        .dst_clear_i          ( 1'b0                         ),
        .dst_clear_pending_o  (                              ),
        .dst_data_o           ( cfg_apply_o                  ),
        .dst_valid_o          ( cfg_apply_valid_o            ),
        .dst_ready_i          ( cfg_apply_ready_i            )
    );

    cdc_2phase_clearable #(
        .T           ( hyper_cmd_t  ),
        .SYNC_STAGES ( CdcSyncStages )
    ) i_cdc_cmd (
        .src_rst_ni           ( rst_sys_ni              ),
        .src_clk_i            ( clk_sys_i               ),
        .src_clear_i          ( 1'b0                    ),
        .src_clear_pending_o  (                         ),
        .src_data_i           ( frontend_cmd_i          ),
        .src_valid_i          ( frontend_cmd_valid_i    ),
        .src_ready_o          ( frontend_cmd_ready_o    ),
        .dst_rst_ni           ( rst_phy_ni              ),
        .dst_clk_i            ( clk_phy_i               ),
        .dst_clear_i          ( 1'b0                    ),
        .dst_clear_pending_o  (                         ),
        .dst_data_o           ( backend_cmd_o           ),
        .dst_valid_o          ( backend_cmd_valid_o     ),
        .dst_ready_i          ( backend_cmd_ready_i     )
    );

    cdc_2phase_clearable #(
        .T           ( logic         ),
        .SYNC_STAGES ( CdcSyncStages )
    ) i_cdc_wrsp (
        .src_rst_ni           ( rst_phy_ni            ),
        .src_clk_i            ( clk_phy_i             ),
        .src_clear_i          ( 1'b0                  ),
        .src_clear_pending_o  (                       ),
        .src_data_i           ( backend_wrsp_error_i  ),
        .src_valid_i          ( backend_wrsp_valid_i  ),
        .src_ready_o          ( backend_wrsp_ready_o  ),
        .dst_rst_ni           ( rst_sys_ni            ),
        .dst_clk_i            ( clk_sys_i             ),
        .dst_clear_i          ( 1'b0                  ),
        .dst_clear_pending_o  (                       ),
        .dst_data_o           ( frontend_wrsp_error_o ),
        .dst_valid_o          ( frontend_wrsp_valid_o ),
        .dst_ready_i          ( frontend_wrsp_ready_i )
    );

    cdc_fifo_gray_clearable #(
        .T           ( hyper_tx_t      ),
        .LOG_DEPTH   ( TxFifoLogDepth  ),
        .SYNC_STAGES ( CdcSyncStages   )
    ) i_cdc_fifo_tx (
        .src_rst_ni           ( rst_sys_ni          ),
        .src_clk_i            ( clk_sys_i           ),
        .src_clear_i          ( 1'b0                ),
        .src_clear_pending_o  (                     ),
        .src_data_i           ( frontend_tx_i       ),
        .src_valid_i          ( frontend_tx_valid_i ),
        .src_ready_o          ( frontend_tx_ready_o ),
        .dst_rst_ni           ( rst_phy_ni          ),
        .dst_clk_i            ( clk_phy_i           ),
        .dst_clear_i          ( 1'b0                ),
        .dst_clear_pending_o  (                     ),
        .dst_data_o           ( backend_tx_o        ),
        .dst_valid_o          ( backend_tx_valid_o  ),
        .dst_ready_i          ( backend_tx_ready_i  )
    );

    cdc_fifo_gray_clearable #(
        .T           ( hyper_rx_t      ),
        .LOG_DEPTH   ( RxFifoLogDepth  ),
        .SYNC_STAGES ( CdcSyncStages   )
    ) i_cdc_fifo_rx (
        .src_rst_ni           ( rst_phy_ni          ),
        .src_clk_i            ( clk_phy_i           ),
        .src_clear_i          ( 1'b0                ),
        .src_clear_pending_o  (                     ),
        .src_data_i           ( backend_rx_i        ),
        .src_valid_i          ( backend_rx_valid_i  ),
        .src_ready_o          ( backend_rx_ready_o  ),
        .dst_rst_ni           ( rst_sys_ni          ),
        .dst_clk_i            ( clk_sys_i           ),
        .dst_clear_i          ( 1'b0                ),
        .dst_clear_pending_o  (                     ),
        .dst_data_o           ( frontend_rx_o       ),
        .dst_valid_o          ( frontend_rx_valid_o ),
        .dst_ready_i          ( frontend_rx_ready_i )
    );

endmodule
