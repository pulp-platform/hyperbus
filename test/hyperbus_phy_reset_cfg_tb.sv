// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

`timescale 1ns/1ps
`include "axi/typedef.svh"
`include "register_interface/typedef.svh"

module hyperbus_phy_reset_cfg_tb #(
    parameter int unsigned CdcSyncStages = 3,
    parameter int unsigned NumPhys = 2
);
    typedef logic [31:0] axi_addr_t;
    typedef logic [63:0] axi_data_t;
    typedef logic [7:0] axi_strb_t;
    typedef logic [2:0] axi_id_t;
    typedef logic [0:0] axi_user_t;
    `AXI_TYPEDEF_ALL(axi, axi_addr_t, axi_id_t, axi_data_t, axi_strb_t, axi_user_t)
    `REG_BUS_TYPEDEF_REQ(reg_req_t, logic [31:0], logic [31:0], logic [3:0])
    `REG_BUS_TYPEDEF_RSP(reg_rsp_t, logic [31:0])
    typedef struct packed {
        logic [31:0] start_addr;
        logic [31:0] end_addr;
        logic [2:0] idx;
    } rule_t;

    logic clk_sys = 0, clk_phy = 0;
    logic rst_sys_n = 0, rst_phy_n = 0;
    axi_req_t axi_req;
    axi_resp_t axi_rsp;
    reg_req_t reg_req;
    reg_rsp_t reg_rsp;
    int unsigned backend_apply_count, source_apply_count, source_done_count;
    int unsigned ar_accept_count, aw_accept_count, w_accept_count;
    int unsigned r_response_count, b_response_count;
    logic replay_check;
    logic replay_saw_sync_low;
    int unsigned replay_done_target;
    logic cfg_apply_stalled;
    logic reg_stalled;
    reg_req_t reg_stall_payload;
    hyperbus_pkg::phy_cfg_t cfg_apply_stall_payload;
    hyperbus_pkg::phy_cfg_t replay_expected_phy;
    hyperbus_pkg::frontend_cfg_t replay_expected_frontend;

    always #5ns clk_sys = ~clk_sys;
    always #3.5ns clk_phy = ~clk_phy;

    hyperbus_asynchronous #(
        .NumPhys(NumPhys), .AxiAddrWidth(32), .AxiDataWidth(64),
        .AxiIdWidth(3), .AxiUserWidth(1),
        .axi_req_t(axi_req_t), .axi_rsp_t(axi_resp_t),
        .RegDataWidth(32), .RegAddrWidth(32),
        .reg_req_t(reg_req_t), .reg_rsp_t(reg_rsp_t), .axi_rule_t(rule_t),
        .PhyStartupCycles(24), .CdcSyncStages(CdcSyncStages),
        .RxFifoLogDepth($clog2(2*CdcSyncStages + 1)),
        .TxFifoLogDepth($clog2(2*CdcSyncStages + 1))
    ) dut (
        .clk_sys_i(clk_sys), .rst_sys_ni(rst_sys_n),
        .clk_phy_i(clk_phy), .rst_phy_ni(rst_phy_n), .test_mode_i(1'b0),
        .axi_req_i(axi_req), .axi_rsp_o(axi_rsp),
        .reg_req_i(reg_req), .reg_rsp_o(reg_rsp),
        .hyper_cs_no(), .hyper_ck_o(), .hyper_ck_no(),
        .hyper_rwds_o(), .hyper_rwds_i('0), .hyper_rwds_oe_o(),
        .hyper_dq_i('0), .hyper_dq_o(), .hyper_dq_oe_o(), .hyper_reset_no()
    );

    always @(posedge clk_phy) begin
        if (rst_sys_n && dut.backend_cfg_apply_valid && dut.backend_cfg_apply_ready)
            backend_apply_count++;
    end

    always @(posedge clk_sys) begin
        if (!rst_sys_n) begin
            cfg_apply_stalled = 1'b0;
            reg_stalled = 1'b0;
        end else begin
            if (reg_stalled && reg_req !== reg_stall_payload)
                $fatal(1, "Regbus producer changed a stalled request");
            reg_stalled = reg_req.valid && !reg_rsp.ready;
            if (reg_stalled) reg_stall_payload = reg_req;
            if ((!dut.phy_reset_sys_n || !dut.i_cfg_frontend.phy_ready_sync) &&
                dut.frontend_cfg_apply_valid)
                $fatal(1, "configuration valid asserted while PHY reset was not ready");
            if (replay_check && !dut.i_cfg_frontend.phy_ready_sync)
                replay_saw_sync_low = 1'b1;
            if (replay_check && dut.frontend_cfg_apply_valid &&
                (!replay_saw_sync_low || dut.frontend_cfg_apply != replay_expected_phy))
                $fatal(1, "replay transfer preceded synchronized reset or selected staged edits");
            if (cfg_apply_stalled &&
                (!dut.frontend_cfg_apply_valid ||
                 dut.frontend_cfg_apply !== cfg_apply_stall_payload))
                $fatal(1, "PHY configuration payload changed while valid was stalled");
            cfg_apply_stalled = dut.frontend_cfg_apply_valid &&
                                !dut.frontend_cfg_apply_ready;
            if (cfg_apply_stalled)
                cfg_apply_stall_payload = dut.frontend_cfg_apply;
            if (dut.frontend_cfg_apply_valid && dut.frontend_cfg_apply_ready)
                source_apply_count++;
            if (dut.frontend_cfg_apply_done) begin
                source_done_count++;
            end
            if (replay_check &&
                ((axi_req.ar_valid && axi_rsp.ar_ready) ||
                 (axi_req.aw_valid && axi_rsp.aw_ready)) &&
                (dut.i_backend.cfg_q != replay_expected_phy ||
                 dut.frontend_cfg != replay_expected_frontend))
                $fatal(1, "AXI admitted before last-applied configuration was effective");
            if (axi_req.ar_valid && axi_rsp.ar_ready) ar_accept_count++;
            if (axi_req.aw_valid && axi_rsp.aw_ready) aw_accept_count++;
            if (axi_req.w_valid && axi_rsp.w_ready) w_accept_count++;
            if (axi_rsp.b_valid && axi_req.b_ready) begin
                b_response_count++;
                if (axi_rsp.b.resp != axi_pkg::RESP_DECERR)
                    $fatal(1, "unmapped write did not return a DECERR response");
            end
            if (axi_rsp.r_valid && axi_req.r_ready) begin
                r_response_count++;
                if (axi_rsp.r.resp != axi_pkg::RESP_DECERR || !axi_rsp.r.last)
                    $fatal(1, "unmapped read did not return one DECERR response");
            end
        end
    end

    always @(negedge clk_sys) begin
        if (rst_sys_n && replay_check && source_done_count < replay_done_target &&
            !dut.frontend_drain)
            $fatal(1, "admission reopened before PHY-reset replay completion");
    end

    task automatic reg_access(input bit write, input logic [31:0] addr,
                              input logic [31:0] wdata, output logic [31:0] rdata);
        @(negedge clk_sys);
        reg_req = '{addr: addr, write: write, wdata: wdata, wstrb: 4'hf, valid: 1'b1};
        do @(posedge clk_sys); while (!reg_rsp.ready);
        if (reg_rsp.error) $fatal(1, "register access failed at %h", addr);
        rdata = reg_rsp.rdata;
        @(negedge clk_sys);
        reg_req.valid = 1'b0;
    endtask

    task automatic apply_then_stage_write(input logic [31:0] addr,
                                          input logic [31:0] value);
        @(negedge clk_sys);
        reg_req = '{addr: 32'h00c, write: 1'b1, wdata: 32'h2,
                    wstrb: 4'hf, valid: 1'b1};
        do @(posedge clk_sys); while (!reg_rsp.ready);
        // Keep the next APB request valid across command acknowledgement.
        @(negedge clk_sys);
        reg_req = '{addr: addr, write: 1'b1, wdata: value,
                    wstrb: 4'hf, valid: 1'b1};
        @(posedge clk_sys);
        if (reg_rsp.ready)
            $fatal(1, "back-to-back staged write was admitted before APPLY barrier");
        do @(posedge clk_sys); while (!reg_rsp.ready);
        if (reg_rsp.error) $fatal(1, "staged write failed at %h", addr);
        @(negedge clk_sys);
        reg_req.valid = 1'b0;
    endtask

    task automatic wait_idle;
        for (int unsigned i = 0; i < 300; i++) begin
            @(negedge clk_sys);
            if (!dut.frontend_drain && !dut.backend_busy && dut.host_idle &&
                !dut.midend_trans_active) return;
        end
        $fatal(1, "configuration/backend did not become idle");
    endtask

    task automatic reset_and_replay(input hyperbus_pkg::phy_cfg_t expected_phy,
                                   input hyperbus_pkg::frontend_cfg_t expected_frontend,
                                   input realtime reset_phase, input realtime reset_width,
                                   input bit require_held_reset_checks = 1'b0);
        int unsigned old_done_count, old_source_count, old_backend_count;
        int unsigned old_ar_count, old_aw_count, old_w_count;
        int unsigned old_r_count, old_b_count;
        bit ar_accepted, aw_accepted, w_accepted;
        bit csr_saw_blocked;
        logic [31:0] status;
        realtime reset_phase_start, reset_asserted_at;
        old_done_count = source_done_count;
        old_source_count = source_apply_count;
        old_backend_count = backend_apply_count;
        old_ar_count = ar_accept_count;
        old_aw_count = aw_accept_count;
        old_w_count = w_accept_count;
        old_r_count = r_response_count;
        old_b_count = b_response_count;
        ar_accepted = 0;
        aw_accepted = 0;
        w_accepted = 0;
        csr_saw_blocked = 0;
        replay_saw_sync_low = 1'b0;
        replay_done_target = old_done_count + 1;
        replay_expected_phy = expected_phy;
        replay_expected_frontend = expected_frontend;

        // Sweep both sides of the sampling edge; short pulses rely on rstgen's
        // existing stretch. This checks logic, not physical metastability.
        if (reset_phase == 5ns)
            $fatal(1, "Reset phase rounded onto system sampling edge");
        @(negedge clk_sys);
        reset_phase_start = $realtime;
        #(reset_phase);
        reset_asserted_at = $realtime;
        if ((reset_asserted_at - reset_phase_start < reset_phase - 1ps) ||
            (reset_asserted_at - reset_phase_start > reset_phase + 1ps))
            $fatal(1, "reset assertion phase was rounded");
        $display("RESET_ASSERT time_ns=%0.3f phase_ns=%0.3f width_ns=%0.3f",
            reset_asserted_at, reset_asserted_at - reset_phase_start, reset_width);
        if (reg_req.valid)
            $fatal(1, "PHY-only reset requires an idle Regbus producer");
        rst_phy_n = 1'b0;
        replay_check = 1'b1;
        fork
            begin
                // Pulse width is independent of request-driver scheduling.
                #(reset_width);
                rst_phy_n = 1'b1;
                if (($realtime - reset_asserted_at < reset_width - 1ps) ||
                    ($realtime - reset_asserted_at > reset_width + 1ps))
                    $fatal(1, "reset pulse width was rounded");
                $display("RESET_RELEASE time_ns=%0.3f width_ns=%0.3f",
                    $realtime, $realtime - reset_asserted_at);
                #100ps;
                if (reset_width < 10ns &&
                    (dut.phy_reset_sys_n || !dut.frontend_drain))
                    $fatal(1, "short reset was not stretched in the system domain");
            end
            begin
                #100ps;
                if (!dut.frontend_drain || dut.phy_reset_sys_n)
                    $fatal(1, "PHY reset did not assert the immediate drain gate");
                if (dut.frontend_cfg != expected_frontend)
                    $fatal(1, "PHY reset changed the applied frontend configuration");
                // The only asynchronous request offer deliberately precedes the
                // next sampling edge and stays unchanged through acknowledgement.
                reg_req = '{addr: 32'h010, write: 1'b0, wdata: '0,
                            wstrb: 4'hf, valid: 1'b1};
                if (!dut.i_cfg_frontend.reset_entry_pending)
                    $fatal(1, "STATUS offer missed the reset-entry guard");
                // Poll from the raw assertion interval. Entry must stall rather
                // than acknowledge the old registered BUSY=0 as completion.
                do begin
                    @(posedge clk_sys);
                    if (dut.i_cfg_frontend.reset_entry_pending && reg_rsp.ready)
                        $fatal(1, "STATUS acknowledged during reset-entry guard");
                end while (!reg_rsp.ready);
                status = reg_rsp.rdata;
                if (reg_rsp.error || !status[1] || !status[2] || !status[0])
                    $fatal(1, "first reset STATUS did not report busy/dirty/sticky error: %h", status);
                @(negedge clk_sys);
                reg_req.valid = 1'b0;
                reg_access(1, 32'h010, 32'h1, status);
                if (require_held_reset_checks && rst_phy_n)
                    $fatal(1, "long-reset W1C did not complete while external reset was held");
                reg_access(0, 32'h010, 0, status);
                // BUSY may already be clear if replay completed quickly. AXI
                // remains withheld so it cannot set sticky error after W1C.
                if (status[0] || !status[2])
                    $fatal(1, "STATUS W1C failed through reset barrier: %h", status);
                if (require_held_reset_checks) begin
                    if (rst_phy_n || !status[1])
                        $fatal(1, "long-reset STATUS checks outlasted external reset");
                    $display("HELD_RESET_W1C time_ns=%0.3f", $realtime);
                end
                fork
                    begin
                        // A legal non-STATUS read must survive the replay barrier.
                        @(negedge clk_sys);
                        reg_req = '{addr: 32'h300, write: 1'b0, wdata: '0,
                                    wstrb: 4'hf, valid: 1'b1};
                        do begin
                            @(posedge clk_sys);
                            if (!reg_rsp.ready) csr_saw_blocked = 1'b1;
                            if (reg_rsp.ready && source_done_count < replay_done_target)
                                $fatal(1, "non-STATUS read admitted before replay completion");
                        end while (!reg_rsp.ready);
                        if (reg_rsp.error || reg_rsp.rdata != 32'h13)
                            $fatal(1, "held non-STATUS read did not preserve staged edits");
                        if (require_held_reset_checks && !csr_saw_blocked)
                            $fatal(1, "long-reset non-STATUS read was never blocked");
                        @(negedge clk_sys);
                        reg_req.valid = 1'b0;
                    end
                    begin
                        @(negedge clk_sys);
                        axi_req.ar.addr = 32'h8000_0000; // Outside every chip range.
                        axi_req.ar.size = 3'd3;
                        axi_req.ar.burst = axi_pkg::BURST_INCR;
                        axi_req.ar_valid = 1'b1;
                        axi_req.aw.addr = 32'h8000_0008;
                        axi_req.aw.id = 3'd1;
                        axi_req.aw.size = 3'd3;
                        axi_req.aw.burst = axi_pkg::BURST_INCR;
                        axi_req.aw_valid = 1'b1;
                        axi_req.w.data = 64'h0123_4567_89ab_cdef;
                        axi_req.w.strb = '1;
                        axi_req.w.last = 1'b1;
                        axi_req.w_valid = 1'b1;
                        while (!ar_accepted || !aw_accepted || !w_accepted) begin
                            @(posedge clk_sys);
                            ar_accepted |= axi_req.ar_valid && axi_rsp.ar_ready;
                            aw_accepted |= axi_req.aw_valid && axi_rsp.aw_ready;
                            w_accepted |= axi_req.w_valid && axi_rsp.w_ready;
                            @(negedge clk_sys);
                            axi_req.ar_valid = !ar_accepted;
                            axi_req.aw_valid = !aw_accepted;
                            axi_req.w_valid = !w_accepted;
                        end
                    end
                join
            end
        join
        wait_idle();
        replay_check = 1'b0;
        if (!replay_saw_sync_low || source_done_count < old_done_count + 1 ||
            source_apply_count < old_source_count + 1 ||
            backend_apply_count < old_backend_count + 1)
            $fatal(1, "reset did not observe synchronized low and complete applied-image replay");
        if (ar_accept_count != old_ar_count + 1 || aw_accept_count != old_aw_count + 1 ||
            w_accept_count != old_w_count + 1 || r_response_count != old_r_count + 1 ||
            b_response_count != old_b_count + 1)
            $fatal(1, "held AXI count mismatch AR=%0d AW=%0d W=%0d R=%0d B=%0d",
                ar_accept_count-old_ar_count, aw_accept_count-old_aw_count,
                w_accept_count-old_w_count, r_response_count-old_r_count,
                b_response_count-old_b_count);
        if (dut.i_backend.cfg_q != expected_phy || dut.frontend_cfg != expected_frontend)
            $fatal(1, "replay did not restore the exact last applied configuration");
        reg_access(0, 32'h010, 0, status);
        if (status[1] || !status[2]) $fatal(1, "replay changed staged dirty/busy status");
        reg_access(0, 32'h300, 0, status);
        if (status != 32'h13) $fatal(1, "PHY reset changed staged PHY edits");
        reg_access(0, 32'h400, 0, status);
        if (status != 32'h0080_0000) $fatal(1, "PHY reset changed staged frontend edits");
    endtask

    initial begin : stimulus
        logic [31:0] data;
        hyperbus_pkg::phy_cfg_t applied_phy;
        hyperbus_pkg::frontend_cfg_t applied_frontend;
        axi_req = '0;
        axi_req.r_ready = 1'b1;
        axi_req.b_ready = 1'b1;
        reg_req = '0;
        backend_apply_count = 0;
        source_apply_count = 0;
        source_done_count = 0;
        ar_accept_count = 0;
        aw_accept_count = 0;
        w_accept_count = 0;
        r_response_count = 0;
        b_response_count = 0;
        replay_check = 0;
        replay_saw_sync_low = 0;
        replay_done_target = 0;
        cfg_apply_stalled = 0;
        reg_stalled = 0;
        repeat (4) @(negedge clk_sys);
        rst_sys_n = 1'b1;
        // CfgInit must not send configuration while PHY remains held in reset.
        repeat (4) @(negedge clk_sys);
        if (!dut.frontend_drain || dut.frontend_cfg_apply_valid || backend_apply_count)
            $fatal(1, "CfgInit did not wait for PHY reset release");
        rst_phy_n = 1'b1;
        wait_idle();
        if (backend_apply_count < 1 || source_done_count < 1 ||
            dut.i_backend.cfg_q != dut.i_cfg_frontend.staged_phy_cfg ||
            dut.frontend_cfg != dut.i_cfg_frontend.staged_frontend_cfg)
            $fatal(1, "combined-reset default initialization mismatch");

        reg_access(1, 32'h300, 32'h12, data);
        reg_access(1, 32'h40c, 32'h0101_0307, data);
        reg_access(1, 32'h400, 32'h0040_0000, data);
        reg_access(1, 32'h00c, 32'h2, data);
        wait_idle();
        applied_phy = dut.i_backend.cfg_q;
        applied_frontend = dut.frontend_cfg;
        if (applied_phy.phy[0].tx_delay != 8'h12 ||
            !applied_phy.chip[0].keep_dq_driven ||
            applied_frontend.chip[0].range_base != 32'h0040_0000)
            $fatal(1, "nondefault APPLY mismatch tx=%h keep=%b base=%h applies=%0d state=%0d",
                applied_phy.phy[0].tx_delay, applied_phy.chip[0].keep_dq_driven,
                applied_frontend.chip[0].range_base, backend_apply_count,
                dut.i_cfg_frontend.cfg_state_q);

        reg_access(1, 32'h300, 32'h14, data);
        applied_phy.phy[0].tx_delay = 8'h14;
        apply_then_stage_write(32'h300, 32'h13);
        wait_idle();
        if (dut.i_backend.cfg_q != applied_phy || dut.frontend_cfg != applied_frontend)
            $fatal(1, "back-to-back write changed the APPLY snapshot");
        reg_access(0, 32'h300, 0, data);
        if (data != 32'h13)
            $fatal(1, "back-to-back write did not update staged TX delay: %h", data);
        reg_access(0, 32'h010, 0, data);
        if (data[1] || !data[2])
            $fatal(1, "back-to-back write did not leave staged configuration dirty");
        reg_access(1, 32'h400, 32'h0080_0000, data);
        // Establish sticky error before W1C during the first reset barrier.
        @(negedge clk_sys);
        axi_req.ar.addr = 32'h8000_0000;
        axi_req.ar.size = 3'd3;
        axi_req.ar.burst = axi_pkg::BURST_INCR;
        axi_req.ar_valid = 1'b1;
        do @(posedge clk_sys); while (!axi_rsp.ar_ready);
        @(negedge clk_sys);
        axi_req.ar_valid = 1'b0;
        wait_idle();
        reg_access(0, 32'h010, 0, data);
        if (!data[0]) $fatal(1, "unmapped AXI read did not establish sticky error");
        reset_and_replay(applied_phy, applied_frontend, 4.8ns, 1ns);
        reset_and_replay(applied_phy, applied_frontend, 5.2ns, 1ns);
        reset_and_replay(applied_phy, applied_frontend, 4.8ns, 73ns);
        reset_and_replay(applied_phy, applied_frontend, 5.2ns, 73ns);
        reset_and_replay(applied_phy, applied_frontend, 4.8ns, 300ns, 1'b1);

        // Restore staged values and verify a later unchanged APPLY remains correct.
        reg_access(1, 32'h300, 32'h14, data);
        reg_access(1, 32'h400, 32'h0040_0000, data);
        reg_access(1, 32'h00c, 32'h2, data);
        wait_idle();
        reg_access(0, 32'h010, 0, data);
        if (data[2:1] != 0 || dut.i_backend.cfg_q != applied_phy)
            $fatal(1, "unchanged APPLY after replay changed effective configuration");
        $display("PASS: defaults, applied replay, staged preservation, phase-swept short/long reset, STATUS/W1C, held-reset W1C, Regbus stability, CSR blocking, AXI gating");
        $finish;
    end

    initial begin
        #30us;
        $fatal(1, "PHY reset configuration test timed out");
    end
endmodule
