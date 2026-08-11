// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

module hyperbus_cfg_regs_tb;

    localparam int unsigned NumChips = 8;

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

    logic                              clk;
    logic                              rst_n;
    reg_req_t                          reg_req;
    reg_rsp_t                          reg_rsp;
    hyperbus_pkg::frontend_cfg_t       frontend_cfg;
    hyperbus_pkg::phy_cfg_t            phy_cfg;
    addr_rule_t [NumChips-1:0]         chip_rules;
    logic                              decode_error;

    task automatic reg_write(
        input logic [31:0] addr,
        input logic [31:0] data,
        input logic        inject_decode_error
    );
        @(negedge clk);
        reg_req.addr  = addr;
        reg_req.write = 1'b1;
        reg_req.wdata = data;
        reg_req.wstrb = '1;
        reg_req.valid = 1'b1;
        decode_error  = inject_decode_error;

        do begin
            @(posedge clk);
        end while (!reg_rsp.ready);
        if (reg_rsp.error) begin
            $error("Register write to 0x%0h failed", addr);
        end

        @(negedge clk);
        reg_req.valid = 1'b0;
        decode_error  = 1'b0;
    endtask

    task automatic reg_read(
        input  logic [31:0] addr,
        output logic [31:0] data
    );
        @(negedge clk);
        reg_req.addr  = addr;
        reg_req.write = 1'b0;
        reg_req.wdata = '0;
        reg_req.wstrb = '0;
        reg_req.valid = 1'b1;

        do begin
            @(posedge clk);
        end while (!reg_rsp.ready);
        data = reg_rsp.rdata;
        if (reg_rsp.error) begin
            $error("Register read from 0x%0h failed", addr);
        end

        @(negedge clk);
        reg_req.valid = 1'b0;
    endtask

    initial begin
        clk = 1'b0;
        forever #5ns clk = ~clk;
    end

    sim_timeout #(
        .Cycles ( 100 )
    ) i_sim_timeout (
        .clk_i  ( clk   ),
        .rst_ni ( rst_n )
    );

    hyperbus_cfg_regs #(
        .NumChips     ( NumChips   ),
        .NumPhys      ( 2          ),
        .RegDataWidth ( 32         ),
        .reg_req_t    ( reg_req_t  ),
        .reg_rsp_t    ( reg_rsp_t  ),
        .addr_rule_t  ( addr_rule_t )
    ) i_cfg_regs (
        .clk_i          ( clk           ),
        .rst_ni         ( rst_n         ),
        .reg_req_i      ( reg_req       ),
        .reg_rsp_o      ( reg_rsp       ),
        .frontend_cfg_o ( frontend_cfg  ),
        .phy_cfg_o      ( phy_cfg       ),
        .chip_rules_o   ( chip_rules    ),
        .decode_error_i ( decode_error  )
    );

    initial begin : proc_stimulus
        logic [31:0] status;
        logic [31:0] capability;
        logic [31:0] chip_addr;
        logic [31:0] clock_div;
        logic [31:0] rx_clk_delay;
        logic [31:0] tx_clk_delay;

        rst_n        = 1'b0;
        reg_req      = '0;
        decode_error = 1'b0;
        repeat (5) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        if ((chip_rules[0].start_addr != 32'h0000_0000) ||
            (chip_rules[0].end_addr != 32'h0040_0000) ||
            (chip_rules[7].start_addr != 32'h01c0_0000) ||
            (chip_rules[7].end_addr != 32'h0200_0000)) begin
            $error("Unexpected reset chip address map");
        end

        reg_read(32'h008, capability);
        if (capability != 32'h0020_0208) begin
            $error("Unexpected implementation capability bits: %h", capability);
        end

        reg_read(32'h200, clock_div);
        if ((clock_div != 8) || (frontend_cfg.phy_clock_div != 8)) begin
            $error("Unexpected PHY clock divider reset value");
        end

        reg_write(32'h200, 8'd4, 1'b0);
        reg_read(32'h200, clock_div);
        if ((clock_div != 4) || (frontend_cfg.phy_clock_div != 4)) begin
            $error("PHY clock divider write did not take effect");
        end

        // Exercise both the fine [4:0] and coarse [7:5] delay settings.
        reg_write(32'h418, 8'hb5, 1'b0);
        reg_write(32'h300, 8'h6a, 1'b0);
        reg_read(32'h418, rx_clk_delay);
        reg_read(32'h300, tx_clk_delay);
        if ((rx_clk_delay != 8'hb5) || (tx_clk_delay != 8'h6a) ||
            (phy_cfg.chip.t_rx_clk_delay != 8'hb5) ||
            (phy_cfg.t_tx_clk_delay != 8'h6a)) begin
            $error("Delay-line configuration fields did not take effect");
        end

        // Only address bits [31:22] are stored; low bits read back as zero.
        reg_write(32'h5c0, 32'h8134_5678, 1'b0);
        reg_read(32'h5c0, chip_addr);
        if ((chip_addr != 32'h8100_0000) ||
            (chip_rules[7].start_addr != 32'h8100_0000)) begin
            $error("Chip address alignment was not enforced");
        end

        // A new hardware event must win over a simultaneous software W1C.
        reg_write(32'h010, 32'h1, 1'b1);
        reg_read(32'h010, status);
        if (!status[0]) begin
            $error("Decode error was lost during a simultaneous W1C");
        end

        reg_write(32'h010, 32'h1, 1'b0);
        reg_read(32'h010, status);
        if (status[0]) begin
            $error("Decode error did not clear without a new hardware event");
        end

        $finish;
    end

endmodule
