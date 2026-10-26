// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

`include "axi/typedef.svh"
`include "hyperbus/typedef.svh"

module hyperbus_axi_atomic_tb #(
    parameter int unsigned HostDataWidth = 64
);
    localparam int unsigned HostBytes = HostDataWidth / 8;
    typedef logic [31:0] addr_t;
    typedef logic [HostDataWidth-1:0] data_t;
    typedef logic [HostBytes-1:0] strb_t;
    typedef logic [3:0] id_t;
    typedef logic user_t;
    typedef struct packed { addr_t start_addr; addr_t end_addr; logic [2:0] idx; } rule_t;
    `AXI_TYPEDEF_ALL(axi, addr_t, id_t, data_t, strb_t, user_t)
    `HYPERBUS_TYPEDEF_HOST_ALL_CT(host, addr_t, data_t, strb_t)
    `HYPERBUS_TYPEDEF_LINK_ALL_CT(link, 1)

    logic clk = 0;
    logic rst_n = 0;
    axi_req_t axi_req;
    axi_resp_t axi_rsp;
    host_req_t host_req;
    host_rsp_t host_rsp;
    link_req_t link_req;
    link_rsp_t link_rsp;
    hyperbus_pkg::frontend_cfg_t cfg;
    rule_t [hyperbus_pkg::HyperNumChips-1:0] rules;
    logic idle, active, decode_error, drain;
    byte unsigned memory [128];
    int unsigned cycle, commands, writes;

    hyperbus_axi_frontend #(
        .AxiDataWidth(HostDataWidth), .AxiAddrWidth(32), .AxiIdWidth(4),
        .AxiUserWidth(1), .MaxWriteDataBeats(8),
        .axi_req_t(axi_req_t), .axi_rsp_t(axi_resp_t),
        .host_req_t(host_req_t), .host_rsp_t(host_rsp_t)
    ) i_frontend (
        .clk_i(clk), .rst_ni(rst_n), .drain_i(drain), .idle_o(idle),
        .axi_req_i(axi_req), .axi_rsp_o(axi_rsp),
        .host_req_o(host_req), .host_rsp_i(host_rsp)
    );

    hyperbus_midend #(
        .HostAddrWidth(32), .HostDataWidth(HostDataWidth), .NumPhys(1),
        .HostWriteBufferBytes(HostBytes * 8),
        .MaxHostBurstBeats(256),
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

    always #5ns clk = ~clk;

    // A byte-addressed physical-link model checks actual adapter strobes. It
    // independently stalls command, TX, RX and write-response channels.
    typedef enum logic [2:0] { BackendIdle, ReadDelay, BackendRead,
        BackendWrite, ResponseDelay, BackendResponse } backend_state_e;
    backend_state_e backend_state;
    int unsigned address, remaining, delay_cycles;
    bit protect_atomic_commands;
    bit competing_command_offered;
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
            backend_state <= BackendIdle;
            protect_atomic_commands <= 1'b0;
            competing_command_offered <= 1'b0;
            cycle <= 0;
            address <= 0;
            remaining <= 0;
            delay_cycles <= 0;
            commands <= 0;
            writes <= 0;
        end else begin
            cycle <= cycle + 1;
            if (protect_atomic_commands &&
                ((axi_req.ar_valid && axi_req.ar.id == 6) ||
                 (axi_req.aw_valid && axi_req.aw.id == 7)))
                competing_command_offered <= 1'b1;
            case (backend_state)
                BackendIdle: if (link_req.cmd_valid && link_rsp.cmd_ready) begin
                    if (protect_atomic_commands && link_req.cmd.trans.address != 0)
                        $fatal(1, "Ordinary backend command interleaved atomic read/write");
                    address <= int'(link_req.cmd.trans.address) * 2;
                    remaining <= int'(link_req.cmd.trans.burst);
                    delay_cycles <= 2;
                    commands <= commands + 1;
                    backend_state <= link_req.cmd.trans.write ? BackendWrite : ReadDelay;
                    if (protect_atomic_commands && link_req.cmd.trans.write)
                        protect_atomic_commands <= 1'b0;
                    if (link_req.cmd.cs != 1 || !link_req.cmd.trans.burst_type)
                        $fatal(1, "Atomic command selected wrong chip or backend WRAP");
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
                    for (int lane = 0; lane < 2; lane++) begin
                        if (link_req.tx.strb[lane]) begin
                            if ($test$plusargs("inject_backend_write_fault") &&
                                address == 0 && lane == 0)
                                memory[address+lane] <= link_req.tx.data[lane*8 +: 8] ^ 8'h01;
                            else
                                memory[address+lane] <= link_req.tx.data[lane*8 +: 8];
                        end
                    end
                    if (link_req.tx.last != (remaining == 1))
                        $fatal(1, "Incorrect atomic physical burst length");
                    address <= address + 2;
                    remaining <= remaining - 1;
                    if (remaining == 1) begin
                        writes <= writes + 1;
                        delay_cycles <= 3;
                        backend_state <= ResponseDelay;
                    end
                end
                ResponseDelay: if (delay_cycles == 0) backend_state <= BackendResponse;
                               else delay_cycles <= delay_cycles - 1;
                BackendResponse: if (link_req.wrsp_ready) begin
                    backend_state <= BackendIdle;
                end
                default: $fatal(1, "Invalid backend state");
            endcase
        end
    end

    task automatic send_aw(input int unsigned delay_count);
        repeat (delay_count) @(negedge clk);
        axi_req.aw_valid = 1;
        do @(posedge clk); while (!axi_rsp.aw_ready);
        @(negedge clk);
        axi_req.aw_valid = 0;
    endtask
    task automatic send_w(input int unsigned delay_count);
        repeat (delay_count) @(negedge clk);
        axi_req.w_valid = 1;
        do @(posedge clk); while (!axi_rsp.w_ready);
        @(negedge clk);
        axi_req.w_valid = 0;
    endtask

    task automatic ordinary_traffic_during_atomic(input int unsigned command_baseline);
        wait (commands > command_baseline);
        axi_req.ar = '0;
        axi_req.ar.addr = 32'h8000_0020;
        axi_req.ar.id = 4'd6;
        axi_req.ar.size = 3'($clog2(HostBytes));
        axi_req.ar.burst = axi_pkg::BURST_INCR;
        axi_req.aw = '0;
        axi_req.aw.addr = 32'h8000_0040;
        axi_req.aw.id = 4'd7;
        axi_req.aw.size = 3'($clog2(HostBytes));
        axi_req.aw.burst = axi_pkg::BURST_INCR;
        axi_req.w = '0;
        for (int lane = 0; lane < HostBytes; lane++)
            axi_req.w.data[lane*8 +: 8] = 8'(8'h40 + lane);
        axi_req.w.strb = '1;
        axi_req.w.last = 1'b1;
        fork
            begin
                @(negedge clk);
                axi_req.ar_valid = 1'b1;
                do @(posedge clk); while (!axi_rsp.ar_ready);
                @(negedge clk);
                axi_req.ar_valid = 1'b0;
            end
            begin
                send_aw(0);
                send_w(0);
            end
        join
    endtask

    task automatic receive_overlap_responses(input data_t atomic_read, atomic_mask,
                                             input data_t ordinary_read);
        bit atomic_r_done, atomic_b_done, ordinary_r_done, ordinary_b_done;
        bit r_stalled, b_stalled;
        axi_r_chan_t held_r;
        axi_b_chan_t held_b;
        int unsigned cycles;
        atomic_r_done = 0;
        atomic_b_done = 0;
        ordinary_r_done = 0;
        ordinary_b_done = 0;
        r_stalled = 0;
        b_stalled = 0;
        cycles = 0;
        while (!(atomic_r_done && atomic_b_done && ordinary_r_done && ordinary_b_done)) begin
            @(negedge clk);
            if (r_stalled && (!axi_rsp.r_valid || axi_rsp.r != held_r))
                $fatal(1, "Overlap R response changed while stalled");
            if (b_stalled && (!axi_rsp.b_valid || axi_rsp.b != held_b))
                $fatal(1, "Overlap B response changed while stalled");
            cycles++;
            axi_req.r_ready = cycles % 5 >= 2;
            axi_req.b_ready = cycles % 7 >= 3;
            r_stalled = axi_rsp.r_valid && !axi_req.r_ready;
            b_stalled = axi_rsp.b_valid && !axi_req.b_ready;
            if (r_stalled) held_r = axi_rsp.r;
            if (b_stalled) held_b = axi_rsp.b;
            @(posedge clk);
            if (axi_rsp.r_valid && axi_req.r_ready) begin
                case (axi_rsp.r.id)
                    5: begin
                        if (atomic_r_done || !axi_rsp.r.last ||
                            axi_rsp.r.resp != axi_pkg::RESP_OKAY ||
                            (axi_rsp.r.data & atomic_mask) != atomic_read)
                            $fatal(1, "Invalid or duplicate atomic read response");
                        atomic_r_done = 1;
                    end
                    6: begin
                        if (ordinary_r_done || !axi_rsp.r.last ||
                            axi_rsp.r.resp != axi_pkg::RESP_OKAY ||
                            axi_rsp.r.data != ordinary_read)
                            $fatal(1, "Invalid or duplicate ordinary read response");
                        ordinary_r_done = 1;
                    end
                    default: $fatal(1, "Unexpected overlap R ID %0d", axi_rsp.r.id);
                endcase
            end
            if (axi_rsp.b_valid && axi_req.b_ready) begin
                case (axi_rsp.b.id)
                    5: begin
                        if (atomic_b_done || axi_rsp.b.resp != axi_pkg::RESP_OKAY)
                            $fatal(1, "Invalid or duplicate atomic B response");
                        atomic_b_done = 1;
                    end
                    7: begin
                        if (ordinary_b_done || axi_rsp.b.resp != axi_pkg::RESP_OKAY)
                            $fatal(1, "Invalid or duplicate ordinary B response");
                        ordinary_b_done = 1;
                    end
                    default: $fatal(1, "Unexpected overlap B ID %0d", axi_rsp.b.id);
                endcase
            end
            if (cycles > 500) $fatal(1, "Timed out receiving overlap responses");
        end
        @(negedge clk);
        axi_req.r_ready = 0;
        axi_req.b_ready = 0;
        for (int lane = 0; lane < HostBytes; lane++)
            if (memory[64+lane] != 8'(8'h40 + lane))
                $fatal(1, "Ordinary write overlapping atomic failed at lane %0d", lane);
    endtask

    task automatic receive_responses(
        input data_t expected_read, mask,
        input axi_pkg::resp_t expected_resp,
        input bit return_read, b_first,
        input id_t expected_id = 4'd5,
        input bit drain_during_stall = 1'b0
    );
        axi_r_chan_t held_r;
        axi_b_chan_t held_b;
        bit r_done, b_done;
        r_done = !return_read;
        b_done = 0;
        // Force response backpressure, then accept the channels in either order.
        wait (axi_rsp.b_valid && (!return_read || axi_rsp.r_valid));
        #1ps;
        held_r = axi_rsp.r;
        held_b = axi_rsp.b;
        repeat (4) begin
            @(negedge clk);
            if (!axi_rsp.b_valid || axi_rsp.b != held_b ||
                (return_read && (!axi_rsp.r_valid || axi_rsp.r != held_r)))
                $fatal(1, "Atomic response changed under independent stalls");
        end
        if (drain_during_stall) begin
            drain = 1'b1;
            @(negedge clk);
            axi_req.ar_valid = 1'b1;
            axi_req.ar = '0;
            axi_req.ar.addr = 32'h8000_0000;
            axi_req.ar.id = 4'd9;
            axi_req.ar.size = 1;
            axi_req.ar.burst = axi_pkg::BURST_INCR;
            axi_req.ar_valid = 1'b1;
            repeat (2) begin
                @(negedge clk);
                if (axi_rsp.ar_ready) $fatal(1, "Drain admitted a new ordinary read");
            end
        end
        if (held_b.id != expected_id || held_b.resp != expected_resp ||
            (return_read && (held_r.id != expected_id || !held_r.last ||
             held_r.resp != expected_resp || ((held_r.data & mask) != expected_read))))
            $fatal(1, "Atomic response got R=%h/%0d B=%0d expected R=%h resp=%0d",
                held_r.data, held_r.resp, held_b.resp, expected_read, expected_resp);
        if (b_first) axi_req.b_ready = 1; else axi_req.r_ready = return_read;
        if (!return_read) axi_req.b_ready = 1;
        repeat (6) begin
            @(posedge clk);
            if (axi_rsp.r_valid && axi_req.r_ready) r_done = 1;
            if (axi_rsp.b_valid && axi_req.b_ready) b_done = 1;
            @(negedge clk);
        end
        axi_req.r_ready = return_read && !r_done;
        axi_req.b_ready = !b_done;
        while (!r_done || !b_done) begin
            @(posedge clk);
            if (axi_rsp.r_valid && axi_req.r_ready) r_done = 1;
            if (axi_rsp.b_valid && axi_req.b_ready) b_done = 1;
            @(negedge clk);
        end
        axi_req.r_ready = 0;
        axi_req.b_ready = 0;
        if (drain_during_stall) begin
            drain = 1'b0;
            do @(posedge clk); while (!axi_rsp.ar_ready);
            @(negedge clk);
            axi_req.ar_valid = 1'b0;
            axi_req.r_ready = 1'b1;
            wait (axi_rsp.r_valid);
            #1ps;
            if (axi_rsp.r.id != 9 || axi_rsp.r.resp != axi_pkg::RESP_OKAY ||
                !axi_rsp.r.last)
                $fatal(1, "Drain-held ordinary read returned ID=%0d resp=%0d last=%b",
                    axi_rsp.r.id, axi_rsp.r.resp, axi_rsp.r.last);
            @(posedge clk);
            @(negedge clk);
            axi_req.r_ready = 1'b0;
        end
        wait (idle && !active);
    endtask

    task automatic check_compare(input int unsigned bytes, offset, pattern,
                                 input bit overlap_ordinary = 1'b0);
        byte unsigned original [128];
        byte unsigned compare_value [16], replacement [16];
        data_t expected_read, read_mask;
        int unsigned pair_base, compare_base, swap_base, initial_commands;
        data_t overlap_read;
        logic [31:0] seed;
        bit match;
        match = pattern % 2 == 0;
        pair_base = (offset / (2*bytes)) * (2*bytes);
        compare_base = offset;
        swap_base = (offset == pair_base) ? pair_base + bytes : pair_base;
        expected_read = '0;
        read_mask = '0;
        overlap_read = '0;
        seed = 32'h5eeda702 ^ (bytes << 16) ^ (offset << 8) ^ pattern;
        @(negedge clk);
        for (int i = 0; i < 128; i++) begin
            original[i] = 8'(32'h6d + 17*i + 3*pattern);
            memory[i] = original[i];
        end
        for (int lane = 0; lane < HostBytes; lane++)
            overlap_read[lane*8 +: 8] = original[32+lane];
        axi_req.aw = '0;
        axi_req.aw.addr = 32'h8000_0000 + offset;
        axi_req.aw.id = 5;
        axi_req.aw.size = 3'($clog2(2*bytes));
        axi_req.aw.burst = offset == pair_base ? axi_pkg::BURST_INCR : axi_pkg::BURST_WRAP;
        axi_req.aw.atop = axi_pkg::ATOP_ATOMICCMP;
        axi_req.w = '0;
        axi_req.w.last = 1;
        for (int i = 0; i < bytes; i++) begin
            compare_value[i] = original[offset+i] ^ (match ? 8'h00 : 8'h80);
            replacement[i] = 8'(32'he1 - 29*i - 7*pattern);
            if (pattern >= 4) begin
                seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5;
                replacement[i] = seed[7:0] | 8'h01;
            end
            axi_req.w.data[(compare_base+i)*8 +: 8] = compare_value[i];
            axi_req.w.data[(swap_base+i)*8 +: 8] = replacement[i];
            axi_req.w.strb[compare_base+i] = 1;
            axi_req.w.strb[swap_base+i] = 1;
            expected_read[(offset+i)*8 +: 8] = original[offset+i];
            read_mask[(offset+i)*8 +: 8] = '1;
        end
        initial_commands = commands;
        if (overlap_ordinary) begin
            competing_command_offered = 1'b0;
            protect_atomic_commands = 1'b1;
        end
        fork
            send_aw(pattern % 3);
            send_w((pattern + 1) % 5);
            if (overlap_ordinary)
                receive_overlap_responses(expected_read, read_mask, overlap_read);
            else
                receive_responses(expected_read, read_mask, axi_pkg::RESP_OKAY, 1,
                    pattern % 2 != 0, 5,
                    bytes == 2 && offset == 0 && pattern == 1);
            if (overlap_ordinary) ordinary_traffic_during_atomic(initial_commands);
        join
        if (overlap_ordinary && !competing_command_offered)
            $fatal(1, "Atomic overlap lacked a competing ordinary offer");
        for (int i = 0; i < 128; i++) begin
            if (match && i >= offset && i < offset + bytes) begin
                if (memory[i] != replacement[i-offset]) $fatal(1, "Compare failed at byte %0d", i);
            end else if (!(overlap_ordinary && i >= 64 && i < 64 + HostBytes) &&
                         memory[i] != original[i])
                $fatal(1, "Compare modified neighboring byte %0d", i);
        end
    endtask

    task automatic check_rejected(
        input axi_pkg::atop_t atop, input int unsigned size, offset,
        input axi_pkg::burst_t burst, input bit locked = 0,
        input int unsigned beats = 1
    );
        int unsigned initial_commands;
        @(negedge clk);
        initial_commands = commands;
        axi_req.aw = '0;
        axi_req.aw.addr = 32'h8000_0000 + offset;
        axi_req.aw.id = 5;
        axi_req.aw.size = 3'(size);
        axi_req.aw.len = 8'(beats - 1);
        axi_req.aw.burst = burst;
        axi_req.aw.atop = atop;
        axi_req.aw.lock = locked;
        axi_req.w = '{data: '1, strb: '1, last: 1'b1, user: '0};
        fork
            send_aw(2);
            begin
                for (int beat = 0; beat < beats; beat++) begin
                    axi_req.w.last = beat == beats - 1;
                    send_w(0);
                end
            end
            receive_responses('0, '0, axi_pkg::RESP_SLVERR, atop[axi_pkg::ATOP_R_RESP], 1);
        join
        if (commands != initial_commands) $fatal(1, "Rejected atomic reached backend");
    endtask

    task automatic check_maximum_rejected_read;
        int unsigned received;
        @(negedge clk);
        axi_req.ar = '0;
        axi_req.ar.addr = 32'h9000_0000;
        axi_req.ar.id = 6;
        axi_req.ar.len = '1;
        axi_req.ar.size = 3'($clog2(HostBytes));
        axi_req.ar.burst = axi_pkg::BURST_INCR;
        axi_req.ar_valid = 1'b1;
        do @(posedge clk); while (!axi_rsp.ar_ready);
        @(negedge clk);
        axi_req.ar_valid = 1'b0;
        received = 0;
        while (received < 256) begin
            axi_req.r_ready = cycle % 5 == 0;
            @(posedge clk);
            if (axi_rsp.r_valid && axi_req.r_ready) begin
                if (axi_rsp.r.id != 6 || axi_rsp.r.resp != axi_pkg::RESP_DECERR ||
                    axi_rsp.r.last != (received == 255))
                    $fatal(1, "Maximum rejected read response %0d malformed: id=%0d resp=%0d last=%b",
                        received, axi_rsp.r.id, axi_rsp.r.resp, axi_rsp.r.last);
                received++;
            end
            @(negedge clk);
        end
        axi_req.r_ready = 1'b0;
        wait (idle && !active);
    endtask

    task automatic check_arithmetic(
        input axi_pkg::atop_t atop,
        input int unsigned bytes, offset,
        input logic [63:0] old_value, operand, expected_value
    );
        byte unsigned original [128];
        data_t expected_read, read_mask;
        @(negedge clk);
        expected_read = '0;
        read_mask = '0;
        for (int i = 0; i < 128; i++) begin
            memory[i] = 8'(32'h41 + 3*i);
            original[i] = memory[i];
        end
        axi_req.aw = '0;
        axi_req.aw.addr = 32'h8000_0000 + offset;
        axi_req.aw.id = 5;
        axi_req.aw.size = 3'($clog2(bytes));
        axi_req.aw.burst = axi_pkg::BURST_INCR;
        axi_req.aw.atop = atop;
        axi_req.w = '0;
        axi_req.w.last = 1;
        for (int i = 0; i < bytes; i++) begin
            memory[offset+i] = old_value[i*8 +: 8];
            original[offset+i] = old_value[i*8 +: 8];
            axi_req.w.data[(offset+i)*8 +: 8] = operand[i*8 +: 8];
            axi_req.w.strb[offset+i] = 1;
            expected_read[(offset+i)*8 +: 8] = old_value[i*8 +: 8];
            read_mask[(offset+i)*8 +: 8] = '1;
        end
        fork
            send_aw(4);
            send_w(1);
            receive_responses(expected_read, read_mask, axi_pkg::RESP_OKAY,
                atop[axi_pkg::ATOP_R_RESP], offset % 2 == 0);
        join
        for (int i = 0; i < 128; i++) begin
            if (i >= offset && i < offset + bytes) begin
                if (memory[i] != expected_value[(i-offset)*8 +: 8])
                    $fatal(1, "ATOP %b bytes=%0d offset=%0d failed at byte %0d", atop, bytes, offset, i);
            end else if (memory[i] != original[i]) $fatal(1, "Arithmetic changed neighbor %0d", i);
        end
    endtask

    initial begin
        axi_req = '0;
        drain = 1'b0;
        cfg = '0;
        rules = '0;
        for (int i = 0; i < hyperbus_pkg::HyperNumChips; i++) begin
            rules[i].idx = 3'(i);
            rules[i].start_addr = 32'hffff_0000 + 2*i;
            rules[i].end_addr = rules[i].start_addr + 1;
        end
        cfg.address_mask_msb = 7;
        rules[0].start_addr = 32'h8000_0000;
        rules[0].end_addr = 32'h8000_0080;
        for (int i = 0; i < 128; i++) memory[i] = 8'(i);
        repeat (4) @(negedge clk);
        rst_n = 1;
        repeat (2) @(negedge clk);
        for (int bytes = 1; bytes*2 <= HostBytes && bytes <= 16; bytes *= 2)
            for (int offset = 0; offset < HostBytes; offset += bytes)
                for (int pattern = 0; pattern < 6; pattern++) check_compare(bytes, offset, pattern);
        for (int bytes = 1; bytes <= HostBytes && bytes <= 8; bytes *= 2) begin
            for (int offset = 0; offset < HostBytes; offset += bytes) begin
                check_arithmetic(6'b100000, bytes, offset, '1, 1, 0); // ADD overflow
                check_arithmetic(6'b100001, bytes, offset, 64'hf0f0_f0f0_f0f0_f0f0,
                    64'hcccc_cccc_cccc_cccc, 64'h3030_3030_3030_3030); // CLR
                check_arithmetic(6'b100010, bytes, offset, 64'haaaa_aaaa_aaaa_aaaa,
                    64'hcccc_cccc_cccc_cccc, 64'h6666_6666_6666_6666); // EOR
                check_arithmetic(6'b101011, bytes, offset, 64'h3030_3030_3030_3030,
                    64'hcccc_cccc_cccc_cccc, 64'hfcfc_fcfc_fcfc_fcfc); // endian ignored SET
                check_arithmetic(6'b100100, bytes, offset, '1, 3, 3); // SMAX
                check_arithmetic(6'b100101, bytes, offset, 3, '1, '1); // SMIN
                check_arithmetic(6'b100110, bytes, offset, 3, '1, '1); // UMAX
                check_arithmetic(6'b100111, bytes, offset, '1, 3, 3); // UMIN
                check_arithmetic(axi_pkg::ATOP_ATOMICSWAP, bytes, offset, 64'h1234_5678_9abc_def1,
                    64'h7654_3210_fedc_ba98, 64'h7654_3210_fedc_ba98);
                check_arithmetic(6'b010000, bytes, offset, '1, 1, 0); // Store B only
            end
        end
        check_rejected(axi_pkg::ATOP_ATOMICCMP, 3, 4, axi_pkg::BURST_INCR);
        check_rejected(axi_pkg::ATOP_ATOMICCMP, 3, 0, axi_pkg::BURST_WRAP);
        check_rejected(axi_pkg::ATOP_ATOMICCMP, 0, 0, axi_pkg::BURST_INCR);
        check_rejected(axi_pkg::ATOP_ATOMICCMP, 2, 1, axi_pkg::BURST_INCR);
        check_rejected(axi_pkg::ATOP_ATOMICSWAP, 2, 1, axi_pkg::BURST_INCR);
        check_rejected(axi_pkg::ATOP_ATOMICSWAP, 2, 0, axi_pkg::BURST_FIXED);
        check_rejected(axi_pkg::ATOP_ATOMICSWAP, 2, 0, axi_pkg::BURST_INCR, 1);
        check_rejected(6'b101000, 2, 0, axi_pkg::BURST_INCR); // big-endian ADD
        check_rejected(6'b110010, 2, 0, axi_pkg::BURST_INCR); // reserved encoding
        check_rejected(6'b011000, 2, 0, axi_pkg::BURST_INCR); // Store: B only
        check_rejected(axi_pkg::ATOP_ATOMICCMP, 3, 0, axi_pkg::BURST_INCR, 0, 2);
        check_rejected(axi_pkg::ATOP_ATOMICCMP, 3, 0, axi_pkg::BURST_FIXED, 0, 2);
        check_rejected(axi_pkg::ATOP_ATOMICCMP, 6, 0, axi_pkg::BURST_INCR);
        check_rejected(axi_pkg::ATOP_ATOMICSWAP, 4, 0, axi_pkg::BURST_INCR);
        if (HostBytes >= 4) begin
            // The compare target ends at the chip boundary. Its paired swap
            // bytes are host payload only, and must not enlarge the memory range.
            rules[0].end_addr = 32'h8000_0002;
            check_compare(2, 0, 0);
            check_compare(2, 0, 1);
        end
        // A byte target still requires a complete physical word in one rule.
        rules[0].end_addr = 32'h8000_0001;
        check_rejected(axi_pkg::ATOP_ATOMICCMP, 1, 0, axi_pkg::BURST_INCR);
        rules[0].end_addr = 32'h8000_0080;
        if (HostBytes >= 4) check_compare(2, 0, 0, 1'b1);
        check_maximum_rejected_read();
        $display("AXI atomic frontend/midend tests passed (%0d-bit host)", HostDataWidth);
        $finish;
    end
    initial begin
        #2ms;
        $fatal(1, "AXI atomic integration test timed out");
    end
endmodule
