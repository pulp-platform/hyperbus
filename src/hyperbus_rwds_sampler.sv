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
    input  logic  clk_i,
    input  logic  rst_ni,
    input  logic  test_mode_i,

    // Transciever control: facing controller
    output logic  rwds_sample_o,

    // Physical interace: facing HyperBus
    input  logic  hyper_cs_ni,
    input  logic  hyper_ck_i,
    input  logic  hyper_ck_ni,
    input  logic  hyper_rwds_i,
    input  logic  hyper_rwds_oe_i
);

    // used to time the sampling of RWDS to determine additional latency
    logic [2:0]     ck_cnt_d, ck_cnt_q; // TODO: check in sim if this can be one less
    logic           rwds_sample_ena;
    logic           rwds_sample_clk;

    // The following guarantees a proper worst-case sampling of RWDS.
    // RWDS may only be valid (and stable) for a single period around 
    // the 3rd hyper_ck_o rising edge (see t_DSV, t_CSS, t_CKDS @ 166MHz).
    // We create a clock gate that open just for this window from falling
    // to falling edge of hyper_ck around the 3rd rising edge.
    // Then and only then will the sample be taken.

    // Constraints: 
    // As long as the clk to clk_90 constraints are proper 
    // (clk_90 being a derived shifted clock) this should not cause problems
    
    always_comb begin : gen_ck_counter
        ck_cnt_d = ck_cnt_q +1; // count hyper_ck falling edges

        // reset counter when the transaction ends (CS goes high)
        if(hyper_cs_ni) begin
            ck_cnt_d = '0;
        end else if(ck_cnt_q == 3) begin // stop counting once sample is taken
            ck_cnt_d = ck_cnt_q;
        end
    end
    // clocked with falling edge, creates an active clk-gate around rising edge
    `FF(ck_cnt_q, ck_cnt_d, '0, hyper_ck_ni);

    assign rwds_sample_ena = (ck_cnt_q == 2); // TODO: Check proper sampling point in sim

    // Gate the sampling of rwds to the third rising CK_90 edge only
    tc_clk_gating i_rwds_in_clk_gate (
        .clk_i      ( hyper_ck_i      ),
        .en_i       ( rwds_sample_ena ),
        .test_en_i  ( test_mode_i     ),
        .clk_o      ( rwds_sample_clk )
    );
    // Sample RWDS on demand for extra latency determination
    `FF(rwds_sample_o, hyper_rwds_i, '0, rwds_sample_clk);

endmodule
