// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

`include "hyperbus/typedef.svh"

module hyperbus_burst_bound_tb #(
    parameter int unsigned MaxHostBurstBeats = 256,
    parameter int unsigned HostAddrWidth = 32,
    parameter int unsigned NumPhys = 1
);
    timeunit 1ns;
    timeprecision 1ps;

    typedef logic [HostAddrWidth-1:0] addr_t;
    typedef logic [63:0] data_t;
    typedef logic [7:0] strb_t;
    typedef struct packed { addr_t start_addr; addr_t end_addr; logic [2:0] idx; } rule_t;
    `HYPERBUS_TYPEDEF_HOST_ALL_CT(host, addr_t, data_t, strb_t)
    `HYPERBUS_TYPEDEF_LINK_ALL_CT(link, NumPhys)

    logic clk = 0;
    logic rst_n = 0;
    host_req_t req;
    host_rsp_t rsp;
    link_req_t link_req;
    link_rsp_t link_rsp;
    hyperbus_pkg::frontend_cfg_t cfg;
    rule_t [hyperbus_pkg::HyperNumChips-1:0] rules;
    int unsigned returned = 0;
    int unsigned cycle = 0;
    int unsigned beats;
    int unsigned physical_address, physical_remaining, physical_words;
    int unsigned start_address;
    bit mapped_read, write_request, expect_decode_error;
    bit address_overflow, near_address_end, end_overflow;

    always #5ns clk = ~clk;

    hyperbus_midend #(
        .HostAddrWidth(HostAddrWidth), .HostDataWidth(64), .NumPhys(NumPhys),
        .MaxHostBurstBeats(MaxHostBurstBeats), .HostWriteBufferBytes(64),
        .host_cmd_t(host_cmd_t), .host_w_t(host_w_t), .host_r_t(host_r_t),
        .host_wrsp_t(host_wrsp_t), .host_req_t(host_req_t), .host_rsp_t(host_rsp_t),
        .hyper_rx_t(link_rx_t), .hyper_tx_t(link_tx_t), .hyper_cmd_t(link_cmd_t),
        .hyper_req_t(link_req_t), .hyper_rsp_t(link_rsp_t), .rule_t(rule_t)
    ) dut (
        .clk_i(clk), .rst_ni(rst_n), .host_link_req_i(req), .host_link_rsp_o(rsp),
        .frontend_cfg_i(cfg), .chip_rules_i(rules), .trans_active_o(), .decode_error_o(),
        .hyper_link_req_o(link_req), .hyper_link_rsp_i(link_rsp)
    );

    function automatic logic [7:0] memory_byte(input int unsigned address);
        return 8'((address * 37) ^ (address >> 8) ^ (address >> 16) ^ 'h5a);
    endfunction

    // Independent physical-link source: no allocated RAM and no adapter internals.
    always_comb begin
        link_rsp = '0;
        link_rsp.cmd_ready = physical_remaining == 0;
        link_rsp.rx_valid = physical_remaining != 0;
        for (int unsigned lane = 0; lane < 2*NumPhys; lane++)
            link_rsp.rx.data[lane*8 +: 8] = memory_byte(physical_address + lane);
        link_rsp.rx.last = physical_remaining == NumPhys;
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            physical_address <= 0;
            physical_remaining <= 0;
            physical_words <= 0;
        end else begin
            if (link_req.cmd_valid && link_rsp.cmd_ready) begin
                if (expect_decode_error || link_req.cmd.cs != 1 || link_req.cmd.trans.write ||
                    link_req.cmd.trans.burst == 0)
                    $fatal(1, "Incorrect mapped read backend command");
                physical_address <= int'(link_req.cmd.trans.address) * 2 * NumPhys;
                physical_remaining <= int'(link_req.cmd.trans.burst);
            end
            if (link_rsp.rx_valid && link_req.rx_ready) begin
                physical_address <= physical_address + 2 * NumPhys;
                physical_remaining <= physical_remaining - NumPhys;
                physical_words <= physical_words + NumPhys;
            end
        end
    end

    initial begin : stimulus
        bit stalled;
        host_r_t held_data;
        int unsigned written;
        bit write_completed;
        host_wrsp_t held_wrsp;
        stalled = 0;
        write_request = $test$plusargs("address-overflow-write");
        address_overflow = $test$plusargs("address-overflow") || write_request;
        near_address_end = $test$plusargs("near-address-end");
        end_overflow = $test$plusargs("end-overflow");
        mapped_read = $test$plusargs("mapped-read") || $test$plusargs("physical-overflow");
        mapped_read |= address_overflow || near_address_end || end_overflow;
        expect_decode_error = !mapped_read || address_overflow || end_overflow;
        beats = mapped_read ? 4096 : 256;
        start_address = 0;
        if (address_overflow) beats = 1025;
        if (near_address_end || end_overflow) begin
            if (HostAddrWidth > 20)
                $fatal(1, "Address-boundary cases require a small address width");
            start_address = (1 << HostAddrWidth) - 8;
            beats = end_overflow ? 2 : 1;
        end
        if ($test$plusargs("out-of-bound")) beats = 257;
        if ($test$plusargs("physical-overflow")) beats = 8193;
        req = '0;
        cfg = '0;
        rules = '0;
        if (HostAddrWidth <= 20)
            $fatal(1, "Focused decoder fixture requires at least 21 address bits");
        for (int i = 0; i < hyperbus_pkg::HyperNumChips; i++) begin
            rules[i].idx = 3'(i);
            rules[i].start_addr = addr_t'('1) - 32 + 2*i;
            rules[i].end_addr = rules[i].start_addr + 1;
        end
        if (mapped_read) begin
            rules[0].start_addr = '0;
            cfg.dual_phy = NumPhys == 2;
            cfg.address_mask_msb = 20;
            // Zero is the full-address-space endpoint on a small address bus.
            rules[0].end_addr = HostAddrWidth <= 20 ? '0 : addr_t'(32'h0010_0000);
        end
        repeat (3) @(negedge clk);
        rst_n = 1;
        @(negedge clk);
        req.cmd.beats = hyperbus_pkg::hyper_blen_t'(beats);
        req.cmd.addr = addr_t'(start_address);
        req.cmd.write = write_request;
        req.cmd.size = 3;
        req.cmd.burst = hyperbus_pkg::HyperBurstIncr;
        req.cmd_valid = 1;
        do @(posedge clk); while (!rsp.cmd_ready);
        @(negedge clk);
        req.cmd_valid = 0;

        written = 0;
        write_completed = 0;
        while (write_request ? !write_completed : returned < beats) begin
            req.r_ready = cycle % 5 != 1 && cycle % 5 != 2;
            req.wrsp_ready = req.r_ready;
            req.w_valid = write_request && written < beats;
            req.w.data = 'h0123_4567_89ab_cdef;
            req.w.strb = '1;
            req.w.last = written == beats - 1;
            #1ps;
            if (stalled && (write_request ?
                (!rsp.wrsp_valid || rsp.wrsp !== held_wrsp) :
                (!rsp.r_valid || rsp.r !== held_data)))
                $fatal(1, "Response changed while stalled");
            stalled = write_request ? rsp.wrsp_valid && !req.wrsp_ready :
                                      rsp.r_valid && !req.r_ready;
            held_data = rsp.r;
            held_wrsp = rsp.wrsp;
            @(posedge clk);
            if (expect_decode_error && link_req.cmd_valid)
                $fatal(1, "Rejected address range reached the backend");
            if (req.w_valid && rsp.w_ready) written++;
            if (rsp.wrsp_valid && req.wrsp_ready) begin
                if (!write_request || written != beats ||
                    rsp.wrsp.resp != hyperbus_pkg::HyperRespDecodeError)
                    $fatal(1, "Incorrect rejected write response after %0d/%0d beats",
                        written, beats);
                write_completed = 1;
            end
            if (rsp.r_valid && req.r_ready) begin
                if (write_request ||
                    rsp.r.resp != (expect_decode_error ? hyperbus_pkg::HyperRespDecodeError :
                                                        hyperbus_pkg::HyperRespOkay) ||
                    rsp.r.last != (returned == beats - 1))
                    $fatal(1, "Incorrect read response beat=%0d last=%b",
                        returned, rsp.r.last);
                if (!expect_decode_error)
                    for (int unsigned lane = 0; lane < 8; lane++)
                        if (rsp.r.data[lane*8 +: 8] !==
                            memory_byte(start_address + returned * 8 + lane))
                            $fatal(1, "Mapped read byte mismatch beat=%0d lane=%0d", returned, lane);
                returned++;
            end
            @(negedge clk);
            cycle++;
        end
        req.w_valid = 0;
        repeat (8) begin
            @(posedge clk);
            if (rsp.r_valid || rsp.wrsp_valid) $fatal(1, "Extra response");
        end
        if ($test$plusargs("out-of-bound"))
            $fatal(1, "Burst-bound assertion failed to reject %0d beats", beats);
        if ($test$plusargs("physical-overflow"))
            $fatal(1, "Physical-span assertion failed to reject %0d bytes", beats * 8);
        if (address_overflow || end_overflow) begin
            if (physical_words != 0)
                $fatal(1, "Rejected address range produced physical read data");
            $display("PASS: address overflow rejected width=%0d PHY=%0d write=%0d beats=%0d",
                HostAddrWidth, NumPhys, write_request, beats);
        end else if (near_address_end) begin
            if (physical_words != 4 || physical_remaining != 0)
                $fatal(1, "Incorrect physical read count at address-space endpoint");
            $display("PASS: exact address-space endpoint width=%0d PHY=%0d", HostAddrWidth, NumPhys);
        end else if (mapped_read) begin
            if (physical_words != beats * 4 || physical_remaining != 0)
                $fatal(1, "Incorrect mapped physical read count %0d", physical_words);
            $display("PASS: generic mapped 32768-byte read with independent payload checks");
        end else begin
            $display("PASS: maximum burst rejected with exactly 256 stalled responses");
        end
        $finish;
    end

    initial begin
        #2ms;
        $fatal(1, "Burst bound test timed out");
    end
endmodule
