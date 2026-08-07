// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

`timescale 1 ns/1 ps

import hyperram_model_pkg::*;

module hyperram_model #(
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
    inout  tri   [7:0] DQ,
    inout  tri         RWDS,
    input  logic       RESETNeg,

    output logic [31:0] read_transactions_o,
    output logic [31:0] write_transactions_o,
    output logic [31:0] read_words_o,
    output logic [31:0] write_words_o,
    output logic [31:0] protocol_violations_o,
    output logic [31:0] memory_words_used_o,
    output logic [31:0] active_quarters_o,
    output logic [31:0] clock_edges_o,
    output logic [31:0] clock_stop_quarters_o,
    output logic [31:0] extra_latency_transactions_o,
    output logic [31:0] written_bytes_o,
    output logic [31:0] masked_write_bytes_o,
    output logic [31:0] discarded_read_words_o,
    output logic [31:0] longest_burst_words_o,
    output logic [31:0] total_burst_words_o,
    output logic [31:0] completed_bursts_o,
    output logic [31:0] average_burst_words_o,
    output logic [31:0] register_read_transactions_o,
    output logic [31:0] register_write_transactions_o,
    output logic [31:0] extra_latency_request_transactions_o,
    output logic [31:0] deep_power_down_entries_o,
    output logic [31:0] hybrid_sleep_entries_o,
    output logic        deep_power_down_o,
    output logic        hybrid_sleep_o,
    output logic        trace_valid_o,
    output logic        trace_write_o,
    output logic        trace_register_space_o,
    output logic [AddrWidth-1:0] trace_addr_o,
    output logic [31:0] trace_words_o
);

    logic [7:0] dq_o;
    logic       dq_oe;
    logic       rwds_o;
    logic       rwds_oe;
    metrics_t   metrics;
    state_t     state;
    trace_t     trace;

    assign DQ = dq_oe ? dq_o : 8'hzz;
    assign RWDS = rwds_oe ? rwds_o : 1'bz;
    assign read_transactions_o = metrics.read_transactions;
    assign write_transactions_o = metrics.write_transactions;
    assign read_words_o = metrics.read_words;
    assign write_words_o = metrics.write_words;
    assign protocol_violations_o = metrics.protocol_violations;
    assign memory_words_used_o = metrics.memory_words_used;
    assign active_quarters_o = metrics.active_quarters;
    assign clock_edges_o = metrics.clock_edges;
    assign clock_stop_quarters_o = metrics.clock_stop_quarters;
    assign extra_latency_transactions_o = metrics.extra_latency_transactions;
    assign written_bytes_o = metrics.written_bytes;
    assign masked_write_bytes_o = metrics.masked_write_bytes;
    assign discarded_read_words_o = metrics.discarded_read_words;
    assign longest_burst_words_o = metrics.longest_burst_words;
    assign total_burst_words_o = metrics.total_burst_words;
    assign completed_bursts_o = metrics.completed_bursts;
    assign average_burst_words_o = metrics.average_burst_words;
    assign register_read_transactions_o = metrics.register_read_transactions;
    assign register_write_transactions_o = metrics.register_write_transactions;
    assign extra_latency_request_transactions_o = metrics.extra_latency_request_transactions;
    assign deep_power_down_entries_o = metrics.deep_power_down_entries;
    assign hybrid_sleep_entries_o = metrics.hybrid_sleep_entries;
    assign deep_power_down_o = state.deep_power_down;
    assign hybrid_sleep_o = state.hybrid_sleep;
    assign trace_valid_o = trace.valid;
    assign trace_write_o = trace.write;
    assign trace_register_space_o = trace.register_space;
    assign trace_addr_o = AddrWidth'(trace.addr);
    assign trace_words_o = trace.words;

    hyperram_model_core #(
        .AddrWidth                    ( AddrWidth                    ),
        .DefaultValue                 ( DefaultValue                 ),
        .FixedLatencyCycles           ( FixedLatencyCycles           ),
        .WrappedBurstLengthWords      ( WrappedBurstLengthWords      ),
        .WrappedBurstHybridLinear     ( WrappedBurstHybridLinear     ),
        .LatencyPolicy                ( LatencyPolicy                ),
        .DeviceProfile                ( DeviceProfile                ),
        .Id0Value                     ( Id0Value                     ),
        .Id1Value                     ( Id1Value                     ),
        .Cfg0ResetValue               ( Cfg0ResetValue               ),
        .Cfg1ResetValue               ( Cfg1ResetValue               ),
        .ExtraLatencyRequestPolicy       ( ExtraLatencyRequestPolicy       ),
        .ExtraLatencyRequestPeriod       ( ExtraLatencyRequestPeriod       ),
        .ExtraLatencyRequestProbabilityPermille ( ExtraLatencyRequestProbabilityPermille ),
        .ZeroLatencyMemoryWrites      ( ZeroLatencyMemoryWrites      ),
        .TPowerOnMinQuarterCycles     ( TPowerOnMinQuarterCycles     ),
        .TResetReleaseMinQuarterCycles ( TResetReleaseMinQuarterCycles ),
        .DqInputDelayQuarterCycles    ( DqInputDelayQuarterCycles    ),
        .InjectXOnProtocolViolation   ( InjectXOnProtocolViolation   ),
        .InjectZOnIllegalLatency      ( InjectZOnIllegalLatency      ),
        .ForceIllegalLatencyIndication ( ForceIllegalLatencyIndication ),
        .ProtocolCheckSeverity        ( ProtocolCheckSeverity        ),
        .TCssMinQuarterCycles         ( TCssMinQuarterCycles         ),
        .TCshiMinQuarterCycles        ( TCshiMinQuarterCycles        ),
        .TRwrMinQuarterCycles         ( TRwrMinQuarterCycles         ),
        .TCshMinQuarterCycles         ( TCshMinQuarterCycles         ),
        .TIhMinQuarterCycles          ( TIhMinQuarterCycles          ),
        .TCsmMaxQuarterCycles         ( TCsmMaxQuarterCycles         ),
        .TResetLowMinQuarterCycles    ( TResetLowMinQuarterCycles    ),
        .CheckCkIdleWhenCsHigh        ( CheckCkIdleWhenCsHigh        )
    ) i_core (
        .clk_2x_i             ( clk_2x_i             ),
        .rst_ni               ( rst_ni               ),
        .CSNeg                ( CSNeg                ),
        .CK                   ( CK                   ),
        .CKNeg                ( CKNeg                ),
        .dq_i                 ( DQ                   ),
        .dq_oe_i              ( !dq_oe && (DQ !== 8'hzz) ),
        .dq_o                 ( dq_o                 ),
        .dq_oe_o              ( dq_oe                ),
        .rwds_i               ( RWDS                 ),
        .rwds_oe_i            ( !rwds_oe && (RWDS !== 1'bz) ),
        .rwds_o               ( rwds_o               ),
        .rwds_oe_o            ( rwds_oe              ),
        .RESETNeg             ( RESETNeg             ),
        .metrics_o            ( metrics              ),
        .state_o              ( state                ),
        .trace_o              ( trace                )
    );

endmodule
