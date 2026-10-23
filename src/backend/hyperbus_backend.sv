// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

`include "common_cells/assertions.svh"
`include "common_cells/registers.svh"

module hyperbus_backend #(
    parameter int unsigned  NumPhys          = 2,
    parameter int unsigned  StartupCycles    = 60000,
    parameter int unsigned  SyncStages       = 2,
    parameter type          hyper_rx_t       = logic,
    parameter type          hyper_tx_t       = logic,
    parameter type          hyper_req_t      = logic,
    parameter type          hyper_rsp_t      = logic
) (
    input  logic                       clk_i,
    input  logic                       rst_ni,
`ifdef TARGET_XILINX
    input  logic                       clk_ref200_i,
`endif
    input  logic                       test_mode_i,

    input  hyperbus_pkg::phy_cfg_t     cfg_apply_i,
    input  logic                       cfg_apply_valid_i,
    output logic                       cfg_apply_ready_o,

    output logic                       busy_o,

    input  hyper_req_t                 req_i,
    output hyper_rsp_t                 rsp_o,

    output logic [NumPhys-1:0][hyperbus_pkg::HyperNumChips-1:0] hyper_cs_no,
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

    /////////////////////////////
    // Configuration and clock //
    /////////////////////////////

    hyperbus_pkg::phy_cfg_t cfg_q;
    logic                   cfg_apply_accepted;
    logic                   phy_busy_any;
    logic [NumPhys-1:0]     clk_tx;

    `ASSERT_INIT(NumPhysValid, NumPhys == 1 || NumPhys == 2)
    `ASSERT_INIT(SyncStagesValid, SyncStages >= 2)

    assign cfg_apply_ready_o  = ~phy_busy_any;
    assign cfg_apply_accepted = cfg_apply_valid_i && cfg_apply_ready_o;
    assign busy_o             = phy_busy_any || cfg_apply_valid_i;

    `FFLARN(cfg_q, cfg_apply_i, cfg_apply_accepted, '0, clk_i, rst_ni)

    for (genvar i = 0; i < NumPhys; i++) begin : gen_tx_clk_delay
        hyperbus_tx_clk_delay i_tx_clk_delay (
            .rst_ni,
`ifdef TARGET_XILINX
            .clk_ref200_i,
`endif
            .clk_i,
            .in_i    ( clk_i                    ),
            .delay_i ( cfg_q.phy[i].tx_delay    ),
            .out_o   ( clk_tx[i]                )
        );
    end

    /////////////////////
    // Physical lanes //
    /////////////////////

    if (NumPhys == 2) begin : gen_dual_phy
        hyperbus_pkg::phy_rx_t [NumPhys-1:0] phy_rx;
        hyperbus_pkg::phy_rx_t [NumPhys-1:0] buffered_rx;
        logic [NumPhys-1:0]                   phy_rx_valid;
        logic [NumPhys-1:0]                   phy_rx_ready;
        logic [NumPhys-1:0]                   buffered_rx_valid;
        logic [NumPhys-1:0][1:0]              buffered_rx_usage;
        logic [NumPhys-1:0]                   phy_tx_ready;
        logic [NumPhys-1:0]                   phy_tx_valid;
        logic [NumPhys-1:0]                   phy_cmd_ready;
        logic [NumPhys-1:0]                   phy_cmd_valid;
        logic [NumPhys-1:0]                   phy_wrsp_valid;
        logic [NumPhys-1:0]                   phy_wrsp_error;
        logic [NumPhys-1:0]                   phy_wrsp_ready;
        logic [NumPhys-1:0]                   phy_enable;
        logic [NumPhys-1:0]                   phy_busy;
        logic [NumPhys-1:0]                   phy_active_q;
        logic [NumPhys-1:0]                   tx_fork_valid;
        logic [NumPhys-1:0]                   cmd_fork_valid;
        logic [NumPhys-1:0]                   rx_join_ready;
        logic                                 active_change;

        assign phy_enable    = cfg_q.dual_phy ? '1 : 2'b01;
        assign active_change = phy_active_q != phy_enable;
        `FFLARN(phy_active_q, phy_enable | phy_busy,
                active_change && (buffered_rx_usage == '0), '1, clk_i, rst_ni)

        assign phy_busy_any     = |phy_busy;
        assign rsp_o.rx.error   = |({buffered_rx[1].error, buffered_rx[0].error} &
                                    phy_active_q);
        assign rsp_o.rx.last    = &({buffered_rx[1].last, buffered_rx[0].last} |
                                    ~phy_active_q);
        assign rsp_o.wrsp.error = |(phy_wrsp_error & phy_active_q);

        stream_fork #(
            .N_OUP ( NumPhys )
        ) i_tx_fork (
            .clk_i,
            .rst_ni,
            .valid_i ( req_i.tx_valid                 ),
            .ready_o ( rsp_o.tx_ready                 ),
            .valid_o ( tx_fork_valid                  ),
            .ready_i ( phy_tx_ready | ~phy_active_q   )
        );

        assign phy_tx_valid = tx_fork_valid & phy_active_q;

        stream_fork #(
            .N_OUP ( NumPhys )
        ) i_cmd_fork (
            .clk_i,
            .rst_ni,
            .valid_i ( req_i.cmd_valid && !active_change ),
            .ready_o ( rsp_o.cmd_ready                    ),
            .valid_o ( cmd_fork_valid                     ),
            .ready_i ( phy_cmd_ready | ~phy_active_q      )
        );

        assign phy_cmd_valid = cmd_fork_valid & phy_active_q;

        stream_join #(
            .N_INP ( NumPhys )
        ) i_rx_join (
            .inp_valid_i ( buffered_rx_valid | ~phy_active_q ),
            .inp_ready_o ( rx_join_ready                     ),
            .oup_valid_o ( rsp_o.rx_valid                    ),
            .oup_ready_i ( req_i.rx_ready                    )
        );

        stream_join #(
            .N_INP ( NumPhys )
        ) i_wrsp_join (
            .inp_valid_i ( phy_wrsp_valid | ~phy_active_q ),
            .inp_ready_o ( phy_wrsp_ready                 ),
            .oup_valid_o ( rsp_o.wrsp_valid               ),
            .oup_ready_i ( req_i.wrsp_ready               )
        );

        for (genvar i = 0; i < NumPhys; i++) begin : gen_phy
            assign rsp_o.rx.data[i*16 +: 16] = buffered_rx[i].data;

            stream_fifo #(
                .FALL_THROUGH ( 1'b0         ),
                .DEPTH        ( 4            ),
                .T            ( hyperbus_pkg::phy_rx_t )
            ) i_rx_fifo (
                .clk_i,
                .rst_ni,
                .flush_i    ( 1'b0                 ),
                .testmode_i ( 1'b0                 ),
                .usage_o    ( buffered_rx_usage[i] ),
                .data_i     ( phy_rx[i]            ),
                .valid_i    ( phy_rx_valid[i]      ),
                .ready_o    ( phy_rx_ready[i]      ),
                .data_o     ( buffered_rx[i]       ),
                .valid_o    ( buffered_rx_valid[i] ),
                .ready_i    ( rx_join_ready[i]     )
            );

            hyperbus_phy #(
                .StartupCycles  ( StartupCycles  ),
                .NumPhys        ( NumPhys        ),
                .SyncStages     ( SyncStages     ),
                .PhyIndex       ( i               )
            ) i_phy (
                .clk_i,
                .clk_tx_i       ( clk_tx[i]         ),
                .rst_ni,
                .test_mode_i,
                .cfg_i          ( cfg_q              ),
                .busy_o         ( phy_busy[i]        ),
                .rx_data_o      ( phy_rx[i].data     ),
                .rx_last_o      ( phy_rx[i].last     ),
                .rx_error_o     ( phy_rx[i].error    ),
                .rx_valid_o     ( phy_rx_valid[i]    ),
                .rx_ready_i     ( phy_rx_ready[i]    ),
                .tx_data_i      ( req_i.tx.data[16*i +: 16] ),
                .tx_strb_i      ( req_i.tx.strb[2*i +: 2]   ),
                .tx_last_i      ( req_i.tx.last      ),
                .tx_valid_i     ( phy_tx_valid[i]    ),
                .tx_ready_o     ( phy_tx_ready[i]    ),
                .b_error_o      ( phy_wrsp_error[i]  ),
                .b_valid_o      ( phy_wrsp_valid[i]  ),
                .b_ready_i      ( phy_wrsp_ready[i]  ),
                .trans_i        ( req_i.cmd.trans    ),
                .trans_cs_i     ( req_i.cmd.cs       ),
                .trans_valid_i  ( phy_cmd_valid[i]   ),
                .trans_ready_o  ( phy_cmd_ready[i]   ),
                .hyper_cs_no    ( hyper_cs_no[i]     ),
                .hyper_ck_o     ( hyper_ck_o[i]      ),
                .hyper_ck_no    ( hyper_ck_no[i]     ),
                .hyper_rwds_o   ( hyper_rwds_o[i]    ),
                .hyper_rwds_i   ( hyper_rwds_i[i]    ),
                .hyper_rwds_oe_o( hyper_rwds_oe_o[i] ),
                .hyper_dq_i     ( hyper_dq_i[i]      ),
                .hyper_dq_o     ( hyper_dq_o[i]      ),
                .hyper_dq_oe_o  ( hyper_dq_oe_o[i]   ),
                .hyper_reset_no ( hyper_reset_no[i]  )
            );
        end
    end else begin : gen_single_phy
        hyperbus_phy #(
            .StartupCycles  ( StartupCycles  ),
            .NumPhys        ( NumPhys        ),
            .SyncStages     ( SyncStages     ),
            .PhyIndex       ( 0               )
        ) i_phy (
            .clk_i,
            .clk_tx_i       ( clk_tx[0]          ),
            .rst_ni,
            .test_mode_i,
            .cfg_i          ( cfg_q              ),
            .busy_o         ( phy_busy_any       ),
            .rx_data_o      ( rsp_o.rx.data      ),
            .rx_last_o      ( rsp_o.rx.last      ),
            .rx_error_o     ( rsp_o.rx.error     ),
            .rx_valid_o     ( rsp_o.rx_valid     ),
            .rx_ready_i     ( req_i.rx_ready     ),
            .tx_data_i      ( req_i.tx.data      ),
            .tx_strb_i      ( req_i.tx.strb      ),
            .tx_last_i      ( req_i.tx.last      ),
            .tx_valid_i     ( req_i.tx_valid     ),
            .tx_ready_o     ( rsp_o.tx_ready     ),
            .b_error_o      ( rsp_o.wrsp.error   ),
            .b_valid_o      ( rsp_o.wrsp_valid   ),
            .b_ready_i      ( req_i.wrsp_ready   ),
            .trans_i        ( req_i.cmd.trans    ),
            .trans_cs_i     ( req_i.cmd.cs       ),
            .trans_valid_i  ( req_i.cmd_valid    ),
            .trans_ready_o  ( rsp_o.cmd_ready    ),
            .hyper_cs_no    ( hyper_cs_no        ),
            .hyper_ck_o     ( hyper_ck_o         ),
            .hyper_ck_no    ( hyper_ck_no        ),
            .hyper_rwds_o   ( hyper_rwds_o       ),
            .hyper_rwds_i   ( hyper_rwds_i       ),
            .hyper_rwds_oe_o( hyper_rwds_oe_o    ),
            .hyper_dq_i     ( hyper_dq_i         ),
            .hyper_dq_o     ( hyper_dq_o         ),
            .hyper_dq_oe_o  ( hyper_dq_oe_o      ),
            .hyper_reset_no ( hyper_reset_no     )
        );
    end

endmodule
