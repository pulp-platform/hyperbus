// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

`timescale 1 ns/1 ps

package hyperram_model_pkg;

    typedef struct packed {
        logic [31:0] read_transactions;
        logic [31:0] write_transactions;
        logic [31:0] read_words;
        logic [31:0] write_words;
        logic [31:0] protocol_violations;
        logic [31:0] memory_words_used;
        logic [31:0] active_quarters;
        logic [31:0] clock_edges;
        logic [31:0] clock_stop_quarters;
        logic [31:0] extra_latency_transactions;
        logic [31:0] written_bytes;
        logic [31:0] masked_write_bytes;
        logic [31:0] discarded_read_words;
        logic [31:0] longest_burst_words;
        logic [31:0] total_burst_words;
        logic [31:0] completed_bursts;
        logic [31:0] average_burst_words;
        logic [31:0] register_read_transactions;
        logic [31:0] register_write_transactions;
        logic [31:0] extra_latency_request_transactions;
        logic [31:0] deep_power_down_entries;
        logic [31:0] hybrid_sleep_entries;
    } metrics_t;

    typedef struct packed {
        logic deep_power_down;
        logic hybrid_sleep;
    } state_t;

    typedef struct packed {
        logic        valid;
        logic        write;
        logic        register_space;
        logic [31:0] addr;
        logic [31:0] words;
    } trace_t;

endpackage
