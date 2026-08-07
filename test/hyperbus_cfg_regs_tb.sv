// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

module hyperbus_cfg_regs_tb;
    typedef struct packed {
        logic [31:0] addr;
        logic        write;
        logic [31:0] wdata;
        logic [3:0]  wstrb;
        logic        valid;
    } reg_req_t;
    typedef struct packed {
        logic [31:0] rdata;
        logic        error;
        logic        ready;
    } reg_rsp_t;
    typedef struct packed {
        logic [31:0] start_addr;
        logic [31:0] end_addr;
        logic [2:0]  idx;
    } addr_rule_t;

    logic clk, rst_n;
    reg_req_t reg_req;
    reg_rsp_t reg_rsp;
    logic status_busy, status_dirty, decode_error;
    logic command_flush, command_apply;
    int unsigned command_pulse_count;
    hyperbus_pkg::frontend_cfg_t frontend_cfg;
    hyperbus_pkg::phy_cfg_t phy_cfg;
    addr_rule_t [hyperbus_pkg::HyperNumChips-1:0] chip_rules;

    task automatic reg_write(input logic [31:0] addr, input logic [31:0] data);
      begin
        @(negedge clk);
        reg_req <= '{addr: addr, write: 1'b1, wdata: data, wstrb: 4'hf, valid: 1'b1};
        do begin @(posedge clk); end while (!reg_rsp.ready);
        if (reg_rsp.error) $fatal(1, "write failed at %h", addr);
        @(negedge clk);
        reg_req.valid <= 1'b0;
      end
    endtask

    task automatic reg_read(input logic [31:0] addr, output logic [31:0] data);
      begin
        @(negedge clk);
        reg_req <= '{addr: addr, write: 1'b0, wdata: '0, wstrb: '0, valid: 1'b1};
        do begin @(posedge clk); end while (!reg_rsp.ready);
        data = reg_rsp.rdata;
        if (reg_rsp.error) $fatal(1, "read failed at %h", addr);
        @(negedge clk);
        reg_req.valid <= 1'b0;
      end
    endtask

    task automatic reg_write_error(input logic [31:0] addr, input logic [31:0] data,
                                   input logic [3:0] strb);
      begin
        @(negedge clk);
        reg_req <= '{addr: addr, write: 1'b1, wdata: data, wstrb: strb, valid: 1'b1};
        do begin @(posedge clk); end while (!reg_rsp.ready);
        if (!reg_rsp.error) $error("invalid write to %h was accepted", addr);
        @(negedge clk);
        reg_req.valid <= 1'b0;
      end
    endtask

    task automatic reg_read_error(input logic [31:0] addr);
      begin
        @(negedge clk);
        reg_req <= '{addr: addr, write: 1'b0, wdata: '0, wstrb: '0, valid: 1'b1};
        do begin @(posedge clk); end while (!reg_rsp.ready);
        if (!reg_rsp.error) $error("unmapped read from %h was accepted", addr);
        @(negedge clk);
        reg_req.valid <= 1'b0;
      end
    endtask

    initial begin clk = 1'b0; forever #5ns clk = ~clk; end

    always @(posedge clk) begin
        if (rst_n && command_flush && command_apply) command_pulse_count++;
    end

    hyperbus_cfg_regs #(
        .NumPhys      ( 2         ),
        .RegDataWidth ( 32        ),
        .RegAddrWidth ( 32        ),
        .ClockDividerImplemented ( 1'b1 ),
        .reg_req_t    ( reg_req_t ),
        .reg_rsp_t    ( reg_rsp_t ),
        .addr_rule_t  ( addr_rule_t )
    ) i_cfg_regs (
        .clk_i          ( clk          ),
        .rst_ni         ( rst_n        ),
        .reg_req_i      ( reg_req      ),
        .reg_rsp_o      ( reg_rsp      ),
        .status_busy_i  ( status_busy  ),
        .status_dirty_i ( status_dirty ),
        .decode_error_i ( decode_error ),
        .command_flush_o( command_flush ),
        .command_apply_o( command_apply ),
        .frontend_cfg_o ( frontend_cfg ),
        .phy_cfg_o      ( phy_cfg      ),
        .chip_rules_o   ( chip_rules   )
    );

    initial begin : proc_stimulus
        logic [31:0] data;
        rst_n = 1'b0;
        reg_req = '0;
        status_busy = 1'b0;
        status_dirty = 1'b0;
        decode_error = 1'b0;
        command_pulse_count = 0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        reg_read(32'h000, data);
        if (data != 32'h0000_0900) $fatal(1, "IP version reset mismatch: %h", data);
        reg_read(32'h004, data);
        if (data != 32'h0001_0000) $error("REG_IF version reset mismatch: %h", data);
        reg_read(32'h008, data);
        if (data != 32'h00ff_0208) $error("capability fields mismatch: %h", data);
        reg_read(32'h400, data);
        if (data != 32'h0000_0000) $fatal(1, "chip0 base reset mismatch");
        reg_read(32'h418, data);
        if (data != 32'h0000_0010) $fatal(1, "chip0 rx delay reset mismatch");
        if ((chip_rules[7].start_addr != 32'h01c0_0000) ||
            (chip_rules[7].end_addr != 32'h0200_0000)) begin
            $error("chip7 reset range mismatch");
        end

        reg_write(32'h440, 32'h8100_0000);
        reg_read(32'h440, data);
        if (data != 32'h8100_0000) $fatal(1, "chip1 base alignment mismatch: %h", data);
        if (frontend_cfg.chip[1].range_base != 32'h8100_0000) begin
            $error("chip1 frontend mapping mismatch");
        end
        reg_write(32'h340, 32'h0000_00a5);
        if (phy_cfg.phy[1].tx_delay != 8'ha5 || phy_cfg.phy[0].tx_delay != 8'h10) begin
            $error("per-PHY delay mapping mismatch");
        end
        reg_write(32'h44c, 32'h0001_0307);
        if ((phy_cfg.chip[1].t_latency_access != 4'd7) ||
            (phy_cfg.chip[1].rwds_sample_delay != 4'd3) ||
            !phy_cfg.chip[1].en_latency_additional) begin
            $error("per-chip latency mapping mismatch");
        end

        reg_write_error(32'h200, 32'h1, 4'b0001);
        reg_read(32'h200, data);
        if (data != 32'h8) $error("invalid divider write changed the register: %h", data);
        reg_write_error(32'h44c, 32'h0000_0002, 4'b0001);
        reg_read(32'h44c, data);
        if (data != 32'h0001_0307) $error("invalid latency write changed the register: %h", data);
        reg_write_error(32'h44c, 32'h0000_0004, 4'b0001);
        reg_write_error(32'h44c, 32'h0000_0600, 4'b0010);
        reg_read(32'h44c, data);
        if (data != 32'h0001_0307) $error("inconsistent sample timing changed the register: %h", data);
        reg_read_error(32'h104);
        reg_read_error(32'h1000);

        reg_write(32'h00c, 32'h3);
        repeat (2) @(posedge clk);
        #1ns;
        if (command_pulse_count != 1) begin
            $error("command strobes were sampled %0d times", command_pulse_count);
        end
        if (command_apply || command_flush) $error("command strobes did not clear");

        status_busy = 1'b1;
        status_dirty = 1'b1;
        decode_error = 1'b1;
        reg_read(32'h010, data);
        if ((data & 32'h7) != 32'h7) $error("live status mismatch: %h", data);
        reg_write(32'h010, 32'h1);
        reg_read(32'h010, data);
        if (!data[0]) $error("hardware set did not win over W1C");
        decode_error = 1'b0;
        reg_write(32'h010, 32'h1);
        reg_read(32'h010, data);
        if (data[0]) $error("decode error did not clear");
        $finish;
    end
endmodule
