// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

module hyperbus_read_counter_tb #(
    parameter int unsigned NumPhys = 1,
    parameter int unsigned HostDataWidth = 64,
    parameter int unsigned MaxHostBurstBeats = 256
);
    timeunit 1ns;
    timeprecision 1ps;
    localparam int unsigned HostBytes = HostDataWidth / 8;
    localparam int unsigned AddrWidth = $clog2(HostBytes);
    localparam int unsigned ConvertedBytes = 2 * NumPhys;
    localparam int unsigned BurstBeats = MaxHostBurstBeats == 0 ? 300 : MaxHostBurstBeats;
    localparam int unsigned OptimizedWidth = MaxHostBurstBeats == 0 ?
        hyperbus_pkg::HyperBurstWidth + AddrWidth : $clog2(MaxHostBurstBeats * HostBytes + 1);
    typedef struct packed {
        logic [HostDataWidth-1:0] data;
        hyperbus_pkg::hyper_resp_e resp;
        logic last;
        logic atomic_ok;
    } read_t;

    logic clk = 0;
    logic rst_n = 0;
    logic [2:0] size;
    logic start, dual_phy, host_ready, phy_valid, phy_last, phy_error;
    logic [AddrWidth-1:0] start_addr;
    logic [hyperbus_pkg::HyperBurstWidth-1:0] burst_len;
    logic [16*NumPhys-1:0] phy_data;
    logic opt_host_valid, opt_phy_ready;
    logic ref_host_valid, ref_phy_ready;
    read_t opt_data, ref_data;
    int unsigned cycle;

    hyperbus_read_adapter #(
        .HostDataWidth(HostDataWidth), .NumPhys(NumPhys), .T(read_t),
        .BurstLength(hyperbus_pkg::HyperBurstWidth), .CounterWidth(OptimizedWidth)
    ) i_optimized (
        .clk_i(clk), .rst_ni(rst_n), .size_i(size), .start_i(start),
        .dual_phy_i(dual_phy), .start_addr_i(start_addr), .burst_len_i(burst_len),
        .host_valid_o(opt_host_valid), .host_ready_i(host_ready), .data_o(opt_data),
        .phy_valid_i(phy_valid), .phy_ready_o(opt_phy_ready), .data_i(phy_data),
        .last_i(phy_last), .error_i(phy_error)
    );

    hyperbus_read_adapter #(
        .HostDataWidth(HostDataWidth), .NumPhys(NumPhys), .T(read_t),
        .BurstLength(hyperbus_pkg::HyperBurstWidth)
    ) i_reference (
        .clk_i(clk), .rst_ni(rst_n), .size_i(size), .start_i(start),
        .dual_phy_i(dual_phy), .start_addr_i(start_addr), .burst_len_i(burst_len),
        .host_valid_o(ref_host_valid), .host_ready_i(host_ready), .data_o(ref_data),
        .phy_valid_i(phy_valid), .phy_ready_o(ref_phy_ready), .data_i(phy_data),
        .last_i(phy_last), .error_i(phy_error)
    );

    always #5ns clk = ~clk;

    // Address-dependent bytes expose dropped/repeated words and counter wrap independently
    // of the default-width instance used for the differential control check.
    function automatic logic [7:0] memory_byte(input int unsigned address);
        return 8'((address * 37) ^ (address >> 8) ^ (address >> 16) ^ 'h5a);
    endfunction

    task automatic run_case(input int unsigned transfer_size, offset, beat_count,
                            input bit use_dual, stall_host, stall_producer,
                            input bit inject_error = 0);
        int unsigned physical_beats, physical_index, host_beats, final_count, elapsed;
        int unsigned phy_bytes, physical_start, transfer_start, transfer_end, host_address;
        bit producer_stalled;
        bit previous_stall;
        bit access_error_seen;
        read_t held_data;
        phy_bytes = use_dual ? 4 : 2;
        // The dual implementation always assembles four-byte converted words.
        physical_start = (offset / ConvertedBytes) * ConvertedBytes;
        transfer_start = (offset >> transfer_size) << transfer_size;
        transfer_end = transfer_start + beat_count * (1 << transfer_size);
        physical_beats = (((transfer_end + ConvertedBytes - 1) / ConvertedBytes) *
            ConvertedBytes - physical_start) / phy_bytes;
        host_address = offset;
        physical_index = 0;
        host_beats = 0;
        final_count = 0;
        elapsed = 0;
        previous_stall = 0;
        producer_stalled = 0;
        access_error_seen = 0;
        @(negedge clk);
        size = 3'(transfer_size);
        start_addr = AddrWidth'(offset);
        burst_len = hyperbus_pkg::hyper_blen_t'(beat_count);
        dual_phy = use_dual;
        start = 1;
        phy_valid = 0;
        phy_last = 0;
        phy_error = 0;
        host_ready = 0;
        @(negedge clk);
        start = 0;
        phy_valid = 1;
        phy_data = '0;
        while (host_beats < beat_count) begin
            elapsed++;
            if (elapsed > 20 * (physical_beats + beat_count + 1))
                $fatal(1, "Read timeout PHY=%0d WIDTH=%0d SIZE=%0d offset=%0d host=%0d phys=%0d/%0d",
                    NumPhys, HostDataWidth, transfer_size, offset, host_beats,
                    physical_index, physical_beats);
            host_ready = !stall_host || ((cycle % 7) != 2 && (cycle % 7) != 3);
            phy_valid = physical_index < physical_beats &&
                (producer_stalled || !stall_producer || (cycle % 5) != 1);
            phy_last = physical_index == physical_beats - 1;
            // Keep the error with the first physical beat until it is accepted.
            phy_error = inject_error && physical_index == 0;
            for (int lane = 0; lane < 2*NumPhys; lane++)
                phy_data[lane*8 +: 8] = memory_byte(physical_start +
                    physical_index * phy_bytes + lane);
            #1ps;
            if (opt_host_valid != ref_host_valid || opt_phy_ready != ref_phy_ready ||
                (opt_host_valid && opt_data !== ref_data))
                $fatal(1, "Optimized/reference mismatch NumPhys=%0d SIZE=%0d offset=%0d beat=%0d",
                    NumPhys, transfer_size, offset, host_beats);
            if (previous_stall && (!opt_host_valid || opt_data !== held_data))
                $fatal(1, "Host response changed while stalled");
            if (opt_host_valid && !host_ready) begin
                previous_stall = 1;
                held_data = opt_data;
            end else begin
                previous_stall = 0;
            end
            @(posedge clk);
            producer_stalled = phy_valid && !opt_phy_ready;
            if (phy_valid && opt_phy_ready) physical_index++;
            if (opt_host_valid && host_ready) begin
                int unsigned next_address, host_base;
                next_address = ((host_address >> transfer_size) + 1) << transfer_size;
                host_base = (host_address / HostBytes) * HostBytes;
                for (int unsigned address = host_address; address < next_address; address++)
                    if (opt_data.data[(address - host_base)*8 +: 8] !== memory_byte(address))
                        $fatal(1, "Read byte mismatch PHY=%0d WIDTH=%0d dual=%0d SIZE=%0d offset=%0d beat=%0d address=%0d got=%h expected=%h",
                            NumPhys, HostDataWidth, use_dual, transfer_size, offset, host_beats,
                            address, opt_data.data[(address - host_base)*8 +: 8], memory_byte(address));
                if (opt_data.atomic_ok ||
                    (!inject_error && opt_data.resp != hyperbus_pkg::HyperRespOkay) ||
                    (inject_error && opt_data.resp != hyperbus_pkg::HyperRespOkay &&
                        opt_data.resp != hyperbus_pkg::HyperRespAccessError))
                    $fatal(1, "Incorrect response metadata");
                if (opt_data.resp == hyperbus_pkg::HyperRespAccessError)
                    access_error_seen = 1;
                if (opt_data.last !== (host_beats == beat_count - 1))
                    $fatal(1, "Incorrect LAST PHY=%0d WIDTH=%0d beat=%0d/%0d",
                        NumPhys, HostDataWidth, host_beats, beat_count);
                if (opt_data.last) begin
                    final_count++;
                    if (host_beats != beat_count - 1)
                        $fatal(1, "Early final response NumPhys=%0d SIZE=%0d offset=%0d beat=%0d",
                            NumPhys, transfer_size, offset, host_beats);
                end
                host_address = next_address;
                host_beats++;
            end
            @(negedge clk);
        end
        if (final_count != 1 || physical_index != physical_beats)
            $fatal(1, "Incomplete burst NumPhys=%0d SIZE=%0d offset=%0d hosts=%0d phys=%0d/%0d final=%0d",
                NumPhys, transfer_size, offset, host_beats, physical_index,
                physical_beats, final_count);
        // Error attribution is transaction-level, not per affected byte or host beat.
        if (inject_error && !access_error_seen)
            $fatal(1, "Accepted physical error was not propagated to the host transaction");
        phy_valid = 0;
        phy_error = 0;
        host_ready = 1;
        repeat (3) begin
            @(posedge clk);
            if (opt_host_valid || ref_host_valid)
                $fatal(1, "Unexpected extra host response");
            @(negedge clk);
        end
    endtask

    initial begin
        size = 0;
        start = 0;
        dual_phy = 0;
        start_addr = 0;
        burst_len = 0;
        host_ready = 0;
        phy_valid = 0;
        phy_last = 0;
        phy_error = 0;
        phy_data = '0;
        cycle = 0;
        repeat (4) @(negedge clk);
        rst_n = 1;
        // Consecutive distinct physical words, followed by independent stall combinations.
        for (int unsigned stalls = 0; stalls < 4; stalls++)
            run_case(AddrWidth, 0, 2, NumPhys == 2, stalls[0], stalls[1]);
        for (int unsigned transfer_size = 0; transfer_size <= AddrWidth; transfer_size++)
            for (int unsigned offset = 0; offset < HostBytes; offset++)
                if (HostDataWidth <= 64 || offset == 0 || offset == HostBytes - 1) begin
                    run_case(transfer_size, offset, BurstBeats, NumPhys == 2, 1, 1);
                    if (NumPhys == 2)
                        run_case(transfer_size, offset, BurstBeats, 0, 1, 1);
                end
        // A narrow transfer reuses converted data across responses under backpressure.
        run_case(0, 0, 4, NumPhys == 2, 1, 1, 1);
        if (NumPhys == 2)
            run_case(0, 0, 4, 0, 1, 1, 1);
        // The original 15-bit default wrapped at 32768 bytes, including at unaligned starts.
        if (MaxHostBurstBeats == 0 && HostDataWidth == 64)
            run_case(AddrWidth, HostBytes - 1, 4096, NumPhys == 2, 1, 1);
        if (MaxHostBurstBeats == 0 && HostDataWidth == 1024)
            run_case(AddrWidth, HostBytes - 1, 256, NumPhys == 2, 1, 1);
        $display("Read counter tests passed (NumPhys=%0d HostDataWidth=%0d MaxHostBurstBeats=%0d)",
            NumPhys, HostDataWidth, MaxHostBurstBeats);
        $finish;
    end

    always @(posedge clk) cycle <= cycle + 1;

    initial begin
        #30ms;
        $fatal(1, "Read counter test timed out (NumPhys=%0d MaxHostBurstBeats=%0d)",
            NumPhys, MaxHostBurstBeats);
    end
endmodule
