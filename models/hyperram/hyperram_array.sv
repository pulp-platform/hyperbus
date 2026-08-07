// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

`timescale 1 ns/1 ps

module hyperram_array #(
    parameter int unsigned AddrWidth = 24,
    parameter logic [15:0] DefaultValue = 16'hffff,
    parameter logic [15:0] Id0Value = 16'h000c,
    parameter logic [15:0] Id1Value = 16'h0000,
    parameter logic [15:0] Cfg0ResetValue = 16'h8f1f,
    parameter logic [15:0] Cfg1ResetValue = 16'h0002
) (
    input  logic                  clk_i,
    input  logic                  rst_ni,

    input  logic                  req_i,
    input  logic                  write_i,
    input  logic                  register_space_i,
    input  logic [AddrWidth-1:0]  addr_i,
    input  logic [15:0]           wdata_i,
    input  logic [1:0]            wstrb_i,
    input  logic                  memory_access_enable_i,
    output logic [15:0]           rdata_o,
    output logic [15:0]           cfg0_o,
    output logic [15:0]           cfg1_o,
    output logic [31:0]           memory_words_used_o
);

    logic [15:0] mem [logic [AddrWidth-1:0]];
    logic [15:0] cfg0_q, cfg1_q;
    logic [31:0] memory_words_used_q;

    assign cfg0_o = cfg0_q;
    assign cfg1_o = cfg1_q;
    assign memory_words_used_o = memory_words_used_q;

    always_comb begin
        if (register_space_i) begin
            unique case (addr_i[2:0])
                3'h0: rdata_o = Id0Value;
                3'h1: rdata_o = Id1Value;
                3'h4: rdata_o = cfg0_q;
                3'h5: rdata_o = cfg1_q;
                default: rdata_o = DefaultValue;
            endcase
        end else if (!memory_access_enable_i) begin
            rdata_o = DefaultValue;
        end else if (mem.exists(addr_i)) begin
            rdata_o = mem[addr_i];
        end else begin
            rdata_o = DefaultValue;
        end
    end

    always @(posedge clk_i or negedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            cfg0_q <= Cfg0ResetValue;
            cfg1_q <= Cfg1ResetValue;
            memory_words_used_q <= '0;
            mem.delete();
        end else if (req_i && write_i) begin
            if (register_space_i) begin
                unique case (addr_i[2:0])
                    3'h4: begin
                        if (wstrb_i[1]) cfg0_q[15:8] <= wdata_i[15:8];
                        if (wstrb_i[0]) cfg0_q[7:0]  <= wdata_i[7:0];
                    end
                    3'h5: begin
                        if (wstrb_i[1]) cfg1_q[15:8] <= wdata_i[15:8];
                        if (wstrb_i[0]) cfg1_q[7:0]  <= wdata_i[7:0];
                    end
                    default:;
                endcase
            end else if (memory_access_enable_i) begin
                if (!mem.exists(addr_i)) begin
                    mem[addr_i] = DefaultValue;
                    if (|wstrb_i) memory_words_used_q <= memory_words_used_q + 1'b1;
                end
                if (wstrb_i[1]) mem[addr_i][15:8] = wdata_i[15:8];
                if (wstrb_i[0]) mem[addr_i][7:0]  = wdata_i[7:0];
            end
        end
    end

endmodule
