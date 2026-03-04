// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Philippe Sauter <phsauter@iis.ee.ethz.ch>

// This modules guarantees proper worst-case sampling of RWDS.
// RWDS may only be valid (and stable) for a single period around 
// the 3rd hyper_ck_o rising edge (see t_DSV, t_CSS, t_CKDS @ 166MHz).
// Since there may be arbitrary pad, PCBs, clock latency delays, the sampling edge
// is fully configurable (edge number).
// A gated clock that is only active around one edge is created
// and then the sample is taken only at the selected edge.
// The final sample is saved into a register in the phy clock domain.
//
// It is not possible to sample on the very first rising clock edge
// with this mechanism.


`include "common_cells/registers.svh"

(* no_ungroup *)
(* no_boundary_optimization *)
(* keep_hierarchy = "yes" *)
module hyperbus_rwds_sampler import hyperbus_pkg::*; #()
(
    // Global signals
    input  logic clk_i, // phy 2x clock
    input  logic rst_ni,

    input  logic [4:0] cfg_edge_idx_i, // #edge where rwds is sampled

    // sampled value going to PHY-FSM
    output logic rwds_sample_o,

    // physical HyperBus signals
    input  logic hyper_cs_ni,
    input  logic hyper_rwds_i
);

    // used to time the sampling of RWDS to determine additional latency
    logic [$bits(cfg_edge_idx_i)-1:0] cnt_edge_d, cnt_edge_q;
    logic       sampling_done_q, sampling_done_d;
    logic       enable_sampling; // sampling clock gate enable

    always_comb begin : gen_edge_cnt
        cnt_edge_d = cnt_edge_q;
        sampling_done_d = sampling_done_q;
        enable_sampling = 1'b0;
        // only count during transfers until idx reached
        if(~hyper_cs_ni && ~sampling_done_q) begin
            if(cnt_edge_q == cfg_edge_idx_i) begin
                enable_sampling = 1'b1;
                sampling_done_d = 1'b1;
            end else begin
                cnt_edge_d++;
            end
        end else if(hyper_cs_ni && sampling_done_q ) begin
            // reset state for next transfer
            sampling_done_d = 0;
            cnt_edge_d = 0;
        end
    end

    `FF(cnt_edge_q, cnt_edge_d, '0, clk_i);
    `FF(sampling_done_q, sampling_done_d, '0, clk_i);


    // gate the sampling of rwds to the selected clock edge
    logic sampling_clk_gated;
    tc_clk_gating i_rwds_sample_rise_gate (
        .clk_i      ( clk_i               ),
        .en_i       ( enable_sampling     ),
        .test_en_i  ( 1'b0                ),
        .clk_o      ( sampling_clk_gated  )
    );

    // sample rwds exactly once using gated clock
    `FF(rwds_sample_o, hyper_rwds_i, '0, sampling_clk_gated);

endmodule
