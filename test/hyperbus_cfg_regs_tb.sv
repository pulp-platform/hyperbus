// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

module hyperbus_cfg_regs_tb;

    localparam int unsigned NumChips = 8;

    typedef struct packed {
        logic [7:0]  addr;
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
    } rule_t;

    logic                              clk;
    logic                              rst_n;
    reg_req_t                          reg_req;
    reg_rsp_t                          reg_rsp;
    hyperbus_pkg::frontend_cfg_t       frontend_cfg;
    hyperbus_pkg::phy_cfg_t            phy_cfg;
    rule_t [NumChips-1:0]              chip_rules;
    logic                              trans_active;

    task automatic reg_write(
        input logic [7:0]  addr,
        input logic [31:0] data
    );
        @(negedge clk);
        reg_req.addr  = addr;
        reg_req.write = 1'b1;
        reg_req.wdata = data;
        reg_req.wstrb = '1;
        reg_req.valid = 1'b1;

        do begin
            @(posedge clk);
        end while (!reg_rsp.ready);
        if (reg_rsp.error) begin
            $error("Register write to 0x%0h failed", addr);
        end

        @(negedge clk);
        reg_req.valid = 1'b0;
    endtask

    task automatic reg_read(
        input  logic [7:0]  addr,
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

    always #5ns clk = ~clk;

    hyperbus_cfg_regs #(
        .NumChips     ( NumChips ),
        .NumPhys      ( 2        ),
        .RegDataWidth ( 32       ),
        .reg_req_t    ( reg_req_t ),
        .reg_rsp_t    ( reg_rsp_t ),
        .rule_t       ( rule_t    )
    ) i_dut (
        .clk_i          ( clk          ),
        .rst_ni         ( rst_n        ),
        .reg_req_i      ( reg_req      ),
        .reg_rsp_o      ( reg_rsp      ),
        .frontend_cfg_o ( frontend_cfg ),
        .phy_cfg_o      ( phy_cfg      ),
        .chip_rules_o   ( chip_rules   ),
        .trans_active_i ( trans_active )
    );

    initial begin : proc_stimulus
        logic [31:0] chip_addr;
        logic [31:0] rx_clk_delay;
        logic [31:0] tx_clk_delay;

        clk          = 1'b0;
        rst_n        = 1'b0;
        reg_req      = '0;
        trans_active = 1'b0;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        for (int unsigned i = 0; i < NumChips; i++) begin
            if ((chip_rules[i].start_addr != i * 32'h0040_0000) ||
                (chip_rules[i].end_addr != (i + 1) * 32'h0040_0000)) begin
                $error("Unexpected reset address range for chip %0d", i);
            end
        end

        // Exercise both the fine [4:0] and coarse [7:5] delay settings.
        reg_write(8'h10, 8'hb5);
        reg_write(8'h14, 8'h6a);
        reg_read(8'h10, rx_clk_delay);
        reg_read(8'h14, tx_clk_delay);
        if ((rx_clk_delay != 8'hb5) || (tx_clk_delay != 8'h6a) ||
            (phy_cfg.chip.t_rx_clk_delay != 8'hb5) ||
            (phy_cfg.t_tx_clk_delay != 8'h6a)) begin
            $error("Delay-line configuration fields did not take effect");
        end

        // Low address bits are not stored and read back as zero.
        reg_write(8'h70, 32'h8134_5678);
        reg_read(8'h70, chip_addr);
        if ((chip_addr != 32'h8100_0000) ||
            (chip_rules[7].start_addr != 32'h8100_0000)) begin
            $error("Chip address alignment was not applied");
        end

        // A new configuration access must wait for an active transfer to finish.
        trans_active = 1'b1;
        @(negedge clk);
        reg_req.addr  = 8'h00;
        reg_req.write = 1'b0;
        reg_req.valid = 1'b1;
        repeat (3) begin
            @(posedge clk);
            if (reg_rsp.ready) begin
                $error("Configuration access completed during an active transfer");
            end
        end
        trans_active = 1'b0;
        do begin
            @(posedge clk);
        end while (!reg_rsp.ready);
        @(negedge clk);
        reg_req.valid = 1'b0;

        $finish;
    end

endmodule
