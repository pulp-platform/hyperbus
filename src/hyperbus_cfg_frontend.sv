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
    input  logic                         phy_reset_ni,
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
        CfgPhyResetWait,
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
    hyperbus_pkg::frontend_cfg_t target_frontend_cfg;
    hyperbus_pkg::phy_cfg_t      target_phy_cfg;
    logic replay_d, replay_q;
    logic command_flush, command_apply;
    logic apply_pending_d, apply_pending_q;
    logic cfg_changed, frontend_changed;
    logic status_access;
    logic clock_changed;
    logic phy_changed;
    logic clock_apply_needed, phy_apply_needed;
    logic drain_complete;
    logic phy_ready_sync;
    logic barrier_active, reset_entry_pending;

    `ASSERT_INIT(NumPhysValid, NumPhys == 1 || NumPhys == 2)
    `ASSERT_INIT(RegDataWidthValid, RegDataWidth == 32)
    `ASSERT_INIT(RegAddrWidthValid, RegAddrWidth >= 12)

    assign frontend_changed = staged_frontend_cfg != applied_frontend_q;
    assign clock_changed = staged_frontend_cfg.divider != applied_frontend_q.divider;
    assign phy_changed = staged_phy_cfg != applied_phy_q;
    assign cfg_changed = frontend_changed || phy_changed;
    // Replay already selects the applied image; only normal APPLY compares edits.
    assign clock_apply_needed = ClockDividerImplemented && !replay_q && clock_changed;
    assign phy_apply_needed = !replay_q && phy_changed;
    assign drain_complete = host_idle_i && !trans_active_i;
    assign target_frontend_cfg = replay_q ? applied_frontend_q : staged_frontend_cfg;
    assign target_phy_cfg = replay_q ? applied_phy_q : staged_phy_cfg;
    assign status_access = reg_req_i.valid &&
                           (reg_req_i.addr == RegAddrWidth'(12'h010));

    // PHY reset is ordinary data here; surviving configuration state uses only
    // this final synchronized level, not the asynchronously asserted indication.
    sync #(
        .STAGES     ( 2    ),
        .ResetValue ( 1'b0 )
    ) i_phy_ready_sync (
        .clk_i    ( clk_i          ),
        .rst_ni   ( rst_ni         ),
        .serial_i ( phy_reset_ni   ),
        .serial_o ( phy_ready_sync )
    );

    // Staged registers are frozen from command acceptance through completion.
    // PHY-reset replay instead selects the retained last-applied configuration.
    assign barrier_active = (cfg_state_q != CfgIdle) || command_apply || command_flush;
    assign drain_o = barrier_active || !phy_reset_ni || !phy_ready_sync;
    assign reset_entry_pending = (cfg_state_q == CfgIdle) &&
                                 (!phy_reset_ni || !phy_ready_sync);
    assign cfg_apply_o = target_phy_cfg;
    assign cfg_apply_valid_o = (cfg_state_q == CfgPhySend) && phy_ready_sync;
    assign clock_div_apply_o = target_frontend_cfg.divider;
    assign clock_div_apply_valid_o = cfg_state_q == CfgClockSend;

    // STATUS stays live through barriers, except reset entry while its registered
    // BUSY may still be zero. On entering ResetWait, BUSY has sampled synced low.
    reg_req_t cfg_reg_req;
    reg_rsp_t cfg_reg_rsp;
    always_comb begin : proc_cfg_reg_gate
        cfg_reg_req = reg_req_i;
        reg_rsp_o = cfg_reg_rsp;
        if ((drain_o && !status_access) || reset_entry_pending) begin
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
        replay_d = replay_q;
        apply_pending_d = apply_pending_q;

        unique case (cfg_state_q)
            CfgInit: begin
                replay_d = 1'b0;
                apply_pending_d = 1'b1;
                if (phy_ready_sync && drain_complete) begin
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
                if (!phy_ready_sync) begin
                    // Replay the last applied values, never staged software edits.
                    replay_d = 1'b1;
                    apply_pending_d = 1'b1;
                    cfg_state_d = CfgPhyResetWait;
                end else if (command_apply) begin
                    replay_d = 1'b0;
                    apply_pending_d = 1'b1;
                    cfg_state_d = CfgDrain;
                end else if (command_flush) begin
                    apply_pending_d = 1'b0;
                    cfg_state_d = CfgDrain;
                end
            end
            CfgPhyResetWait: begin
                if (phy_ready_sync) cfg_state_d = CfgPhySend;
            end
            CfgDrain: begin
                if (drain_complete) begin
                    if (apply_pending_q) begin
                        if (clock_apply_needed) begin
                            cfg_state_d = CfgClockSend;
                        end else if (phy_apply_needed) begin
                            cfg_state_d = CfgPhySend;
                        end else begin
                            applied_frontend_d = target_frontend_cfg;
                            applied_phy_d = target_phy_cfg;
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
                        if (phy_apply_needed) begin
                            cfg_state_d = CfgPhySend;
                        end else begin
                            applied_frontend_d = target_frontend_cfg;
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
                    if (phy_apply_needed) begin
                        cfg_state_d = CfgPhySend;
                    end else begin
                        applied_frontend_d = target_frontend_cfg;
                        apply_pending_d = 1'b0;
                        cfg_state_d = CfgIdle;
                    end
                end
            end
            CfgPhySend: begin
                if (cfg_apply_valid_o && cfg_apply_ready_i) begin
                    cfg_state_d = cfg_apply_done_i ? CfgIdle : CfgPhyWait;
                    if (cfg_apply_done_i) begin
                        applied_frontend_d = target_frontend_cfg;
                        applied_phy_d = target_phy_cfg;
                        apply_pending_d = 1'b0;
                    end
                end
            end
            CfgPhyWait: begin
                if (cfg_apply_done_i) begin
                    applied_frontend_d = target_frontend_cfg;
                    applied_phy_d = target_phy_cfg;
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
    `FFARN(replay_q, replay_d, 1'b0, clk_i, rst_ni)
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
        .status_busy_i  ( barrier_active || !phy_ready_sync ),
        .status_dirty_i ( cfg_changed        ),
        .decode_error_i ( decode_error_i     ),
        .command_flush_o( command_flush     ),
        .command_apply_o( command_apply     ),
        .frontend_cfg_o ( staged_frontend_cfg ),
        .phy_cfg_o      ( staged_phy_cfg     ),
        .chip_rules_o   (                    )
    );

    assign frontend_cfg_o = applied_frontend_q;

    // PHY-only reset is not transaction or configuration-barrier recovery.
    // A second reset is supported only after the previous replay has completed.
    `ASSERT(PhyResetOnlyWhenQuiescent,
        $fell(phy_reset_ni) |->
        ((cfg_state_q == CfgInit || cfg_state_q == CfgIdle) && drain_complete),
        clk_i, !rst_ni)
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
