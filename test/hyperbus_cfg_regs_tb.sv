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
    } rule_t;

    logic                              clk;
    logic                              rst_n;
    reg_req_t                          reg_req;
    reg_rsp_t                          reg_rsp;
    hyperbus_pkg::frontend_cfg_t       frontend_cfg;
    hyperbus_pkg::phy_cfg_t            phy_cfg;
    rule_t [NumChips-1:0]              chip_rules;
    logic                              trans_active;
    logic                              cfg_busy;
    logic                              decode_error;
    logic                              cfg_dirty;
    logic                              flush_req;
    logic                              apply_req;
    int unsigned                       command_pulse_count;

    task automatic reg_write_strobe(input logic [31:0] addr, input logic [31:0] data,
                                    input logic [3:0] strb);
        @(negedge clk);
        reg_req = '{addr: addr, write: 1'b1, wdata: data, wstrb: strb, valid: 1'b1};
        do @(posedge clk); while (!reg_rsp.ready);
        if (reg_rsp.error) $error("Register write to 0x%0h failed", addr);
        @(negedge clk);
        reg_req.valid = 1'b0;
    endtask

    task automatic reg_write(input logic [31:0] addr, input logic [31:0] data);
        reg_write_strobe(addr, data, 4'b1111);
    endtask

    task automatic reg_write_error(input logic [31:0] addr, input logic [31:0] data,
                                   input logic [3:0] strb);
        @(negedge clk);
        reg_req = '{addr: addr, write: 1'b1, wdata: data, wstrb: strb, valid: 1'b1};
        do @(posedge clk); while (!reg_rsp.ready);
        if (!reg_rsp.error) $error("Invalid register write to 0x%0h was accepted", addr);
        @(negedge clk);
        reg_req.valid = 1'b0;
    endtask

    task automatic reg_read(input logic [31:0] addr, output logic [31:0] data);
        @(negedge clk);
        reg_req = '{addr: addr, write: 1'b0, wdata: '0, wstrb: '0, valid: 1'b1};
        do @(posedge clk); while (!reg_rsp.ready);
        data = reg_rsp.rdata;
        if (reg_rsp.error) $error("Register read from 0x%0h failed", addr);
        @(negedge clk);
        reg_req.valid = 1'b0;
    endtask

    task automatic reg_read_error(input logic [31:0] addr);
        logic [31:0] unused;
        @(negedge clk);
        reg_req = '{addr: addr, write: 1'b0, wdata: '0, wstrb: '0, valid: 1'b1};
        do @(posedge clk); while (!reg_rsp.ready);
        if (!reg_rsp.error) $error("Unmapped read from 0x%0h was accepted", addr);
        unused = reg_rsp.rdata;
        @(negedge clk);
        reg_req.valid = 1'b0;
    endtask

    always #5ns clk = ~clk;

    always @(posedge clk) begin
        if (rst_n && flush_req && apply_req) command_pulse_count++;
    end

    hyperbus_cfg_regs #(
        .NumChips     ( NumChips ),
        .NumPhys      ( 2        ),
        .RegDataWidth ( 32       ),
        .RegAddrWidth ( 32       ),
        .CapabilityFeatures ( 8'hff     ),
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
        .trans_active_i ( trans_active ),
        .cfg_busy_i     ( cfg_busy     ),
        .decode_error_i ( decode_error ),
        .cfg_dirty_i    ( cfg_dirty    ),
        .flush_req_o    ( flush_req    ),
        .apply_req_o    ( apply_req    )
    );

    initial begin : proc_stimulus
        logic [31:0] data;

        clk          = 1'b0;
        rst_n        = 1'b0;
        reg_req      = '0;
        trans_active = 1'b0;
        cfg_busy     = 1'b0;
        decode_error = 1'b0;
        cfg_dirty    = 1'b0;
        command_pulse_count = 0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        reg_read(12'h000, data);
        if (data != 32'h0000_0900) $error("Unexpected IP_VERSION reset: %h", data);
        reg_read(12'h004, data);
        if (data != 32'h0001_0000) $error("Unexpected REG_IF_VERSION reset: %h", data);
        @(negedge clk);
        reg_req = '{addr: 32'h00c, write: 1'b1, wdata: 32'h3, wstrb: 4'b1111, valid: 1'b1};
        do @(posedge clk); while (!reg_rsp.ready);
        if (reg_rsp.error) $error("COMMAND write failed");
        @(negedge clk);
        reg_req.valid = 1'b0;
        repeat (2) @(posedge clk);
        #1ns;
        if (command_pulse_count != 1) begin
            $error("COMMAND strobes were sampled %0d times", command_pulse_count);
        end
        if (flush_req || apply_req) $error("COMMAND strobes were not one-cycle pulses");
        reg_read(12'h00c, data);
        if (data != 32'h0) $error("COMMAND strobes did not clear after one cycle: %h", data);
        reg_read(12'h008, data);
        if (data != 32'h00ff_0208) $error("Unexpected CAPABILITY reset: %h", data);
        reg_read(12'h010, data);
        if (data != 32'h0) $error("Unexpected STATUS reset: %h", data);
        reg_read(12'h100, data);
        if ((data != 32'h1) || !frontend_cfg.phys_in_use) $error("Unexpected frontend reset");
        reg_read(12'h200, data);
        if (data != 32'h8) $error("Unexpected CLOCK_CFG reset: %h", data);
        reg_write_error(32'h200, 32'h1, 4'b0001);
        reg_read(32'h200, data);
        if (data != 32'h8) $error("Invalid divider write modified the register: %h", data);
        reg_read(12'h300, data);
        if (data != 32'h10) $error("Unexpected PHY0 TX_DELAY reset: %h", data);
        reg_read(12'h340, data);
        if (data != 32'h10) $error("Unexpected PHY1 TX_DELAY reset: %h", data);
        reg_read(12'h408, data);
        if (data != 32'h0001_1900) $error("Unexpected chip0 ADDRESS_CFG reset: %h", data);
        reg_read(12'h40c, data);
        if (data != 32'h6) $error("Unexpected chip0 LATENCY_CFG reset: %h", data);
        reg_read(12'h410, data);
        if (data != 32'd350) $error("Unexpected chip0 BURST_CFG reset: %h", data);
        reg_read(12'h414, data);
        if (data != 32'h106) $error("Unexpected chip0 CHIP_TIMING reset: %h", data);
        reg_read(12'h418, data);
        if (data != 32'h10) $error("Unexpected chip0 RX_DELAY reset: %h", data);

        for (int unsigned i = 0; i < NumChips; i++) begin
            if ((chip_rules[i].start_addr != i * 32'h0040_0000) ||
                (chip_rules[i].end_addr != (i + 1) * 32'h0040_0000)) begin
                $error("Unexpected reset address range for chip %0d", i);
            end
        end

        reg_write(12'h340, 32'h0000_00a5);
        reg_read(12'h340, data);
        if ((data != 8'ha5) || (phy_cfg.t_tx_clk_delay != 8'h10))
            $error("PHY1 write/read or PHY0 mapping failed");
        reg_write(12'h300, 32'h0000_005a);
        if (phy_cfg.t_tx_clk_delay != 8'h5a) $error("PHY0 TX_DELAY mapping failed");

        reg_write(12'h400 + 12'h1c0, 32'h8134_5678);
        reg_read(12'h400 + 12'h1c0, data);
        if ((data != 32'h8100_0000) || (chip_rules[7].start_addr != 32'h8100_0000))
            $error("Chip7 address alignment was not applied");

        reg_write(12'h40c, 32'h0001_0007);
        reg_read(12'h40c, data);
        if ((data != 32'h0001_0007) || (phy_cfg.chip.t_latency_access != 7) ||
            !phy_cfg.chip.en_latency_additional) $error("Chip0 latency mapping failed");
        reg_write(12'h414, 32'h0000_010a);
        reg_write_strobe(32'h414, 32'h0000_0007, 4'b0001);
        reg_read(32'h414, data);
        if (data != 32'h0000_0107) $error("Partial timing write failed: %h", data);
        reg_write_error(32'h414, 32'h0000_0010, 4'b0001);
        reg_read(32'h414, data);
        if (data != 32'h0000_0107) $error("Invalid timing write modified the register: %h", data);
        reg_write_error(32'h40c, 32'h0000_0002, 4'b0001);
        reg_read(32'h40c, data);
        if (data != 32'h0001_0007) $error("Invalid latency write modified the register: %h", data);
        reg_read_error(12'h415);

        reg_read_error(12'h104);
        reg_read_error(32'h0000_1000);
        reg_read(12'hffc, data);
        if (data != '0) $error("Reserved endpoint did not read as zero");

        trans_active = 1'b1;
        cfg_busy = 1'b1;
        reg_read(32'h010, data);
        if ((data & 32'h2) == 0) $error("STATUS read was blocked during active transfer");
        decode_error = 1'b1;
        cfg_dirty = 1'b1;
        reg_read(32'h010, data);
        if ((data & 32'h5) != 32'h5) $error("STATUS hardware bits were not set: %h", data);
        trans_active = 1'b0;
        reg_write(32'h010, 32'h1);
        reg_read(32'h010, data);
        if ((data & 32'h1) == 0) $error("STATUS hwset did not win over W1C");
        decode_error = 1'b0;
        cfg_dirty = 1'b0;
        reg_write(32'h010, 32'h1);
        reg_read(32'h010, data);
        if ((data & 32'h1) != 0) $error("STATUS W1C did not clear decode_error");
        trans_active = 1'b1;
        @(negedge clk);
        reg_req = '{addr: 32'h000, write: 1'b0, wdata: '0, wstrb: '0, valid: 1'b1};
        repeat (3) begin
            @(posedge clk);
            if (reg_rsp.ready) $error("Access completed during active transfer");
        end
        trans_active = 1'b0;
        cfg_busy = 1'b0;
        do @(posedge clk); while (!reg_rsp.ready);
        @(negedge clk);
        reg_req.valid = 1'b0;

        $finish;
    end
endmodule
