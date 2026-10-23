// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

`include "axi/typedef.svh"
`include "hyperbus/typedef.svh"
`include "common_cells/assertions.svh"

module hyperbus_axi_barrier_tb #(
    parameter int unsigned AxiMaxReadTxns = 4,
    parameter int unsigned AxiMaxWriteTxns = 4,
    parameter int unsigned HostWriteBufferBytes = 64
);
    localparam int unsigned MaxWriteDataBeats = HostWriteBufferBytes / 8;
    typedef logic [31:0] addr_t;
    typedef logic [63:0] data_t;
    typedef logic [7:0] strb_t;
    typedef logic [3:0] id_t;
    typedef logic user_t;
    localparam data_t AtomicReplacement = 64'h0000_0000_d3a5_79e1;
    typedef struct packed {
        addr_t start_addr;
        addr_t end_addr;
        logic [2:0] idx;
    } rule_t;
    typedef struct packed {
        addr_t addr;
        logic write;
        logic [31:0] wdata;
        logic [3:0] wstrb;
        logic valid;
    } reg_req_t;
    typedef struct packed {
        logic [31:0] rdata;
        logic error;
        logic ready;
    } reg_rsp_t;
    `AXI_TYPEDEF_ALL(axi, addr_t, id_t, data_t, strb_t, user_t)
    `HYPERBUS_TYPEDEF_HOST_ALL_CT(host, addr_t, data_t, strb_t)
    `HYPERBUS_TYPEDEF_LINK_ALL_CT(link, 1)

    logic clk = 0;
    logic rst_n = 0;
    axi_req_t axi_req;
    axi_resp_t axi_rsp;
    reg_req_t reg_req;
    reg_rsp_t reg_rsp;
    host_req_t host_req;
    host_rsp_t host_rsp;
    link_req_t link_req;
    link_rsp_t link_rsp;
    hyperbus_pkg::frontend_cfg_t cfg;
    hyperbus_pkg::phy_cfg_t cfg_apply, accepted_cfg;
    rule_t [hyperbus_pkg::HyperNumChips-1:0] rules;
    logic idle, active, decode_error, drain;
    logic cfg_valid, cfg_ready, cfg_done;
    logic apply_pending;
    int unsigned apply_delay, apply_count, cycle;
    byte unsigned memory [128];
    int unsigned aw_count [16], ar_count [16], r_count [16], b_count [16];
    int unsigned aw_goal [16], ar_goal [16], atomic_count [16], atomic_goal [16];
    int unsigned w_count, w_goal, read_peak, write_peak;
    data_t expected_read [16];
    byte unsigned expected_memory [128];
    bit scenario_active, atomic_aw_accepted, late_offers;
    bit queue_apply_tracking;
    logic [4:0] queue_previous_mask, queue_next_mask;
    logic [7:0] queue_next_delay;
    int unsigned atomic_r_baseline, atomic_b_baseline;
    logic [4:0] previous_mask;

    `ASSERT_INIT(TestIdsFit, AxiMaxReadTxns <= 7 && AxiMaxWriteTxns <= 7)
    `ASSERT_INIT(TestMemoryFits, MaxWriteDataBeats <= 14)

    always #5ns clk = ~clk;

    hyperbus_axi_frontend #(
        .AxiDataWidth(64), .AxiAddrWidth(32), .AxiIdWidth(4),
        .AxiUserWidth(1), .AxiMaxReadTxns(AxiMaxReadTxns),
        .AxiMaxWriteTxns(AxiMaxWriteTxns), .MaxWriteDataBeats(MaxWriteDataBeats),
        .axi_req_t(axi_req_t), .axi_rsp_t(axi_resp_t),
        .host_req_t(host_req_t), .host_rsp_t(host_rsp_t)
    ) i_frontend (
        .clk_i(clk), .rst_ni(rst_n), .drain_i(drain), .idle_o(idle),
        .axi_req_i(axi_req), .axi_rsp_o(axi_rsp),
        .host_req_o(host_req), .host_rsp_i(host_rsp)
    );

    hyperbus_cfg_frontend #(
        .NumPhys(1), .RegDataWidth(32), .RegAddrWidth(32),
        .reg_req_t(reg_req_t), .reg_rsp_t(reg_rsp_t), .host_rule_t(rule_t)
    ) i_cfg (
        .clk_i(clk), .rst_ni(rst_n), .phy_reset_ni(rst_n),
        .reg_req_i(reg_req), .reg_rsp_o(reg_rsp),
        .drain_o(drain), .host_idle_i(idle), .trans_active_i(active),
        .cfg_apply_o(cfg_apply), .cfg_apply_valid_o(cfg_valid),
        .cfg_apply_ready_i(cfg_ready), .cfg_apply_done_i(cfg_done),
        .clock_div_apply_o(), .clock_div_apply_valid_o(),
        .clock_div_apply_ready_i(1'b1), .clock_div_apply_done_i(1'b1),
        .frontend_cfg_o(cfg), .chip_rules_o(rules), .decode_error_i(decode_error)
    );

    hyperbus_midend #(
        .HostAddrWidth(32), .HostDataWidth(64), .NumPhys(1),
        .HostWriteBufferBytes(HostWriteBufferBytes), .MaxHostBurstBeats(256),
        .host_cmd_t(host_cmd_t), .host_w_t(host_w_t),
        .host_r_t(host_r_t), .host_wrsp_t(host_wrsp_t),
        .host_req_t(host_req_t), .host_rsp_t(host_rsp_t),
        .hyper_rx_t(link_rx_t), .hyper_tx_t(link_tx_t),
        .hyper_cmd_t(link_cmd_t), .hyper_req_t(link_req_t),
        .hyper_rsp_t(link_rsp_t), .rule_t(rule_t)
    ) i_midend (
        .clk_i(clk), .rst_ni(rst_n),
        .host_link_req_i(host_req), .host_link_rsp_o(host_rsp),
        .frontend_cfg_i(cfg), .chip_rules_i(rules),
        .trans_active_o(active), .decode_error_o(decode_error),
        .hyper_link_req_o(link_req), .hyper_link_rsp_i(link_rsp)
    );

    // A configuration consumer with independent acceptance and completion latency.
    assign cfg_ready = !apply_pending && cycle % 3 == 0;
    always @(posedge clk) begin
        if (!rst_n) begin
            apply_pending <= 0;
            cfg_done <= 0;
            apply_delay <= 0;
            apply_count <= 0;
            accepted_cfg <= '0;
        end else begin
            cfg_done <= 0;
            if (cfg_valid && cfg_ready) begin
                accepted_cfg <= cfg_apply;
                apply_pending <= 1;
                apply_delay <= 3;
                apply_count <= apply_count + 1;
            end else if (apply_pending) begin
                if (apply_delay == 0) begin
                    cfg_done <= 1;
                    apply_pending <= 0;
                end else apply_delay <= apply_delay - 1;
            end
        end
    end

    // Physical addresses are independently interpreted as 16-bit word addresses.
    typedef enum logic [2:0] { BackendIdle, ReadDelay, BackendRead,
        BackendWrite, ResponseDelay, BackendResponse } backend_state_e;
    backend_state_e backend_state;
    int unsigned address, remaining, delay_cycles;
    always_comb begin
        link_rsp = '0;
        link_rsp.cmd_ready = backend_state == BackendIdle && cycle % 4 == 0;
        link_rsp.tx_ready = backend_state == BackendWrite && cycle % 3 != 0;
        link_rsp.rx_valid = backend_state == BackendRead;
        link_rsp.rx.data = {memory[address+1], memory[address]};
        link_rsp.rx.last = remaining == 1;
        link_rsp.wrsp_valid = backend_state == BackendResponse;
    end
    always @(posedge clk) begin
        if (!rst_n) begin
            cycle <= 0;
            backend_state <= BackendIdle;
            address <= 0;
            remaining <= 0;
            delay_cycles <= 0;
        end else begin
            cycle <= cycle + 1;
            case (backend_state)
                BackendIdle: if (link_req.cmd_valid && link_rsp.cmd_ready) begin
                    if (link_req.cmd.cs != 1 || !link_req.cmd.trans.burst_type ||
                        int'(link_req.cmd.trans.address)*2 +
                        int'(link_req.cmd.trans.burst)*2 > 128)
                        $fatal(1, "Physical command outside the independent memory model");
                    address <= int'(link_req.cmd.trans.address)*2;
                    remaining <= int'(link_req.cmd.trans.burst);
                    delay_cycles <= 2;
                    backend_state <= link_req.cmd.trans.write ? BackendWrite : ReadDelay;
                end
                ReadDelay: if (delay_cycles == 0) backend_state <= BackendRead;
                           else delay_cycles <= delay_cycles - 1;
                BackendRead: if (link_req.rx_ready) begin
                    address <= address + 2;
                    remaining <= remaining - 1;
                    delay_cycles <= cycle % 3;
                    backend_state <= remaining == 1 ? BackendIdle : ReadDelay;
                end
                BackendWrite: if (link_req.tx_valid && link_rsp.tx_ready) begin
                    for (int lane = 0; lane < 2; lane++)
                        if (link_req.tx.strb[lane])
                            memory[address+lane] <= link_req.tx.data[lane*8 +: 8];
                    if (link_req.tx.last != (remaining == 1))
                        $fatal(1, "Physical write LAST mismatch");
                    address <= address + 2;
                    remaining <= remaining - 1;
                    if (remaining == 1) begin
                        delay_cycles <= 3;
                        backend_state <= ResponseDelay;
                    end
                end
                ResponseDelay: if (delay_cycles == 0) backend_state <= BackendResponse;
                               else delay_cycles <= delay_cycles - 1;
                BackendResponse: if (link_req.wrsp_ready) backend_state <= BackendIdle;
                default: $fatal(1, "Invalid independent backend state");
            endcase
        end
    end

    // Check presentation as well as acceptance: an unaccepted atomic must not
    // create a neutral command or acquire a response ID in the serializer.
    always @(posedge clk) begin
        int unsigned read_pending, write_pending;
        bit all_responses_complete;
        if (!rst_n) begin
            w_count = 0;
            read_peak = 0;
            write_peak = 0;
            for (int id = 0; id < 16; id++) begin
                aw_count[id] = 0;
                ar_count[id] = 0;
                atomic_count[id] = 0;
                r_count[id] = 0;
                b_count[id] = 0;
            end
        end else begin
            if (scenario_active && !atomic_aw_accepted &&
                ((host_req.cmd_valid && host_req.cmd.atomic_op != hyperbus_pkg::HyperAtomicNone) ||
                 (axi_rsp.r_valid && axi_rsp.r.id == 5) ||
                 (axi_rsp.b_valid && axi_rsp.b.id == 5)))
                $fatal(1, "Atomic command or response preceded external AW acceptance");
            if (late_offers && drain &&
                ((axi_req.ar_valid && axi_rsp.ar_ready) ||
                 (axi_req.aw_valid && axi_rsp.aw_ready) ||
                 (axi_req.w_valid && axi_rsp.w_ready)))
                $fatal(1, "Barrier accepted an offer first presented after drain");
            if (scenario_active && (cfg_valid || cfg.chip[0].address_mask_msb != previous_mask) &&
                (r_count[5] != atomic_r_baseline + 1 ||
                 b_count[5] != atomic_b_baseline + 1))
                $fatal(1, "APPLY changed effective settings before atomic completion");
            if (axi_req.aw_valid && axi_rsp.aw_ready) begin
                aw_count[axi_req.aw.id]++;
                if (axi_req.aw.atop[axi_pkg::ATOP_R_RESP]) atomic_count[axi_req.aw.id]++;
                if (scenario_active && axi_req.aw.id == 5) atomic_aw_accepted = 1;
                if (aw_count[axi_req.aw.id] > aw_goal[axi_req.aw.id])
                    $fatal(1, "Unexpected accepted AW ID=%0d", axi_req.aw.id);
            end
            if (axi_req.ar_valid && axi_rsp.ar_ready) begin
                ar_count[axi_req.ar.id]++;
                if (ar_count[axi_req.ar.id] > ar_goal[axi_req.ar.id])
                    $fatal(1, "Unexpected accepted AR ID=%0d", axi_req.ar.id);
            end
            if (axi_req.w_valid && axi_rsp.w_ready) begin
                w_count++;
                if (w_count > w_goal) $fatal(1, "Unexpected accepted W beat");
            end
            if (axi_rsp.r_valid && axi_req.r_ready) begin
                r_count[axi_rsp.r.id]++;
                if (!axi_rsp.r.last || axi_rsp.r.resp != axi_pkg::RESP_OKAY ||
                    (scenario_active && axi_rsp.r.id == 5 ?
                        axi_rsp.r.data[31:0] != expected_read[5][31:0] :
                        axi_rsp.r.data != expected_read[axi_rsp.r.id]) ||
                    r_count[axi_rsp.r.id] > ar_count[axi_rsp.r.id] + atomic_count[axi_rsp.r.id])
                    $fatal(1, "Unexpected, duplicate or corrupted R response ID=%0d", axi_rsp.r.id);
            end
            if (axi_rsp.b_valid && axi_req.b_ready) begin
                b_count[axi_rsp.b.id]++;
                if (axi_rsp.b.resp != axi_pkg::RESP_OKAY ||
                    b_count[axi_rsp.b.id] > aw_count[axi_rsp.b.id])
                    $fatal(1, "Unexpected or duplicate B response ID=%0d", axi_rsp.b.id);
            end
            read_pending = 0;
            write_pending = 0;
            all_responses_complete = 1;
            for (int id = 0; id < 16; id++) begin
                read_pending += ar_count[id] + atomic_count[id] - r_count[id];
                write_pending += aw_count[id] - b_count[id];
                if (r_count[id] != ar_goal[id] + atomic_goal[id] || b_count[id] != aw_goal[id])
                    all_responses_complete = 0;
            end
            if (read_pending > AxiMaxReadTxns || write_pending > AxiMaxWriteTxns)
                $fatal(1, "External outstanding limit exceeded: R=%0d/%0d W=%0d/%0d",
                    read_pending, AxiMaxReadTxns, write_pending, AxiMaxWriteTxns);
            if (read_pending > read_peak) read_peak = read_pending;
            if (write_pending > write_peak) write_peak = write_pending;
            if (queue_apply_tracking && !all_responses_complete &&
                (cfg_valid || cfg.chip[0].address_mask_msb != queue_previous_mask))
                $fatal(1, "Queue APPLY preceded completion of all held/accepted requests");
        end
    end

    `ASSERT(AwProducerStable, axi_req.aw_valid && !axi_rsp.aw_ready |=>
        axi_req.aw_valid && $stable(axi_req.aw), clk, !rst_n)
    `ASSERT(WProducerStable, axi_req.w_valid && !axi_rsp.w_ready |=>
        axi_req.w_valid && $stable(axi_req.w), clk, !rst_n)
    `ASSERT(ArProducerStable, axi_req.ar_valid && !axi_rsp.ar_ready |=>
        axi_req.ar_valid && $stable(axi_req.ar), clk, !rst_n)
    `ASSERT(RegProducerStable, reg_req.valid && !reg_rsp.ready |=>
        reg_req.valid && $stable(reg_req), clk, !rst_n)
    `ASSERT(RResponseStable, axi_rsp.r_valid && !axi_req.r_ready |=>
        axi_rsp.r_valid && $stable(axi_rsp.r), clk, !rst_n)
    `ASSERT(BResponseStable, axi_rsp.b_valid && !axi_req.b_ready |=>
        axi_rsp.b_valid && $stable(axi_rsp.b), clk, !rst_n)
    `ASSERT(CfgProducerStable, cfg_valid && !cfg_ready |=>
        cfg_valid && $stable(cfg_apply), clk, !rst_n)

    task automatic reg_write(input addr_t addr, input logic [31:0] data);
        @(negedge clk);
        reg_req = '{addr: addr, write: 1'b1, wdata: data, wstrb: 4'hf, valid: 1'b1};
        do @(posedge clk); while (!reg_rsp.ready);
        if (reg_rsp.error) $fatal(1, "CSR write failed at %h", addr);
        @(negedge clk);
        reg_req.valid = 0;
    endtask

    task automatic send_aw;
        axi_req.aw_valid = 1;
        do @(posedge clk); while (!axi_rsp.aw_ready);
        @(negedge clk);
        axi_req.aw_valid = 0;
    endtask
    task automatic send_w;
        axi_req.w_valid = 1;
        do @(posedge clk); while (!axi_rsp.w_ready);
        @(negedge clk);
        axi_req.w_valid = 0;
    endtask
    task automatic send_ar;
        axi_req.ar_valid = 1;
        do @(posedge clk); while (!axi_rsp.ar_ready);
        @(negedge clk);
        axi_req.ar_valid = 0;
    endtask

    // w_order: 0 = AW before W, 1 = accepted early W, 2 = parallel AW/W.
    task automatic check_barrier(input bit apply_command, input int unsigned w_order);
        byte unsigned original [128];
        int unsigned before_aw5, before_aw7, before_ar1, before_ar6;
        int unsigned before_r1, before_r6, before_b7, before_w, before_apply;
        logic [4:0] next_mask;
        logic [7:0] next_delay;
        bit aw_done, w_done, exposed_unaccepted_aw;
        data_t late_write;
        @(negedge clk);
        previous_mask = cfg.chip[0].address_mask_msb;
        next_mask = previous_mask == 7 ? 8 : 7;
        next_delay = accepted_cfg.phy[0].tx_delay + 1;
        if (apply_command) begin
            reg_write('h408, 32'h0001_0000 | (32'(next_mask) << 8));
            reg_write('h300, 32'(next_delay));
            if (cfg.chip[0].address_mask_msb != previous_mask)
                $fatal(1, "Staging changed the effective frontend setting");
        end
        @(negedge clk);
        for (int i = 0; i < 128; i++) begin
            original[i] = 8'(32'h31 + 13*i + 7*w_order + int'(apply_command));
            memory[i] = original[i];
        end
        expected_read[1] = '0;
        for (int lane = 0; lane < 8; lane++)
            expected_read[1][lane*8 +: 8] = original[32+lane];
        expected_read[6] = expected_read[1];
        expected_read[5] = '0;
        for (int lane = 0; lane < 4; lane++)
            expected_read[5][lane*8 +: 8] = original[lane];
        late_write = 64'h7591_23de_4ca8_b60f;
        before_aw5 = aw_count[5];
        before_aw7 = aw_count[7];
        before_ar1 = ar_count[1];
        before_ar6 = ar_count[6];
        before_r1 = r_count[1];
        before_r6 = r_count[6];
        atomic_r_baseline = r_count[5];
        atomic_b_baseline = b_count[5];
        before_b7 = b_count[7];
        before_w = w_count;
        before_apply = apply_count;
        aw_goal[5]++;
        aw_goal[7]++;
        ar_goal[1]++;
        ar_goal[6]++;
        atomic_goal[5]++;
        w_goal += 2;
        atomic_aw_accepted = 0;
        scenario_active = 1;
        late_offers = 0;
        axi_req.ar = '0;
        axi_req.ar.addr = 32'h8000_0020;
        axi_req.ar.id = 1;
        axi_req.ar.size = 3;
        axi_req.ar.burst = axi_pkg::BURST_INCR;
        send_ar();
        wait (axi_rsp.r_valid);
        @(negedge clk);
        if (axi_rsp.r.id != 1) $fatal(1, "Missing ordinary R drain precondition");
        axi_req.aw = '0;
        axi_req.aw.addr = 32'h8000_0000;
        axi_req.aw.id = 5;
        axi_req.aw.size = 2;
        axi_req.aw.burst = axi_pkg::BURST_INCR;
        axi_req.aw.atop = axi_pkg::ATOP_ATOMICSWAP;
        axi_req.w = '{data: AtomicReplacement, strb: 8'h0f, last: 1'b1, user: '0};
        aw_done = 0;
        w_done = 0;
        exposed_unaccepted_aw = 0;
        if (w_order == 1) begin
            send_w();
            w_done = 1;
            if (w_count != before_w + 1)
                $fatal(1, "Early-W scenario did not accept W before AW");
        end
        fork
            begin send_aw(); aw_done = 1; end
            begin
                if (w_order == 2) begin send_w(); w_done = 1; end
            end
            begin
                // This observation establishes serializer exposure, not a state
                // encoding or a required number of internal microtransactions.
                do @(posedge clk); while (!(i_frontend.ser_in_req.aw_valid &&
                                            !axi_rsp.aw_ready && !drain));
                exposed_unaccepted_aw = 1;
                reg_write('hc, apply_command ? 32'h2 : 32'h1);
                if (!drain || atomic_aw_accepted)
                    $fatal(1, "CSR command missed the pre-acceptance AW barrier window");
                repeat (3) begin
                    @(negedge clk);
                    if (!drain || !axi_rsp.r_valid || axi_rsp.r.id != 1)
                        $fatal(1, "Barrier did not retain the older stalled R response");
                end
                axi_req.r_ready = 1;
                do @(posedge clk); while (!(axi_rsp.r_valid && axi_rsp.r.id == 1));
                @(negedge clk);
                axi_req.r_ready = 0;
                wait (aw_done);
                if (w_order == 0) begin send_w(); w_done = 1; end
                wait (w_done);
                wait (axi_rsp.r_valid && axi_rsp.r.id == 5 &&
                      axi_rsp.b_valid && axi_rsp.b.id == 5);
                @(negedge clk);
                if (!drain) $fatal(1, "Barrier completed with atomic responses stalled");
                // All three offers are new after drain; accepted early-W debt
                // has already been paired with the atomic AW and W here.
                axi_req.ar = '0;
                axi_req.ar.addr = 32'h8000_0020;
                axi_req.ar.id = 6;
                axi_req.ar.size = 3;
                axi_req.ar.burst = axi_pkg::BURST_INCR;
                axi_req.aw = '0;
                axi_req.aw.addr = 32'h8000_0040;
                axi_req.aw.id = 7;
                axi_req.aw.size = 3;
                axi_req.aw.burst = axi_pkg::BURST_INCR;
                axi_req.w = '{data: late_write, strb: '1, last: 1'b1, user: '0};
                late_offers = 1;
                fork
                    send_ar();
                    send_aw();
                    send_w();
                    begin
                        repeat (4) begin
                            @(negedge clk);
                            if (!drain || axi_rsp.ar_ready || axi_rsp.aw_ready || axi_rsp.w_ready)
                                $fatal(1, "New late offer was not blocked throughout drain");
                        end
                        // B is consumed while R remains stalled, then R is released.
                        axi_req.b_ready = 1;
                        do @(posedge clk); while (!axi_rsp.b_valid);
                        @(negedge clk);
                        axi_req.b_ready = 0;
                        repeat (3) @(negedge clk);
                        if (!drain || !axi_rsp.r_valid || axi_rsp.r.id != 5)
                            $fatal(1, "Barrier ignored the independently stalled atomic R");
                        axi_req.r_ready = 1;
                        do @(posedge clk); while (!axi_rsp.r_valid);
                        @(negedge clk);
                        axi_req.r_ready = 0;
                        wait (!drain);
                    end
                join
                late_offers = 0;
                fork
                    begin
                        repeat (3) @(negedge clk);
                        axi_req.r_ready = 1;
                        do @(posedge clk); while (!axi_rsp.r_valid);
                        @(negedge clk);
                        axi_req.r_ready = 0;
                    end
                    begin
                        repeat (6) @(negedge clk);
                        axi_req.b_ready = 1;
                        do @(posedge clk); while (!axi_rsp.b_valid);
                        @(negedge clk);
                        axi_req.b_ready = 0;
                    end
                join
            end
        join
        wait (idle && !active && !drain);
        repeat (4) @(negedge clk);
        if (!exposed_unaccepted_aw || aw_count[5] != before_aw5 + 1 ||
            aw_count[7] != before_aw7 + 1 || ar_count[1] != before_ar1 + 1 ||
            ar_count[6] != before_ar6 + 1 || r_count[1] != before_r1 + 1 ||
            r_count[6] != before_r6 + 1 || r_count[5] != atomic_r_baseline + 1 ||
            b_count[5] != atomic_b_baseline + 1 || b_count[7] != before_b7 + 1 ||
            w_count != before_w + 2 || axi_rsp.r_valid || axi_rsp.b_valid)
            $fatal(1, "Barrier acceptance/response counts or nonvacuity mismatch");
        for (int i = 0; i < 128; i++) begin
            if (i < 4) begin
                if (memory[i] != AtomicReplacement[i*8 +: 8])
                    $fatal(1, "Atomic SWAP write mismatch at byte %0d", i);
            end else if (i >= 64 && i < 72) begin
                if (memory[i] != late_write[(i-64)*8 +: 8])
                    $fatal(1, "Late ordinary write mismatch at byte %0d", i);
            end else if (memory[i] != original[i])
                $fatal(1, "Barrier traffic changed neighboring byte %0d", i);
        end
        if (apply_command && (cfg.chip[0].address_mask_msb != next_mask ||
            accepted_cfg.phy[0].tx_delay != next_delay || apply_count <= before_apply))
            $fatal(1, "APPLY failed to publish the staged frontend/PHY settings");
        if (!apply_command && cfg.chip[0].address_mask_msb != previous_mask)
            $fatal(1, "FLUSH changed the effective frontend setting");
        scenario_active = 0;
        $display("Barrier case passed: apply=%0d W-order=%0d", apply_command, w_order);
    endtask

    function automatic bit responses_complete;
        for (int id = 0; id < 16; id++)
            if (r_count[id] != ar_goal[id] + atomic_goal[id] || b_count[id] != aw_goal[id])
                return 0;
        return 1;
    endfunction

    task automatic prepare_queue_case(input int unsigned pattern);
        wait (idle && !active && !drain);
        @(negedge clk);
        queue_previous_mask = cfg.chip[0].address_mask_msb;
        queue_next_mask = queue_previous_mask == 7 ? 8 : 7;
        queue_next_delay = accepted_cfg.phy[0].tx_delay + 1;
        reg_write('h408, 32'h0001_0000 | (32'(queue_next_mask) << 8));
        reg_write('h300, 32'(queue_next_delay));
        if (cfg.chip[0].address_mask_msb != queue_previous_mask)
            $fatal(1, "Queue staging changed the effective frontend setting");
        @(negedge clk);
        for (int i = 0; i < 128; i++) begin
            expected_memory[i] = 8'(32'h47 + 19*i + 11*pattern);
            memory[i] = expected_memory[i];
        end
        queue_apply_tracking = 1;
    endtask

    task automatic set_read_request(input int unsigned id, byte_address);
        axi_req.ar = '0;
        axi_req.ar.addr = 32'h8000_0000 + byte_address;
        axi_req.ar.id = id_t'(id);
        axi_req.ar.size = 3;
        axi_req.ar.burst = axi_pkg::BURST_INCR;
        for (int lane = 0; lane < 8; lane++)
            expected_read[id][lane*8 +: 8] = expected_memory[byte_address+lane];
    endtask

    task automatic set_write_request(input int unsigned id, first_beat, beats = 1);
        axi_req.aw = '0;
        axi_req.aw.addr = 32'h8000_0000 + first_beat*8;
        axi_req.aw.id = id_t'(id);
        axi_req.aw.size = 3;
        axi_req.aw.len = 8'(beats - 1);
        axi_req.aw.burst = axi_pkg::BURST_INCR;
    endtask

    task automatic set_write_beat(input int unsigned beat, input bit last);
        axi_req.w = '0;
        axi_req.w.data = 64'hc468_127e_a9df_035b ^ (64'(beat + 1) * 64'h0103_0507_090b_0d0f);
        axi_req.w.strb = 8'hb5;
        axi_req.w.last = last;
        for (int lane = 0; lane < 8; lane++)
            if (axi_req.w.strb[lane])
                expected_memory[beat*8+lane] = axi_req.w.data[lane*8 +: 8];
    endtask

    task automatic release_queue_responses;
        // Release consumers independently of acceptance of a held producer.
        while (!responses_complete() || drain) begin
            @(negedge clk);
            axi_req.r_ready = cycle % 5 >= 2;
            axi_req.b_ready = cycle % 7 >= 3;
        end
        axi_req.r_ready = 0;
        axi_req.b_ready = 0;
    endtask

    task automatic finish_queue_case(input string name);
        wait (idle && !active && !drain);
        repeat (4) @(negedge clk);
        if (!responses_complete() || w_count != w_goal || axi_rsp.r_valid || axi_rsp.b_valid)
            $fatal(1, "%s: external acceptance/response count mismatch", name);
        for (int id = 0; id < 16; id++)
            if (aw_count[id] != aw_goal[id] || ar_count[id] != ar_goal[id] ||
                atomic_count[id] != atomic_goal[id])
                $fatal(1, "%s: accepted request count mismatch ID=%0d", name, id);
        for (int i = 0; i < 128; i++)
            if (memory[i] != expected_memory[i])
                $fatal(1, "%s: memory/neighbor mismatch byte=%0d got=%h expected=%h",
                    name, i, memory[i], expected_memory[i]);
        if (cfg.chip[0].address_mask_msb != queue_next_mask ||
            accepted_cfg.phy[0].tx_delay != queue_next_delay)
            $fatal(1, "%s: APPLY did not publish the staged settings", name);
        queue_apply_tracking = 0;
        $display("Queue case passed: %s read-peak=%0d write-peak=%0d", name, read_peak, write_peak);
    endtask

    task automatic check_read_queue;
        int unsigned extra_before;
        prepare_queue_case(0);
        for (int i = 0; i <= AxiMaxReadTxns; i++) ar_goal[8+i]++;
        for (int i = 0; i < AxiMaxReadTxns; i++) begin
            set_read_request(8+i, i*8);
            send_ar();
        end
        wait (axi_rsp.r_valid);
        @(negedge clk);
        if (read_peak != AxiMaxReadTxns)
            $fatal(1, "Read test failed to reach configured outstanding limit");
        extra_before = ar_count[8+AxiMaxReadTxns];
        set_read_request(8+AxiMaxReadTxns, AxiMaxReadTxns*8);
        fork
            send_ar();
            begin
                repeat (3) begin
                    @(negedge clk);
                    if (axi_rsp.ar_ready || ar_count[8+AxiMaxReadTxns] != extra_before)
                        $fatal(1, "Read queue did not stall the extra AR at its limit");
                end
                reg_write('hc, 32'h2);
                if (!drain) $fatal(1, "Read queue APPLY did not establish drain");
                release_queue_responses();
            end
        join
        finish_queue_case("read ID limit with held AR");
    endtask

    task automatic check_write_queue;
        int unsigned extra_before;
        prepare_queue_case(1);
        for (int i = 0; i <= AxiMaxWriteTxns; i++) aw_goal[8+i]++;
        w_goal += AxiMaxWriteTxns + 1;
        for (int i = 0; i < AxiMaxWriteTxns; i++) begin
            set_write_request(8+i, i);
            send_aw();
            set_write_beat(i, 1);
            send_w();
        end
        wait (axi_rsp.b_valid);
        @(negedge clk);
        if (write_peak != AxiMaxWriteTxns)
            $fatal(1, "Write test failed to reach configured outstanding limit");
        extra_before = aw_count[8+AxiMaxWriteTxns];
        set_write_request(8+AxiMaxWriteTxns, AxiMaxWriteTxns);
        fork
            send_aw();
            begin
                // The held extra write is AW-before-W, unlike buffered early W.
                wait (aw_count[8+AxiMaxWriteTxns] == extra_before + 1);
                @(negedge clk);
                set_write_beat(AxiMaxWriteTxns, 1);
                send_w();
            end
            begin
                repeat (3) begin
                    @(negedge clk);
                    if (axi_rsp.aw_ready || aw_count[8+AxiMaxWriteTxns] != extra_before)
                        $fatal(1, "Write queue did not stall the extra AW at its limit");
                end
                reg_write('hc, 32'h2);
                if (!drain) $fatal(1, "Write queue APPLY did not establish drain");
                release_queue_responses();
            end
        join
        finish_queue_case("write ID limit with held AW before W");
    endtask

    task automatic check_complete_early_w_queue;
        int unsigned before_w, before_aw;
        prepare_queue_case(2);
        before_w = w_count;
        before_aw = 0;
        for (int id = 0; id < 16; id++) before_aw += aw_count[id];
        for (int i = 0; i <= MaxWriteDataBeats; i++) aw_goal[i]++;
        w_goal += MaxWriteDataBeats + 1;
        for (int i = 0; i < MaxWriteDataBeats; i++) begin
            set_write_beat(i, 1);
            send_w();
        end
        set_write_beat(MaxWriteDataBeats, 1);
        fork
            send_w();
            begin
                repeat (3) begin
                    int unsigned current_aw;
                    @(negedge clk);
                    current_aw = 0;
                    for (int id = 0; id < 16; id++) current_aw += aw_count[id];
                    if (axi_rsp.w_ready || w_count != before_w + MaxWriteDataBeats ||
                        current_aw != before_aw)
                        $fatal(1, "Complete early W did not fill and stall at actual FIFO capacity");
                end
                reg_write('hc, 32'h2);
                if (!drain) $fatal(1, "Complete early-W APPLY did not establish drain");
                fork
                    begin
                        for (int i = 0; i <= MaxWriteDataBeats; i++) begin
                            set_write_request(i, i);
                            send_aw();
                        end
                    end
                    release_queue_responses();
                join
            end
        join
        finish_queue_case("complete early-W FIFO and held extra W");
        $display("Early-W capacity reached: %0d complete packets before any AW", MaxWriteDataBeats);
    endtask

    task automatic check_partial_early_w_queue;
        int unsigned before_w;
        prepare_queue_case(3);
        before_w = w_count;
        aw_goal[8]++;
        w_goal += MaxWriteDataBeats + 2;
        for (int i = 0; i < MaxWriteDataBeats; i++) begin
            set_write_beat(i, 0);
            send_w();
        end
        set_write_beat(MaxWriteDataBeats, 0);
        fork
            begin
                send_w();
                set_write_beat(MaxWriteDataBeats+1, 1);
                send_w();
            end
            begin
                repeat (3) begin
                    @(negedge clk);
                    if (axi_rsp.w_ready || w_count != before_w + MaxWriteDataBeats)
                        $fatal(1, "Partial early W did not fill and stall at actual FIFO capacity");
                end
                reg_write('hc, 32'h2);
                if (!drain) $fatal(1, "Partial early-W APPLY did not establish drain");
                fork
                    begin
                        set_write_request(8, 0, MaxWriteDataBeats+2);
                        send_aw();
                    end
                    release_queue_responses();
                join
            end
        join
        finish_queue_case("partial early-W burst longer than FIFO");
        $display("Partial-W capacity reached: %0d non-LAST beats before matching AW",
            MaxWriteDataBeats);
    endtask

    initial begin
        axi_req = '0;
        reg_req = '0;
        scenario_active = 0;
        atomic_aw_accepted = 0;
        late_offers = 0;
        queue_apply_tracking = 0;
        w_goal = 0;
        for (int id = 0; id < 16; id++) begin
            aw_goal[id] = 0;
            ar_goal[id] = 0;
            atomic_goal[id] = 0;
            expected_read[id] = '0;
        end
        previous_mask = 0;
        atomic_r_baseline = 0;
        atomic_b_baseline = 0;
        for (int i = 0; i < 128; i++) memory[i] = 8'(i);
        repeat (4) @(negedge clk);
        rst_n = 1;
        wait (!drain);
        reg_write('h400, 32'h8000_0000);
        reg_write('h404, 32'h8040_0000);
        reg_write('h408, 32'h0001_0700);
        reg_write('hc, 32'h2);
        wait (!drain);
        for (int command = 0; command < 2; command++)
            for (int order = 0; order < 3; order++)
                check_barrier(command != 0, order);
        check_read_queue();
        check_write_queue();
        check_complete_early_w_queue();
        check_partial_early_w_queue();
        $display("Queue profile passed: read=%0d write=%0d buffer-beats=%0d read-peak=%0d write-peak=%0d",
            AxiMaxReadTxns, AxiMaxWriteTxns, MaxWriteDataBeats, read_peak, write_peak);
        $display("AXI CSR barrier integration tests passed");
        $finish;
    end
    initial begin
        #200us;
        $fatal(1, "AXI CSR barrier timed out waiting for external acceptance or completion");
    end
endmodule
