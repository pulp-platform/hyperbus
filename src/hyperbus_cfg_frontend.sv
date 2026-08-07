// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

`include "common_cells/registers.svh"
`include "common_cells/assertions.svh"

module hyperbus_cfg_frontend #(
    parameter int unsigned NumPhys                 = 2,
    parameter int unsigned RegDataWidth            = -1,
    parameter int unsigned RegAddrWidth            = 32,
    parameter bit          ClockDividerImplemented = 1'b0,
    parameter type         reg_req_t               = logic,
    parameter type         reg_rsp_t               = logic,
    parameter type         host_rule_t             = logic
) (
    input  logic                         clk_i,
    input  logic                         rst_ni,
    input  reg_req_t                      reg_req_i,
    output reg_rsp_t                      reg_rsp_o,
    output logic                         drain_o,
    input  logic                         host_idle_i,
    input  logic                         trans_active_i,
    output hyperbus_pkg::phy_cfg_t       cfg_apply_o,
    output logic                         cfg_apply_valid_o,
    input  logic                         cfg_apply_ready_i,
    input  logic                         cfg_apply_done_i,
    output logic [7:0]                   clock_div_apply_o,
    output logic                         clock_div_apply_valid_o,
    input  logic                         clock_div_apply_ready_i,
    input  logic                         clock_div_apply_done_i,
    output hyperbus_pkg::frontend_cfg_t frontend_cfg_o,
    output host_rule_t [hyperbus_pkg::HyperNumChips-1:0] chip_rules_o,
    input  logic                         decode_error_i
);
    typedef enum logic [3:0] {
        CfgInit,
        CfgIdle,
        CfgDrain,
        CfgClockSend,
        CfgClockWait,
        CfgPhySend,
        CfgPhyWait
    } cfg_state_e;

    cfg_state_e cfg_state_d, cfg_state_q;
    hyperbus_pkg::frontend_cfg_t staged_frontend_cfg;
    hyperbus_pkg::phy_cfg_t      staged_phy_cfg;
    hyperbus_pkg::frontend_cfg_t applied_frontend_d, applied_frontend_q;
    hyperbus_pkg::phy_cfg_t      applied_phy_d, applied_phy_q;
    hyperbus_pkg::frontend_cfg_t pending_frontend_d, pending_frontend_q;
    hyperbus_pkg::phy_cfg_t      pending_phy_d, pending_phy_q;
    logic command_flush, command_apply;
    logic apply_pending_d, apply_pending_q;
    logic cfg_changed;
    logic status_access;
    logic clock_changed;
    logic phy_changed;
    logic drain_complete;

    `ASSERT_INIT(NumPhysValid, NumPhys == 1 || NumPhys == 2)
    `ASSERT_INIT(RegDataWidthValid, RegDataWidth == 32)
    `ASSERT_INIT(RegAddrWidthValid, RegAddrWidth >= 12)

    assign cfg_changed = (staged_frontend_cfg != applied_frontend_q) ||
                         (staged_phy_cfg != applied_phy_q);
    assign clock_changed = staged_frontend_cfg.divider != applied_frontend_q.divider;
    assign phy_changed = staged_phy_cfg != applied_phy_q;
    assign drain_complete = host_idle_i && !trans_active_i;
    assign status_access = reg_req_i.valid &&
                           (reg_req_i.addr == RegAddrWidth'(12'h010));

    assign drain_o = cfg_state_q != CfgIdle;
    assign cfg_apply_o = pending_phy_q;
    assign cfg_apply_valid_o = cfg_state_q == CfgPhySend;
    assign clock_div_apply_o = pending_frontend_q.divider;
    assign clock_div_apply_valid_o = cfg_state_q == CfgClockSend;

    // STATUS reads and W1C writes stay live while a barrier is in progress.
    reg_req_t cfg_reg_req;
    reg_rsp_t cfg_reg_rsp;
    always_comb begin : proc_cfg_reg_gate
        cfg_reg_req = reg_req_i;
        reg_rsp_o = cfg_reg_rsp;
        if (cfg_state_q != CfgIdle && !status_access) begin
            cfg_reg_req.valid = 1'b0;
            reg_rsp_o.ready = 1'b0;
            reg_rsp_o.error = 1'b0;
            reg_rsp_o.rdata = '0;
        end
    end

    always_comb begin : proc_cfg_fsm
        cfg_state_d = cfg_state_q;
        applied_frontend_d = applied_frontend_q;
        applied_phy_d = applied_phy_q;
        pending_frontend_d = pending_frontend_q;
        pending_phy_d = pending_phy_q;
        apply_pending_d = apply_pending_q;

        unique case (cfg_state_q)
            CfgInit: begin
                pending_frontend_d = staged_frontend_cfg;
                pending_phy_d = staged_phy_cfg;
                apply_pending_d = 1'b1;
                if (drain_complete) begin
                    if (ClockDividerImplemented && clock_changed) begin
                        cfg_state_d = CfgClockSend;
                    end else if (phy_changed) begin
                        cfg_state_d = CfgPhySend;
                    end else begin
                        applied_frontend_d = staged_frontend_cfg;
                        applied_phy_d = staged_phy_cfg;
                        apply_pending_d = 1'b0;
                        cfg_state_d = CfgIdle;
                    end
                end
            end
            CfgIdle: begin
                // APPLY wins if both command bits are written together.
                if (command_apply) begin
                    pending_frontend_d = staged_frontend_cfg;
                    pending_phy_d = staged_phy_cfg;
                    apply_pending_d = 1'b1;
                    cfg_state_d = CfgDrain;
                end else if (command_flush) begin
                    apply_pending_d = 1'b0;
                    cfg_state_d = CfgDrain;
                end
            end
            CfgDrain: begin
                if (drain_complete) begin
                    if (apply_pending_q) begin
                        if (ClockDividerImplemented &&
                            (pending_frontend_q.divider != applied_frontend_q.divider)) begin
                            cfg_state_d = CfgClockSend;
                        end else if (pending_phy_q != applied_phy_q) begin
                            cfg_state_d = CfgPhySend;
                        end else begin
                            applied_frontend_d = pending_frontend_q;
                            applied_phy_d = pending_phy_q;
                            apply_pending_d = 1'b0;
                            cfg_state_d = CfgIdle;
                        end
                    end else begin
                        cfg_state_d = CfgIdle;
                    end
                end
            end
            CfgClockSend: begin
                if (clock_div_apply_valid_o && clock_div_apply_ready_i) begin
                    if (clock_div_apply_done_i) begin
                        if (pending_phy_q != applied_phy_q) begin
                            cfg_state_d = CfgPhySend;
                        end else begin
                            applied_frontend_d = pending_frontend_q;
                            apply_pending_d = 1'b0;
                            cfg_state_d = CfgIdle;
                        end
                    end else begin
                        cfg_state_d = CfgClockWait;
                    end
                end
            end
            CfgClockWait: begin
                if (clock_div_apply_done_i) begin
                    if (pending_phy_q != applied_phy_q) begin
                        cfg_state_d = CfgPhySend;
                    end else begin
                        applied_frontend_d = pending_frontend_q;
                        apply_pending_d = 1'b0;
                        cfg_state_d = CfgIdle;
                    end
                end
            end
            CfgPhySend: begin
                if (cfg_apply_valid_o && cfg_apply_ready_i) begin
                    cfg_state_d = cfg_apply_done_i ? CfgIdle : CfgPhyWait;
                    if (cfg_apply_done_i) begin
                        applied_frontend_d = pending_frontend_q;
                        applied_phy_d = pending_phy_q;
                        apply_pending_d = 1'b0;
                    end
                end
            end
            CfgPhyWait: begin
                if (cfg_apply_done_i) begin
                    applied_frontend_d = pending_frontend_q;
                    applied_phy_d = pending_phy_q;
                    apply_pending_d = 1'b0;
                    cfg_state_d = CfgIdle;
                end
            end
            default: cfg_state_d = CfgInit;
        endcase
    end

    `FFARN(cfg_state_q, cfg_state_d, CfgInit, clk_i, rst_ni)
    `FFARN(applied_frontend_q, applied_frontend_d, '0, clk_i, rst_ni)
    `FFARN(applied_phy_q, applied_phy_d, '0, clk_i, rst_ni)
    `FFARN(pending_frontend_q, pending_frontend_d, '0, clk_i, rst_ni)
    `FFARN(pending_phy_q, pending_phy_d, '0, clk_i, rst_ni)
    `FFARN(apply_pending_q, apply_pending_d, 1'b0, clk_i, rst_ni)

    hyperbus_cfg_regs #(
        .NumPhys                 ( NumPhys                 ),
        .RegDataWidth            ( RegDataWidth            ),
        .RegAddrWidth            ( RegAddrWidth            ),
        .ClockDividerImplemented ( ClockDividerImplemented ),
        .reg_req_t               ( reg_req_t               ),
        .reg_rsp_t               ( reg_rsp_t               ),
        .addr_rule_t             ( host_rule_t              )
    ) i_cfg_regs (
        .clk_i          ( clk_i             ),
        .rst_ni         ( rst_ni            ),
        .reg_req_i      ( cfg_reg_req       ),
        .reg_rsp_o      ( cfg_reg_rsp       ),
        .status_busy_i  ( cfg_state_q != CfgIdle ),
        .status_dirty_i ( cfg_changed        ),
        .decode_error_i ( decode_error_i     ),
        .command_flush_o( command_flush     ),
        .command_apply_o( command_apply     ),
        .frontend_cfg_o ( staged_frontend_cfg ),
        .phy_cfg_o      ( staged_phy_cfg     ),
        .chip_rules_o   (                    )
    );

    assign frontend_cfg_o = applied_frontend_q;
    always_comb begin : proc_applied_rules
        chip_rules_o = '0;
        for (int unsigned i = 0; i < hyperbus_pkg::HyperNumChips; i++) begin
            chip_rules_o[i].idx = unsigned'(i);
            chip_rules_o[i].start_addr = applied_frontend_q.chip[i].range_base;
            chip_rules_o[i].end_addr = applied_frontend_q.chip[i].range_bound;
        end
    end

    for (genvar i = 0; i < hyperbus_pkg::HyperNumChips; i++) begin : gen_cfg_range_checks
        `ASSERT(CfgLatencyAccessRange, staged_phy_cfg.chip[i].t_latency_access >= 4'd3,
            clk_i, !rst_ni)
        `ASSERT(CfgRwdsSampleFitsLatency,
            ({1'b0, staged_phy_cfg.chip[i].rwds_sample_delay} + 5'd2) <=
            {1'b0, staged_phy_cfg.chip[i].t_latency_access},
            clk_i, !rst_ni)
    end
endmodule : hyperbus_cfg_frontend
