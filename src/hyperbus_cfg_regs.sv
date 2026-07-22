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
    parameter type          reg_req_t       = logic,
    parameter type          reg_rsp_t       = logic,
    parameter type          rule_t          = logic
) (
    input  logic     clk_i,
    input  logic     rst_ni,

    input  reg_req_t reg_req_i,
    output reg_rsp_t reg_rsp_o,

    output hyperbus_pkg::frontend_cfg_t frontend_cfg_o,
    output hyperbus_pkg::phy_cfg_t      phy_cfg_o,
    output rule_t [NumChips-1:0]        chip_rules_o,
    input                               trans_active_i
);
    `include "common_cells/registers.svh"

    localparam int unsigned NumChipsMax = 8;
    localparam int unsigned NumRegs      = 30;
    localparam int unsigned RegsBits     = cf_math_pkg::idx_width(NumRegs);
    localparam int unsigned RegStrbWidth = RegDataWidth/8;

    `ASSERT_INIT(NumChipsValid, NumChips >= 1 && NumChips <= NumChipsMax)
    `ASSERT_INIT(NumPhysValid, NumPhys == 1 || NumPhys == 2)
    `ASSERT_INIT(RegDataWidthValid, RegDataWidth == 32)

    typedef logic [RegsBits-1:0]     reg_idx_t;
    typedef logic [6:0]              cfg_addr_t;
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
    rule_t [NumChipsMax-1:0] chip_rules_all;

    reg_idx_t sel_reg;
    logic sel_reg_mapped;
    logic cfg_access_active_d, cfg_access_active_q;
    logic cfg_access_open;

    cfg_reg_req_t cfg_reg_req;
    cfg_reg_rsp_t cfg_reg_rsp;
    cfg_apb_req_t cfg_apb_req;
    cfg_apb_rsp_t cfg_apb_rsp;

    assign sel_reg        = reg_req_i.addr[$clog2(RegStrbWidth) +: RegsBits];
    assign sel_reg_mapped = (sel_reg < NumRegs);
    assign cfg_access_open = ~trans_active_i | cfg_access_active_q;

    assign reg_rsp_o.ready = cfg_access_open &
                             (~reg_req_i.valid | ~sel_reg_mapped | cfg_reg_rsp.ready);
    assign reg_rsp_o.error = ~sel_reg_mapped | cfg_reg_rsp.error;
    assign reg_rsp_o.rdata = sel_reg_mapped ? RegDataWidth'(cfg_reg_rsp.rdata) : '0;

    assign cfg_reg_req.valid = reg_req_i.valid & sel_reg_mapped & cfg_access_open;
    assign cfg_reg_req.addr  = {sel_reg, 2'b00};
    assign cfg_reg_req.write = reg_req_i.write;
    assign cfg_reg_req.wdata = 32'(reg_req_i.wdata);
    assign cfg_reg_req.wstrb = cfg_strb_t'(reg_req_i.wstrb);

    always_comb begin : proc_cfg_access
        cfg_access_active_d = cfg_access_active_q;
        if (!cfg_access_active_q && cfg_reg_req.valid) begin
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
            unique case (i)
                0: begin
                    chip_rules_all[i].start_addr = {
                        cfg_hwif_out.chip0_base.value.value, 22'b0};
                    chip_rules_all[i].end_addr = {
                        cfg_hwif_out.chip0_bound.value.value, 22'b0};
                end
                1: begin
                    chip_rules_all[i].start_addr = {
                        cfg_hwif_out.chip1_base.value.value, 22'b0};
                    chip_rules_all[i].end_addr = {
                        cfg_hwif_out.chip1_bound.value.value, 22'b0};
                end
                2: begin
                    chip_rules_all[i].start_addr = {
                        cfg_hwif_out.chip2_base.value.value, 22'b0};
                    chip_rules_all[i].end_addr = {
                        cfg_hwif_out.chip2_bound.value.value, 22'b0};
                end
                3: begin
                    chip_rules_all[i].start_addr = {
                        cfg_hwif_out.chip3_base.value.value, 22'b0};
                    chip_rules_all[i].end_addr = {
                        cfg_hwif_out.chip3_bound.value.value, 22'b0};
                end
                4: begin
                    chip_rules_all[i].start_addr = {
                        cfg_hwif_out.chip4_base.value.value, 22'b0};
                    chip_rules_all[i].end_addr = {
                        cfg_hwif_out.chip4_bound.value.value, 22'b0};
                end
                5: begin
                    chip_rules_all[i].start_addr = {
                        cfg_hwif_out.chip5_base.value.value, 22'b0};
                    chip_rules_all[i].end_addr = {
                        cfg_hwif_out.chip5_bound.value.value, 22'b0};
                end
                6: begin
                    chip_rules_all[i].start_addr = {
                        cfg_hwif_out.chip6_base.value.value, 22'b0};
                    chip_rules_all[i].end_addr = {
                        cfg_hwif_out.chip6_bound.value.value, 22'b0};
                end
                7: begin
                    chip_rules_all[i].start_addr = {
                        cfg_hwif_out.chip7_base.value.value, 22'b0};
                    chip_rules_all[i].end_addr = {
                        cfg_hwif_out.chip7_bound.value.value, 22'b0};
                end
                default:;
            endcase
        end
    end

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
        .hwif_out      ( cfg_hwif_out     )
    );

    always_comb begin : proc_cfg_output
        frontend_cfg_o = '0;
        phy_cfg_o      = '0;

        frontend_cfg_o.address_mask_msb = cfg_hwif_out.address_mask_msb.value.value;
        frontend_cfg_o.address_space    = cfg_hwif_out.address_space.value.value;
        frontend_cfg_o.phys_in_use      = (NumPhys == 2) &&
            cfg_hwif_out.phys_in_use.value.value;
        frontend_cfg_o.which_phy        = (NumPhys == 2) &&
            cfg_hwif_out.which_phy.value.value;

        phy_cfg_o.chip.t_latency_access      = cfg_hwif_out.t_latency_access.value.value;
        phy_cfg_o.chip.en_latency_additional = cfg_hwif_out.en_latency_additional.value.value;
        phy_cfg_o.chip.t_burst_max           = cfg_hwif_out.t_burst_max.value.value;
        phy_cfg_o.chip.t_read_write_recovery = cfg_hwif_out.t_read_write_recovery.value.value;
        phy_cfg_o.chip.t_rx_clk_delay        = {
            cfg_hwif_out.t_rx_clk_delay.coarse.value,
            cfg_hwif_out.t_rx_clk_delay.fine.value
        };
        phy_cfg_o.chip.t_csh_cycles          = cfg_hwif_out.t_csh_cycles.value.value;
        phy_cfg_o.chip.csn_to_ck_cycles      = cfg_hwif_out.csn_to_ck_cycles.value.value;
        phy_cfg_o.t_tx_clk_delay             = {
            cfg_hwif_out.t_tx_clk_delay.coarse.value,
            cfg_hwif_out.t_tx_clk_delay.fine.value
        };
        phy_cfg_o.phys_in_use                = (NumPhys == 2) &&
            cfg_hwif_out.phys_in_use.value.value;
        phy_cfg_o.which_phy                  = (NumPhys == 2) &&
            cfg_hwif_out.which_phy.value.value;
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
