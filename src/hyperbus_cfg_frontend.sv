// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

`include "common_cells/registers.svh"
`include "common_cells/assertions.svh"

module hyperbus_cfg_frontend #(
    parameter int unsigned  NumChips         = -1,
    parameter int unsigned  NumPhys          = 2,
    parameter type          reg_req_t        = logic,
    parameter type          reg_rsp_t        = logic,
    parameter type          host_rule_t      = logic,
    parameter int unsigned  RegDataWidth     = -1,
    parameter logic [7:0]   CapabilityFeatures = 8'b0010_0000
) (
    input  logic                       clk_i,
    input  logic                       rst_ni,

    input  reg_req_t                   reg_req_i,
    output reg_rsp_t                   reg_rsp_o,

    output logic                       drain_o,
    input  logic                       host_idle_i,
    input  logic                       trans_active_i,

    output hyperbus_pkg::phy_cfg_t     cfg_apply_o,
    output logic                       cfg_apply_valid_o,
    input  logic                       cfg_apply_ready_i,
    input  logic                       cfg_apply_done_i,

    output logic [7:0]                 clock_div_apply_o,
    output logic                       clock_div_apply_valid_o,
    input  logic                       clock_div_apply_ready_i,
    input  logic                       clock_div_apply_done_i,

    output hyperbus_pkg::frontend_cfg_t frontend_cfg_o,
    output host_rule_t [NumChips-1:0]  chip_rules_o,
    input  logic                       decode_error_i
);

    typedef enum logic [2:0] {
        CfgIdle,
        CfgDrain,
        CfgCommit,
        CfgObserve,
        CfgClockSend,
        CfgClockWaitAck,
        CfgPhySend,
        CfgPhyWaitAck
    } cfg_state_e;

    cfg_state_e                       cfg_state_d;
    cfg_state_e                       cfg_state_q;
    hyperbus_pkg::phy_cfg_t           phy_cfg;
    hyperbus_pkg::phy_cfg_t           cfg_applied_d;
    hyperbus_pkg::phy_cfg_t           cfg_applied_q;
    logic [7:0]                       clock_div_applied_d;
    logic [7:0]                       clock_div_applied_q;
    logic                             phy_cfg_changed;
    logic                             clock_div_changed;
    logic                             cfg_changed;
    logic                             cfg_write_pending_d;
    logic                             cfg_write_pending_q;

    `ASSERT_INIT(NumChipsValid, NumChips >= 1 && NumChips <= 8)
    `ASSERT_INIT(NumPhysValid, NumPhys == 1 || NumPhys == 2)
    `ASSERT_INIT(RegDataWidthValid, RegDataWidth == 32)

    reg_req_t                         cfg_reg_req;
    reg_rsp_t                         cfg_reg_rsp;

    assign phy_cfg_changed          = phy_cfg != cfg_applied_q;
    assign clock_div_changed        = frontend_cfg_o.phy_clock_div != clock_div_applied_q;
    assign cfg_changed              = phy_cfg_changed || clock_div_changed;
    assign drain_o                  = (cfg_state_q != CfgIdle) || cfg_changed;
    assign cfg_apply_valid_o        = cfg_state_q == CfgPhySend;
    assign cfg_apply_o              = phy_cfg;
    assign clock_div_apply_valid_o  = cfg_state_q == CfgClockSend;
    assign clock_div_apply_o        = frontend_cfg_o.phy_clock_div;

    always_comb begin : proc_cfg_reg_gate
        cfg_reg_req = reg_req_i;
        reg_rsp_o   = cfg_reg_rsp;

        if (reg_req_i.write) begin
            cfg_reg_req.valid = reg_req_i.valid && (cfg_state_q == CfgCommit);
            if (cfg_state_q != CfgCommit) begin
                reg_rsp_o.ready = 1'b0;
                reg_rsp_o.error = 1'b0;
                reg_rsp_o.rdata = '0;
            end
        end else if (cfg_state_q != CfgIdle) begin
            cfg_reg_req.valid = 1'b0;
            reg_rsp_o.ready = 1'b0;
            reg_rsp_o.error = 1'b0;
            reg_rsp_o.rdata = '0;
        end
    end

    always_comb begin : proc_cfg_apply
        cfg_state_d   = cfg_state_q;
        cfg_applied_d = cfg_applied_q;
        clock_div_applied_d = clock_div_applied_q;
        cfg_write_pending_d = cfg_write_pending_q;

        unique case (cfg_state_q)
            CfgIdle: begin
                if (cfg_changed) begin
                    cfg_write_pending_d = 1'b0;
                    cfg_state_d = CfgDrain;
                end else if (reg_req_i.valid && reg_req_i.write) begin
                    cfg_write_pending_d = 1'b1;
                    cfg_state_d = CfgDrain;
                end
            end
            CfgDrain: begin
                if (host_idle_i && !trans_active_i) begin
                    cfg_state_d = cfg_write_pending_q ? CfgCommit : CfgObserve;
                end
            end
            CfgCommit: begin
                if (cfg_reg_rsp.ready) begin
                    cfg_write_pending_d = 1'b0;
                    cfg_state_d = CfgObserve;
                end
            end
            CfgObserve: begin
                if (clock_div_changed) begin
                    cfg_state_d = CfgClockSend;
                end else if (phy_cfg_changed) begin
                    cfg_state_d = CfgPhySend;
                end else begin
                    cfg_state_d = CfgIdle;
                end
            end
            CfgClockSend: begin
                if (clock_div_apply_ready_i) begin
                    if (clock_div_apply_done_i) begin
                        clock_div_applied_d = frontend_cfg_o.phy_clock_div;
                        cfg_state_d = phy_cfg_changed ? CfgPhySend : CfgIdle;
                    end else begin
                        cfg_state_d = CfgClockWaitAck;
                    end
                end
            end
            CfgClockWaitAck: begin
                if (clock_div_apply_done_i) begin
                    clock_div_applied_d = frontend_cfg_o.phy_clock_div;
                    cfg_state_d = phy_cfg_changed ? CfgPhySend : CfgIdle;
                end
            end
            CfgPhySend: begin
                if (cfg_apply_ready_i) begin
                    if (cfg_apply_done_i) begin
                        cfg_applied_d = phy_cfg;
                        cfg_state_d   = CfgIdle;
                    end else begin
                        cfg_state_d = CfgPhyWaitAck;
                    end
                end
            end
            CfgPhyWaitAck: begin
                if (cfg_apply_done_i) begin
                    cfg_applied_d = phy_cfg;
                    cfg_state_d   = CfgIdle;
                end
            end
            default: begin
                cfg_state_d = CfgIdle;
            end
        endcase
    end

    `FFARN(cfg_state_q, cfg_state_d, CfgIdle, clk_i, rst_ni)
    `FFARN(cfg_applied_q, cfg_applied_d, '0, clk_i, rst_ni)
    `FFARN(clock_div_applied_q, clock_div_applied_d, '0, clk_i, rst_ni)
    `FFARN(cfg_write_pending_q, cfg_write_pending_d, 1'b0, clk_i, rst_ni)

    hyperbus_cfg_regs #(
        .NumChips     ( NumChips     ),
        .NumPhys      ( NumPhys      ),
        .RegDataWidth ( RegDataWidth ),
        .CapabilityFeatures ( CapabilityFeatures ),
        .reg_req_t    ( reg_req_t    ),
        .reg_rsp_t    ( reg_rsp_t    ),
        .addr_rule_t  ( host_rule_t  )
    ) i_cfg_regs (
        .clk_i          ( clk_i             ),
        .rst_ni         ( rst_ni            ),
        .reg_req_i      ( cfg_reg_req       ),
        .reg_rsp_o      ( cfg_reg_rsp       ),
        .frontend_cfg_o ( frontend_cfg_o    ),
        .phy_cfg_o      ( phy_cfg           ),
        .chip_rules_o   ( chip_rules_o      ),
        .decode_error_i ( decode_error_i    )
    );

endmodule
