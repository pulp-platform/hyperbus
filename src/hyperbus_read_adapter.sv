// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Luca Valente <luca.valente@unibo.it>

`include "common_cells/registers.svh"

module hyperbus_read_adapter #(
    parameter int unsigned HostDataWidth = -1,
    parameter int unsigned NumPhys       = -1,
    parameter type         T             = logic,
    parameter int unsigned BurstLength   = -1,
    parameter int unsigned AddrWidth     = $clog2(HostDataWidth / 8)
) (
    input  logic                   clk_i,
    input  logic                   rst_ni,
    input  logic [2:0]             size_i,
    input  logic                   start_i,
    input  logic                   dual_phy_i,
    input  logic [AddrWidth-1:0]   start_addr_i,
    input  logic [BurstLength-1:0] burst_len_i,
    output logic                   host_valid_o,
    input  logic                   host_ready_i,
    output T                       data_o,
    input  logic                   phy_valid_i,
    output logic                   phy_ready_o,
    input  logic [16*NumPhys-1:0]  data_i,
    input  logic                   last_i,
    input  logic                   error_i
);

    localparam int unsigned NumHostBytes     = HostDataWidth / 8;
    localparam int unsigned NumPhyBytes      = NumPhys * 2;
    localparam int unsigned PhyBeatsPerHost  = NumHostBytes / NumPhyBytes;
    localparam int unsigned WordCntWidth     =
        (PhyBeatsPerHost == 1) ? 1 : $clog2(PhyBeatsPerHost);

    typedef enum logic [2:0] {
        Idle,
        WaitData,
        Sample,
        CntReady
    } read_adapter_state_e;

    read_adapter_state_e          state_d, state_q;
    logic [BurstLength-1:0]       byte_host_addr_d, byte_host_addr_q;
    logic [BurstLength-1:0]       byte_phy_cnt_d, byte_phy_cnt_q;
    logic [BurstLength-1:0]       last_addr_d, last_addr_q;
    logic [3:0]                   size_d, size_q;
    T                             data_buffer_d, data_buffer_q;
    logic [WordCntWidth-1:0]      word_cnt;
    logic                         enough_data;
    logic                         enough_data_q;
    logic                         sent_available_data;
    logic [BurstLength-1:0]       next_host_addr;
    logic                         host_last;
    logic [16*NumPhys-1:0]        converted_data;
    logic                         converted_last;
    logic                         converted_error;
    logic                         converted_valid;
    logic                         converted_ready;

    assign word_cnt = (PhyBeatsPerHost == 1) ? '0 :
        byte_phy_cnt_q[($clog2(NumPhys) + 1) +: WordCntWidth];
    assign next_host_addr      = ((byte_host_addr_q >> size_q) << size_q) + (1 << size_q);
    assign enough_data         = byte_phy_cnt_d >= next_host_addr;
    assign enough_data_q       = byte_phy_cnt_q >= next_host_addr;
    assign sent_available_data = byte_host_addr_d >= byte_phy_cnt_q;
    assign host_last           = data_buffer_q.last && (last_addr_q == next_host_addr);

    assign data_o.data      = data_buffer_q.data;
    assign data_o.resp      = data_buffer_q.resp;
    assign data_o.last      = host_last;
    assign data_o.atomic_ok = 1'b0;

    always_comb begin : proc_counters
        byte_host_addr_d = byte_host_addr_q;
        byte_phy_cnt_d   = byte_phy_cnt_q;
        last_addr_d      = last_addr_q;
        size_d           = size_q;

        if (start_i) begin
            byte_host_addr_d[BurstLength-1:AddrWidth] = '0;
            byte_host_addr_d[AddrWidth-1:0] = start_addr_i;
            byte_phy_cnt_d[BurstLength-1:AddrWidth] = '0;
            byte_phy_cnt_d[AddrWidth-1:0] = (start_addr_i >> NumPhys) << NumPhys;
            last_addr_d = ((start_addr_i >> size_i) << size_i) + (burst_len_i << size_i);
            size_d = size_i;
        end
        if (host_valid_o && host_ready_i) begin
            byte_host_addr_d = ((byte_host_addr_q >> size_q) << size_q) + (1 << size_q);
        end
        if (converted_valid && converted_ready) begin
            byte_phy_cnt_d = byte_phy_cnt_q + NumPhys * 2;
        end
    end

    always_comb begin : proc_sample
        data_buffer_d = data_buffer_q;

        if (state_d == Idle) begin
            data_buffer_d.last = 1'b0;
            data_buffer_d.data = '0;
            data_buffer_d.resp = hyperbus_pkg::HyperRespOkay;
        end else begin
            if (host_valid_o && host_ready_i) begin
                data_buffer_d.resp = hyperbus_pkg::HyperRespOkay;
            end
            if (converted_ready && converted_valid) begin
                data_buffer_d.data[word_cnt*(16*NumPhys) +: (16*NumPhys)] = converted_data;
                if (converted_error) begin
                    data_buffer_d.resp = hyperbus_pkg::HyperRespAccessError;
                end
                data_buffer_d.last = converted_last;
            end
        end
    end

    always_comb begin : proc_fsm
        state_d      = state_q;
        host_valid_o = 1'b0;
        converted_ready = 1'b0;

        unique case (state_q)
            Idle: begin
                if (start_i) begin
                    state_d = WaitData;
                end
            end
            WaitData: begin
                converted_ready = 1'b1;
                if (converted_valid) begin
                    state_d = Sample;
                end
            end
            Sample: begin
                converted_ready = 1'b1;
                if (enough_data) begin
                    state_d = CntReady;
                end
            end
            CntReady: begin
                host_valid_o = enough_data_q;
                converted_ready = !enough_data_q;
                if (host_valid_o && host_ready_i) begin
                    if (data_o.last || (last_addr_q == byte_host_addr_d)) begin
                        state_d = Idle;
                    end else if (sent_available_data) begin
                        converted_ready = 1'b1;
                        state_d = converted_valid ? Sample : WaitData;
                    end
                end
            end
            default: begin
                state_d = Idle;
            end
        endcase
    end

    if (NumPhys == 2) begin : gen_dual_phy
        logic [15:0] lower_data_d, lower_data_q;
        logic        lower_error_d, lower_error_q;
        logic        merge_d, merge_q;

        always_comb begin : proc_phy_width
            converted_data  = data_i;
            converted_last  = last_i;
            converted_error = error_i;
            converted_valid = phy_valid_i;
            phy_ready_o      = converted_ready;
            lower_data_d     = lower_data_q;
            lower_error_d    = lower_error_q;
            merge_d          = merge_q;

            if (!dual_phy_i) begin
                converted_data  = {data_i[15:0], lower_data_q};
                converted_last  = last_i && merge_q;
                converted_error = error_i || lower_error_q;
                converted_valid = phy_valid_i && merge_q;
                if (phy_valid_i && phy_ready_o) begin
                    merge_d = !merge_q;
                    if (!merge_q) begin
                        lower_data_d  = data_i[15:0];
                        lower_error_d = error_i;
                    end else begin
                        lower_error_d = 1'b0;
                    end
                end
            end
            if (start_i) begin
                merge_d       = 1'b0;
                lower_error_d = 1'b0;
            end
        end

        `FFARN(lower_data_q, lower_data_d, '0, clk_i, rst_ni)
        `FFARN(lower_error_q, lower_error_d, 1'b0, clk_i, rst_ni)
        `FFARN(merge_q, merge_d, 1'b0, clk_i, rst_ni)
    end else begin : gen_single_phy
        always_comb begin : proc_phy_width
            converted_data  = data_i;
            converted_last  = last_i;
            converted_error = error_i;
            converted_valid = phy_valid_i;
            phy_ready_o      = converted_ready;
        end
    end

    `FFARN(state_q, state_d, Idle, clk_i, rst_ni)
    `FFARN(data_buffer_q, data_buffer_d, '0, clk_i, rst_ni)
    `FFARN(byte_host_addr_q, byte_host_addr_d, '0, clk_i, rst_ni)
    `FFARN(byte_phy_cnt_q, byte_phy_cnt_d, '0, clk_i, rst_ni)
    `FFARN(size_q, size_d, '0, clk_i, rst_ni)
    `FFARN(last_addr_q, last_addr_d, '0, clk_i, rst_ni)
endmodule : hyperbus_read_adapter
