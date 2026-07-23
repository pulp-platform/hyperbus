// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Luca Valente <luca.valente@unibo.it>
// Philippe Sauter <phsauter@iis.ee.ethz.ch>

`include "common_cells/registers.svh"

module hyperbus_phy_if import hyperbus_pkg::*; #(
    parameter int unsigned NumChips      = 2,
    parameter int unsigned NumPhys       = 2,
    parameter int unsigned StartupCycles = 60000,
    parameter int unsigned SyncStages    = 2,
    parameter type         hyper_tx_t    = logic,
    parameter type         hyper_rx_t    = logic
) (
    input  logic                clk_phy_i,
    input  logic                clk_phy_i_90,
    input  logic                rst_phy_ni,
    input  logic                test_mode_i,
    input  phy_cfg_t            cfg_i,
    output logic                busy_o,

    input  logic                trans_valid_i,
    output logic                trans_ready_o,
    input  hyper_tf_t           trans_i,
    input  logic [NumChips-1:0] trans_cs_i,

    input  logic                tx_valid_i,
    output logic                tx_ready_o,
    input  hyper_tx_t           tx_i,

    output logic                rx_valid_o,
    input  logic                rx_ready_i,
    output hyper_rx_t           rx_o,

    output logic                b_valid_o,
    input  logic                b_ready_i,
    output logic                b_error_o,

    // Physical interface: facing HyperBus
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

    logic clk_phy_0, clk_phy_90;

    assign clk_phy_0  = clk_phy_i;
    assign clk_phy_90 = clk_phy_i_90;


    phy_rx_t [NumPhys-1:0]      phy_fifo_rx;
    phy_rx_t [NumPhys-1:0]      fifo_axi_rx;
    logic [NumPhys-1:0]         phy_fifo_valid;
    logic [NumPhys-1:0]         phy_fifo_ready;
    logic [NumPhys-1:0]         fifo_axi_valid;
    logic [NumPhys-1:0][1:0]    fifo_axi_usage;
    logic [NumPhys-1:0]         phy_tx_ready;
    logic [NumPhys-1:0]         phy_tx_valid;
    logic [NumPhys-1:0]         phy_trans_ready;
    logic [NumPhys-1:0]         phy_trans_valid;
    logic [NumPhys-1:0]         phy_b_valid;
    logic [NumPhys-1:0]         phy_b_error;
    logic [NumPhys-1:0]         phy_b_ready;

    if (NumPhys == 2) begin : gen_dual_phy

        logic [NumPhys-1:0] phy_enable;
        logic [NumPhys-1:0] phy_busy;
        logic [NumPhys-1:0] phy_active_q, phy_active_d;
        logic [NumPhys-1:0] tx_fork_valid;
        logic [NumPhys-1:0] trans_fork_valid;
        logic [NumPhys-1:0] rx_join_ready;
        logic               change_phy_active;

        assign change_phy_active = phy_active_q != phy_enable;
        assign phy_enable        = cfg_i.dual_phy ? '1 : 2'b01;
        assign phy_active_d = change_phy_active && (fifo_axi_usage == '0) ?
                              (phy_enable | phy_busy) : phy_active_q;

        `FFARN(phy_active_q, phy_active_d, '1, clk_phy_0, rst_phy_ni)

        assign busy_o      = |phy_busy;
        assign rx_o.error  = |({fifo_axi_rx[1].error, fifo_axi_rx[0].error} & phy_active_q);
        assign rx_o.last   = &({fifo_axi_rx[1].last, fifo_axi_rx[0].last} | ~phy_active_q);
        assign b_error_o   = |(phy_b_error & phy_active_q);

        stream_fork #(
            .N_OUP ( NumPhys )
        ) i_tx_fork (
            .clk_i   ( clk_phy_0                   ),
            .rst_ni  ( rst_phy_ni                  ),
            .valid_i ( tx_valid_i                  ),
            .ready_o ( tx_ready_o                  ),
            .valid_o ( tx_fork_valid               ),
            .ready_i ( phy_tx_ready | ~phy_active_q )
        );

        assign phy_tx_valid = tx_fork_valid & phy_active_q;

        stream_fork #(
            .N_OUP ( NumPhys )
        ) i_trans_fork (
            .clk_i   ( clk_phy_0                         ),
            .rst_ni  ( rst_phy_ni                       ),
            .valid_i ( trans_valid_i && !change_phy_active ),
            .ready_o ( trans_ready_o                    ),
            .valid_o ( trans_fork_valid                 ),
            .ready_i ( phy_trans_ready | ~phy_active_q )
        );

        assign phy_trans_valid = trans_fork_valid & phy_active_q;

        stream_join #(
            .N_INP ( NumPhys )
        ) i_rx_join (
            .inp_valid_i ( fifo_axi_valid | ~phy_active_q ),
            .inp_ready_o ( rx_join_ready                  ),
            .oup_valid_o ( rx_valid_o                     ),
            .oup_ready_i ( rx_ready_i                     )
        );

        stream_join #(
            .N_INP ( NumPhys )
        ) i_wrsp_join (
            .inp_valid_i ( phy_b_valid | ~phy_active_q ),
            .inp_ready_o ( phy_b_ready                 ),
            .oup_valid_o ( b_valid_o                   ),
            .oup_ready_i ( b_ready_i                   )
        );

        for (genvar i = 0; i < NumPhys; i++) begin : gen_phy
            assign rx_o.data[i*16 +: 16] = fifo_axi_rx[i].data;

            stream_fifo #(
                .FALL_THROUGH ( 1'b0        ),
                .DEPTH        ( 4           ),
                .T            ( phy_rx_t    )
            ) i_rx_fifo (
                .clk_i          ( clk_phy_0         ),
                .rst_ni         ( rst_phy_ni        ),
                .flush_i        ( 1'b0              ),
                .testmode_i     ( 1'b0              ),
                .usage_o        ( fifo_axi_usage[i] ),
                .data_i         ( phy_fifo_rx[i]    ),
                .valid_i        ( phy_fifo_valid[i] ),
                .ready_o        ( phy_fifo_ready[i] ),
                .data_o         ( fifo_axi_rx[i]    ),
                .valid_o        ( fifo_axi_valid[i] ),
                .ready_i        ( rx_join_ready[i]  )
            );

            hyperbus_phy #(
                .NumChips       ( NumChips          ),
                .StartupCycles  ( StartupCycles     ),
                .NumPhys        ( NumPhys           ),
                .SyncStages     ( SyncStages        )
            ) i_phy (
                .clk_i          ( clk_phy_0         ),
                .clk_i_90       ( clk_phy_90        ),
                .rst_ni         ( rst_phy_ni        ),
                .test_mode_i    ( test_mode_i       ),

                .cfg_i          ( cfg_i             ),

                .busy_o         ( phy_busy[i]       ),

                .rx_data_o      ( phy_fifo_rx[i].data ),
                .rx_last_o      ( phy_fifo_rx[i].last ),
                .rx_error_o     ( phy_fifo_rx[i].error),
                .rx_valid_o     ( phy_fifo_valid[i]   ),
                .rx_ready_i     ( phy_fifo_ready[i]   ),

                .tx_data_i      ( tx_i.data[16*i +: 16] ),
                .tx_strb_i      ( tx_i.strb[2*i +: 2]   ),
                .tx_last_i      ( tx_i.last            ),
                .tx_valid_i     ( phy_tx_valid[i]      ),
                .tx_ready_o     ( phy_tx_ready[i]      ),

                .b_error_o      ( phy_b_error[i]       ),
                .b_valid_o      ( phy_b_valid[i]       ),
                .b_ready_i      ( phy_b_ready[i]       ),

                .trans_i        ( trans_i              ),
                .trans_cs_i     ( trans_cs_i           ),
                .trans_valid_i  ( phy_trans_valid[i]   ),
                .trans_ready_o  ( phy_trans_ready[i]   ),

                .hyper_cs_no    ( hyper_cs_no[i]       ),
                .hyper_ck_o     ( hyper_ck_o[i]        ),
                .hyper_ck_no    ( hyper_ck_no[i]       ),
                .hyper_rwds_o   ( hyper_rwds_o[i]      ),
                .hyper_rwds_i   ( hyper_rwds_i[i]      ),
                .hyper_rwds_oe_o( hyper_rwds_oe_o[i]   ),
                .hyper_dq_i     ( hyper_dq_i[i]        ),
                .hyper_dq_o     ( hyper_dq_o[i]        ),
                .hyper_dq_oe_o  ( hyper_dq_oe_o[i]     ),
                .hyper_reset_no ( hyper_reset_no[i]    )
            );
        end
    end else begin : gen_single_phy

        hyperbus_phy #(
            .NumChips       ( NumChips          ),
            .StartupCycles  ( StartupCycles     ),
            .NumPhys        ( NumPhys           ),
            .SyncStages     ( SyncStages        )
        ) i_phy (
            .clk_i          ( clk_phy_0       ),
            .clk_i_90       ( clk_phy_90      ),
            .rst_ni         ( rst_phy_ni      ),
            .test_mode_i    ( test_mode_i     ),

            .cfg_i          ( cfg_i           ),

            .busy_o         ( busy_o          ),

            .rx_data_o      ( rx_o.data       ),
            .rx_last_o      ( rx_o.last       ),
            .rx_error_o     ( rx_o.error      ),
            .rx_valid_o     ( rx_valid_o      ),
            .rx_ready_i     ( rx_ready_i      ),

            .tx_data_i      ( tx_i.data       ),
            .tx_strb_i      ( tx_i.strb       ),
            .tx_last_i      ( tx_i.last       ),
            .tx_valid_i     ( tx_valid_i      ),
            .tx_ready_o     ( tx_ready_o      ),

            .b_error_o      ( b_error_o       ),
            .b_valid_o      ( b_valid_o       ),
            .b_ready_i      ( b_ready_i       ),

            .trans_i        ( trans_i         ),
            .trans_cs_i     ( trans_cs_i      ),
            .trans_valid_i  ( trans_valid_i   ),
            .trans_ready_o  ( trans_ready_o   ),

            .hyper_cs_no    ( hyper_cs_no     ),
            .hyper_ck_o     ( hyper_ck_o      ),
            .hyper_ck_no    ( hyper_ck_no     ),
            .hyper_rwds_o   ( hyper_rwds_o    ),
            .hyper_rwds_i   ( hyper_rwds_i    ),
            .hyper_rwds_oe_o( hyper_rwds_oe_o ),
            .hyper_dq_i     ( hyper_dq_i      ),
            .hyper_dq_o     ( hyper_dq_o      ),
            .hyper_dq_oe_o  ( hyper_dq_oe_o   ),
            .hyper_reset_no ( hyper_reset_no  )
        );
    end

endmodule
