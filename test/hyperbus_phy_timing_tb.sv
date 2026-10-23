// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

`timescale 1ns/1ps

// Control timing at the macro boundary; full memory transfers are covered by axi_hyper_tb.
module hyperbus_phy_timing_tb;
    import hyperbus_pkg::*;
    localparam time Period = 10ns;
    localparam time TxDelay = 2ns;
    logic clk = 0;
    always #(Period/2) clk = ~clk;
    wire clk_tx;
    assign #(TxDelay) clk_tx = clk;
    logic rst_n = 0;
    phy_cfg_t cfg;
    hyper_tf_t trans;
    logic valid, ready, busy, dq_oe, rwds_oe, ck, tx_valid;
    logic [HyperNumChips-1:0] cs_n;
    logic [7:0] dq_out;
    logic rwds_in = 0;
    logic [7:0] dq_in = 0;
    logic rx_valid, rx_last;
    logic [15:0] rx_data;
    int rx_words;
    int segments, latency_checks, sample_checks;
    int ck_edges_in_segment, ca_oe_checks, read_oe_checks, write_data_checks;
    int setup_measurements;
    int read_turnaround_edges;
    time cs_asserted, last_ck, last_sample, first_spacing, end_spacing;
    time rwds_oe_asserted_at, setup_delay, setup_delay_min;
    bit first_ck;
    bit rwds_oe_seen_in_segment;
    bit write_data_seen_in_segment;
    bit nonretained_latency_release;
    bit first_write_payload_edge;

    hyperbus_phy #(.NumPhys(1), .PhyIndex(0), .StartupCycles(4)) dut (
        .clk_i(clk), .clk_tx_i(clk_tx), .rst_ni(rst_n), .test_mode_i(1'b0),
        .cfg_i(cfg), .busy_o(busy), .trans_valid_i(valid), .trans_ready_o(ready),
        .trans_i(trans), .trans_cs_i(HyperNumChips'(1)),
        .tx_valid_i(tx_valid), .tx_ready_o(), .tx_data_i(16'ha53c),
        .tx_strb_i(2'b11), .tx_last_i(1'b0),
        .rx_valid_o(rx_valid), .rx_ready_i(1'b1), .rx_data_o(rx_data),
        .rx_error_o(), .rx_last_o(rx_last),
        .b_valid_o(), .b_ready_i(1'b1), .b_error_o(),
        .hyper_cs_no(cs_n), .hyper_ck_o(ck), .hyper_ck_no(),
        .hyper_rwds_o(), .hyper_rwds_i(rwds_in), .hyper_rwds_oe_o(rwds_oe),
        .hyper_dq_i(dq_in), .hyper_dq_o(dq_out), .hyper_dq_oe_o(dq_oe)
    );

    always @(negedge cs_n[0]) if (rst_n) begin
        cs_asserted = $time;
        first_ck = 1;
        ck_edges_in_segment = 0;
        rwds_oe_seen_in_segment = 0;
        write_data_seen_in_segment = 0;
        nonretained_latency_release = 0;
        read_turnaround_edges = 0;
        segments++;
    end

    // This initial CS-to-CK equation is a documented integration contract.
    always @(posedge ck) if (rst_n && first_ck) begin
        if ($time - cs_asserted != cfg.chip[0].csn_to_ck_cycles * Period +
                                   Period/2 + TxDelay)
            $fatal(1, "CS-to-CK interval wrong on segment %0d: %0t", segments,
                   $time - cs_asserted);
        first_spacing = $time - cs_asserted;
        first_ck = 0;
    end

    always @(negedge ck) if (rst_n) last_ck = $time;
    always @(posedge cs_n[0]) if (rst_n && segments != 0) begin
        end_spacing = $time - last_ck;
        // Starvation may have stopped CK well before the segment timer expires.
        if (end_spacing < (cfg.chip[0].t_csh_cycles + 1) * Period - TxDelay)
            $fatal(1, "Final CK-to-CS interval wrong: %0t", end_spacing);
    end

    always @(posedge clk) if (rst_n && dut.trx_rwds_sample_ena) begin
        if (segments > sample_checks && last_sample != 0 &&
            $time - cs_asserted != last_sample)
            $fatal(1, "RWDS sample offset changed at segment restart");
        last_sample = $time - cs_asserted;
        sample_checks++;
    end

    always @(posedge rwds_oe) if (rst_n && !cs_n[0] && !trans.address_space) begin
        rwds_oe_asserted_at = $time;
        rwds_oe_seen_in_segment = 1;
    end

    // Observe ownership and data at CK edges, separating six CA edges from payload.
    always @(posedge ck or negedge ck) begin
        if (rst_n && !cs_n[0]) begin
            #1ps;
            first_write_payload_edge = 0;
            if (ck_edges_in_segment < 6) begin
                ca_oe_checks++;
                if (!dq_oe)
                    $fatal(1, "DQ OE was not active for CA edge %0d", ck_edges_in_segment);
            end else if (trans.write) begin
                if (!write_data_seen_in_segment && dq_oe &&
                    ((ck && dq_out == 8'ha5) || (!ck && dq_out == 8'h3c))) begin
                    write_data_seen_in_segment = 1;
                    first_write_payload_edge = 1;
                end
                if (write_data_seen_in_segment) begin
                    write_data_checks++;
                    if (!dq_oe)
                        $fatal(1, "DQ OE was inactive on write payload CK edge");
                    if (!cfg.chip[0].keep_dq_driven && !trans.address_space &&
                        !nonretained_latency_release)
                        $fatal(1, "Non-retained write never released DQ OE during latency");
                    if (ck && dq_out !== 8'ha5)
                        $fatal(1, "Write payload high byte mismatch at CK rising edge: %h", dq_out);
                    if (!ck && dq_out !== 8'h3c)
                        $fatal(1, "Write payload low byte mismatch at CK falling edge: %h", dq_out);
                    if (first_write_payload_edge && !trans.address_space &&
                        cfg.phy[0].rwds_oe_setup_cycles != 0) begin
                        if (!rwds_oe_seen_in_segment)
                            $fatal(1, "RWDS OE had not asserted before write payload");
                        setup_delay = $time - rwds_oe_asserted_at;
                        setup_measurements++;
                        if (setup_measurements == 1 || setup_delay < setup_delay_min)
                            setup_delay_min = setup_delay;
                        if (setup_delay < cfg.phy[0].rwds_oe_setup_cycles * Period)
                            $fatal(1, "RWDS OE setup too short: observed=%0t minimum=%0t",
                                   setup_delay, cfg.phy[0].rwds_oe_setup_cycles * Period);
                    end
                end else begin
                    latency_checks++;
                    if (cfg.chip[0].keep_dq_driven && !dq_oe)
                        $fatal(1, "Retained DQ OE dropped during write latency");
                    if (!cfg.chip[0].keep_dq_driven && !dq_oe)
                        nonretained_latency_release = 1;
                end
                if (trans.address_space && rwds_oe)
                    $fatal(1, "Host RWDS enabled during zero-latency write");
            end else begin
                read_turnaround_edges++;
                // Allow one CK cycle after CA for DQ turnaround.
                if (read_turnaround_edges > 2) begin
                    if (dq_oe !== 1'b0 || rwds_oe !== 1'b0)
                        $fatal(1, "Host output enable active during read CK edges");
                    read_oe_checks++;
                end
            end
            ck_edges_in_segment++;
        end
    end

    always @(posedge rwds_in or negedge rwds_in) if (rst_n && !trans.write) begin
        if (dq_oe !== 1'b0 || rwds_oe !== 1'b0)
            $fatal(1, "Host output enable active during delayed read return");
    end

    always @(posedge clk) if (rst_n && rx_valid) begin
        if (rx_data !== 16'h5ac3)
            $fatal(1, "Delayed read data mismatch: %h", rx_data);
        rx_words++;
    end

    task automatic run_case(input bit keep_dq, input int cs_delay, input bit extra,
                            input int setup_cycles, input int sample_delay,
                            input bit read_access, input bit zero_latency,
                            input int csh_cycles);
        @(negedge clk);
        rst_n = 0;
        valid = 0;
        tx_valid = 0;
        cfg = '0;
        cfg.chip[0].t_latency_access = 6;
        cfg.chip[0].keep_dq_driven = keep_dq;
        cfg.chip[0].en_latency_additional = extra;
        cfg.chip[0].rwds_sample_delay = 4'(sample_delay);
        cfg.chip[0].csn_to_ck_cycles = 4'(cs_delay);
        cfg.chip[0].t_read_write_recovery = 6;
        cfg.chip[0].t_csh_cycles = 4'(csh_cycles);
        cfg.chip[0].t_burst_max = 8;
        cfg.phy[0].rwds_oe_setup_cycles = 4'(setup_cycles);
        trans = '0;
        trans.write = !read_access;
        trans.address_space = zero_latency;
        trans.burst = read_access ? 1 : 24;
        segments = 0;
        latency_checks = 0;
        sample_checks = 0;
        ck_edges_in_segment = 0;
        ca_oe_checks = 0;
        read_oe_checks = 0;
        write_data_checks = 0;
        read_turnaround_edges = 0;
        setup_measurements = 0;
        setup_delay_min = 0;
        rwds_oe_seen_in_segment = 0;
        write_data_seen_in_segment = 0;
        nonretained_latency_release = 0;
        rx_words = 0;
        rwds_in = 0;
        dq_in = 0;
        last_sample = 0;
        repeat (3) @(negedge clk);
        rst_n = 1;
        wait (ready);
        @(negedge clk);
        valid = 1;
        @(posedge clk);
        if (!ready) $fatal(1, "Command was not accepted");
        @(negedge clk);
        valid = 0;
        if (read_access) begin
            wait (cs_n[0] === 1'b0);
            @(posedge cs_n[0]);
            #1ps;
            if (dq_oe || rwds_oe)
                $fatal(1, "Host output enable remained active before delayed read return");
            // Return one word well after the PHY has armed the RWDS capture path.
            #25ns;
            dq_in = 8'h5a;
            #3ns rwds_in = 1;
            #3ns dq_in = 8'hc3;
            #3ns rwds_in = 0;
            #3ns rwds_in = 1;
            #3ns rwds_in = 0;
            wait (rx_words == 1);
            if (!rx_last) $fatal(1, "Delayed read word did not complete the transaction");
            wait (!busy);
        end else begin
            // Exercise late write data independently of pad setup.
            repeat (25) @(negedge clk);
            tx_valid = 1;
            wait (!busy);
            if (segments < 2) $fatal(1, "Segment restart was not exercised");
        end
        if (!zero_latency && !read_access && latency_checks == 0)
            $fatal(1, "Pad-observed write latency OE check was vacuous");
        if (ca_oe_checks < 6 * segments)
            $fatal(1, "CA OE check did not cover six CK edges per segment");
        if (read_access && read_oe_checks == 0)
            $fatal(1, "Pad-observed read OE check was vacuous");
        if (!read_access && write_data_checks == 0)
            $fatal(1, "Pad-observed write payload check was vacuous");
        if (setup_cycles != 0 && !read_access && !zero_latency &&
            setup_measurements == 0)
            $fatal(1, "RWDS OE setup was not measured before write payload");
        if (!zero_latency && sample_checks != segments)
            $fatal(1, "RWDS sample count %0d differs from segments %0d", sample_checks, segments);
        if (read_access && rx_words != 1)
            $fatal(1, "Delayed read completion was not observed");
        $display("[PHY-TIMING] keep=%0d cs=%0d extra=%0d setup=%0d setup_min=%0t measurements=%0d sample=%0d read=%0d zero=%0d csh=%0d segments=%0d passed",
                 keep_dq, cs_delay, extra, setup_cycles, setup_delay_min,
                 setup_measurements, sample_delay, read_access, zero_latency,
                 csh_cycles, segments);
    endtask

    initial begin
        for (int keep = 0; keep < 2; keep++) begin
            run_case(1'(keep), 0, 0, 1, 0, 0, 0, 1);
            run_case(1'(keep), 1, 1, 1, 2, 0, 0, 1);
            run_case(1'(keep), 3, 0, 15, 4, 0, 0, 3);
            run_case(1'(keep), 2, 0, 1, 0, 0, 1, 1);
            run_case(1'(keep), 3, 1, 1, 2, 1, 0, 1);
            run_case(1'(keep), 3, 1, 1, 2, 1, 0, 4);
        end
        $display("[PHY-TIMING] all checks passed");
        $finish;
    end

    initial begin
        #100us;
        $fatal(1, "PHY timing test timed out");
    end
endmodule
