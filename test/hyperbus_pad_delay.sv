// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

`timescale 1 ns/1 ps

import hyperbus_tb_pkg::*;

// Behavioral pad-side timing adapter.  tick_i is the pad-delay reference clock,
// with one edge representing one quarter HyperBus cycle.  Non-zero delays use
// sampled, tick-owned pipelines: a source value must be stable before a tick
// to be captured on that tick, and a pulse shorter than one quarter cycle may
// therefore be unobserved.  N=1 is the first subsequent tick; N=0 is direct.
module hyperbus_pad_delay #(
    parameter int unsigned NumPhys = 1,
    parameter int unsigned NumConnectedChips = 1,
    parameter int unsigned NumChips = NumConnectedChips
) (
    input  logic tick_i,
    input  logic rst_ni,
    input  pad_delay_cfg_t cfg_i,

    input  logic [NumPhys-1:0][NumChips-1:0] cs_n_i,
    input  logic [NumPhys-1:0]               ck_i,
    input  logic [NumPhys-1:0]               ck_n_i,
    input  logic [NumPhys-1:0]               rwds_o_i,
    input  logic [NumPhys-1:0][7:0]          dq_o_i,
    input  logic [NumPhys-1:0]               reset_n_i,
    input  logic [NumPhys-1:0]               dq_oe_i,
    input  logic [NumPhys-1:0]               rwds_oe_i,

    output logic [NumPhys-1:0][NumChips-1:0] cs_n_o,
    output logic [NumPhys-1:0]               ck_o,
    output logic [NumPhys-1:0]               ck_n_o,
    output logic [NumPhys-1:0]               rwds_o_o,
    output logic [NumPhys-1:0][7:0]          dq_o_o,
    output logic [NumPhys-1:0]               reset_n_o,
    output logic [NumPhys-1:0]               dq_oe_o,
    output logic [NumPhys-1:0]               rwds_oe_o,

    input  logic [NumPhys-1:0]               rwds_i_pad,
    input  logic [NumPhys-1:0][7:0]          dq_i_pad,
    output logic [NumPhys-1:0]               rwds_i,
    output logic [NumPhys-1:0][7:0]          dq_i
);

    localparam int unsigned DelayStages = 64;

    typedef struct packed {
        logic [NumPhys-1:0][NumChips-1:0] cs_n;
        logic [NumPhys-1:0]               ck;
        logic [NumPhys-1:0]               ck_n;
        logic [NumPhys-1:0]               rwds_o;
        logic [NumPhys-1:0][7:0]          dq_o;
        logic [NumPhys-1:0]               reset_n;
    } output_bundle_t;

    typedef struct packed {
        logic [NumPhys-1:0]      rwds;
        logic [NumPhys-1:0][7:0] dq;
    } input_bundle_t;

    output_bundle_t output_stage_q [0:DelayStages-1];
    input_bundle_t  input_stage_q  [0:DelayStages-1];

    logic [NumPhys-1:0] dq_oe_state_q;
    logic [NumPhys-1:0] rwds_oe_state_q;
    logic [NumPhys-1:0] dq_oe_pending_q;
    logic [NumPhys-1:0] rwds_oe_pending_q;
    logic [NumPhys-1:0] dq_oe_target_q;
    logic [NumPhys-1:0] rwds_oe_target_q;
    logic [NumPhys-1:0][6:0] dq_oe_remaining_q;
    logic [NumPhys-1:0][6:0] rwds_oe_remaining_q;
    logic [NumPhys-1:0] dq_oe_last_req_q;
    logic [NumPhys-1:0] rwds_oe_last_req_q;
    logic [NumPhys-1:0] dq_oe_immediate_state_q;
    logic [NumPhys-1:0] rwds_oe_immediate_state_q;
    logic [NumPhys-1:0][31:0] dq_oe_immediate_epoch_q;
    logic [NumPhys-1:0][31:0] rwds_oe_immediate_epoch_q;
    logic [NumPhys-1:0][31:0] dq_oe_immediate_seen_q;
    logic [NumPhys-1:0][31:0] rwds_oe_immediate_seen_q;

    // Initialize the behavioral state so a testbench that starts with reset
    // low is deterministic even before the first tick edge is scheduled.
    initial begin
        for (int unsigned s = 0; s < DelayStages; s++) begin
            output_stage_q[s] = '{cs_n: '1, ck: '0, ck_n: '1, rwds_o: '0,
                                  dq_o: '0, reset_n: '0};
            input_stage_q[s] = '0;
        end
        dq_oe_state_q = '0;
        rwds_oe_state_q = '0;
        dq_oe_pending_q = '0;
        rwds_oe_pending_q = '0;
        dq_oe_target_q = '0;
        rwds_oe_target_q = '0;
        dq_oe_remaining_q = '0;
        rwds_oe_remaining_q = '0;
        dq_oe_last_req_q = '0;
        rwds_oe_last_req_q = '0;
        dq_oe_immediate_state_q = '0;
        rwds_oe_immediate_state_q = '0;
        dq_oe_immediate_epoch_q = '0;
        rwds_oe_immediate_epoch_q = '0;
        dq_oe_immediate_seen_q = '0;
        rwds_oe_immediate_seen_q = '0;
    end

    // Capture zero-delay OE transitions independently of tick_i.  The
    // blocking assignments make the unconsumed immediate state visible to
    // the combinational outputs in the same simulation time step.  These
    // event-owned values are consumed by the tick process above on its next
    // observation edge, at which point a non-zero opposite direction starts
    // its complete countdown.
    always @(dq_oe_i or rst_ni) begin
        if (!rst_ni) begin
            dq_oe_last_req_q = '0;
            dq_oe_immediate_state_q = '0;
            dq_oe_immediate_epoch_q = '0;
        end else begin
            for (int unsigned p = 0; p < NumPhys; p++) begin
                if (dq_oe_i[p] != dq_oe_last_req_q[p]) begin
                    dq_oe_last_req_q[p] = dq_oe_i[p];
                    if (dq_oe_i[p] ? (cfg_i.dq_oe_assert_steps == 0) :
                                     (cfg_i.dq_oe_release_steps == 0)) begin
                        dq_oe_immediate_state_q[p] = dq_oe_i[p];
                        dq_oe_immediate_epoch_q[p] =
                            dq_oe_immediate_epoch_q[p] + 32'd1;
                    end
                end
            end
        end
    end

    always @(rwds_oe_i or rst_ni) begin
        if (!rst_ni) begin
            rwds_oe_last_req_q = '0;
            rwds_oe_immediate_state_q = '0;
            rwds_oe_immediate_epoch_q = '0;
        end else begin
            for (int unsigned p = 0; p < NumPhys; p++) begin
                if (rwds_oe_i[p] != rwds_oe_last_req_q[p]) begin
                    rwds_oe_last_req_q[p] = rwds_oe_i[p];
                    if (rwds_oe_i[p] ? (cfg_i.rwds_oe_assert_steps == 0) :
                                       (cfg_i.rwds_oe_release_steps == 0)) begin
                        rwds_oe_immediate_state_q[p] = rwds_oe_i[p];
                        rwds_oe_immediate_epoch_q[p] =
                            rwds_oe_immediate_epoch_q[p] + 32'd1;
                    end
                end
            end
        end
    end

    // Every state transition is owned by this one tick process.  The whole
    // bundle is sampled together and shifted with nonblocking assignments,
    // preventing CK/CS/DQ from exposing partial same-tick updates.
    // tick_i toggles at each quarter-cycle observation point, so both edges
    // are meaningful samples.  The source must be stable before either edge.
    always @(posedge tick_i or negedge tick_i or negedge rst_ni) begin
        if (!rst_ni) begin
            for (int unsigned s = 0; s < DelayStages; s++) begin
                output_stage_q[s] <= '{cs_n: '1, ck: '0, ck_n: '1, rwds_o: '0,
                                       dq_o: '0, reset_n: '0};
                input_stage_q[s] <= '0;
            end
            dq_oe_state_q <= '0;
            rwds_oe_state_q <= '0;
            dq_oe_pending_q <= '0;
            rwds_oe_pending_q <= '0;
            dq_oe_target_q <= '0;
            rwds_oe_target_q <= '0;
            dq_oe_remaining_q <= '0;
            rwds_oe_remaining_q <= '0;
            dq_oe_immediate_seen_q <= '0;
            rwds_oe_immediate_seen_q <= '0;
        end else begin
            output_stage_q[0] <= '{cs_n: cs_n_i, ck: ck_i, ck_n: ck_n_i,
                                    rwds_o: rwds_o_i, dq_o: dq_o_i,
                                    reset_n: reset_n_i};
            input_stage_q[0] <= '{rwds: rwds_i_pad, dq: dq_i_pad};
            for (int unsigned s = 1; s < DelayStages; s++) begin
                output_stage_q[s] <= output_stage_q[s-1];
                input_stage_q[s] <= input_stage_q[s-1];
            end

            for (int unsigned p = 0; p < NumPhys; p++) begin
                logic dq_effective;
                logic rwds_effective;
                logic dq_immediate_pending;
                logic rwds_immediate_pending;
                logic [6:0] dq_delay;
                logic [6:0] rwds_delay;

                dq_delay = {1'b0, dq_oe_i[p] ? cfg_i.dq_oe_assert_steps :
                                               cfg_i.dq_oe_release_steps};
                dq_immediate_pending =
                    (dq_oe_immediate_epoch_q[p] != dq_oe_immediate_seen_q[p]);
                dq_effective = dq_oe_state_q[p];
                if (dq_immediate_pending) begin
                    // Consume a zero-delay event first.  A current request in
                    // the opposite non-zero direction starts a full delay
                    // from this committed immediate state.
                    dq_effective = dq_oe_immediate_state_q[p];
                    dq_oe_state_q[p] <= dq_effective;
                    dq_oe_immediate_seen_q[p] <= dq_oe_immediate_epoch_q[p];
                    dq_oe_pending_q[p] <= 1'b0;
                    dq_oe_remaining_q[p] <= '0;
                    if (dq_oe_i[p] != dq_effective) begin
                        dq_oe_target_q[p] <= dq_oe_i[p];
                        if (dq_delay == 0) begin
                            dq_oe_state_q[p] <= dq_oe_i[p];
                        end else if (dq_delay == 7'd1) begin
                            dq_oe_state_q[p] <= dq_oe_i[p];
                        end else begin
                            dq_oe_pending_q[p] <= 1'b1;
                            dq_oe_remaining_q[p] <= dq_delay - 7'd1;
                        end
                    end
                end else if (dq_oe_i[p] == dq_oe_state_q[p]) begin
                    dq_oe_pending_q[p] <= 1'b0;
                    dq_oe_remaining_q[p] <= '0;
                end else if (dq_delay == 0) begin
                    dq_oe_state_q[p] <= dq_oe_i[p];
                    dq_oe_pending_q[p] <= 1'b0;
                    dq_oe_remaining_q[p] <= '0;
                end else if (dq_oe_pending_q[p] &&
                             (dq_oe_i[p] == dq_oe_target_q[p])) begin
                    if (dq_oe_remaining_q[p] <= 7'd1) begin
                        dq_oe_state_q[p] <= dq_oe_i[p];
                        dq_oe_pending_q[p] <= 1'b0;
                        dq_oe_remaining_q[p] <= '0;
                    end else begin
                        dq_oe_remaining_q[p] <= dq_oe_remaining_q[p] - 7'd1;
                    end
                end else begin
                    dq_oe_target_q[p] <= dq_oe_i[p];
                    if (dq_delay == 7'd1) begin
                        dq_oe_state_q[p] <= dq_oe_i[p];
                        dq_oe_pending_q[p] <= 1'b0;
                        dq_oe_remaining_q[p] <= '0;
                    end else begin
                        dq_oe_pending_q[p] <= 1'b1;
                        dq_oe_remaining_q[p] <= dq_delay - 7'd1;
                    end
                end

                rwds_delay = {1'b0, rwds_oe_i[p] ? cfg_i.rwds_oe_assert_steps :
                                                   cfg_i.rwds_oe_release_steps};
                rwds_immediate_pending =
                    (rwds_oe_immediate_epoch_q[p] != rwds_oe_immediate_seen_q[p]);
                rwds_effective = rwds_oe_state_q[p];
                if (rwds_immediate_pending) begin
                    rwds_effective = rwds_oe_immediate_state_q[p];
                    rwds_oe_state_q[p] <= rwds_effective;
                    rwds_oe_immediate_seen_q[p] <= rwds_oe_immediate_epoch_q[p];
                    rwds_oe_pending_q[p] <= 1'b0;
                    rwds_oe_remaining_q[p] <= '0;
                    if (rwds_oe_i[p] != rwds_effective) begin
                        rwds_oe_target_q[p] <= rwds_oe_i[p];
                        if (rwds_delay == 0) begin
                            rwds_oe_state_q[p] <= rwds_oe_i[p];
                        end else if (rwds_delay == 7'd1) begin
                            rwds_oe_state_q[p] <= rwds_oe_i[p];
                        end else begin
                            rwds_oe_pending_q[p] <= 1'b1;
                            rwds_oe_remaining_q[p] <= rwds_delay - 7'd1;
                        end
                    end
                end else if (rwds_oe_i[p] == rwds_oe_state_q[p]) begin
                    rwds_oe_pending_q[p] <= 1'b0;
                    rwds_oe_remaining_q[p] <= '0;
                end else if (rwds_delay == 0) begin
                    rwds_oe_state_q[p] <= rwds_oe_i[p];
                    rwds_oe_pending_q[p] <= 1'b0;
                    rwds_oe_remaining_q[p] <= '0;
                end else if (rwds_oe_pending_q[p] &&
                             (rwds_oe_i[p] == rwds_oe_target_q[p])) begin
                    if (rwds_oe_remaining_q[p] <= 7'd1) begin
                        rwds_oe_state_q[p] <= rwds_oe_i[p];
                        rwds_oe_pending_q[p] <= 1'b0;
                        rwds_oe_remaining_q[p] <= '0;
                    end else begin
                        rwds_oe_remaining_q[p] <= rwds_oe_remaining_q[p] - 7'd1;
                    end
                end else begin
                    rwds_oe_target_q[p] <= rwds_oe_i[p];
                    if (rwds_delay == 7'd1) begin
                        rwds_oe_state_q[p] <= rwds_oe_i[p];
                        rwds_oe_pending_q[p] <= 1'b0;
                        rwds_oe_remaining_q[p] <= '0;
                    end else begin
                        rwds_oe_pending_q[p] <= 1'b1;
                        rwds_oe_remaining_q[p] <= rwds_delay - 7'd1;
                    end
                end
            end
        end
    end

    // N=0 is a combinational bypass.  For a direction with zero OE delay,
    // the request also passes through immediately while the registered state
    // catches up on the next tick.
    always_comb begin
        cs_n_o = '1;
        ck_o = '0;
        ck_n_o = '1;
        rwds_o_o = '0;
        dq_o_o = '0;
        reset_n_o = '0;
        rwds_i = '0;
        dq_i = '0;

        if (rst_ni) begin
            if (cfg_i.output_delay_steps == 0) begin
                cs_n_o = cs_n_i;
                ck_o = ck_i;
                ck_n_o = ck_n_i;
                rwds_o_o = rwds_o_i;
                dq_o_o = dq_o_i;
                reset_n_o = reset_n_i;
            end else begin
                cs_n_o = output_stage_q[cfg_i.output_delay_steps - 1].cs_n;
                ck_o = output_stage_q[cfg_i.output_delay_steps - 1].ck;
                ck_n_o = output_stage_q[cfg_i.output_delay_steps - 1].ck_n;
                rwds_o_o = output_stage_q[cfg_i.output_delay_steps - 1].rwds_o;
                dq_o_o = output_stage_q[cfg_i.output_delay_steps - 1].dq_o;
                reset_n_o = output_stage_q[cfg_i.output_delay_steps - 1].reset_n;
            end
            if (cfg_i.input_delay_steps == 0) begin
                rwds_i = rwds_i_pad;
                dq_i = dq_i_pad;
            end else begin
                rwds_i = input_stage_q[cfg_i.input_delay_steps - 1].rwds;
                dq_i = input_stage_q[cfg_i.input_delay_steps - 1].dq;
            end
        end

        dq_oe_o = dq_oe_state_q;
        rwds_oe_o = rwds_oe_state_q;
        for (int unsigned p = 0; p < NumPhys; p++) begin
            if (dq_oe_immediate_epoch_q[p] != dq_oe_immediate_seen_q[p]) begin
                dq_oe_o[p] = dq_oe_immediate_state_q[p];
            end else if (dq_oe_i[p] && (cfg_i.dq_oe_assert_steps == 0)) begin
                dq_oe_o[p] = 1'b1;
            end else if (!dq_oe_i[p] && (cfg_i.dq_oe_release_steps == 0)) begin
                dq_oe_o[p] = 1'b0;
            end
            if (rwds_oe_immediate_epoch_q[p] != rwds_oe_immediate_seen_q[p]) begin
                rwds_oe_o[p] = rwds_oe_immediate_state_q[p];
            end else if (rwds_oe_i[p] && (cfg_i.rwds_oe_assert_steps == 0)) begin
                rwds_oe_o[p] = 1'b1;
            end else if (!rwds_oe_i[p] && (cfg_i.rwds_oe_release_steps == 0)) begin
                rwds_oe_o[p] = 1'b0;
            end
        end
        if (!rst_ni) begin
            dq_oe_o = '0;
            rwds_oe_o = '0;
        end
    end

endmodule
