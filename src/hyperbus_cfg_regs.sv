// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Paul Scheffler <paulsc@iis.ee.ethz.ch>

`include "common_cells/assertions.svh"

module hyperbus_cfg_regs #(
    parameter int unsigned  NumChips        = -1,
    parameter int unsigned  NumPhys         = -1,
    parameter int unsigned  RegDataWidth    = -1,
    parameter int unsigned  RegAddrWidth    = 32,
    // Capability bits are supplied by the selected top-level clocking
    // implementation.  The register map itself remains stable across tops.
    parameter logic [7:0]   CapabilityFeatures = 8'b0010_0000,
    parameter type          reg_req_t       = logic,
    parameter type          reg_rsp_t       = logic,
    parameter type          addr_rule_t     = logic
) (
    input  logic     clk_i,
    input  logic     rst_ni,

    input  reg_req_t reg_req_i,
    output reg_rsp_t reg_rsp_o,

    output hyperbus_pkg::frontend_cfg_t frontend_cfg_o,
    output hyperbus_pkg::phy_cfg_t      phy_cfg_o,
    output addr_rule_t [NumChips-1:0]   chip_rules_o,
    input  logic                        decode_error_i
);
    `include "common_cells/registers.svh"

    localparam int unsigned NumChipsMax = 8;
    `ASSERT_INIT(NumChipsValid, NumChips >= 1 && NumChips <= NumChipsMax)
    `ASSERT_INIT(NumPhysValid, NumPhys == 1 || NumPhys == 2)
    `ASSERT_INIT(RegAddrWidthValid, RegAddrWidth >= 12)
    `ASSERT_INIT(RegDataWidthValid, RegDataWidth == 32)

    typedef logic [11:0]             cfg_addr_t;
    typedef logic [31:0]             cfg_data_t;
    typedef logic [3:0]              cfg_strb_t;

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
        cfg_addr_t  paddr;
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

    hyperbus_cfg_regblock_pkg::hyperbus_cfg_regs__out_t cfg_hwif_out;
    hyperbus_cfg_regblock_pkg::hyperbus_cfg_regs__in_t  cfg_hwif_in;
    addr_rule_t [NumChipsMax-1:0] chip_rules_all;

    cfg_addr_t cfg_addr;
    logic cfg_addr_in_window;
    logic sel_reg_mapped;
    logic cfg_access_active_d, cfg_access_active_q;
    logic cfg_access_open;
    logic cfg_status_access;
    logic cfg_value_valid;
    logic unused_cfg_fields;

    cfg_reg_req_t cfg_reg_req;
    cfg_reg_rsp_t cfg_reg_rsp;
    cfg_apb_req_t cfg_apb_req;
    cfg_apb_rsp_t cfg_apb_rsp;

    assign cfg_addr = cfg_addr_t'(reg_req_i.addr);
    assign cfg_addr_in_window = reg_req_i.addr == RegAddrWidth'(cfg_addr);
    assign cfg_status_access = reg_req_i.valid &&
                               cfg_addr_in_window && (cfg_addr == 12'h010);

    always_comb begin : proc_cfg_addr_mapped
        sel_reg_mapped = cfg_addr_in_window &&
                         ((cfg_addr == 12'h000) ||
                          (cfg_addr == 12'h004) ||
                          (cfg_addr == 12'h008) ||
                          (cfg_addr == 12'h00c) ||
                          (cfg_addr == 12'h010) ||
                          (cfg_addr == 12'h100) ||
                          (cfg_addr == 12'h200) ||
                          (cfg_addr == 12'hffc));
        for (int unsigned i = 0; i < 2; i++) begin
            sel_reg_mapped |= cfg_addr_in_window &&
                              ((cfg_addr == (12'h300 + i * 12'h40)) ||
                               (cfg_addr == (12'h304 + i * 12'h40)));
        end
        for (int unsigned i = 0; i < 8; i++) begin
            sel_reg_mapped |= cfg_addr_in_window &&
                              ((cfg_addr == (12'h400 + i * 12'h40)) ||
                               (cfg_addr == (12'h404 + i * 12'h40)) ||
                               (cfg_addr == (12'h408 + i * 12'h40)) ||
                               (cfg_addr == (12'h40c + i * 12'h40)) ||
                               (cfg_addr == (12'h410 + i * 12'h40)) ||
                               (cfg_addr == (12'h414 + i * 12'h40)) ||
                               (cfg_addr == (12'h418 + i * 12'h40)));
        end
    end
    // The configuration frontend owns draining and automatic apply sequencing.
    // Keep this wrapper purely responsible for the stable register-map access.
    assign cfg_access_open = 1'b1;

    always_comb begin : proc_cfg_value_valid
        cfg_value_valid = 1'b1;
        if (reg_req_i.valid && reg_req_i.write && sel_reg_mapped) begin
            // All byte-backed legacy values are range-checked only when their
            // corresponding byte is written, preserving partial-write behavior.
            if ((cfg_addr == 12'h100) && reg_req_i.wstrb[0]) begin
                cfg_value_valid &= (reg_req_i.wdata[7:0] <= 8'd1);
            end
            if ((cfg_addr == 12'h200) && reg_req_i.wstrb[0]) begin
                cfg_value_valid &= (reg_req_i.wdata[7:0] >= 8'd2);
            end
            if (((cfg_addr == 12'h304) || (cfg_addr == 12'h344)) &&
                reg_req_i.wstrb[0]) begin
                cfg_value_valid &= (reg_req_i.wdata[7:0] <= 8'd15);
            end
            for (int unsigned i = 0; i < 8; i++) begin
                if (cfg_addr == (12'h408 + i * 12'h40)) begin
                    if (reg_req_i.wstrb[0]) cfg_value_valid &= (reg_req_i.wdata[7:0] <= 8'd1);
                    if (reg_req_i.wstrb[1]) cfg_value_valid &= (reg_req_i.wdata[15:8] <= 8'd31);
                    if (reg_req_i.wstrb[2]) cfg_value_valid &= (reg_req_i.wdata[23:16] <= 8'd1);
                end
                if (cfg_addr == (12'h40c + i * 12'h40)) begin
                    if (reg_req_i.wstrb[0]) cfg_value_valid &=
                        (reg_req_i.wdata[7:0] >= 8'd3 && reg_req_i.wdata[7:0] <= 8'd15);
                    if (reg_req_i.wstrb[1]) cfg_value_valid &= (reg_req_i.wdata[15:8] <= 8'd15);
                    if (reg_req_i.wstrb[2]) cfg_value_valid &= (reg_req_i.wdata[23:16] <= 8'd1);
                end
                if (cfg_addr == (12'h414 + i * 12'h40)) begin
                    if (reg_req_i.wstrb[0]) cfg_value_valid &= (reg_req_i.wdata[7:0] <= 8'd15);
                    if (reg_req_i.wstrb[1]) cfg_value_valid &= (reg_req_i.wdata[15:8] <= 8'd15);
                    if (reg_req_i.wstrb[2]) cfg_value_valid &= (reg_req_i.wdata[23:16] <= 8'd15);
                end
            end
        end
    end

    assign reg_rsp_o.ready = cfg_access_open &
                             (~reg_req_i.valid | ~sel_reg_mapped | ~cfg_value_valid | cfg_reg_rsp.ready);
    assign reg_rsp_o.error = (reg_req_i.valid && ~sel_reg_mapped) |
                             (reg_req_i.valid && reg_req_i.write && sel_reg_mapped && !cfg_value_valid) |
                             cfg_reg_rsp.error;
    assign reg_rsp_o.rdata = sel_reg_mapped ? RegDataWidth'(cfg_reg_rsp.rdata) : '0;

    assign cfg_reg_req.valid = reg_req_i.valid & sel_reg_mapped & cfg_access_open & cfg_value_valid;
    assign cfg_reg_req.addr  = cfg_addr;
    assign cfg_reg_req.write = reg_req_i.write;
    assign cfg_reg_req.wdata = 32'(reg_req_i.wdata);
    assign cfg_reg_req.wstrb = cfg_strb_t'(reg_req_i.wstrb);

    always_comb begin : proc_cfg_access
        cfg_access_active_d = cfg_access_active_q;
        if (!cfg_access_active_q && cfg_reg_req.valid && !cfg_status_access) begin
            cfg_access_active_d = 1'b1;
        end
        if (cfg_access_active_q && cfg_reg_rsp.ready) begin
            cfg_access_active_d = 1'b0;
        end
    end

    `FFARN(cfg_access_active_q, cfg_access_active_d, 1'b0, clk_i, rst_ni);

    always_comb begin : proc_chip_rules
        chip_rules_all = '0;
        for (int unsigned i = 0; i < NumChipsMax; i++) begin
            chip_rules_all[i].idx = unsigned'(i);
        end
        chip_rules_all[0].start_addr = {cfg_hwif_out.chip_0.range_base.value.value, 22'b0};
        chip_rules_all[0].end_addr   = {cfg_hwif_out.chip_0.range_bound.value.value, 22'b0};
        chip_rules_all[1].start_addr = {cfg_hwif_out.chip_1.range_base.value.value, 22'b0};
        chip_rules_all[1].end_addr   = {cfg_hwif_out.chip_1.range_bound.value.value, 22'b0};
        chip_rules_all[2].start_addr = {cfg_hwif_out.chip_2.range_base.value.value, 22'b0};
        chip_rules_all[2].end_addr   = {cfg_hwif_out.chip_2.range_bound.value.value, 22'b0};
        chip_rules_all[3].start_addr = {cfg_hwif_out.chip_3.range_base.value.value, 22'b0};
        chip_rules_all[3].end_addr   = {cfg_hwif_out.chip_3.range_bound.value.value, 22'b0};
        chip_rules_all[4].start_addr = {cfg_hwif_out.chip_4.range_base.value.value, 22'b0};
        chip_rules_all[4].end_addr   = {cfg_hwif_out.chip_4.range_bound.value.value, 22'b0};
        chip_rules_all[5].start_addr = {cfg_hwif_out.chip_5.range_base.value.value, 22'b0};
        chip_rules_all[5].end_addr   = {cfg_hwif_out.chip_5.range_bound.value.value, 22'b0};
        chip_rules_all[6].start_addr = {cfg_hwif_out.chip_6.range_base.value.value, 22'b0};
        chip_rules_all[6].end_addr   = {cfg_hwif_out.chip_6.range_bound.value.value, 22'b0};
        chip_rules_all[7].start_addr = {cfg_hwif_out.chip_7.range_base.value.value, 22'b0};
        chip_rules_all[7].end_addr   = {cfg_hwif_out.chip_7.range_bound.value.value, 22'b0};
    end

    assign cfg_hwif_in.global_cfg.capability.num_chips.next = 8'(NumChips);
    assign cfg_hwif_in.global_cfg.capability.num_phys.next  = 8'(NumPhys);
    assign cfg_hwif_in.global_cfg.capability.per_chip_cfg.next  = CapabilityFeatures[0];
    assign cfg_hwif_in.global_cfg.capability.per_phy_cfg.next   = CapabilityFeatures[1];
    assign cfg_hwif_in.global_cfg.capability.chip_enable.next   = CapabilityFeatures[2];
    assign cfg_hwif_in.global_cfg.capability.clock_divider.next = CapabilityFeatures[3];
    assign cfg_hwif_in.global_cfg.capability.staged_apply.next  = CapabilityFeatures[4];
    assign cfg_hwif_in.global_cfg.capability.error_status.next  = CapabilityFeatures[5];
    assign cfg_hwif_in.global_cfg.capability.rwds_sample_timing.next =
        CapabilityFeatures[6];
    assign cfg_hwif_in.global_cfg.capability.rwds_oe_timing.next = CapabilityFeatures[7];
    assign cfg_hwif_in.global_cfg.status.decode_error.next  =
        cfg_hwif_out.global_cfg.status.decode_error.value;
    assign cfg_hwif_in.global_cfg.status.decode_error.hwset = decode_error_i;
    assign cfg_hwif_in.global_cfg.status.busy.next          = 1'b0;
    assign cfg_hwif_in.global_cfg.status.dirty.next         = 1'b0;
    // COMMAND fields are intentionally left unconsumed until staged apply is
    // implemented.  STATUS busy/dirty likewise have no point-3 source.

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
        .clk           ( clk_i            ),
        .arst_n        ( rst_ni           ),
        .s_apb_psel    ( cfg_apb_req.psel     ),
        .s_apb_penable ( cfg_apb_req.penable  ),
        .s_apb_pwrite  ( cfg_apb_req.pwrite   ),
        .s_apb_pprot   ( cfg_apb_req.pprot    ),
        .s_apb_paddr   ( cfg_apb_req.paddr    ),
        .s_apb_pwdata  ( cfg_apb_req.pwdata   ),
        .s_apb_pstrb   ( cfg_apb_req.pstrb    ),
        .s_apb_pready  ( cfg_apb_rsp.pready   ),
        .s_apb_prdata  ( cfg_apb_rsp.prdata   ),
        .s_apb_pslverr ( cfg_apb_rsp.pslverr  ),
        .hwif_in       ( cfg_hwif_in       ),
        .hwif_out      ( cfg_hwif_out     )
    );

    always_comb begin : proc_cfg_output
        frontend_cfg_o = '0;
        phy_cfg_o      = '0;

        frontend_cfg_o.address_mask_msb = cfg_hwif_out.chip_0.address_cfg.address_mask_msb.value;
        frontend_cfg_o.address_space    = cfg_hwif_out.chip_0.address_cfg.address_space.value[0];
        frontend_cfg_o.dual_phy         = (NumPhys == 2) &&
            cfg_hwif_out.frontend.frontend_cfg.dual_phy.value;
        frontend_cfg_o.phy_clock_div    = cfg_hwif_out.backend.clock_cfg.divider.value;

        phy_cfg_o.chip.t_latency_access      = cfg_hwif_out.chip_0.latency_cfg.t_latency_access.value;
        phy_cfg_o.chip.en_latency_additional = cfg_hwif_out.chip_0.latency_cfg.en_latency_additional.value;
        phy_cfg_o.chip.t_burst_max           = cfg_hwif_out.chip_0.burst_cfg.t_burst_max.value;
        phy_cfg_o.chip.t_read_write_recovery = cfg_hwif_out.chip_0.chip_timing.t_read_write_recovery.value;
        phy_cfg_o.chip.t_rx_clk_delay        = cfg_hwif_out.chip_0.rx_delay.value.value;
        phy_cfg_o.chip.t_csh_cycles          = cfg_hwif_out.chip_0.chip_timing.t_csh_cycles.value;
        phy_cfg_o.chip.csn_to_ck_cycles      = cfg_hwif_out.chip_0.chip_timing.csn_to_ck_cycles.value;
        phy_cfg_o.t_tx_clk_delay             = cfg_hwif_out.phy_0.tx_delay.value.value;
        phy_cfg_o.dual_phy                   = (NumPhys == 2) &&
            cfg_hwif_out.frontend.frontend_cfg.dual_phy.value;
    end

    // The legacy PR34 interface has no destinations for these newer fields.
    always_comb begin : proc_unused_cfg_fields
        unused_cfg_fields = ^cfg_hwif_out.backend.clock_cfg.divider.value;
        unused_cfg_fields |= ^cfg_hwif_out.phy_0.rwds_timing.rwds_oe_setup_cycles.value;
        unused_cfg_fields |= ^cfg_hwif_out.phy_1.rwds_timing.rwds_oe_setup_cycles.value;
        unused_cfg_fields |= ^cfg_hwif_out.chip_0.address_cfg.enable.value;
        unused_cfg_fields |= ^cfg_hwif_out.chip_0.latency_cfg.rwds_sample_delay.value;
        unused_cfg_fields |= ^cfg_hwif_out.chip_1.address_cfg.enable.value;
        unused_cfg_fields |= ^cfg_hwif_out.chip_1.latency_cfg.rwds_sample_delay.value;
        unused_cfg_fields |= ^cfg_hwif_out.chip_2.address_cfg.enable.value;
        unused_cfg_fields |= ^cfg_hwif_out.chip_2.latency_cfg.rwds_sample_delay.value;
        unused_cfg_fields |= ^cfg_hwif_out.chip_3.address_cfg.enable.value;
        unused_cfg_fields |= ^cfg_hwif_out.chip_3.latency_cfg.rwds_sample_delay.value;
        unused_cfg_fields |= ^cfg_hwif_out.chip_4.address_cfg.enable.value;
        unused_cfg_fields |= ^cfg_hwif_out.chip_4.latency_cfg.rwds_sample_delay.value;
        unused_cfg_fields |= ^cfg_hwif_out.chip_5.address_cfg.enable.value;
        unused_cfg_fields |= ^cfg_hwif_out.chip_5.latency_cfg.rwds_sample_delay.value;
        unused_cfg_fields |= ^cfg_hwif_out.chip_6.address_cfg.enable.value;
        unused_cfg_fields |= ^cfg_hwif_out.chip_6.latency_cfg.rwds_sample_delay.value;
        unused_cfg_fields |= ^cfg_hwif_out.chip_7.address_cfg.enable.value;
        unused_cfg_fields |= ^cfg_hwif_out.chip_7.latency_cfg.rwds_sample_delay.value;
    end

    for (genvar i = 0; unsigned'(i) < NumChipsMax; i++) begin : gen_chip_rules
        if (i < NumChips) begin : gen_active
            assign chip_rules_o[i] = chip_rules_all[i];
        end else begin : gen_inactive
            logic unused_chip_rule;
            assign unused_chip_rule = ^chip_rules_all[i];
        end
    end

endmodule : hyperbus_cfg_regs
