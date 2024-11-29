// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Philippe Sauter <phsauter@iis.ee.ethz.ch>

// This modules guarantees proper worst-case sampling of RWDS.
// RWDS may only be valid (and stable) for a single period around 
// the 3rd hyper_ck_o rising edge (see t_DSV, t_CSS, t_CKDS @ 166MHz).
// Since there may be arbitrary pad and PCBs delays, the sampling edge
// is fully configurable (edge number and polarity).
// A gated clock that is only active around one edge is created
// and then the sample is taken only at the selected edge.
// The final sample is saved into a register in the phy clock domain.
//
// It is not possible to sample on the very first rising clock edge
// with this mechanism.
// Therefore cfg_edge_idx_i = 0 selects the first failling edge 
// or the subsequent rising edge, depending on cfg_edge_pol_i.
// With this naming scheme, the default edge should be idx=1, pol=1.
//
// Constraints: 
// cfg* signals are pseudostatic (set_false_path -setup or set_multicycle_path)

`include "common_cells/registers.svh"

module hyperbus_rwds_sampler import hyperbus_pkg::*; #()
(
    // Global signals
    input  logic clk_i, // phy clock
    input  logic rst_ni,
    input  logic test_mode_i,

    input  logic [1:0] cfg_edge_idx_i, // #edge where rwds is sampled
    input  logic       cfg_edge_pol_i, // 1: rising, 0: falling

    // sampled value going to PHY-FSM
    output logic rwds_sample_o,

    // ungated hyperbus clock
    input  logic tx_clk_90_i,

    // physical HyperBus signals
    input  logic hyper_cs_ni,
    input  logic hyper_ck_i,
    input  logic hyper_ck_ni,
    input  logic hyper_rwds_i
);

    // used to time the sampling of RWDS to determine additional latency
    logic [2:0] cnt_edge_d, cnt_edge_q; // one bit larger than config
    logic       start_of_tf_d, start_of_tf_q; // start of transfer indicator
    logic [2:0] cnt_target_value;
    logic       cnt_at_target;
    logic       cnt_clk; // clock used for edge counting
    logic       sampling_clk, sampling_clk_gated; // clock used for sampling
    logic       enable_sampling; // sampling clock gate enable
    logic       rwds_sample;

    assign cnt_target_value = cfg_edge_idx_i + 1;
    assign cnt_at_target    = (cnt_target_value == cnt_edge_q);
    
    always_comb begin : gen_edge_cnt
        // only count at the start of a transfer
        if(start_of_tf_q) begin
            cnt_edge_d = cnt_edge_q +1; // count hyper_ck(_n) edges
        end else begin
            // reset counter for next start of transfer
            cnt_edge_d = 1'b0;
        end
    end
    // sampling on the rising edge requires counting on falling edges to create
    // a window where the clk-gate is transparent around rising edge and vice versa
    tc_clk_mux2 i_cnt_clk_mux (
        .clk0_i    ( hyper_ck_ni     ),
        .clk1_i    ( hyper_ck_i      ),
        .clk_sel_i ( ~cfg_edge_pol_i ),
        .clk_o     ( cnt_clk         )
    );

    `FF(cnt_edge_q, cnt_edge_d, '0, cnt_clk);

    // used to reset counter and ensure clock gate opens only once
    // clocked with ungated clock to detect cs_n going high
    always_comb begin : gen_start_of_transfer
        start_of_tf_d = start_of_tf_q;
        if(hyper_cs_ni) begin
            start_of_tf_d = 1'b1;
        end else if (cnt_at_target) begin
            start_of_tf_d = 1'b0;
        end
    end
    `FF(start_of_tf_q, start_of_tf_d, '0, tx_clk_90_i);

    // TODO: Check proper sampling point in sim
    assign enable_sampling = (cnt_at_target && start_of_tf_q);

    tc_clk_mux2 i_sampling_clk_mux (
        .clk0_i    ( hyper_ck_ni    ),
        .clk1_i    ( hyper_ck_i     ),
        .clk_sel_i ( cfg_edge_pol_i ),
        .clk_o     ( sampling_clk   )
    );

    // gate the sampling of rwds to the selected clock edge
    tc_clk_gating i_rwds_sample_rise_gate (
        .clk_i      ( sampling_clk        ),
        .en_i       ( enable_sampling     ),
        .test_en_i  ( test_mode_i         ),
        .clk_o      ( sampling_clk_gated  )
    );

    // sample rwds exactly once using gated clock
    `FF(rwds_sample, hyper_rwds_i, '0, sampling_clk_gated);

    // pass rwds to phy-clock domain
    `FF(rwds_sample_o, rwds_sample, '0, clk_i);

endmodule
