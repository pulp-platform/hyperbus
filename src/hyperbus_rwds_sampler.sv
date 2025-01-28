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

(* no_ungroup *)
(* no_boundary_optimization *)
(* keep_hierarchy = "yes" *)
module hyperbus_rwds_sampler import hyperbus_pkg::*; #()
(
    // Global signals
    input  logic clk_i, // phy clock
    input  logic rst_ni,
    input  logic test_mode_i,

    input  logic [3:0] cfg_edge_idx_i, // #edge where rwds is sampled
    input  logic       cfg_edge_pol_i, // 1: rising, 0: falling

    // sampled value going to PHY-FSM
    output logic rwds_sample_o,

    // ungated hyperbus clock
    input  logic tx_clk_90_i,

    // physical HyperBus signals
    input  logic hyper_cs_ni,
    input  logic hyper_rwds_i
);

    // used to time the sampling of RWDS to determine additional latency
    logic       tx_clk_270; // inverted 90deg clock
    logic [4:0] cnt_edge_d, cnt_edge_q; // one bit larger than config
    logic       cnt_clk; // clock used for edge counting
    logic [4:0] target_value;
    logic       sampling_clk, sampling_clk_gated; // clock used for sampling
    logic       enable_sampling; // sampling clock gate enable
    logic       rwds_sample;

    // needed so the first falling edge is cfg = '0 and it increments from there
    // without this there would be an illegal config reg combination since the
    // first edge we can sample is the first falling (1/2 cycle after CS going low)
    // the rising edge considing with CS going low is illegal
    assign target_value = cfg_edge_pol_i ? cfg_edge_idx_i +1 : cfg_edge_idx_i;

    // generate and select clocks
    // Sampling is either clocked by un-inverted or inverted 90deg hyperbus clock
    // Counter is clocked by the inverse as it controls the clock gate
    // which should be on for one cycle with sampling edge in the middle
    tc_clk_inverter i_tx_clk_inv (
        .clk_i ( tx_clk_90_i ),
        .clk_o ( tx_clk_270  )
    );

    tc_clk_mux2 i_sampling_clk_mux (
        .clk0_i    ( tx_clk_270     ),
        .clk1_i    ( tx_clk_90_i    ),
        .clk_sel_i ( cfg_edge_pol_i ),
        .clk_o     ( sampling_clk   )
    );

    tc_clk_inverter i_edge_cnt_clk_inv (
        .clk_i ( sampling_clk ),
        .clk_o ( cnt_clk      )
    );

    always_comb begin : gen_edge_cnt
        // only count during transfers
        if(~hyper_cs_ni) begin
            cnt_edge_d = cnt_edge_q +1;
            if(cnt_edge_q == '1) begin
                cnt_edge_d = cnt_edge_q; // saturating counter
            end
        end else begin
            // reset counter for next transfer
            cnt_edge_d = 1'b0;
        end
    end

    `FF(cnt_edge_q, cnt_edge_d, '0, cnt_clk);

    assign enable_sampling = (cnt_edge_q == target_value) & ~hyper_cs_ni;

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
