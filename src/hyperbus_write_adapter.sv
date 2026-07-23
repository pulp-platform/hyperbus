// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Thomas Benz <paulsc@iis.ee.ethz.ch>
// Paul Scheffler <paulsc@iis.ee.ethz.ch>
// Luca Valente <luca.valente@unibo.it>

`include "common_cells/registers.svh"

module hyperbus_write_adapter #(
    parameter int unsigned HostDataWidth = -1,
    parameter int unsigned NumPhys       = -1,
    parameter type         T             = logic,
    parameter int unsigned AddrWidth     = $clog2(HostDataWidth / 8)
) (
    input  logic                   clk_i,
    input  logic                   rst_ni,
    input  logic [2:0]             size_i,
    input  logic [AddrWidth-1:0]   start_addr_i,
    input  logic                   start_i,
    input  logic                   dual_phy_i,
    input  logic                   host_valid_i,
    output logic                   host_ready_o,
    input  T                       data_i,
    output logic                   phy_valid_o,
    input  logic                   phy_ready_i,
    output logic [16*NumPhys-1:0] data_o,
    output logic                   last_o,
    output logic [2*NumPhys-1:0]  strb_o
);

    localparam int unsigned NumHostBytes       = HostDataWidth / 8;
    localparam int unsigned NumPhyBytes        = NumPhys * 2;
    localparam int unsigned PhyBeatsPerHost    = NumHostBytes / NumPhyBytes;
    localparam int unsigned WordCntWidth       =
        (PhyBeatsPerHost == 1) ? 1 : $clog2(PhyBeatsPerHost);

    typedef enum logic [2:0] {
        Idle,
        Sample,
        CntReady
    } write_adapter_state_e;

    typedef struct packed {
        logic [HostDataWidth/8-1:0] strb;
        logic [HostDataWidth-1:0]   data;
        logic                       last;
    } write_buffer_t;

    write_adapter_state_e          state_d, state_q;
    write_buffer_t                 data_buffer_d, data_buffer_q;
    logic                          upsize;
    logic                          enough_data;
    logic                          first_tx_d, first_tx_q;
    logic [NumPhys*2-1:0]          mask_strobe_d, mask_strobe_q;
    logic [WordCntWidth-1:0]       word_cnt;
    logic [AddrWidth-1:0]          byte_idx_d, byte_idx_q;
    logic [3:0]                    size_d, size_q;
    logic [AddrWidth-1:0]          cnt_data_phy_d, cnt_data_phy_q;
    logic                          keep_sending;
    logic [16*NumPhys-1:0]         converted_data;
    logic [2*NumPhys-1:0]          converted_strb;
    logic                          converted_last;
    logic                          converted_valid;
    logic                          converted_ready;

    assign upsize       = ((size_q == 1) && (NumPhys == 2)) || (size_q == 0);
    assign enough_data  = !upsize;
    assign keep_sending = (size_d > ($clog2(NumPhys) + 1)) &&
                          (cnt_data_phy_d != byte_idx_q);
    assign word_cnt     = cnt_data_phy_q >> ($clog2(NumPhys) + 1);

    assign converted_data = data_buffer_q.data[(16*NumPhys)*word_cnt +: (16*NumPhys)];
    assign converted_strb = data_buffer_q.strb[(2*NumPhys)*word_cnt +: (2*NumPhys)] &
                            mask_strobe_q;
    assign converted_last = data_buffer_q.last && (!keep_sending || upsize);

    always_comb begin : proc_counters
        byte_idx_d      = byte_idx_q;
        size_d          = size_q;
        cnt_data_phy_d  = cnt_data_phy_q;
        first_tx_d      = first_tx_q;

        if (start_i) begin
            byte_idx_d     = start_addr_i;
            size_d         = size_i;
            cnt_data_phy_d = (start_addr_i >> NumPhys) << NumPhys;
            first_tx_d     = 1'b1;
        end
        if (host_valid_i && host_ready_o) begin
            byte_idx_d = ((byte_idx_q >> size_d) << size_d) + (1 << size_d);
            first_tx_d = 1'b0;
        end
        if (converted_valid && converted_ready) begin
            cnt_data_phy_d = cnt_data_phy_q + NumPhys * 2;
        end
    end

    always_comb begin : proc_sample
        data_buffer_d = data_buffer_q;

        if (state_d == Idle) begin
            data_buffer_d.last = 1'b0;
            data_buffer_d.data = '0;
        end else if (host_ready_o && host_valid_i) begin
            if (!upsize) begin
                // A full host beat remains buffered until all PHY words are emitted.
                data_buffer_d.data = data_i.data;
                data_buffer_d.strb = data_i.strb;
                data_buffer_d.last = data_i.last;
                if (first_tx_q) begin
                    for (int unsigned i = 0; i < byte_idx_q; i++) begin
                        data_buffer_d.strb[i] = 1'b0;
                    end
                end
            end else begin
                data_buffer_d.strb[byte_idx_q +: (2*NumPhys)] =
                    data_i.strb[byte_idx_q +: (2*NumPhys)];
                data_buffer_d.data[byte_idx_q*8 +: (8*NumPhys)] =
                    data_i.data[byte_idx_q*8 +: (8*NumPhys)];
                data_buffer_d.last = data_i.last;
                if (first_tx_q) begin
                    for (int unsigned i = 0; i < byte_idx_q; i++) begin
                        data_buffer_d.strb[i] = 1'b0;
                    end
                end
            end
        end
    end

    always_comb begin : proc_fsm
        state_d        = state_q;
        mask_strobe_d  = mask_strobe_q;
        host_ready_o   = 1'b0;
        converted_valid = 1'b0;

        unique case (state_q)
            Idle: begin
                mask_strobe_d = '1;
                if (start_i) begin
                    state_d = Sample;
                end
            end
            Sample: begin
                host_ready_o = 1'b1;
                if (host_valid_i && enough_data) begin
                    state_d = CntReady;
                end else if (host_valid_i) begin
                    if (byte_idx_d[NumPhys-1:0] != '0) begin
                        if (data_i.last) begin
                            state_d = CntReady;
                            for (int unsigned i = 0; i < NumPhys * 2; i++) begin
                                mask_strobe_d[i] = i < byte_idx_d[NumPhys-1:0];
                            end
                        end
                    end else begin
                        state_d = CntReady;
                    end
                end
            end
            CntReady: begin
                converted_valid = 1'b1;
                if (converted_ready) begin
                    if (converted_last) begin
                        state_d = start_i ? Sample : Idle;
                    end else if (size_d >= NumPhys) begin
                        if (cnt_data_phy_d != byte_idx_q) begin
                            state_d = CntReady;
                        end else if (host_valid_i) begin
                            host_ready_o = 1'b1;
                            state_d = enough_data ? CntReady : Sample;
                        end else begin
                            state_d = Sample;
                        end
                    end else if (cnt_data_phy_d[NumPhys-1:0] == '0) begin
                        host_ready_o = !upsize;
                        state_d = Sample;
                    end
                end
            end
            default: begin
                state_d = Idle;
            end
        endcase
    end

    if (NumPhys == 2) begin : gen_dual_phy
        logic split_d, split_q;

        always_comb begin : proc_phy_width
            data_o          = converted_data;
            strb_o          = converted_strb;
            last_o          = converted_last;
            phy_valid_o     = converted_valid;
            converted_ready = phy_ready_i;
            split_d         = split_q;

            if (!dual_phy_i) begin
                data_o          = {converted_data[15:0], converted_data[15:0]};
                strb_o          = {converted_strb[1:0], converted_strb[1:0]};
                last_o          = converted_last && split_q;
                converted_ready = phy_ready_i && split_q;
                if (split_q) begin
                    data_o = {converted_data[31:16], converted_data[31:16]};
                    strb_o = {converted_strb[3:2], converted_strb[3:2]};
                end
                if (phy_valid_o && phy_ready_i) begin
                    split_d = !split_q;
                end
            end
            if (start_i) begin
                split_d = 1'b0;
            end
        end

        `FFARN(split_q, split_d, 1'b0, clk_i, rst_ni)
    end else begin : gen_single_phy
        always_comb begin : proc_phy_width
            data_o          = converted_data;
            strb_o          = converted_strb;
            last_o          = converted_last;
            phy_valid_o     = converted_valid;
            converted_ready = phy_ready_i;
        end
    end

    `FFARN(state_q, state_d, Idle, clk_i, rst_ni)
    `FFARN(data_buffer_q, data_buffer_d, '0, clk_i, rst_ni)
    `FFARN(byte_idx_q, byte_idx_d, '0, clk_i, rst_ni)
    `FFARN(size_q, size_d, '0, clk_i, rst_ni)
    `FFARN(cnt_data_phy_q, cnt_data_phy_d, '0, clk_i, rst_ni)
    `FFARN(first_tx_q, first_tx_d, 1'b0, clk_i, rst_ni)
    `FFARN(mask_strobe_q, mask_strobe_d, '0, clk_i, rst_ni)
endmodule : hyperbus_write_adapter
