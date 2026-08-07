// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

`timescale 1 ns/1 ps

import hyperram_model_pkg::*;

module hyperram_model_core #(
    parameter int unsigned AddrWidth = 24,
    parameter logic [15:0] DefaultValue = 16'hffff,
    parameter int unsigned FixedLatencyCycles = 6,
    parameter int unsigned WrappedBurstLengthWords = 16,
    parameter bit WrappedBurstHybridLinear = 1'b1,
    parameter int unsigned LatencyPolicy = 0,
    parameter int unsigned DeviceProfile = 0,
    parameter logic [15:0] Id0Value = 16'h000c,
    parameter logic [15:0] Id1Value = 16'h0000,
    parameter logic [15:0] Cfg0ResetValue = 16'h8f1f,
    parameter logic [15:0] Cfg1ResetValue = 16'h0002,
    parameter int unsigned ExtraLatencyRequestPolicy = 0,
    parameter int unsigned ExtraLatencyRequestPeriod = 0,
    parameter int unsigned ExtraLatencyRequestProbabilityPermille = 0,
    parameter bit ZeroLatencyMemoryWrites = 1'b0,
    parameter int unsigned TPowerOnMinQuarterCycles = 0,
    parameter int unsigned TResetReleaseMinQuarterCycles = 0,
    parameter int unsigned DqInputDelayQuarterCycles = 0,
    parameter bit InjectXOnProtocolViolation = 1'b0,
    parameter bit InjectZOnIllegalLatency = 1'b0,
    parameter bit ForceIllegalLatencyIndication = 1'b0,
    parameter int unsigned ProtocolCheckSeverity = 2,
    parameter int unsigned TCssMinQuarterCycles = 1,
    parameter int unsigned TCshiMinQuarterCycles = 1,
    parameter int unsigned TRwrMinQuarterCycles = 0,
    parameter int unsigned TCshMinQuarterCycles = 0,
    parameter int unsigned TIhMinQuarterCycles = 0,
    parameter int unsigned TCsmMaxQuarterCycles = 0,
    parameter int unsigned TResetLowMinQuarterCycles = 0,
    parameter bit CheckCkIdleWhenCsHigh = 1'b1
) (
    input  logic       clk_2x_i,
    input  logic       rst_ni,

    input  logic       CSNeg,
    input  logic       CK,
    input  logic       CKNeg,
    input  logic [7:0] dq_i,
    input  logic       dq_oe_i,
    output logic [7:0] dq_o,
    output logic       dq_oe_o,
    input  logic       rwds_i,
    input  logic       rwds_oe_i,
    output logic       rwds_o,
    output logic       rwds_oe_o,
    input  logic       RESETNeg,

    output metrics_t   metrics_o,
    output state_t     state_o,
    output trace_t     trace_o
);

    typedef enum logic [2:0] {
        StReset,
        StIdle,
        StCA,
        StLatency,
        StRead,
        StWrite
    } state_e;

    state_e state_q, state_d;

    localparam int unsigned LatencyPolicyNeverExtra   = 0;
    localparam int unsigned LatencyPolicyAlwaysExtra  = 1;
    localparam int unsigned LatencyPolicyAddressBit   = 2;
    localparam int unsigned LatencyPolicyPseudoRandom = 3;
    localparam int unsigned ExtraLatencyRequestNone      = 0;
    localparam int unsigned ExtraLatencyRequestPeriodic  = 1;
    localparam int unsigned ExtraLatencyRequestRandom    = 2;
    localparam int unsigned DeviceProfileCustom       = 0;
    localparam int unsigned DeviceProfileS27KS0641    = 1;
    localparam int unsigned DeviceProfileW956         = 2;

    logic ck_q;
    logic ck_rise, ck_fall, ck_edge;
    logic selected;
    logic reset_n;
    logic array_reset_n;

    logic [47:0] ca_q, ca_d;
    logic [2:0]  ca_edge_count_q, ca_edge_count_d;
    logic [15:0] tx_word_q, tx_word_d;
    logic        tx_have_hi_q, tx_have_hi_d;
    logic [15:0] rx_word_q, rx_word_d;
    logic        rx_have_hi_q, rx_have_hi_d;
    logic        rx_mask_hi_q, rx_mask_hi_d;
    logic [15:0] array_rdata;
    logic [AddrWidth-1:0] addr_q, addr_d;
    logic [AddrWidth-1:0] array_addr;
    logic                 read_q, read_d;
    logic                 register_space_q, register_space_d;
    logic                 zero_latency_write_q, zero_latency_write_d;
    logic                 linear_burst_q, linear_burst_d;
    logic [15:0]          latency_count_q, latency_count_d;
    logic [15:0]          latency_target;
    logic                 array_req;
    logic                 array_write;
    logic [15:0]          array_wdata;
    logic [1:0]           array_wstrb;
    logic [15:0]          cfg0_q;
    logic [15:0]          cfg1_q;
    logic [31:0]          memory_words_used;
    logic                 memory_access_enable;
    logic [7:0]           dq_out_q, dq_out_d;
    logic                 dq_oe_q, dq_oe_d;
    logic                 rwds_out_q, rwds_out_d;
    logic                 rwds_oe_q, rwds_oe_d;
    logic [31:0]          read_transactions_q, read_transactions_d;
    logic [31:0]          write_transactions_q, write_transactions_d;
    logic [31:0]          read_words_q, read_words_d;
    logic [31:0]          write_words_q, write_words_d;
    logic [31:0]          protocol_violations_q;
    logic [31:0]          active_quarters_q;
    logic [31:0]          clock_edges_q;
    logic [31:0]          clock_stop_quarters_q;
    logic [31:0]          extra_latency_transactions_q, extra_latency_transactions_d;
    logic [31:0]          written_bytes_q, written_bytes_d;
    logic [31:0]          masked_write_bytes_q, masked_write_bytes_d;
    logic [31:0]          discarded_read_words_q, discarded_read_words_d;
    logic [31:0]          longest_burst_words_q, longest_burst_words_d;
    logic [31:0]          total_burst_words_q, total_burst_words_d;
    logic [31:0]          completed_bursts_q, completed_bursts_d;
    logic [31:0]          register_read_transactions_q, register_read_transactions_d;
    logic [31:0]          register_write_transactions_q, register_write_transactions_d;
    logic [31:0]          extra_latency_request_transactions_q, extra_latency_request_transactions_d;
    logic [31:0]          burst_words_q, burst_words_d;
    logic [31:0]          transaction_count_q, transaction_count_d;
    logic [AddrWidth-1:0] start_addr_q, start_addr_d;
    logic                 extra_latency_q, extra_latency_d;
    logic [15:0]          lfsr_q;
    logic                 cs_n_q;
    logic                 reset_neg_q;
    logic [7:0]           dq_sample_q, dq_edge_sample_q;
    logic                 rwds_sample_q, rwds_edge_sample_q;
    logic [7:0]           dq_ck_sample;
    logic                 rwds_ck_sample;
    logic                 host_edge_sample_q, rwds_host_edge_sample_q;
    logic [31:0]          cs_low_quarters_q;
    logic [31:0]          cs_high_quarters_q;
    logic [31:0]          ck_stable_selected_quarters_q;
    logic [31:0]          quarters_since_last_ck_fall_q;
    logic [31:0]          quarters_since_power_on_q;
    logic [31:0]          quarters_since_reset_release_q;
    logic [31:0]          reset_low_quarters_q;
    logic [7:0]           dq_input_pipe_q [DqInputDelayQuarterCycles + 1];
    logic                 rwds_input_pipe_q [DqInputDelayQuarterCycles + 1];
    logic [7:0]           dq_model_drive;
    logic                 rwds_model_drive;
    logic [7:0]           dq_in;
    logic                 rwds_in;
    logic                 protocol_error_inject_q;
    logic                 extra_latency_request;
    logic                 selected_extra_latency;
    logic                 decoded_extra_latency;
    logic                 decoded_zero_latency_write;
    logic                 host_starts_ca;
    logic                 trace_valid_q, trace_valid_d;
    logic                 trace_write_q, trace_write_d;
    logic                 trace_register_space_q, trace_register_space_d;
    logic [AddrWidth-1:0] trace_addr_q, trace_addr_d;
    logic [31:0]          trace_words_q, trace_words_d;

    task automatic report_protocol_violation(input string msg);
        if (ProtocolCheckSeverity == 1) begin
            $warning("[HYPERRAM-MODEL] %s", msg);
        end else if (ProtocolCheckSeverity == 2) begin
            $error("[HYPERRAM-MODEL] %s", msg);
        end else if (ProtocolCheckSeverity >= 3) begin
            $fatal(1, "[HYPERRAM-MODEL] %s", msg);
        end
    endtask

    function automatic logic [15:0] profile_id0(input int unsigned profile);
        unique case (profile)
            DeviceProfileS27KS0641: profile_id0 = 16'h000c;
            DeviceProfileW956:      profile_id0 = 16'h0c81;
            default:                profile_id0 = Id0Value;
        endcase
    endfunction

    function automatic logic [15:0] profile_id1(input int unsigned profile);
        unique case (profile)
            DeviceProfileS27KS0641: profile_id1 = 16'h0000;
            DeviceProfileW956:      profile_id1 = 16'h0000;
            default:                profile_id1 = Id1Value;
        endcase
    endfunction

    function automatic logic [15:0] profile_cfg0(input int unsigned profile);
        unique case (profile)
            DeviceProfileS27KS0641: profile_cfg0 = 16'h8f1f;
            DeviceProfileW956:      profile_cfg0 = 16'h8f1f;
            default:                profile_cfg0 = Cfg0ResetValue;
        endcase
    endfunction

    function automatic logic [15:0] profile_cfg1(input int unsigned profile);
        unique case (profile)
            DeviceProfileS27KS0641: profile_cfg1 = 16'h0002;
            DeviceProfileW956:      profile_cfg1 = 16'h0002;
            default:                profile_cfg1 = Cfg1ResetValue;
        endcase
    endfunction

    function automatic logic host_owns_dq(input state_e state, input logic selected_now);
        return selected_now && (state == StCA || state == StWrite);
    endfunction

    function automatic logic host_may_drive_dq(input state_e state, input logic selected_now);
        return selected_now && (state == StCA || state == StLatency || state == StWrite);
    endfunction

    function automatic logic host_owns_rwds(input state_e state, input logic selected_now);
        return selected_now && (state == StWrite) && !zero_latency_write_q;
    endfunction

    function automatic logic cfg_fixed_latency(input logic [15:0] cfg0);
        return cfg0[11];
    endfunction

    function automatic logic choose_extra_latency(input logic [AddrWidth-1:0] addr,
                                                  input logic [15:0] lfsr);
        unique case (LatencyPolicy)
            LatencyPolicyNeverExtra:   choose_extra_latency = 1'b0;
            LatencyPolicyAlwaysExtra:  choose_extra_latency = 1'b1;
            LatencyPolicyAddressBit:   choose_extra_latency = addr[12];
            LatencyPolicyPseudoRandom: choose_extra_latency = lfsr[0];
            default:                   choose_extra_latency = 1'b0;
        endcase
    endfunction

    function automatic logic choose_extra_latency_request(input logic [15:0] lfsr,
                                                      input logic [31:0] transactions);
        unique case (ExtraLatencyRequestPolicy)
            ExtraLatencyRequestNone: choose_extra_latency_request = 1'b0;
            ExtraLatencyRequestPeriodic: begin
                choose_extra_latency_request = (ExtraLatencyRequestPeriod != 0) &&
                                           ((transactions % ExtraLatencyRequestPeriod) == 0);
            end
            ExtraLatencyRequestRandom: begin
                choose_extra_latency_request =
                    (ExtraLatencyRequestProbabilityPermille != 0) &&
                    ({6'b0, lfsr[9:0]} < ExtraLatencyRequestProbabilityPermille);
            end
            default: choose_extra_latency_request = 1'b0;
        endcase
    endfunction

    function automatic logic [AddrWidth-1:0] next_burst_addr(
        input logic [AddrWidth-1:0] addr,
        input logic [AddrWidth-1:0] start_addr,
        input logic [31:0]          burst_words,
        input logic                 linear_burst
    );
        logic [AddrWidth-1:0] window_base;
        logic [AddrWidth-1:0] window_offs;
        if (linear_burst || WrappedBurstLengthWords == 0) begin
            next_burst_addr = addr + 1'b1;
        end else if (WrappedBurstHybridLinear && burst_words + 1 >= WrappedBurstLengthWords) begin
            next_burst_addr = start_addr + AddrWidth'(burst_words + 1);
        end else begin
            window_base = start_addr & ~AddrWidth'(WrappedBurstLengthWords - 1);
            window_offs = (start_addr + AddrWidth'(burst_words + 1)) &
                          AddrWidth'(WrappedBurstLengthWords - 1);
            next_burst_addr = window_base | window_offs;
        end
    endfunction

    assign dq_model_drive = protocol_error_inject_q ? 8'hxx : dq_out_q;
    assign rwds_model_drive = protocol_error_inject_q ? 1'bx :
                              ((InjectZOnIllegalLatency && ForceIllegalLatencyIndication) ? 1'bz :
                               rwds_out_q);
    assign dq_o = dq_model_drive;
    assign dq_oe_o = dq_oe_q;
    assign rwds_o = rwds_model_drive;
    assign rwds_oe_o = rwds_oe_q;

    assign selected = !CSNeg;
    assign host_starts_ca = selected && state_q == StIdle;

    // Capture source-synchronous data at the physical CK edge. The quarter-cycle
    // observer can run after DQ has already advanced to the next DDR byte.
    always @(CK or negedge reset_n) begin
        if (!reset_n) begin
            dq_ck_sample   = '0;
            rwds_ck_sample = 1'b0;
        end else begin
            dq_ck_sample   = dq_in;
            rwds_ck_sample = rwds_in;
        end
    end
    assign reset_n = rst_ni;
    assign array_reset_n = rst_ni && RESETNeg;
    assign ck_rise = selected && !ck_q && CK;
    assign ck_fall = selected && ck_q && !CK;
    assign ck_edge = ck_rise || ck_fall;
    assign memory_access_enable = 1'b1;
    if (DqInputDelayQuarterCycles == 0) begin : gen_no_input_delay
        assign dq_in = dq_i;
        assign rwds_in = rwds_i;
    end else begin : gen_input_delay
        assign dq_in = dq_input_pipe_q[DqInputDelayQuarterCycles - 1];
        assign rwds_in = rwds_input_pipe_q[DqInputDelayQuarterCycles - 1];
    end

    assign latency_target = (cfg_fixed_latency(cfg0_q) ||
                             (extra_latency_q && !cfg_fixed_latency(cfg0_q))) ?
                            (FixedLatencyCycles[15:0] << 1) : FixedLatencyCycles[15:0];

    assign metrics_o.read_transactions = read_transactions_q;
    assign metrics_o.write_transactions = write_transactions_q;
    assign metrics_o.read_words = read_words_q;
    assign metrics_o.write_words = write_words_q;
    assign metrics_o.protocol_violations = protocol_violations_q;
    assign metrics_o.memory_words_used = memory_words_used;
    assign metrics_o.active_quarters = active_quarters_q;
    assign metrics_o.clock_edges = clock_edges_q;
    assign metrics_o.clock_stop_quarters = clock_stop_quarters_q;
    assign metrics_o.extra_latency_transactions = extra_latency_transactions_q;
    assign metrics_o.written_bytes = written_bytes_q;
    assign metrics_o.masked_write_bytes = masked_write_bytes_q;
    assign metrics_o.discarded_read_words = discarded_read_words_q;
    assign metrics_o.longest_burst_words = longest_burst_words_q;
    assign metrics_o.total_burst_words = total_burst_words_q;
    assign metrics_o.completed_bursts = completed_bursts_q;
    assign metrics_o.average_burst_words = (completed_bursts_q == 0) ? 32'd0 :
                                           total_burst_words_q / completed_bursts_q;
    assign metrics_o.register_read_transactions = register_read_transactions_q;
    assign metrics_o.register_write_transactions = register_write_transactions_q;
    assign metrics_o.extra_latency_request_transactions = extra_latency_request_transactions_q;
    assign metrics_o.deep_power_down_entries = 32'd0;
    assign metrics_o.hybrid_sleep_entries = 32'd0;
    assign state_o.deep_power_down = 1'b0;
    assign state_o.hybrid_sleep = 1'b0;
    assign trace_o.valid = trace_valid_q;
    assign trace_o.write = trace_write_q;
    assign trace_o.register_space = trace_register_space_q;
    assign trace_o.addr = 32'(trace_addr_q);
    assign trace_o.words = trace_words_q;

    hyperram_array #(
        .AddrWidth      ( AddrWidth      ),
        .DefaultValue   ( DefaultValue   ),
        .Id0Value       ( profile_id0(DeviceProfile)   ),
        .Id1Value       ( profile_id1(DeviceProfile)   ),
        .Cfg0ResetValue ( profile_cfg0(DeviceProfile)  ),
        .Cfg1ResetValue ( profile_cfg1(DeviceProfile)  )
    ) i_array (
        .clk_i             ( clk_2x_i           ),
        .rst_ni            ( array_reset_n      ),
        .req_i             ( array_req          ),
        .write_i           ( array_write        ),
        .register_space_i  ( register_space_q   ),
        .addr_i            ( array_addr         ),
        .wdata_i           ( array_wdata        ),
        .wstrb_i           ( array_wstrb        ),
        .memory_access_enable_i ( memory_access_enable ),
        .rdata_o           ( array_rdata        ),
        .cfg0_o            ( cfg0_q             ),
        .cfg1_o            ( cfg1_q             ),
        .memory_words_used_o ( memory_words_used )
    );

    always_comb begin
        state_d              = state_q;
        ca_d                 = ca_q;
        ca_edge_count_d      = ca_edge_count_q;
        tx_word_d            = tx_word_q;
        tx_have_hi_d         = tx_have_hi_q;
        rx_word_d            = rx_word_q;
        rx_have_hi_d         = rx_have_hi_q;
        rx_mask_hi_d         = rx_mask_hi_q;
        addr_d               = addr_q;
        read_d               = read_q;
        register_space_d     = register_space_q;
        zero_latency_write_d  = zero_latency_write_q;
        linear_burst_d       = linear_burst_q;
        latency_count_d      = latency_count_q;
        dq_out_d             = dq_out_q;
        dq_oe_d              = dq_oe_q;
        rwds_out_d           = rwds_out_q;
        rwds_oe_d            = rwds_oe_q;
        read_transactions_d  = read_transactions_q;
        write_transactions_d = write_transactions_q;
        read_words_d         = read_words_q;
        write_words_d        = write_words_q;
        extra_latency_transactions_d = extra_latency_transactions_q;
        written_bytes_d      = written_bytes_q;
        masked_write_bytes_d = masked_write_bytes_q;
        discarded_read_words_d = discarded_read_words_q;
        longest_burst_words_d = longest_burst_words_q;
        total_burst_words_d   = total_burst_words_q;
        completed_bursts_d    = completed_bursts_q;
        register_read_transactions_d = register_read_transactions_q;
        register_write_transactions_d = register_write_transactions_q;
        extra_latency_request_transactions_d = extra_latency_request_transactions_q;
        burst_words_d        = burst_words_q;
        transaction_count_d   = transaction_count_q;
        start_addr_d         = start_addr_q;
        extra_latency_d      = extra_latency_q;
        trace_valid_d        = 1'b0;
        trace_write_d        = trace_write_q;
        trace_register_space_d = trace_register_space_q;
        trace_addr_d         = trace_addr_q;
        trace_words_d        = trace_words_q;
        array_req            = 1'b0;
        array_write          = 1'b0;
        array_addr           = addr_q;
        array_wdata          = rx_word_q;
        array_wstrb          = 2'b00;
        extra_latency_request    = 1'b0;
        selected_extra_latency   = 1'b0;
        decoded_extra_latency = 1'b0;
        decoded_zero_latency_write = 1'b0;

        if (!selected) begin
            state_d         = StIdle;
            ca_edge_count_d = '0;
            extra_latency_d = 1'b0;
            dq_oe_d         = 1'b0;
            rwds_oe_d       = 1'b0;
            rx_have_hi_d    = 1'b0;
            tx_have_hi_d    = 1'b0;
            zero_latency_write_d = 1'b0;
            if (burst_words_q > longest_burst_words_q) begin
                longest_burst_words_d = burst_words_q;
            end
            if (burst_words_q != 0) begin
                trace_valid_d = 1'b1;
                trace_write_d = !read_q;
                trace_register_space_d = register_space_q;
                trace_addr_d = start_addr_q;
                trace_words_d = burst_words_q;
                total_burst_words_d = total_burst_words_q + burst_words_q;
                completed_bursts_d = completed_bursts_q + 1'b1;
            end
            burst_words_d = '0;
        end else begin
            unique case (state_q)
                StReset: begin
                    state_d = StIdle;
                end

                StIdle: begin
                    dq_oe_d = 1'b0;
                    rwds_oe_d = 1'b1;
                    rwds_out_d = cfg_fixed_latency(cfg0_q);
                    if (selected) begin
                        state_d = StCA;
                        ca_d = '0;
                        ca_edge_count_d = '0;
                        extra_latency_request = !cfg_fixed_latency(cfg0_q) &&
                            choose_extra_latency_request(lfsr_q, transaction_count_q);
                        extra_latency_d = !cfg_fixed_latency(cfg0_q) &&
                            ((LatencyPolicy != LatencyPolicyAddressBit &&
                              choose_extra_latency('0, lfsr_q)) ||
                             extra_latency_request);
                        if (extra_latency_request) begin
                            extra_latency_request_transactions_d =
                                extra_latency_request_transactions_q + 1'b1;
                        end
                    end
                end

                StCA: begin
                    rwds_oe_d = 1'b1;
                    selected_extra_latency = !cfg_fixed_latency(cfg0_q) &&
                        (extra_latency_q ||
                         ((LatencyPolicy == LatencyPolicyAddressBit) &&
                          (ca_edge_count_q >= 3) && ca_q[1]));
                    rwds_out_d = cfg_fixed_latency(cfg0_q) || selected_extra_latency;
                    if (ck_edge) begin
                        ca_d = {ca_q[39:0], dq_ck_sample};
                        ca_edge_count_d = ca_edge_count_q + 1'b1;
                        if (ca_edge_count_q == 3'd3) begin
                            extra_latency_d = selected_extra_latency;
                        end
                        if (ca_edge_count_q == 3'd5) begin
                            decoded_extra_latency = !cfg_fixed_latency(cfg0_q) &&
                                                    extra_latency_q;
                            decoded_zero_latency_write = ca_d[46] ||
                                                         (ZeroLatencyMemoryWrites && !ca_d[47]);
                            read_d           = ca_d[47];
                            register_space_d = ca_d[46];
                            linear_burst_d   = ca_d[45];
                            addr_d           = AddrWidth'({ca_d[44:16], ca_d[2:0]});
                            start_addr_d     = AddrWidth'({ca_d[44:16], ca_d[2:0]});
                            latency_count_d  = '0;
                            rx_have_hi_d     = 1'b0;
                            burst_words_d    = '0;
                            extra_latency_d  = decoded_extra_latency;
                            transaction_count_d = transaction_count_q + 1'b1;
                            if (decoded_extra_latency) begin
                                extra_latency_transactions_d = extra_latency_transactions_q + 1'b1;
                            end
                            if (ca_d[47]) begin
                                read_transactions_d = read_transactions_q + 1'b1;
                                if (ca_d[46]) begin
                                    register_read_transactions_d = register_read_transactions_q + 1'b1;
                                end
                                array_addr = AddrWidth'({ca_d[44:16], ca_d[2:0]});
                                state_d = StLatency;
                            end else begin
                                write_transactions_d = write_transactions_q + 1'b1;
                                if (ca_d[46]) begin
                                    register_write_transactions_d = register_write_transactions_q + 1'b1;
                                end
                                zero_latency_write_d = decoded_zero_latency_write;
                                if (!decoded_zero_latency_write) begin
                                    rwds_oe_d = 1'b0;
                                end
                                if (decoded_zero_latency_write) begin
                                    state_d = StWrite;
                                end else begin
                                    state_d = StLatency;
                                end
                            end
                        end
                    end
                end

                StLatency: begin
                    dq_oe_d = 1'b0;
                    rwds_oe_d = read_q;
                    rwds_out_d = 1'b0;
                    if (ck_rise) begin
                        if (latency_count_q + 16'd1 >= latency_target) begin
                            if (read_q) begin
                                array_addr = addr_q;
                                tx_word_d = array_rdata;
                                dq_oe_d = 1'b1;
                                rwds_oe_d = 1'b1;
                                dq_out_d = array_rdata[15:8];
                                rwds_out_d = 1'b1;
                                tx_have_hi_d = 1'b1;
                                state_d = StRead;
                            end else begin
                                rx_word_d[15:8] = dq_ck_sample;
                                rx_mask_hi_d = rwds_ck_sample;
                                rx_have_hi_d = 1'b1;
                                rwds_oe_d = 1'b0;
                                state_d = StWrite;
                            end
                        end else begin
                            latency_count_d = latency_count_q + 16'd1;
                        end
                    end
                end

                StRead: begin
                    dq_oe_d = 1'b1;
                    rwds_oe_d = 1'b1;
                    if (ck_rise) begin
                        array_addr = addr_q;
                        tx_word_d = array_rdata;
                        dq_out_d = array_rdata[15:8];
                        rwds_out_d = 1'b1;
                        tx_have_hi_d = 1'b1;
                    end else if (ck_fall && tx_have_hi_q) begin
                        dq_out_d = tx_word_q[7:0];
                        rwds_out_d = 1'b0;
                        addr_d = next_burst_addr(addr_q, start_addr_q, burst_words_q, linear_burst_q);
                        read_words_d = read_words_q + 1'b1;
                        burst_words_d = burst_words_q + 1'b1;
                        tx_have_hi_d = 1'b0;
                    end
                end

                StWrite: begin
                    dq_oe_d = 1'b0;
                    rwds_oe_d = 1'b0;
                    if (ck_rise) begin
                        rx_word_d[15:8] = dq_ck_sample;
                        rx_mask_hi_d = rwds_ck_sample;
                        rx_have_hi_d = 1'b1;
                    end else if (ck_fall && rx_have_hi_q) begin
                        rx_word_d[7:0] = dq_ck_sample;
                        array_req = 1'b1;
                        array_write = 1'b1;
                        array_addr = addr_q;
                        array_wdata = {rx_word_q[15:8], dq_ck_sample};
                        array_wstrb = zero_latency_write_q ? 2'b11 :
                                      {~rx_mask_hi_q, ~rwds_ck_sample};
                        addr_d = next_burst_addr(addr_q, start_addr_q, burst_words_q, linear_burst_q);
                        rx_have_hi_d = 1'b0;
                        write_words_d = write_words_q + 1'b1;
                        written_bytes_d = written_bytes_q + {31'b0, array_wstrb[0]} +
                                          {31'b0, array_wstrb[1]};
                        masked_write_bytes_d = masked_write_bytes_q + {31'b0, ~array_wstrb[0]} +
                                               {31'b0, ~array_wstrb[1]};
                        burst_words_d = burst_words_q + 1'b1;
                    end
                end

                default: state_d = StIdle;
            endcase
        end
    end

    always @(posedge clk_2x_i or negedge clk_2x_i or negedge reset_n) begin
        int unsigned violations_this_tick;
        violations_this_tick = 0;
        if (!reset_n) begin
            state_q              <= StReset;
            ck_q                 <= 1'b0;
            cs_n_q               <= 1'b1;
            reset_neg_q          <= 1'b0;
            ca_q                 <= '0;
            ca_edge_count_q      <= '0;
            tx_word_q            <= DefaultValue;
            tx_have_hi_q         <= 1'b0;
            rx_word_q            <= '0;
            rx_have_hi_q         <= 1'b0;
            rx_mask_hi_q         <= 1'b0;
            addr_q               <= '0;
            read_q               <= 1'b0;
            register_space_q     <= 1'b0;
            zero_latency_write_q  <= 1'b0;
            linear_burst_q       <= 1'b1;
            latency_count_q      <= '0;
            dq_out_q             <= '0;
            dq_oe_q              <= 1'b0;
            rwds_out_q           <= 1'b0;
            rwds_oe_q            <= 1'b0;
            read_transactions_q  <= '0;
            write_transactions_q <= '0;
            read_words_q         <= '0;
            write_words_q        <= '0;
            protocol_violations_q <= '0;
            active_quarters_q     <= '0;
            clock_edges_q         <= '0;
            clock_stop_quarters_q <= '0;
            extra_latency_transactions_q <= '0;
            written_bytes_q       <= '0;
            masked_write_bytes_q  <= '0;
            discarded_read_words_q <= '0;
            longest_burst_words_q <= '0;
            total_burst_words_q    <= '0;
            completed_bursts_q     <= '0;
            register_read_transactions_q <= '0;
            register_write_transactions_q <= '0;
            extra_latency_request_transactions_q <= '0;
            burst_words_q         <= '0;
            transaction_count_q    <= '0;
            start_addr_q          <= '0;
            extra_latency_q       <= 1'b0;
            lfsr_q                <= 16'hace1;
            dq_sample_q          <= '0;
            dq_edge_sample_q     <= '0;
            rwds_sample_q        <= 1'b0;
            rwds_edge_sample_q   <= 1'b0;
            host_edge_sample_q   <= 1'b0;
            rwds_host_edge_sample_q <= 1'b0;
            cs_low_quarters_q    <= '0;
            cs_high_quarters_q   <= 32'hffff_ffff;
            ck_stable_selected_quarters_q <= '0;
            quarters_since_last_ck_fall_q <= 32'hffff_ffff;
            quarters_since_power_on_q <= '0;
            quarters_since_reset_release_q <= '0;
            reset_low_quarters_q <= '0;
            for (int unsigned i = 0; i <= DqInputDelayQuarterCycles; i++) begin
                dq_input_pipe_q[i] <= '0;
                rwds_input_pipe_q[i] <= 1'b0;
            end
            protocol_error_inject_q <= 1'b0;
            trace_valid_q         <= 1'b0;
            trace_write_q         <= 1'b0;
            trace_register_space_q <= 1'b0;
            trace_addr_q          <= '0;
            trace_words_q         <= '0;
        end else begin
            if (ProtocolCheckSeverity != 0) begin
                if ($isunknown(CSNeg)) begin
                    report_protocol_violation("CS# is unknown while sampled");
                    violations_this_tick++;
                end
                if ($isunknown(RESETNeg)) begin
                    report_protocol_violation("RESET# is unknown while sampled");
                    violations_this_tick++;
                end
                if ($isunknown(CK) || $isunknown(CKNeg)) begin
                    report_protocol_violation("CK/CK# contains X");
                    violations_this_tick++;
                end
                if (!RESETNeg && !CSNeg) begin
                    report_protocol_violation("CS# asserted while RESET# is low");
                    violations_this_tick++;
                end
                if (!reset_neg_q && RESETNeg &&
                    reset_low_quarters_q < TResetLowMinQuarterCycles) begin
                    report_protocol_violation("RESET# low time too short");
                    violations_this_tick++;
                end
                if (CSNeg && CheckCkIdleWhenCsHigh &&
                    (CK !== 1'b0 || CKNeg !== 1'b1)) begin
                    report_protocol_violation("CK/CK# are not idle low/high while CS# is high");
                    violations_this_tick++;
                end
                if (!CSNeg && (CK === CKNeg)) begin
                    report_protocol_violation("CK and CK# are not complementary while CS# is low");
                    violations_this_tick++;
                end
                if (!CSNeg && state_q == StCA && ca_edge_count_q != 0 &&
                    ck_stable_selected_quarters_q >= 2) begin
                    report_protocol_violation("CK stopped during CA transfer");
                    violations_this_tick++;
                end
                if (cs_n_q && !CSNeg) begin
                    if (CK !== 1'b0 || CKNeg !== 1'b1) begin
                        report_protocol_violation("CS# asserted while CK/CK# are not idle low/high");
                        violations_this_tick++;
                    end
                    if (cs_high_quarters_q < TCshiMinQuarterCycles) begin
                        report_protocol_violation("tCSHI violation: CS# high time too short");
                        violations_this_tick++;
                    end
                    if (quarters_since_last_ck_fall_q < TRwrMinQuarterCycles) begin
                        report_protocol_violation("tRWR violation: read/write recovery too short");
                        violations_this_tick++;
                    end
                    if (quarters_since_power_on_q < TPowerOnMinQuarterCycles) begin
                        report_protocol_violation("power-on access timing violation");
                        violations_this_tick++;
                    end
                    if (quarters_since_reset_release_q < TResetReleaseMinQuarterCycles) begin
                        report_protocol_violation("RESET# release access timing violation");
                        violations_this_tick++;
                    end
                end
                if (!cs_n_q && CSNeg) begin
                    if (CK !== 1'b0 || CKNeg !== 1'b1) begin
                        report_protocol_violation("CS# deasserted while CK/CK# are not idle low/high");
                        violations_this_tick++;
                    end
                    if (state_q == StCA && ca_edge_count_q != 0) begin
                        report_protocol_violation("CS# deasserted before completing the CA phase");
                        violations_this_tick++;
                    end
                    if (state_q == StLatency) begin
                        report_protocol_violation("CS# deasserted before the data phase");
                        violations_this_tick++;
                    end
                    if (state_q == StRead && tx_have_hi_q) begin
                        report_protocol_violation("CS# deasserted in the middle of a read word");
                        violations_this_tick++;
                    end
                    if (state_q == StWrite && rx_have_hi_q) begin
                        report_protocol_violation("CS# deasserted in the middle of a write word");
                        violations_this_tick++;
                    end
                    if (quarters_since_last_ck_fall_q < TCshMinQuarterCycles) begin
                        report_protocol_violation("tCSH violation: CS# hold after final CK falling edge too short");
                        violations_this_tick++;
                    end
                end
                // DQ may carry CA as soon as CS# falls, before the observer advances to StCA.
                if (!CSNeg && dq_oe_i &&
                    !(host_may_drive_dq(state_q, selected) || host_starts_ca)) begin
                    report_protocol_violation("DQ driven by host outside CA/write ownership window");
                    violations_this_tick++;
                end
                if (!CSNeg && rwds_oe_i && !host_owns_rwds(state_q, selected) &&
                    !(state_q == StLatency && !read_q && !zero_latency_write_q)) begin
                    report_protocol_violation("RWDS driven by host outside write-mask ownership window");
                    violations_this_tick++;
                end
                if (!CSNeg && state_q == StLatency && read_q &&
                    (latency_count_q + 16'd1 >= latency_target) && (dq_oe_i || rwds_oe_i)) begin
                    report_protocol_violation("host did not release DQ/RWDS before read data turnaround");
                    violations_this_tick++;
                end
                if (!CSNeg && state_q == StLatency && !read_q &&
                    (latency_count_q + 16'd1 >= latency_target) && rwds_oe_q && rwds_oe_i) begin
                    report_protocol_violation("model did not release RWDS before write data turnaround");
                    violations_this_tick++;
                end
                if (!CSNeg && ck_q != CK) begin
                    if (cs_low_quarters_q < TCssMinQuarterCycles) begin
                        report_protocol_violation("tCSS violation: CS# low to first CK edge too short");
                        violations_this_tick++;
                    end
                    if (host_owns_dq(state_q, selected)) begin
                        if (!dq_oe_i || $isunknown(dq_ck_sample)) begin
                            report_protocol_violation("DQ is not driven by host at CA/write sampling edge");
                            violations_this_tick++;
                        end
                        if (dq_ck_sample !== dq_sample_q) begin
                            report_protocol_violation("DQ setup violation around CA/write edge");
                            violations_this_tick++;
                        end
                    end
                    if (host_owns_rwds(state_q, selected)) begin
                        if (!rwds_oe_i || $isunknown(rwds_ck_sample)) begin
                            report_protocol_violation("RWDS mask is not driven by host at write sampling edge");
                            violations_this_tick++;
                        end
                        if (rwds_ck_sample !== rwds_sample_q) begin
                            report_protocol_violation("RWDS setup violation around write edge");
                            violations_this_tick++;
                        end
                    end
                end
                if (TIhMinQuarterCycles != 0 && host_edge_sample_q) begin
                    if (dq_in !== dq_edge_sample_q) begin
                        report_protocol_violation("DQ hold violation after CA/write edge");
                        violations_this_tick++;
                    end
                    if (rwds_host_edge_sample_q && rwds_in !== rwds_edge_sample_q) begin
                        report_protocol_violation("RWDS hold violation after write edge");
                        violations_this_tick++;
                    end
                end
                if (dq_oe_q && dq_oe_i) begin
                    report_protocol_violation("DQ bus contention while model drives read data");
                    violations_this_tick++;
                end
                if (rwds_oe_q && rwds_oe_i) begin
                    report_protocol_violation("RWDS bus contention while model drives RWDS");
                    violations_this_tick++;
                end
                if (TCsmMaxQuarterCycles != 0 && !CSNeg &&
                    cs_low_quarters_q >= TCsmMaxQuarterCycles) begin
                    report_protocol_violation("tCSM violation: CS# low maximum exceeded");
                    violations_this_tick++;
                end
            end
            state_q              <= state_d;
            ck_q                 <= CK;
            cs_n_q               <= CSNeg;
            reset_neg_q          <= RESETNeg;
            ca_q                 <= ca_d;
            ca_edge_count_q      <= ca_edge_count_d;
            tx_word_q            <= tx_word_d;
            tx_have_hi_q         <= tx_have_hi_d;
            rx_word_q            <= rx_word_d;
            rx_have_hi_q         <= rx_have_hi_d;
            rx_mask_hi_q         <= rx_mask_hi_d;
            addr_q               <= addr_d;
            read_q               <= read_d;
            register_space_q     <= register_space_d;
            zero_latency_write_q  <= zero_latency_write_d;
            linear_burst_q       <= linear_burst_d;
            latency_count_q      <= latency_count_d;
            dq_out_q             <= dq_out_d;
            dq_oe_q              <= dq_oe_d;
            rwds_out_q           <= rwds_out_d;
            rwds_oe_q            <= rwds_oe_d;
            read_transactions_q  <= read_transactions_d;
            write_transactions_q <= write_transactions_d;
            read_words_q         <= read_words_d;
            write_words_q        <= write_words_d;
            protocol_violations_q <= protocol_violations_q + violations_this_tick;
            active_quarters_q     <= active_quarters_q + {31'b0, !CSNeg};
            clock_edges_q         <= clock_edges_q + {31'b0, !CSNeg && (ck_q != CK)};
            clock_stop_quarters_q <= clock_stop_quarters_q +
                                     {31'b0, !CSNeg && (state_q != StIdle) && (ck_q == CK)};
            extra_latency_transactions_q <= extra_latency_transactions_d;
            written_bytes_q       <= written_bytes_d;
            masked_write_bytes_q  <= masked_write_bytes_d;
            discarded_read_words_q <= discarded_read_words_d;
            longest_burst_words_q <= longest_burst_words_d;
            total_burst_words_q    <= total_burst_words_d;
            completed_bursts_q     <= completed_bursts_d;
            register_read_transactions_q <= register_read_transactions_d;
            register_write_transactions_q <= register_write_transactions_d;
            extra_latency_request_transactions_q <= extra_latency_request_transactions_d;
            burst_words_q         <= burst_words_d;
            transaction_count_q    <= transaction_count_d;
            start_addr_q          <= start_addr_d;
            extra_latency_q       <= extra_latency_d;
            if (!CSNeg && ck_q != CK) begin
                lfsr_q <= {lfsr_q[14:0], lfsr_q[15] ^ lfsr_q[13] ^ lfsr_q[12] ^ lfsr_q[10]};
            end
            dq_sample_q          <= dq_in;
            rwds_sample_q        <= rwds_in;
            if (!CSNeg && ck_q != CK) begin
                dq_edge_sample_q   <= dq_ck_sample;
                rwds_edge_sample_q <= rwds_ck_sample;
                host_edge_sample_q <= host_owns_dq(state_q, selected);
                rwds_host_edge_sample_q <= host_owns_rwds(state_q, selected);
            end else begin
                host_edge_sample_q <= 1'b0;
                rwds_host_edge_sample_q <= 1'b0;
            end
            trace_valid_q         <= trace_valid_d;
            trace_write_q         <= trace_write_d;
            trace_register_space_q <= trace_register_space_d;
            trace_addr_q          <= trace_addr_d;
            trace_words_q         <= trace_words_d;
            if (!CSNeg) begin
                cs_low_quarters_q  <= cs_low_quarters_q + 1'b1;
                cs_high_quarters_q <= '0;
            end else begin
                cs_low_quarters_q  <= '0;
                if (cs_high_quarters_q != 32'hffff_ffff) begin
                    cs_high_quarters_q <= cs_high_quarters_q + 1'b1;
                end
            end
            if (!CSNeg && ck_q == CK) begin
                ck_stable_selected_quarters_q <= ck_stable_selected_quarters_q + 1'b1;
            end else begin
                ck_stable_selected_quarters_q <= '0;
            end
            if (!CSNeg && ck_q && !CK) begin
                quarters_since_last_ck_fall_q <= '0;
            end else if (quarters_since_last_ck_fall_q != 32'hffff_ffff) begin
                quarters_since_last_ck_fall_q <= quarters_since_last_ck_fall_q + 1'b1;
            end
            if (quarters_since_power_on_q != 32'hffff_ffff) begin
                quarters_since_power_on_q <= quarters_since_power_on_q + 1'b1;
            end
            if (!reset_neg_q && RESETNeg) begin
                quarters_since_reset_release_q <= '0;
            end else if (RESETNeg && quarters_since_reset_release_q != 32'hffff_ffff) begin
                quarters_since_reset_release_q <= quarters_since_reset_release_q + 1'b1;
            end else if (!RESETNeg) begin
                quarters_since_reset_release_q <= '0;
            end
            if (!RESETNeg) begin
                reset_low_quarters_q <= reset_low_quarters_q + 1'b1;
            end else if (!reset_neg_q && RESETNeg) begin
                reset_low_quarters_q <= '0;
            end
            dq_input_pipe_q[0] <= dq_i;
            rwds_input_pipe_q[0] <= rwds_i;
            for (int unsigned i = 1; i <= DqInputDelayQuarterCycles; i++) begin
                dq_input_pipe_q[i] <= dq_input_pipe_q[i-1];
                rwds_input_pipe_q[i] <= rwds_input_pipe_q[i-1];
            end
            if (!RESETNeg) begin
                state_q              <= StReset;
                ca_q                 <= '0;
                ca_edge_count_q      <= '0;
                tx_have_hi_q         <= 1'b0;
                rx_have_hi_q         <= 1'b0;
                rx_mask_hi_q         <= 1'b0;
                read_q               <= 1'b0;
                register_space_q     <= 1'b0;
                zero_latency_write_q  <= 1'b0;
                linear_burst_q       <= 1'b1;
                latency_count_q      <= '0;
                ck_stable_selected_quarters_q <= '0;
                dq_out_q             <= '0;
                dq_oe_q              <= 1'b0;
                rwds_out_q           <= 1'b0;
                rwds_oe_q            <= 1'b0;
                burst_words_q        <= '0;
                extra_latency_q      <= 1'b0;
                trace_valid_q        <= 1'b0;
            end
            protocol_error_inject_q <= InjectXOnProtocolViolation && (violations_this_tick != 0);
        end
    end

endmodule
