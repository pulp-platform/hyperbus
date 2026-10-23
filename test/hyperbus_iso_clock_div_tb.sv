// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

`timescale 1ns/1ps
`include "axi/typedef.svh"
`include "register_interface/typedef.svh"

// Real AXI, configuration, divider, bridge and PHY; writes need no device model.
module hyperbus_iso_clock_div_tb #(
    parameter int unsigned PhySyncStages = 2,
    parameter int unsigned LatencyOracleOffsetCycles = 0
);
    import hyperbus_pkg::*;
    typedef logic [31:0] addr_t;
    typedef logic [63:0] data_t;
    typedef logic [7:0] strb_t;
    typedef logic [2:0] id_t;
    `AXI_TYPEDEF_ALL(axi, addr_t, id_t, data_t, strb_t, logic)
    `REG_BUS_TYPEDEF_REQ(reg_req_t, addr_t, addr_t, logic [3:0])
    `REG_BUS_TYPEDEF_RSP(reg_rsp_t, addr_t)
    typedef axi_pkg::xbar_rule_32_t rule_t;

    logic clk = 0;
    always #5ns clk = !clk;
    logic rst_n = 0;
    axi_req_t axi_req;
    axi_resp_t axi_rsp;
    reg_req_t reg_req;
    reg_rsp_t reg_rsp;
    logic [7:0] previous_divider;
    logic [hyperbus_pkg::HyperNumChips-1:0] hyper_cs_n;
    logic hyper_ck;
    int divider_updates, b_responses, recovery_samples;
    int cycle_count, w_accept_cycle, bvalid_latency;
    time w_backend_phase;
    bit latency_armed, w_accepted_for_latency, bvalid_latency_seen;
    bit pending_latency_case;
    bit check_recovery;
    time last_backend_edge;
    int expected_divider;

    hyperbus_isochronous #(
        .NumPhys(1), .AxiAddrWidth(32), .AxiDataWidth(64),
        .AxiIdWidth(3), .AxiUserWidth(1), .RegDataWidth(32),
        .PhyStartupCycles(32), .SyncStages(PhySyncStages),
        .axi_req_t(axi_req_t), .axi_rsp_t(axi_resp_t),
        .reg_req_t(reg_req_t), .reg_rsp_t(reg_rsp_t), .axi_rule_t(rule_t)
    ) dut (
        .clk_sys_i(clk), .rst_sys_ni(rst_n), .test_mode_i(1'b0),
        .axi_req_i(axi_req), .axi_rsp_o(axi_rsp),
        .reg_req_i(reg_req), .reg_rsp_o(reg_rsp),
        .hyper_cs_no(hyper_cs_n), .hyper_ck_o(hyper_ck), .hyper_ck_no(),
        .hyper_rwds_o(), .hyper_rwds_i('0), .hyper_rwds_oe_o(),
        .hyper_dq_i('0), .hyper_dq_o(), .hyper_dq_oe_o(), .hyper_reset_no()
    );

    // Sample before the accepting edge, independently of the RTL SVA macros.
    always @(posedge clk) if (rst_n) begin
        cycle_count++;
        if (latency_armed && axi_req.w_valid && axi_rsp.w_ready) begin
            w_accept_cycle = cycle_count;
            w_backend_phase = $time - last_backend_edge;
            w_accepted_for_latency = 1;
        end
        if (latency_armed && w_accepted_for_latency && axi_rsp.b_valid &&
            !bvalid_latency_seen) begin
            bvalid_latency = cycle_count - w_accept_cycle +
                (pending_latency_case ? LatencyOracleOffsetCycles : 0);
            bvalid_latency_seen = 1;
        end
        if (dut.clock_div_req_valid &&
            (dut.backend_busy || !dut.rst_backend_n || !dut.frontend_drain ||
             !dut.host_idle || dut.midend_trans_active))
            $fatal(1, "Divider request before complete backend/frontend idle");
        if (axi_rsp.b_valid && axi_req.b_ready) begin
            b_responses++;
            if (check_recovery && (!dut.backend_busy || !dut.frontend_drain))
                $fatal(1, "Final B response did not overlap pending APPLY and PHY recovery");
        end
        if (check_recovery && dut.backend_busy) begin
            if (dut.i_clk_div.div_q != 8'(expected_divider))
                $fatal(1, "Divider changed during PHY recovery");
            if (!hyper_cs_n[0]) recovery_samples++;
        end
        #1ps;
        if (dut.i_clk_div.div_q != previous_divider) begin
            if (dut.backend_busy || !dut.rst_backend_n)
                $fatal(1, "Actual divider update while backend busy/reset");
            divider_updates++;
        end
        previous_divider = dut.i_clk_div.div_q;
    end

    always @(posedge dut.clk_backend) begin
        if (check_recovery && dut.backend_busy && last_backend_edge != 0 &&
            $time - last_backend_edge != expected_divider * 10ns)
            $fatal(1, "Backend clock period changed during PHY recovery");
        last_backend_edge = $time;
    end

    task automatic reg_write(input logic [31:0] addr, input logic [31:0] data);
        @(negedge clk);
        reg_req = '{addr: addr, write: 1'b1, wdata: data, wstrb: '1, valid: 1'b1};
        do @(posedge clk); while (!reg_rsp.ready);
        if (reg_rsp.error) $fatal(1, "Configuration write failed at %h", addr);
        @(negedge clk);
        reg_req.valid = 0;
    endtask

    task automatic wait_apply_idle;
        wait (!dut.frontend_drain);
        @(negedge clk);
    endtask

    task automatic drive_write(input bit align_phase, input time target_phase,
                               output time launch_phase);
        // Match W acceptance phase; WREADY depends on accepted AW in this path.
        @(negedge clk);
        axi_req.aw = '0;
        axi_req.aw.addr = 32'h8000_0100;
        axi_req.aw.size = 3;
        axi_req.aw.burst = axi_pkg::BURST_INCR;
        axi_req.aw.id = 3'd3;
        axi_req.aw_valid = 1;
        do @(posedge clk); while (!axi_rsp.aw_ready);
        @(negedge clk);
        axi_req.aw_valid = 0;
        do begin
            @(negedge clk);
            launch_phase = $time - last_backend_edge;
        end while ((align_phase && launch_phase != target_phase) ||
                   !axi_rsp.w_ready);
        axi_req.w = '0;
        axi_req.w.data = 64'h1234_5678_9abc_def0;
        axi_req.w.strb = '1;
        axi_req.w.last = 1;
        axi_req.w_valid = 1;
        do @(posedge clk); while (!axi_rsp.w_ready);
        @(negedge clk);
        axi_req.w_valid = 0;
    endtask

    task automatic measure_normal_b_latency(output int latency, output time launch_phase,
                                             output time backend_phase);
        axi_req.b_ready = 0;
        latency_armed = 1;
        pending_latency_case = 0;
        w_accepted_for_latency = 0;
        bvalid_latency_seen = 0;
        drive_write(0, '0, launch_phase);
        wait (axi_rsp.b_valid);
        wait (bvalid_latency_seen);
        #1ps;
        if (!bvalid_latency_seen)
            $fatal(1, "Normal BVALID latency measurement was not observed");
        latency = bvalid_latency;
        backend_phase = w_backend_phase;
        axi_req.b_ready = 1;
        @(posedge clk);
        @(negedge clk);
        axi_req.b_ready = 0;
        latency_armed = 0;
        pending_latency_case = 0;
        wait (!dut.backend_busy);
        @(negedge clk);
    endtask

    task automatic run_divider_change(input int from_divider, input int to_divider,
                                      input int baseline_latency, input time baseline_launch_phase,
                                      input time baseline_accept_phase);
        int responses_before;
        time pending_launch_phase;
        responses_before = b_responses;
        expected_divider = from_divider;
        recovery_samples = 0;
        check_recovery = 0;
        reg_write(32'h200, 32'(to_divider));

        // Both cases use the same write, backend phase, and B backpressure.
        axi_req.b_ready = 0;
        latency_armed = 1;
        pending_latency_case = 1;
        w_accepted_for_latency = 0;
        bvalid_latency_seen = 0;
        drive_write(1, baseline_launch_phase, pending_launch_phase);
        reg_write(32'h00c, 32'h2);

        wait (axi_rsp.b_valid);
        wait (bvalid_latency_seen);
        #1ps;
        if (!bvalid_latency_seen || bvalid_latency != baseline_latency ||
            w_backend_phase != baseline_accept_phase ||
            pending_launch_phase != baseline_launch_phase)
            $fatal(1, "BVALID latency/phase mismatch: pending=%0d baseline=%0d observed=%0d phase=%0t baseline_phase=%0t",
                !bvalid_latency_seen, baseline_latency, bvalid_latency,
                w_backend_phase, baseline_accept_phase);
        @(negedge clk);
        if (!dut.frontend_drain || !dut.backend_busy || hyper_cs_n[0])
            $fatal(1, "APPLY/B did not overlap long final CS hold");
        if (axi_rsp.b.id != 3'd3 || axi_rsp.b.resp != axi_pkg::RESP_OKAY)
            $fatal(1, "Write response incorrect");
        check_recovery = 1;
        axi_req.b_ready = 1;
        @(posedge clk);
        if (!axi_rsp.b_valid) $fatal(1, "Write response was gated by divider guard");
        @(negedge clk);
        axi_req.b_ready = 0;

        // Frontend idle precedes PHY idle: the pending clock request must wait.
        wait (dut.frontend_clock_div_apply_valid);
        @(negedge clk);
        if (!dut.host_idle || dut.midend_trans_active || !dut.backend_busy ||
            dut.clock_div_req_valid)
            $fatal(1, "Clock barrier did not wait for backend recovery after B");
        wait_apply_idle();
        check_recovery = 0;
        latency_armed = 0;
        pending_latency_case = 0;
        if (dut.i_clk_div.div_q != 8'(to_divider) ||
            b_responses != responses_before + 1 ||
            recovery_samples == 0)
            $fatal(1, "Divider APPLY/recovery/B latency check failed: div=%0d/%0d responses=%0d/%0d recovery=%0d latency=%0d baseline=%0d",
                dut.i_clk_div.div_q, to_divider, b_responses-responses_before,
                1, recovery_samples, bvalid_latency, baseline_latency);
        $display("[ISO-DIV] %0d -> %0d: W-to-BVALID cycles=%0d baseline=%0d, CS-active recovery samples=%0d passed",
                 from_divider, to_divider, bvalid_latency, baseline_latency, recovery_samples);
    endtask

    initial begin
        int normal_b_latency;
        time normal_launch_phase, normal_backend_phase;
        axi_req = '0;
        reg_req = '0;
        previous_divider = 8'd8;
        cycle_count = 0;
        w_accept_cycle = 0;
        bvalid_latency = 0;
        latency_armed = 0;
        w_accepted_for_latency = 0;
        bvalid_latency_seen = 0;
        repeat (4) @(negedge clk);
        rst_n = 1;
        wait (dut.frontend_clock_div_apply_valid);
        @(negedge clk);
        if (!dut.backend_busy || !dut.backend_busy_sys || dut.clock_div_req_valid)
            $fatal(1, "Startup APPLY was not blocked by PHY startup/reset");
        wait_apply_idle();
        if (dut.i_clk_div.div_q != 8'd8 || dut.backend_busy)
            $fatal(1, "Startup APPLY did not finish at default divider");
        $display("[ISO-DIV] startup APPLY passed");

        reg_write(32'h400, 32'h8000_0000);
        reg_write(32'h404, 32'h8100_0000);
        reg_write(32'h414, 32'h0000_0f0f); // Long final CS hold and recovery.
        reg_write(32'h00c, 32'h2);
        wait_apply_idle();
        measure_normal_b_latency(normal_b_latency, normal_launch_phase, normal_backend_phase);
        $display("[ISO-DIV] normal W-to-BVALID latency at divider 8=%0d cycles phase=%0t/%0t",
            normal_b_latency, normal_launch_phase, normal_backend_phase);
        run_divider_change(8, 2, normal_b_latency, normal_launch_phase, normal_backend_phase);
        measure_normal_b_latency(normal_b_latency, normal_launch_phase, normal_backend_phase);
        $display("[ISO-DIV] normal W-to-BVALID latency at divider 2=%0d cycles phase=%0t/%0t",
            normal_b_latency, normal_launch_phase, normal_backend_phase);
        run_divider_change(2, 8, normal_b_latency, normal_launch_phase, normal_backend_phase);
        if (divider_updates != 2) $fatal(1, "Unexpected divider update count");
        $display("[ISO-DIV] all checks passed");
        $finish;
    end

    initial begin
        #200us;
        $fatal(1, "Isochronous clock-divider regression timed out");
    end
endmodule
