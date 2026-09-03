// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Armin Berger <bergerar@ethz.ch>
// Stephan Keck <kecks@ethz.ch>
// Thomas Benz <tbenz@iis.ee.ethz.ch>
// Paul Scheffler <paulsc@iis.ee.ethz.ch>

`include "common_cells/assertions.svh"

module hyperbus_phy import hyperbus_pkg::*; #(
    parameter int unsigned NumPhys          = -1,
    parameter int unsigned TimerWidth       = 16,
    parameter int unsigned RxFifoLogDepth   = 3,
    parameter int unsigned SyncStages       = 2,
    parameter int unsigned PhyIndex         = 0,
    // Conservative startup delay: 300 us at 200 MHz.
    parameter int unsigned StartupCycles    = 300 * 200
)(
    input  logic                clk_i,
    input  logic                clk_tx_i,
    input  logic                rst_ni,
    input  logic                test_mode_i,
    // Config registers
    input  phy_cfg_t            cfg_i,
    // PHY control status
    output logic                busy_o,
    // Transactions
    input  logic                trans_valid_i,
    output logic                trans_ready_o,
    input  hyper_tf_t           trans_i,            // TODO: increase burst width!
    input  logic [HyperNumChips-1:0] trans_cs_i,
    // Transmitting channel
    input  logic                tx_valid_i,
    output logic                tx_ready_o,
    input  logic [15:0]         tx_data_i,
    input  logic [1:0]          tx_strb_i,
    input  logic                tx_last_i,
    // Receiving channel
    output logic                rx_valid_o,
    input  logic                rx_ready_i,
    output logic [15:0]         rx_data_o,
    output logic                rx_error_o,
    output logic                rx_last_o,
    // B response
    output logic                b_valid_o,
    input  logic                b_ready_i,
    output logic                b_error_o,
    // Physical interface
    output logic [HyperNumChips-1:0] hyper_cs_no,
    output logic                hyper_ck_o,
    output logic                hyper_ck_no,
    output logic                hyper_rwds_o,
    input  logic                hyper_rwds_i,
    output logic                hyper_rwds_oe_o,
    input  logic [7:0]          hyper_dq_i,
    output logic [7:0]          hyper_dq_o,
    output logic                hyper_dq_oe_o,
    output logic                hyper_reset_no
);

    localparam int unsigned RxFifoDepth = 2 ** RxFifoLogDepth;
    // r_outstand_q includes samples still crossing the RWDS CDC, so its limit
    // must not include the synchronizer depth again. Reserve two entries for
    // stopping CK and the final RWDS capture at the clock-gating boundary.
    localparam int unsigned RxFifoStopMargin = 2;
    localparam int unsigned RxOutstandingLimit = (RxFifoDepth > RxFifoStopMargin) ?
                                                 (RxFifoDepth - RxFifoStopMargin) : 1;

    `ASSERT_INIT(PhyIndexValid, PhyIndex < 2)

    logic [1:0] words_per_beat;

    //////////////////////
    // Persistent state //
    //////////////////////

    hyper_phy_state_t       state_d,    state_q;
    logic [TimerWidth-1:0]  timer_d,    timer_q;
    hyper_tf_t              tf_d,       tf_q;
    logic [HyperNumChips-1:0] cs_d, cs_q;
    logic [3:0]             rwds_sample_countdown_d, rwds_sample_countdown_q;
    logic [3:0]             rwds_oe_setup_count_d, rwds_oe_setup_count_q;

    logic [HyperNumChips-1:0] cfg_select_cs;
    logic [2:0]                cfg_chip_idx;
    chip_phy_cfg_t             cfg_chip;
    phy_lane_cfg_t             cfg_lane;

    // During Idle the incoming command CS is authoritative. Once accepted,
    // retain the registered CS for every subsequent phase of the transfer.
    assign cfg_select_cs = (state_q == Idle) ? trans_cs_i : cs_q;
    onehot_to_bin #(
        .ONEHOT_WIDTH ( HyperNumChips )
    ) i_cfg_chip_idx (
        .onehot ( cfg_select_cs ),
        .bin    ( cfg_chip_idx  )
    );
    assign cfg_chip = cfg_i.chip[cfg_chip_idx];
    assign cfg_lane = cfg_i.phy[PhyIndex];

    assign words_per_beat = (NumPhys == 2 && cfg_i.dual_phy) ? 2 : 1;

    // Whether B response is pending
    logic b_pending_q;
    logic b_pending_set;
    logic b_pending_clear;

    // How many R response words are outstanding if any
    logic [RxFifoLogDepth:0]    r_outstand_q;
    logic                       r_outstand_inc;
    logic                       r_outstand_dec;

    // Auxiliary control signals
    logic ctl_write_zero_lat;
    logic ctl_add_latency;
    logic ctl_rwds_sample;
    logic ctl_tf_burst_last;
    logic ctl_tf_burst_done;
    logic ctl_timer_two;
    logic ctl_timer_one;
    logic ctl_timer_zero;
    logic ctl_timer_rwr_done;
    logic ctl_rclk_ena;
    logic ctl_rcnt_ena;
    logic ctl_wclk_ena;
    logic rx_outstanding_room;
    logic [4:0] rwds_sample_delay_plus_two;
    logic rwds_oe_setup_ready;

    // Command-address
    hyper_phy_ca_t  ca;

    // Transceiver I/O
    logic           trx_clk_ena;
    logic           trx_cs_ena;
    logic           trx_rwds_sample;
    logic           trx_rwds_sample_ena;
    logic [15:0]    trx_tx_data;
    logic           trx_tx_data_oe;
    logic [1:0]     trx_tx_rwds;
    logic           trx_tx_rwds_oe;
    logic           trx_rx_clk_set;
    logic           trx_rx_clk_reset;
    logic [15:0]    trx_rx_data;
    logic           trx_rx_valid;
    logic           trx_rx_ready;

    //////////////////////
    // Transceiver I/O //
    //////////////////////

    hyperbus_trx #(
        .RxFifoLogDepth ( RxFifoLogDepth    ),
        .SyncStages     ( SyncStages        )
    ) i_trx (
        .clk_i,
        .clk_tx_i,
        .rst_ni,
        .test_mode_i,
        .cs_i               ( cs_q                        ),
        .cs_ena_i           ( trx_cs_ena                  ),
        .rwds_sample_o      ( trx_rwds_sample             ),
        .rwds_sample_ena_i  ( trx_rwds_sample_ena         ),
        .tx_clk_ena_i       ( trx_clk_ena                 ),
        .tx_data_i          ( trx_tx_data                 ),
        .tx_data_oe_i       ( trx_tx_data_oe              ),
        .tx_rwds_i          ( trx_tx_rwds                 ),
        .tx_rwds_oe_i       ( trx_tx_rwds_oe              ),
        .rx_clk_delay_i     ( cfg_chip.t_rx_clk_delay   ),
        .rx_clk_set_i       ( trx_rx_clk_set              ),
        .rx_clk_reset_i     ( trx_rx_clk_reset            ),
        .rx_data_o          ( trx_rx_data                 ),
        .rx_valid_o         ( trx_rx_valid                ),
        .rx_ready_i         ( trx_rx_ready                ),
        .hyper_cs_no,
        .hyper_ck_o,
        .hyper_ck_no,
        .hyper_rwds_o,
        .hyper_rwds_i,
        .hyper_rwds_oe_o,
        .hyper_dq_i,
        .hyper_dq_o,
        .hyper_dq_oe_o,
        .hyper_reset_no
    );

    //////////////
    // Dataflow //
    //////////////

    // Command-address
    assign ca = hyper_phy_ca_t '{
        write:      ~tf_q.write,
        addr_space: tf_q.address_space,
        burst_type: tf_q.burst_type,
        addr_upper: tf_q.address[31:3],
        reserved:   '0,
        addr_lower: tf_q.address[2:0]
    };

    // Write dataflow
    always_comb begin : proc_comb_tx
        trx_tx_data     = '0;
        trx_tx_rwds     = '0;
        tx_ready_o      = 1'b0;
        ctl_wclk_ena    = 1'b0;
        if (state_q == SendCA) begin
            // In CA phase: use timer to select word
            trx_tx_data     = ca[(8'(timer_q) << 4) +: 16];
        end else if (state_q == Write) begin
            trx_tx_data     = tx_data_i;
            trx_tx_rwds     = ~tx_strb_i;
            tx_ready_o      = rwds_oe_setup_ready;
            ctl_wclk_ena   = tx_valid_i && rwds_oe_setup_ready;
        end
    end

    // Write response dataflow
    assign b_valid_o        = b_pending_q;
    assign b_error_o        = 1'b0;            // TODO
    assign b_pending_clear  = b_valid_o & b_ready_i;

    // FF indicating whether B response pending
    always_ff @(posedge clk_i or negedge rst_ni) begin : proc_ff_b_pending
        if      (~rst_ni)           b_pending_q <= 1'b0;
        else if (b_pending_set)     b_pending_q <= 1'b1;
        else if (b_pending_clear)   b_pending_q <= 1'b0;
    end

    // Read response dataflow
    assign rx_data_o = trx_rx_data;
    assign rx_error_o = 1'b0;
    assign rx_last_o = (state_q != Read) & ctl_tf_burst_done & (r_outstand_q == 1);

    assign trx_rx_ready     = rx_ready_i;
    assign rx_valid_o       = trx_rx_valid & (r_outstand_q != '0);
    assign rx_outstanding_room = r_outstand_q < RxOutstandingLimit;
    // Suspend CK for visible downstream stalls and before the RWDS CDC FIFO can
    // fill with already-launched, not-yet-drained read words.
    assign ctl_rclk_ena     = rx_outstanding_room & ~(rx_valid_o & ~rx_ready_i);
    // Keep RWDS sampling enabled until all read words launched before a CS break
    // have crossed back into the PHY clock domain.
    assign trx_rx_clk_reset = (state_q != Read) & (r_outstand_q == '0);

    // Counter for outstanding R responses
    assign r_outstand_dec   = rx_valid_o & rx_ready_i;
    always_ff @(posedge clk_i or negedge rst_ni) begin : proc_ff_r_outstand
        if      (~rst_ni)                           r_outstand_q <= '0;
        else if (r_outstand_inc & ~r_outstand_dec)  r_outstand_q <= r_outstand_q + 1;
        else if (r_outstand_dec & ~r_outstand_inc)  r_outstand_q <= r_outstand_q - 1;
    end

    /////////////
    // Control //
    /////////////

    // Auxiliary control signals
    assign ctl_write_zero_lat   = tf_q.address_space & tf_q.write;
    // Force additional latency when configured; otherwise use the held RWDS sample.
    assign ctl_add_latency      = trx_rwds_sample | cfg_chip.en_latency_additional;
    assign ctl_rwds_sample      = ~ctl_write_zero_lat &&
        ((state_q == SendCA && ctl_timer_zero && (rwds_sample_countdown_q == 4'd0)) ||
         (state_q == WaitLatAccess && (rwds_sample_countdown_q == 4'd1)));

    assign ctl_tf_burst_last    = (tf_q.burst == 1) || (tf_q.burst == words_per_beat);
    assign ctl_tf_burst_done    = (tf_q.burst == 0);

    assign ctl_timer_rwr_done   = (timer_q <= 3);
    assign ctl_timer_two        = (timer_q == 2);
    assign ctl_timer_one        = (timer_q == 1);
    assign ctl_timer_zero       = (timer_q == 0);

    // Count from the registered, pad-facing RWDS OE boundary. The resumed
    // clock-enable pipeline guarantees one additional complete PHY cycle
    // before the first write-data CK edge, so include that cycle in the
    // minimum setup interval. Saturating the counter avoids wraparound while
    // a write remains setup-stalled.
    assign rwds_oe_setup_ready = ctl_write_zero_lat ||
        (cfg_lane.rwds_oe_setup_cycles == 0) ||
        ({1'b0, rwds_oe_setup_count_q} + 5'd1 >=
         {1'b0, cfg_lane.rwds_oe_setup_cycles});

    assign busy_o = (state_q != Idle);

    // FSM logic
    always_comb begin : proc_comb_phy_fsm
        // Default outputs
        trans_ready_o       = 1'b0;
        r_outstand_inc      = 1'b0;
        b_pending_set       = 1'b0;
        trx_cs_ena          = 1'b1;
        trx_clk_ena         = 1'b0;
        trx_rx_clk_set      = 1'b0;
        trx_rwds_sample_ena = 1'b0;
        // Default next state
        state_d = state_q;
        timer_d = timer_q - 1;
        tf_d    = tf_q;
        cs_d    = cs_q;
        rwds_sample_countdown_d = rwds_sample_countdown_q;
        rwds_oe_setup_count_d = rwds_oe_setup_count_q;
        if (!hyper_rwds_oe_o) begin
            rwds_oe_setup_count_d = '0;
        end else if (rwds_oe_setup_count_q != '1) begin
            rwds_oe_setup_count_d = rwds_oe_setup_count_q + 1'b1;
        end
        // Tri-state control of dq and rwds
        trx_tx_rwds_oe = 1'b0;
        trx_tx_data_oe = 1'b0;
        // State-dependent logic
        unique case (state_q)
            // Hold chip select inactive until the startup delay expires.
            Startup: begin
                trx_cs_ena  = 1'b0;
                // Timer resets to parameterized startup delay
                if (ctl_timer_one) begin
                    state_d = Idle;
                end
            end
            // Accept a transfer only after all responses from the previous one have drained.
            Idle: begin
                trx_cs_ena  = 1'b0;
                timer_d     = timer_q;
                // Accept the next transfer only after pending responses and
                // read samples from the previous segment have drained.
                trans_ready_o = ~b_pending_q & (r_outstand_q == '0);
                if (trans_valid_i & trans_ready_o) begin
                    tf_d    = trans_i;
                    cs_d    = trans_cs_i;
                    rwds_sample_countdown_d = cfg_chip.rwds_sample_delay;

                    if(cfg_chip.csn_to_ck_cycles != 0) begin
                        // assert CS but delay hyper_ck to allow more time
                        // for memory to drive RWDS (to satisfy t_DSV)
                        state_d = DelayCK;
                        timer_d = cfg_chip.csn_to_ck_cycles -1;
                    end else begin
                        // max throughput when memory RWDS signal arrives early
                        state_d = SendCA;
                        // Send 3 CA words (t_CSS respected through clock delay)
                        timer_d = 2;
                    end

                    // Enable output driver (needs to be enabled at least
                    // one cycle earlier since tri-state enables of IO pads
                    // are quite slow compared to the data pins)
                    trx_tx_data_oe = 1'b1;
                end
            end
            // Assert chip select early when RWDS needs extra setup time before CK starts.
            DelayCK: begin
                trx_clk_ena = 1'b0;
                trx_tx_data_oe = 1'b1;
                if (ctl_timer_zero) begin
                    timer_d = 2; // Send 3 CA words
                    state_d = SendCA;
                end
            end
            // Shift the three command/address words onto DQ.
            SendCA: begin
                // Dataflow handled outside FSM
                trx_clk_ena         = 1'b1;
                trx_tx_data_oe      = 1'b1;
                trx_rwds_sample_ena = ctl_rwds_sample;
                if (ctl_timer_zero) begin
                    if (ctl_write_zero_lat) begin
                        timer_d = cfg_chip.t_burst_max;
                        state_d = Write;
                    end else begin
                        timer_d = TimerWidth'(cfg_chip.t_latency_access);
                        state_d = WaitLatAccess;
                    end
                end
            end
            // Wait one access-latency interval and decide on the extra latency.
            WaitLatAccess: begin
                trx_clk_ena = 1'b1;
                // Establish a LOW RWDS preamble as soon as the one-shot
                // sample has completed; setup time overlaps natural latency.
                trx_tx_rwds_oe = tf_q.write && !ctl_write_zero_lat &&
                    (rwds_sample_countdown_q == 0);
                // The registered DQ OE stays active through the final delayed
                // CA edge, then releases DQ on the following PHY clock edge.
                // A valid TX phase keeps the delayed edge within that cycle.
                trx_rwds_sample_ena = ctl_rwds_sample;
                if (rwds_sample_countdown_q != '0) begin
                    rwds_sample_countdown_d = rwds_sample_countdown_q - 1'b1;
                end
                // Decide from the final sampled RWDS value at the normal-latency boundary.
                if (ctl_timer_two) begin
                    if (ctl_add_latency) begin
                        // Enter one cycle earlier and compensate the extra-latency timer.
                        state_d = WaitAddLatAccess;
                        timer_d = TimerWidth'(cfg_chip.t_latency_access) + 1;
                    end else begin
                        if (tf_q.write && !ctl_write_zero_lat && !rwds_oe_setup_ready) begin
                            // Hold the final natural-latency count while CK is
                            // stopped until the registered RWDS OE has settled.
                            state_d = WaitRwdsOe;
                            timer_d = timer_q;
                            trx_clk_ena = 1'b0;
                            trx_tx_rwds_oe = 1'b1;
                        end else begin
                            // Substract cycle for last CA and another for state delay
                            timer_d = cfg_chip.t_burst_max;
                            // Switch to write or read phase and already start
                            // turnaround of tri-state driver (depending on latency
                            // config and if read or write transaction).
                            if (tf_q.write) begin
                                state_d = Write;
                                trx_tx_data_oe = 1'b1;
                                // For zero latency writes, we must not drive the RWDS
                                // signal (see specs page 9). Depending on the latency
                                // mode we thus drive only the DQ signals or DQ + RWDS.
                                trx_tx_rwds_oe = ~ctl_write_zero_lat;
                            end else begin
                                state_d = Read;
                                trx_tx_data_oe = 1'b0;
                                trx_tx_rwds_oe = 1'b0;
                            end
                        end
                    end
                end
            end
            // Complete the requested second access-latency interval.
            WaitAddLatAccess: begin
                // Same as WaitLatAccess but without possibility
                // of adding another latency count
                trx_clk_ena = 1'b1;
                trx_tx_rwds_oe = tf_q.write && !ctl_write_zero_lat;
                if (ctl_timer_two) begin
                    timer_d = cfg_chip.t_burst_max;
                    if (tf_q.write) begin
                        if (!ctl_write_zero_lat && !rwds_oe_setup_ready) begin
                            state_d = WaitRwdsOe;
                            timer_d = timer_q;
                            trx_clk_ena = 1'b0;
                        end else begin
                            state_d = Write;
                            trx_tx_data_oe = 1'b1;
                            trx_tx_rwds_oe = 1'b1;
                        end
                    end else begin
                        state_d = Read;
                        trx_tx_data_oe = 1'b0;
                        trx_tx_rwds_oe = 1'b0;
                    end
                end
            end
            // Pause CK at the natural data boundary without consuming its
            // latency count. Once setup is met, resume CK and enter Write;
            // the resumed clock-enable edge provides the final complete setup
            // cycle, and Write's normal path then launches data on the next edge.
            WaitRwdsOe: begin
                trx_clk_ena = 1'b0;
                trx_tx_rwds_oe = 1'b1;
                timer_d = timer_q;
                if (rwds_oe_setup_ready) begin
                    // The registered clock-enable pipeline needs one resumed
                    // CK edge to consume the remaining latency cycle; Write's
                    // normal path then launches data on the following edge.
                    state_d = Write;
                    timer_d = cfg_chip.t_burst_max;
                    trx_clk_ena = 1'b1;
                    trx_tx_data_oe = 1'b1;
                end
            end
            // Capture read data until this segment completes or reaches its time limit.
            Read: begin
                // Dataflow handled outside FSM
                trx_rx_clk_set = 1'b1;
                if (ctl_rclk_ena) begin
                    trx_clk_ena     = 1'b1;
                    r_outstand_inc  = 1'b1;
                    tf_d.burst      = tf_q.burst - words_per_beat;
                    tf_d.address    = tf_q.address + 1;
                    if (ctl_tf_burst_last) begin
                        timer_d = cfg_chip.t_csh_cycles;
                        state_d = WaitXfer;
                    end
                end
                // Force-terminate access on burst time limit
                if (ctl_timer_one) begin
                    timer_d = cfg_chip.t_csh_cycles;
                    state_d = WaitXfer;
                end
            end
            // Transmit write data until this segment completes or reaches its time limit.
            Write: begin
                // Drive DQ lines in write mode
                trx_tx_data_oe = 1'b1;
                // For zero-latency writes we must not use RWDS as mask signal
                trx_tx_rwds_oe = ~ctl_write_zero_lat;
                // Dataflow handled outside FSM
                if (ctl_wclk_ena) begin
                    trx_clk_ena = 1'b1;
                    tf_d.burst  = tf_q.burst - words_per_beat;
                    tf_d.address    = tf_q.address + 1;
                    if (ctl_tf_burst_last) begin
                        b_pending_set   = 1'b1;
                        timer_d = cfg_chip.t_csh_cycles;
                        state_d         = WaitXfer;
                    end
                end
                // Force-terminate access on burst time limit
                if (ctl_timer_one) begin
                    timer_d = cfg_chip.t_csh_cycles;
                    state_d = WaitXfer;
                end
            end
            // Keep chip select asserted until the final generated clock edge has settled.
            WaitXfer: begin
                // Wait for FFed Clock and output to stop
                // May have to be prolonged for potential future devices with t_CSH > 0
                if (ctl_timer_zero) begin
                    timer_d = cfg_chip.t_read_write_recovery;
                    state_d = WaitRWR;
                end
            end
            // Enforce read/write recovery, then continue a split transfer or return idle.
            WaitRWR: begin
                trx_cs_ena = 1'b0;
                if (ctl_timer_rwr_done) begin
                    if (ctl_tf_burst_done) begin
                        state_d = Idle;
                    end else if (!tf_q.write && (r_outstand_q != '0)) begin
                        // Before starting the next read segment, let all samples
                        // from the previous segment drain and reset RWDS sampling.
                        timer_d = timer_q;
                    end else begin
                        rwds_sample_countdown_d = cfg_chip.rwds_sample_delay;
                        state_d = SendCA;
                        // Re-enable the io driver if we immediately start the
                        // next transaction.
                        trx_tx_data_oe = 1'b1;
                    end
                end
            end
            // Recover safely from an invalid state through the normal startup sequence.
            default: begin
                state_d       = Startup;
                timer_d       = StartupCycles;
                tf_d          = hyper_tf_t'{burst_type: 1'b1, default: '0};
                cs_d          = '0;
                trx_cs_ena    = 1'b0;
            end
        endcase
    end

    // PHY state registers, including timer and transfer
    always_ff @(posedge clk_i or negedge rst_ni) begin : proc_ff_phy
        if (!rst_ni) begin
            state_q <= Startup;
            timer_q <= StartupCycles;
            tf_q    <= hyper_tf_t'{burst_type: 1'b1, default:'0};
            cs_q    <= '0;
            rwds_sample_countdown_q <= '0;
            rwds_oe_setup_count_q <= '0;
        end else begin
            state_q <= state_d;
            timer_q <= timer_d;
            tf_q    <= tf_d;
            cs_q    <= cs_d;
            rwds_sample_countdown_q <= rwds_sample_countdown_d;
            rwds_oe_setup_count_q <= rwds_oe_setup_count_d;
        end
    end

    assign rwds_sample_delay_plus_two = {1'b0, cfg_chip.rwds_sample_delay} + 5'd2;

    // At this exact boundary the held RWDS sample controls whether the PHY
    // uses natural or additional latency. A forced additional-latency
    // configuration makes the sample irrelevant and intentionally bypasses
    // this check.
    `ASSERT_KNOWN_IF(RwdsLatencySampleKnown, trx_rwds_sample,
        state_q == WaitLatAccess && ctl_timer_two && !ctl_write_zero_lat &&
        !cfg_chip.en_latency_additional)

    `ASSERT(RxCaptureResetOnlyWhenDrained, trx_rx_clk_reset |->
        (state_q != Read && r_outstand_q == '0))
    `ASSERT(RxCaptureActiveDuringRead, state_q == Read |-> !trx_rx_clk_reset)
    `ASSERT(RxCaptureResetAfterDrain,
        (r_outstand_dec && r_outstand_q == 1 && state_q != Read) |=> trx_rx_clk_reset)
    `ASSERT(DqOutputDisabledDuringLatency,
        (((state_q == WaitLatAccess && timer_q < cfg_chip.t_latency_access) ||
          state_q == WaitAddLatAccess || state_q == WaitRwdsOe) &&
         state_d != Write) |-> !hyper_dq_oe_o)
    `ASSERT(OutputDriversDisabledDuringRecovery,
        (state_q == WaitRWR && state_d != SendCA) |->
        (!hyper_dq_oe_o && !hyper_rwds_oe_o))
    `ASSERT(LatencyAccessAtLeastThree,
        (state_q == SendCA && !ctl_write_zero_lat) |-> cfg_chip.t_latency_access >= 3)
    `ASSERT(RwdsSampleDelayFitsLatency,
        (state_q == SendCA && !ctl_write_zero_lat) |->
        rwds_sample_delay_plus_two <= {1'b0, cfg_chip.t_latency_access})
    `ASSERT(RwdsOeSetupOnlyMemoryWrite,
        state_q == WaitRwdsOe |-> tf_q.write && !ctl_write_zero_lat)

endmodule
