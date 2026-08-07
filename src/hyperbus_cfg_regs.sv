// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

`include "common_cells/assertions.svh"

module hyperbus_cfg_regs #(
    parameter int unsigned NumPhys                  = -1,
    parameter int unsigned RegDataWidth             = -1,
    parameter int unsigned RegAddrWidth             = 32,
    parameter bit          ClockDividerImplemented  = 1'b0,
    parameter type         reg_req_t                = logic,
    parameter type         reg_rsp_t                = logic,
    parameter type         addr_rule_t              = logic
) (
    input  logic                         clk_i,
    input  logic                         rst_ni,
    input  reg_req_t                      reg_req_i,
    output reg_rsp_t                      reg_rsp_o,
    input  logic                         status_busy_i,
    input  logic                         status_dirty_i,
    input  logic                         decode_error_i,
    output logic                         command_flush_o,
    output logic                         command_apply_o,
    output hyperbus_pkg::frontend_cfg_t  frontend_cfg_o,
    output hyperbus_pkg::phy_cfg_t       phy_cfg_o,
    output addr_rule_t [hyperbus_pkg::HyperNumChips-1:0] chip_rules_o
);
    localparam int unsigned RegStrbWidth = RegDataWidth / 8;

    `ASSERT_INIT(NumPhysValid, NumPhys == 1 || NumPhys == 2)
    `ASSERT_INIT(RegDataWidthValid, RegDataWidth == 32)
    `ASSERT_INIT(RegAddrWidthValid, RegAddrWidth >= 12)

    typedef logic [11:0] cfg_addr_t;
    typedef logic [31:0] cfg_data_t;
    typedef logic [3:0]  cfg_strb_t;

    typedef struct packed {
        cfg_addr_t addr;
        logic      write;
        cfg_data_t wdata;
        cfg_strb_t wstrb;
        logic      valid;
    } cfg_reg_req_t;

    typedef struct packed {
        cfg_data_t rdata;
        logic      error;
        logic      ready;
    } cfg_reg_rsp_t;

    typedef struct packed {
        cfg_addr_t paddr;
        logic [2:0] pprot;
        logic       psel;
        logic       penable;
        logic       pwrite;
        cfg_data_t  pwdata;
        cfg_strb_t  pstrb;
    } cfg_apb_req_t;

    typedef struct packed {
        logic      pready;
        cfg_data_t prdata;
        logic      pslverr;
    } cfg_apb_rsp_t;

    hyperbus_cfg_regblock_pkg::hyperbus_cfg_regs__in_t  cfg_hwif_in;
    hyperbus_cfg_regblock_pkg::hyperbus_cfg_regs__out_t cfg_hwif_out;
    cfg_reg_req_t cfg_reg_req;
    cfg_reg_rsp_t cfg_reg_rsp;
    cfg_apb_req_t cfg_apb_req;
    cfg_apb_rsp_t cfg_apb_rsp;
    cfg_addr_t    cfg_addr;
    logic         addr_in_window;
    logic         cfg_addr_mapped;
    logic         cfg_value_valid;

    assign cfg_addr = cfg_addr_t'(reg_req_i.addr);
    assign addr_in_window = reg_req_i.addr == RegAddrWidth'(cfg_addr);

    always_comb begin : proc_cfg_addr_mapped
        cfg_addr_mapped = addr_in_window &&
                          ((cfg_addr == 12'h000) ||
                           (cfg_addr == 12'h004) ||
                           (cfg_addr == 12'h008) ||
                           (cfg_addr == 12'h00c) ||
                           (cfg_addr == 12'h010) ||
                           (cfg_addr == 12'h100) ||
                           (cfg_addr == 12'h200) ||
                           (cfg_addr == 12'hffc));
        for (int unsigned i = 0; i < 2; i++) begin
            cfg_addr_mapped |= addr_in_window &&
                               ((cfg_addr == (12'h300 + i * 12'h40)) ||
                                (cfg_addr == (12'h304 + i * 12'h40)));
        end
        for (int unsigned i = 0; i < hyperbus_pkg::HyperNumChips; i++) begin
            cfg_addr_mapped |= addr_in_window &&
                               ((cfg_addr == (12'h400 + i * 12'h40)) ||
                                (cfg_addr == (12'h404 + i * 12'h40)) ||
                                (cfg_addr == (12'h408 + i * 12'h40)) ||
                                (cfg_addr == (12'h40c + i * 12'h40)) ||
                                (cfg_addr == (12'h410 + i * 12'h40)) ||
                                (cfg_addr == (12'h414 + i * 12'h40)) ||
                                (cfg_addr == (12'h418 + i * 12'h40)));
        end
    end

    always_comb begin : proc_cfg_value_valid
        cfg_value_valid = 1'b1;
        if (reg_req_i.valid && reg_req_i.write && addr_in_window) begin
            // Range-check byte-backed fields before narrowing them for the RTL.
            if ((cfg_addr == 12'h100) && reg_req_i.wstrb[0]) begin
                cfg_value_valid &= reg_req_i.wdata[7:0] <= 8'd1;
            end
            if ((cfg_addr == 12'h200) && reg_req_i.wstrb[0]) begin
                cfg_value_valid &= reg_req_i.wdata[7:0] >= 8'd2;
            end
            if (((cfg_addr == 12'h304) || (cfg_addr == 12'h344)) && reg_req_i.wstrb[0]) begin
                cfg_value_valid &= reg_req_i.wdata[7:0] <= 8'd15;
            end
            for (int unsigned i = 0; i < hyperbus_pkg::HyperNumChips; i++) begin
                if (cfg_addr == (12'h408 + i * 12'h40)) begin
                    if (reg_req_i.wstrb[0]) begin
                        cfg_value_valid &= reg_req_i.wdata[7:0] <= 8'd1;
                    end
                    if (reg_req_i.wstrb[1]) begin
                        cfg_value_valid &= reg_req_i.wdata[15:8] <= 8'd31;
                    end
                    if (reg_req_i.wstrb[2]) begin
                        cfg_value_valid &= reg_req_i.wdata[23:16] <= 8'd1;
                    end
                end
                if (cfg_addr == (12'h40c + i * 12'h40)) begin
                    if (reg_req_i.wstrb[0]) begin
                        cfg_value_valid &= reg_req_i.wdata[7:0] inside {[8'd3:8'd15]};
                    end
                    if (reg_req_i.wstrb[1]) begin
                        cfg_value_valid &= reg_req_i.wdata[15:8] <= 8'd15;
                    end
                    if (reg_req_i.wstrb[2]) begin
                        cfg_value_valid &= reg_req_i.wdata[23:16] <= 8'd1;
                    end
                end
                if (cfg_addr == (12'h414 + i * 12'h40)) begin
                    if (reg_req_i.wstrb[0]) begin
                        cfg_value_valid &= reg_req_i.wdata[7:0] <= 8'd15;
                    end
                    if (reg_req_i.wstrb[1]) begin
                        cfg_value_valid &= reg_req_i.wdata[15:8] <= 8'd15;
                    end
                    if (reg_req_i.wstrb[2]) begin
                        cfg_value_valid &= reg_req_i.wdata[23:16] <= 8'd15;
                    end
                end
            end
        end
    end

    assign reg_rsp_o.ready = !reg_req_i.valid || !cfg_addr_mapped ||
                             !cfg_value_valid || cfg_reg_rsp.ready;
    assign reg_rsp_o.error = reg_req_i.valid &&
                             (!cfg_addr_mapped || !cfg_value_valid || cfg_reg_rsp.error);
    assign reg_rsp_o.rdata = RegDataWidth'(cfg_reg_rsp.rdata);

    assign cfg_reg_req.valid = reg_req_i.valid && cfg_addr_mapped && cfg_value_valid;
    assign cfg_reg_req.addr  = cfg_addr;
    assign cfg_reg_req.write = reg_req_i.write;
    assign cfg_reg_req.wdata = cfg_data_t'(reg_req_i.wdata);
    assign cfg_reg_req.wstrb = cfg_strb_t'(reg_req_i.wstrb);

    // Capability and live status fields are driven by the implementation.
    assign cfg_hwif_in.global_cfg.capability.num_chips.next = 8'(hyperbus_pkg::HyperNumChips);
    assign cfg_hwif_in.global_cfg.capability.num_phys.next  = 8'(NumPhys);
    assign cfg_hwif_in.global_cfg.capability.per_chip_cfg.next = 1'b1;
    assign cfg_hwif_in.global_cfg.capability.per_phy_cfg.next = 1'b1;
    assign cfg_hwif_in.global_cfg.capability.chip_enable.next = 1'b1;
    assign cfg_hwif_in.global_cfg.capability.clock_divider.next = ClockDividerImplemented;
    assign cfg_hwif_in.global_cfg.capability.staged_apply.next = 1'b1;
    assign cfg_hwif_in.global_cfg.capability.error_status.next = 1'b1;
    assign cfg_hwif_in.global_cfg.capability.rwds_sample_timing.next = 1'b0;
    assign cfg_hwif_in.global_cfg.capability.rwds_oe_timing.next = 1'b0;
    assign cfg_hwif_in.global_cfg.status.busy.next = status_busy_i;
    assign cfg_hwif_in.global_cfg.status.dirty.next = status_dirty_i;
    assign cfg_hwif_in.global_cfg.status.decode_error.next =
        cfg_hwif_out.global_cfg.status.decode_error.value;
    assign cfg_hwif_in.global_cfg.status.decode_error.hwset = decode_error_i;

    assign command_flush_o = cfg_hwif_out.global_cfg.command.flush.value;
    assign command_apply_o = cfg_hwif_out.global_cfg.command.apply.value;

    reg_to_apb #(
        .reg_req_t ( cfg_reg_req_t ),
        .reg_rsp_t ( cfg_reg_rsp_t ),
        .apb_req_t ( cfg_apb_req_t ),
        .apb_rsp_t ( cfg_apb_rsp_t )
    ) i_reg_to_apb (
        .clk_i     ( clk_i       ),
        .rst_ni    ( rst_ni      ),
        .reg_req_i ( cfg_reg_req ),
        .reg_rsp_o ( cfg_reg_rsp ),
        .apb_req_o ( cfg_apb_req ),
        .apb_rsp_i ( cfg_apb_rsp )
    );

    hyperbus_cfg_regblock i_cfg_regblock (
        .clk           ( clk_i               ),
        .arst_n        ( rst_ni              ),
        .s_apb_psel    ( cfg_apb_req.psel    ),
        .s_apb_penable ( cfg_apb_req.penable ),
        .s_apb_pwrite  ( cfg_apb_req.pwrite  ),
        .s_apb_pprot   ( cfg_apb_req.pprot   ),
        .s_apb_paddr   ( cfg_apb_req.paddr   ),
        .s_apb_pwdata  ( cfg_apb_req.pwdata  ),
        .s_apb_pstrb   ( cfg_apb_req.pstrb   ),
        .s_apb_pready  ( cfg_apb_rsp.pready  ),
        .s_apb_prdata  ( cfg_apb_rsp.prdata  ),
        .s_apb_pslverr ( cfg_apb_rsp.pslverr ),
        .hwif_in       ( cfg_hwif_in         ),
        .hwif_out      ( cfg_hwif_out        )
    );

    always_comb begin : proc_cfg_output
        frontend_cfg_o = '0;
        phy_cfg_o      = '0;

        frontend_cfg_o.dual_phy = (NumPhys == 2) &&
            cfg_hwif_out.frontend.frontend_cfg.dual_phy.value;
        frontend_cfg_o.divider = cfg_hwif_out.backend.clock_cfg.divider.value;

        phy_cfg_o.dual_phy = frontend_cfg_o.dual_phy;
        for (int unsigned i = 0; i < hyperbus_pkg::HyperNumChips; i++) begin
            unique case (i)
                0: begin
                    frontend_cfg_o.chip[i].range_base = {cfg_hwif_out.chip_0.range_base.value.value, 22'b0};
                    frontend_cfg_o.chip[i].range_bound = {cfg_hwif_out.chip_0.range_bound.value.value, 22'b0};
                    frontend_cfg_o.chip[i].address_space = cfg_hwif_out.chip_0.address_cfg.address_space.value[0];
                    frontend_cfg_o.chip[i].address_mask_msb = cfg_hwif_out.chip_0.address_cfg.address_mask_msb.value[4:0];
                    frontend_cfg_o.chip[i].enable = cfg_hwif_out.chip_0.address_cfg.enable.value;
                    phy_cfg_o.chip[i].t_latency_access = cfg_hwif_out.chip_0.latency_cfg.t_latency_access.value[3:0];
                    phy_cfg_o.chip[i].rwds_sample_delay = cfg_hwif_out.chip_0.latency_cfg.rwds_sample_delay.value[3:0];
                    phy_cfg_o.chip[i].en_latency_additional = cfg_hwif_out.chip_0.latency_cfg.en_latency_additional.value;
                    phy_cfg_o.chip[i].t_burst_max = cfg_hwif_out.chip_0.burst_cfg.t_burst_max.value;
                    phy_cfg_o.chip[i].t_read_write_recovery = cfg_hwif_out.chip_0.chip_timing.t_read_write_recovery.value[3:0];
                    phy_cfg_o.chip[i].t_csh_cycles = cfg_hwif_out.chip_0.chip_timing.t_csh_cycles.value[3:0];
                    phy_cfg_o.chip[i].csn_to_ck_cycles = cfg_hwif_out.chip_0.chip_timing.csn_to_ck_cycles.value[3:0];
                    phy_cfg_o.chip[i].t_rx_clk_delay = cfg_hwif_out.chip_0.rx_delay.value.value;
                end
                1: begin
                    frontend_cfg_o.chip[i].range_base = {cfg_hwif_out.chip_1.range_base.value.value, 22'b0};
                    frontend_cfg_o.chip[i].range_bound = {cfg_hwif_out.chip_1.range_bound.value.value, 22'b0};
                    frontend_cfg_o.chip[i].address_space = cfg_hwif_out.chip_1.address_cfg.address_space.value[0];
                    frontend_cfg_o.chip[i].address_mask_msb = cfg_hwif_out.chip_1.address_cfg.address_mask_msb.value[4:0];
                    frontend_cfg_o.chip[i].enable = cfg_hwif_out.chip_1.address_cfg.enable.value;
                    phy_cfg_o.chip[i].t_latency_access = cfg_hwif_out.chip_1.latency_cfg.t_latency_access.value[3:0];
                    phy_cfg_o.chip[i].rwds_sample_delay = cfg_hwif_out.chip_1.latency_cfg.rwds_sample_delay.value[3:0];
                    phy_cfg_o.chip[i].en_latency_additional = cfg_hwif_out.chip_1.latency_cfg.en_latency_additional.value;
                    phy_cfg_o.chip[i].t_burst_max = cfg_hwif_out.chip_1.burst_cfg.t_burst_max.value;
                    phy_cfg_o.chip[i].t_read_write_recovery = cfg_hwif_out.chip_1.chip_timing.t_read_write_recovery.value[3:0];
                    phy_cfg_o.chip[i].t_csh_cycles = cfg_hwif_out.chip_1.chip_timing.t_csh_cycles.value[3:0];
                    phy_cfg_o.chip[i].csn_to_ck_cycles = cfg_hwif_out.chip_1.chip_timing.csn_to_ck_cycles.value[3:0];
                    phy_cfg_o.chip[i].t_rx_clk_delay = cfg_hwif_out.chip_1.rx_delay.value.value;
                end
                2: begin
                    frontend_cfg_o.chip[i].range_base = {cfg_hwif_out.chip_2.range_base.value.value, 22'b0};
                    frontend_cfg_o.chip[i].range_bound = {cfg_hwif_out.chip_2.range_bound.value.value, 22'b0};
                    frontend_cfg_o.chip[i].address_space = cfg_hwif_out.chip_2.address_cfg.address_space.value[0];
                    frontend_cfg_o.chip[i].address_mask_msb = cfg_hwif_out.chip_2.address_cfg.address_mask_msb.value[4:0];
                    frontend_cfg_o.chip[i].enable = cfg_hwif_out.chip_2.address_cfg.enable.value;
                    phy_cfg_o.chip[i].t_latency_access = cfg_hwif_out.chip_2.latency_cfg.t_latency_access.value[3:0];
                    phy_cfg_o.chip[i].rwds_sample_delay = cfg_hwif_out.chip_2.latency_cfg.rwds_sample_delay.value[3:0];
                    phy_cfg_o.chip[i].en_latency_additional = cfg_hwif_out.chip_2.latency_cfg.en_latency_additional.value;
                    phy_cfg_o.chip[i].t_burst_max = cfg_hwif_out.chip_2.burst_cfg.t_burst_max.value;
                    phy_cfg_o.chip[i].t_read_write_recovery = cfg_hwif_out.chip_2.chip_timing.t_read_write_recovery.value[3:0];
                    phy_cfg_o.chip[i].t_csh_cycles = cfg_hwif_out.chip_2.chip_timing.t_csh_cycles.value[3:0];
                    phy_cfg_o.chip[i].csn_to_ck_cycles = cfg_hwif_out.chip_2.chip_timing.csn_to_ck_cycles.value[3:0];
                    phy_cfg_o.chip[i].t_rx_clk_delay = cfg_hwif_out.chip_2.rx_delay.value.value;
                end
                3: begin
                    frontend_cfg_o.chip[i].range_base = {cfg_hwif_out.chip_3.range_base.value.value, 22'b0};
                    frontend_cfg_o.chip[i].range_bound = {cfg_hwif_out.chip_3.range_bound.value.value, 22'b0};
                    frontend_cfg_o.chip[i].address_space = cfg_hwif_out.chip_3.address_cfg.address_space.value[0];
                    frontend_cfg_o.chip[i].address_mask_msb = cfg_hwif_out.chip_3.address_cfg.address_mask_msb.value[4:0];
                    frontend_cfg_o.chip[i].enable = cfg_hwif_out.chip_3.address_cfg.enable.value;
                    phy_cfg_o.chip[i].t_latency_access = cfg_hwif_out.chip_3.latency_cfg.t_latency_access.value[3:0];
                    phy_cfg_o.chip[i].rwds_sample_delay = cfg_hwif_out.chip_3.latency_cfg.rwds_sample_delay.value[3:0];
                    phy_cfg_o.chip[i].en_latency_additional = cfg_hwif_out.chip_3.latency_cfg.en_latency_additional.value;
                    phy_cfg_o.chip[i].t_burst_max = cfg_hwif_out.chip_3.burst_cfg.t_burst_max.value;
                    phy_cfg_o.chip[i].t_read_write_recovery = cfg_hwif_out.chip_3.chip_timing.t_read_write_recovery.value[3:0];
                    phy_cfg_o.chip[i].t_csh_cycles = cfg_hwif_out.chip_3.chip_timing.t_csh_cycles.value[3:0];
                    phy_cfg_o.chip[i].csn_to_ck_cycles = cfg_hwif_out.chip_3.chip_timing.csn_to_ck_cycles.value[3:0];
                    phy_cfg_o.chip[i].t_rx_clk_delay = cfg_hwif_out.chip_3.rx_delay.value.value;
                end
                4: begin
                    frontend_cfg_o.chip[i].range_base = {cfg_hwif_out.chip_4.range_base.value.value, 22'b0};
                    frontend_cfg_o.chip[i].range_bound = {cfg_hwif_out.chip_4.range_bound.value.value, 22'b0};
                    frontend_cfg_o.chip[i].address_space = cfg_hwif_out.chip_4.address_cfg.address_space.value[0];
                    frontend_cfg_o.chip[i].address_mask_msb = cfg_hwif_out.chip_4.address_cfg.address_mask_msb.value[4:0];
                    frontend_cfg_o.chip[i].enable = cfg_hwif_out.chip_4.address_cfg.enable.value;
                    phy_cfg_o.chip[i].t_latency_access = cfg_hwif_out.chip_4.latency_cfg.t_latency_access.value[3:0];
                    phy_cfg_o.chip[i].rwds_sample_delay = cfg_hwif_out.chip_4.latency_cfg.rwds_sample_delay.value[3:0];
                    phy_cfg_o.chip[i].en_latency_additional = cfg_hwif_out.chip_4.latency_cfg.en_latency_additional.value;
                    phy_cfg_o.chip[i].t_burst_max = cfg_hwif_out.chip_4.burst_cfg.t_burst_max.value;
                    phy_cfg_o.chip[i].t_read_write_recovery = cfg_hwif_out.chip_4.chip_timing.t_read_write_recovery.value[3:0];
                    phy_cfg_o.chip[i].t_csh_cycles = cfg_hwif_out.chip_4.chip_timing.t_csh_cycles.value[3:0];
                    phy_cfg_o.chip[i].csn_to_ck_cycles = cfg_hwif_out.chip_4.chip_timing.csn_to_ck_cycles.value[3:0];
                    phy_cfg_o.chip[i].t_rx_clk_delay = cfg_hwif_out.chip_4.rx_delay.value.value;
                end
                5: begin
                    frontend_cfg_o.chip[i].range_base = {cfg_hwif_out.chip_5.range_base.value.value, 22'b0};
                    frontend_cfg_o.chip[i].range_bound = {cfg_hwif_out.chip_5.range_bound.value.value, 22'b0};
                    frontend_cfg_o.chip[i].address_space = cfg_hwif_out.chip_5.address_cfg.address_space.value[0];
                    frontend_cfg_o.chip[i].address_mask_msb = cfg_hwif_out.chip_5.address_cfg.address_mask_msb.value[4:0];
                    frontend_cfg_o.chip[i].enable = cfg_hwif_out.chip_5.address_cfg.enable.value;
                    phy_cfg_o.chip[i].t_latency_access = cfg_hwif_out.chip_5.latency_cfg.t_latency_access.value[3:0];
                    phy_cfg_o.chip[i].rwds_sample_delay = cfg_hwif_out.chip_5.latency_cfg.rwds_sample_delay.value[3:0];
                    phy_cfg_o.chip[i].en_latency_additional = cfg_hwif_out.chip_5.latency_cfg.en_latency_additional.value;
                    phy_cfg_o.chip[i].t_burst_max = cfg_hwif_out.chip_5.burst_cfg.t_burst_max.value;
                    phy_cfg_o.chip[i].t_read_write_recovery = cfg_hwif_out.chip_5.chip_timing.t_read_write_recovery.value[3:0];
                    phy_cfg_o.chip[i].t_csh_cycles = cfg_hwif_out.chip_5.chip_timing.t_csh_cycles.value[3:0];
                    phy_cfg_o.chip[i].csn_to_ck_cycles = cfg_hwif_out.chip_5.chip_timing.csn_to_ck_cycles.value[3:0];
                    phy_cfg_o.chip[i].t_rx_clk_delay = cfg_hwif_out.chip_5.rx_delay.value.value;
                end
                6: begin
                    frontend_cfg_o.chip[i].range_base = {cfg_hwif_out.chip_6.range_base.value.value, 22'b0};
                    frontend_cfg_o.chip[i].range_bound = {cfg_hwif_out.chip_6.range_bound.value.value, 22'b0};
                    frontend_cfg_o.chip[i].address_space = cfg_hwif_out.chip_6.address_cfg.address_space.value[0];
                    frontend_cfg_o.chip[i].address_mask_msb = cfg_hwif_out.chip_6.address_cfg.address_mask_msb.value[4:0];
                    frontend_cfg_o.chip[i].enable = cfg_hwif_out.chip_6.address_cfg.enable.value;
                    phy_cfg_o.chip[i].t_latency_access = cfg_hwif_out.chip_6.latency_cfg.t_latency_access.value[3:0];
                    phy_cfg_o.chip[i].rwds_sample_delay = cfg_hwif_out.chip_6.latency_cfg.rwds_sample_delay.value[3:0];
                    phy_cfg_o.chip[i].en_latency_additional = cfg_hwif_out.chip_6.latency_cfg.en_latency_additional.value;
                    phy_cfg_o.chip[i].t_burst_max = cfg_hwif_out.chip_6.burst_cfg.t_burst_max.value;
                    phy_cfg_o.chip[i].t_read_write_recovery = cfg_hwif_out.chip_6.chip_timing.t_read_write_recovery.value[3:0];
                    phy_cfg_o.chip[i].t_csh_cycles = cfg_hwif_out.chip_6.chip_timing.t_csh_cycles.value[3:0];
                    phy_cfg_o.chip[i].csn_to_ck_cycles = cfg_hwif_out.chip_6.chip_timing.csn_to_ck_cycles.value[3:0];
                    phy_cfg_o.chip[i].t_rx_clk_delay = cfg_hwif_out.chip_6.rx_delay.value.value;
                end
                default: begin
                    frontend_cfg_o.chip[i].range_base = {cfg_hwif_out.chip_7.range_base.value.value, 22'b0};
                    frontend_cfg_o.chip[i].range_bound = {cfg_hwif_out.chip_7.range_bound.value.value, 22'b0};
                    frontend_cfg_o.chip[i].address_space = cfg_hwif_out.chip_7.address_cfg.address_space.value[0];
                    frontend_cfg_o.chip[i].address_mask_msb = cfg_hwif_out.chip_7.address_cfg.address_mask_msb.value[4:0];
                    frontend_cfg_o.chip[i].enable = cfg_hwif_out.chip_7.address_cfg.enable.value;
                    phy_cfg_o.chip[i].t_latency_access = cfg_hwif_out.chip_7.latency_cfg.t_latency_access.value[3:0];
                    phy_cfg_o.chip[i].rwds_sample_delay = cfg_hwif_out.chip_7.latency_cfg.rwds_sample_delay.value[3:0];
                    phy_cfg_o.chip[i].en_latency_additional = cfg_hwif_out.chip_7.latency_cfg.en_latency_additional.value;
                    phy_cfg_o.chip[i].t_burst_max = cfg_hwif_out.chip_7.burst_cfg.t_burst_max.value;
                    phy_cfg_o.chip[i].t_read_write_recovery = cfg_hwif_out.chip_7.chip_timing.t_read_write_recovery.value[3:0];
                    phy_cfg_o.chip[i].t_csh_cycles = cfg_hwif_out.chip_7.chip_timing.t_csh_cycles.value[3:0];
                    phy_cfg_o.chip[i].csn_to_ck_cycles = cfg_hwif_out.chip_7.chip_timing.csn_to_ck_cycles.value[3:0];
                    phy_cfg_o.chip[i].t_rx_clk_delay = cfg_hwif_out.chip_7.rx_delay.value.value;
                end
            endcase
        end

        phy_cfg_o.phy[0].tx_delay = cfg_hwif_out.phy_0.tx_delay.value.value;
        phy_cfg_o.phy[0].rwds_oe_setup_cycles = cfg_hwif_out.phy_0.rwds_timing.rwds_oe_setup_cycles.value[3:0];
        phy_cfg_o.phy[1].tx_delay = cfg_hwif_out.phy_1.tx_delay.value.value;
        phy_cfg_o.phy[1].rwds_oe_setup_cycles = cfg_hwif_out.phy_1.rwds_timing.rwds_oe_setup_cycles.value[3:0];
    end

    always_comb begin : proc_chip_rules
        chip_rules_o = '0;
        for (int unsigned i = 0; i < hyperbus_pkg::HyperNumChips; i++) begin
            chip_rules_o[i].idx = unsigned'(i);
            chip_rules_o[i].start_addr = frontend_cfg_o.chip[i].range_base;
            chip_rules_o[i].end_addr = frontend_cfg_o.chip[i].range_bound;
        end
    end
endmodule : hyperbus_cfg_regs
