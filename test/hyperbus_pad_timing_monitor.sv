// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

module hyperbus_pad_timing_monitor #(
    parameter int unsigned NumPhys = 1,
    parameter int unsigned NumChips = 1,
    parameter int unsigned TickPeriodPs = 2500
) (
    input logic rst_ni,
    input logic enabled_i,
    input logic end_i,
    input hyperbus_tb_pkg::pad_delay_cfg_t cfg_i,
    input logic [NumPhys-1:0] ideal_ck_i,
    input logic [NumPhys-1:0] delayed_ck_i,
    input logic [NumPhys-1:0] raw_rwds_i,
    input logic [NumPhys-1:0] delayed_rwds_i,
    input logic [NumPhys-1:0] ideal_dq_oe_i,
    input logic [NumPhys-1:0] delayed_dq_oe_i,
    input logic [NumPhys-1:0] ideal_rwds_oe_i,
    input logic [NumPhys-1:0] delayed_rwds_oe_i,
    input logic [NumPhys-1:0][NumChips-1:0] cs_no,
    input logic [NumPhys-1:0][7:0] dq_i,
    input logic [NumPhys-1:0] rwds_i
);
    timeunit 1ps;
    timeprecision 1ps;
    localparam time TickPeriod = TickPeriodPs * 1ps;

    localparam int unsigned OutputAxis = 0;
    localparam int unsigned InputAxis = 1;
    localparam int unsigned DqAssertAxis = 2;
    localparam int unsigned DqReleaseAxis = 3;
    localparam int unsigned RwdsAssertAxis = 4;
    localparam int unsigned RwdsReleaseAxis = 5;
    localparam int unsigned NumAxes = 6;

    for (genvar p = 0; p < NumPhys; p++) begin : gen_phy
        time source_times [NumAxes][$];
        time minimum_delay [NumAxes];
        time maximum_delay [NumAxes];
        int unsigned samples [NumAxes];
        int unsigned ca_edges;
        int unsigned ca_observations;
        int unsigned read_observations;
        bit read_transaction;
        bit read_data_started;

        initial begin
            ca_edges = 0;
            ca_observations = 0;
            read_observations = 0;
            read_transaction = 0;
            read_data_started = 0;
            for (int a = 0; a < NumAxes; a++) begin
                minimum_delay[a] = 0;
                maximum_delay[a] = 0;
                samples[a] = 0;
            end
        end

        always @(negedge rst_ni) begin
            ca_edges = 0;
            ca_observations = 0;
            read_observations = 0;
            read_transaction = 0;
            read_data_started = 0;
            for (int a = 0; a < NumAxes; a++) begin
                source_times[a].delete();
                minimum_delay[a] = 0;
                maximum_delay[a] = 0;
                samples[a] = 0;
            end
        end

        // Queue source events, not sampled values: lost/coalesced pulses must fail.
        task automatic measure_delay(input int unsigned axis,
                                     input int unsigned ticks,
                                     input time destination_time);
            time source_time;
            time realized_delay;
            time earliest;
            time latest;
            if (ticks != 0) begin
                // Preserve the edge timestamp while settling same-time event ordering.
                #1ps;
                if (source_times[axis].size() == 0)
                    $fatal(1, "[PAD-MEASURE] phy=%0d axis=%0d unmatched destination edge", p, axis);
                source_time = source_times[axis].pop_front();
                if (destination_time < source_time)
                    $fatal(1, "[PAD-MEASURE] phy=%0d axis=%0d destination preceded source", p, axis);
                realized_delay = destination_time - source_time;
                earliest = ticks * TickPeriod - TickPeriod;
                latest = ticks * TickPeriod;
                if (realized_delay + 1ps < earliest || realized_delay > latest + 1ps)
                    $fatal(1, "[PAD-MEASURE] phy=%0d axis=%0d delay_ps=%0d expected_ps=[%0d,%0d]",
                           p, axis, realized_delay, earliest, latest);
                if (samples[axis] == 0 || realized_delay < minimum_delay[axis])
                    minimum_delay[axis] = realized_delay;
                if (samples[axis] == 0 || realized_delay > maximum_delay[axis])
                    maximum_delay[axis] = realized_delay;
                samples[axis]++;
            end
        endtask

        always @(posedge ideal_ck_i[p])
            if (rst_ni && enabled_i && ideal_ck_i[p] === 1'b1 &&
                cfg_i.output_delay_steps != 0)
                source_times[OutputAxis].push_back($time);
        always @(posedge delayed_ck_i[p])
            if (rst_ni && enabled_i && delayed_ck_i[p] === 1'b1)
                measure_delay(OutputAxis, int'(cfg_i.output_delay_steps), $time);

        // Measure memory read strobes, not host write-mask transitions or the
        // latency indication. Return edges may arrive after CS has deasserted.
        always @(posedge raw_rwds_i[p]) begin
            automatic time edge_time = $time;
            #1ps;
            if (rst_ni && enabled_i && raw_rwds_i[p] === 1'b1 &&
                cfg_i.input_delay_steps != 0 && ca_edges == 6 &&
                read_transaction && !$isunknown(dq_i[p]) &&
                delayed_rwds_oe_i[p] === 1'b0)
                source_times[InputAxis].push_back(edge_time);
        end
        always @(posedge delayed_rwds_i[p]) begin
            automatic time edge_time = $time;
            // Source qualification settles for 1 ps, including zero-time
            // sampled returns. Check its queue only after that has completed.
            #2ps;
            if (rst_ni && enabled_i && delayed_rwds_i[p] === 1'b1 &&
                source_times[InputAxis].size() != 0 &&
                edge_time >= source_times[InputAxis][0] &&
                (edge_time - source_times[InputAxis][0] + 1ps >=
                 (int'(cfg_i.input_delay_steps) - 1) * TickPeriod))
                measure_delay(InputAxis, int'(cfg_i.input_delay_steps), edge_time);
        end

        always @(posedge ideal_dq_oe_i[p])
            if (rst_ni && enabled_i && ideal_dq_oe_i[p] === 1'b1 &&
                cfg_i.dq_oe_assert_steps != 0)
                source_times[DqAssertAxis].push_back($time);
        always @(posedge delayed_dq_oe_i[p])
            if (rst_ni && enabled_i && delayed_dq_oe_i[p] === 1'b1)
                measure_delay(DqAssertAxis, int'(cfg_i.dq_oe_assert_steps), $time);
        always @(negedge ideal_dq_oe_i[p])
            if (rst_ni && enabled_i && ideal_dq_oe_i[p] === 1'b0 &&
                cfg_i.dq_oe_release_steps != 0)
                source_times[DqReleaseAxis].push_back($time);
        always @(negedge delayed_dq_oe_i[p])
            if (rst_ni && enabled_i && delayed_dq_oe_i[p] === 1'b0)
                measure_delay(DqReleaseAxis, int'(cfg_i.dq_oe_release_steps), $time);

        always @(posedge ideal_rwds_oe_i[p])
            if (rst_ni && enabled_i && ideal_rwds_oe_i[p] === 1'b1 &&
                cfg_i.rwds_oe_assert_steps != 0)
                source_times[RwdsAssertAxis].push_back($time);
        always @(posedge delayed_rwds_oe_i[p])
            if (rst_ni && enabled_i && delayed_rwds_oe_i[p] === 1'b1)
                measure_delay(RwdsAssertAxis, int'(cfg_i.rwds_oe_assert_steps), $time);
        always @(negedge ideal_rwds_oe_i[p])
            if (rst_ni && enabled_i && ideal_rwds_oe_i[p] === 1'b0 &&
                cfg_i.rwds_oe_release_steps != 0)
                source_times[RwdsReleaseAxis].push_back($time);
        always @(negedge delayed_rwds_oe_i[p])
            if (rst_ni && enabled_i && delayed_rwds_oe_i[p] === 1'b0)
                measure_delay(RwdsReleaseAxis, int'(cfg_i.rwds_oe_release_steps), $time);

        always @(posedge (&cs_no[p])) begin
            ca_edges = 0;
            read_transaction = 0;
            read_data_started = 0;
        end

        // This deliberately decodes only CA[47] (read), not the memory protocol.
        always @(posedge delayed_ck_i[p] or negedge delayed_ck_i[p]) begin
            #1ps;
            if (rst_ni && enabled_i && ((&cs_no[p]) === 1'b0) && ca_edges < 6) begin
                if (delayed_dq_oe_i[p] !== 1'b1 || $isunknown(dq_i[p]))
                    $fatal(1, "[PAD-PINS] phy=%0d CA edge=%0d requires driven known DQ", p, ca_edges);
                if (delayed_rwds_oe_i[p] !== 1'b0)
                    $fatal(1, "[PAD-PINS] phy=%0d host drove RWDS during CA", p);
                if (ca_edges == 0) read_transaction = dq_i[p][7];
                ca_edges++;
                ca_observations++;
            end
        end

        always @(posedge rwds_i[p] or negedge rwds_i[p]) begin
            #1ps;
            // The latency indication can fall while the host still holds CA.
            // Read data starts with the following known rising RWDS edge.
            if (rst_ni && enabled_i && ((&cs_no[p]) === 1'b0) &&
                ca_edges == 6 && read_transaction && !$isunknown(rwds_i[p])) begin
                if (rwds_i[p] === 1'b1) read_data_started = 1;
                if (read_data_started && !$isunknown(dq_i[p])) begin
                    if (delayed_dq_oe_i[p] !== 1'b0 || delayed_rwds_oe_i[p] !== 1'b0)
                        $fatal(1, "[PAD-PINS] phy=%0d host drove DQ/RWDS during read data", p);
                    read_observations++;
                end
            end
        end

        task automatic report_axis(input int unsigned axis,
                                   input string name,
                                   input int unsigned ticks);
            $display("[PAD-MEASURE] phy=%0d axis=%s samples=%0d min_ps=%0d max_ps=%0d",
                     p, name, samples[axis], minimum_delay[axis], maximum_delay[axis]);
            if (ticks != 0 && samples[axis] == 0)
                $fatal(1, "[PAD-MEASURE] phy=%0d axis=%s has no measured transitions", p, name);
            if (source_times[axis].size() != 0)
                $fatal(1, "[PAD-MEASURE] phy=%0d axis=%s pending=%0d source transitions",
                       p, name, source_times[axis].size());
        endtask

        always @(posedge end_i) begin
            #1ps;
            if (enabled_i) begin
                report_axis(OutputAxis, "out", int'(cfg_i.output_delay_steps));
                report_axis(InputAxis, "in", int'(cfg_i.input_delay_steps));
                report_axis(DqAssertAxis, "dq_assert", int'(cfg_i.dq_oe_assert_steps));
                report_axis(DqReleaseAxis, "dq_release", int'(cfg_i.dq_oe_release_steps));
                report_axis(RwdsAssertAxis, "rwds_assert", int'(cfg_i.rwds_oe_assert_steps));
                report_axis(RwdsReleaseAxis, "rwds_release", int'(cfg_i.rwds_oe_release_steps));
                $display("[PAD-PINS] phy=%0d ca_edges=%0d read_edges=%0d",
                         p, ca_observations, read_observations);
                if (ca_observations == 0 || read_observations == 0)
                    $fatal(1, "[PAD-MEASURE] phy=%0d missing CA/read coverage", p);
            end
        end
    end
endmodule
