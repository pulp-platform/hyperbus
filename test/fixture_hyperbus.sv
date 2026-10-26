// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Thomas Benz <tbenz@iis.ee.ethz.ch>

`timescale 1 ns/1 ps

`include "axi/assign.svh"

module fixture_hyperbus #(
    parameter int unsigned NumConnectedChips    = 2,
    parameter int unsigned NumPhys              = 2,
    parameter int unsigned DutVariant           = 0,
    parameter int unsigned HostWriteBufferBytes = 64,
    parameter time        SysClkPeriod          = 4ns,
    parameter bit         AnnotateSdf           = 1'b1
);

    localparam time SYS_TCK  = SysClkPeriod;
    localparam time SYS_TA   = 2ns;
    localparam time SYS_TT   = SYS_TCK - 1ns;
    localparam time PHY_TCK  = 6ns;

    logic sys_clk = 0;
    logic phy_clk = 0;
    logic rst_n   = 1;
    logic eos     = 0;

    // -------------------- AXI drivers --------------------

    localparam AxiAw = 32;
    localparam AxiDw = 64;
    localparam AxiIw = 6;
    localparam RegAw = 32;
    localparam RegDw = 32;

    AXI_BUS_DV #(
        .AXI_ADDR_WIDTH(AxiAw ),
        .AXI_DATA_WIDTH(AxiDw ),
        .AXI_ID_WIDTH  (AxiIw ),
        .AXI_USER_WIDTH(1     )
    ) axi_dv(sys_clk);

    AXI_BUS #(
        .AXI_ADDR_WIDTH(AxiAw ),
        .AXI_DATA_WIDTH(AxiDw ),
        .AXI_ID_WIDTH  (AxiIw ),
        .AXI_USER_WIDTH(1     )
    ) axi_master();

    `AXI_ASSIGN(axi_master, axi_dv)

    typedef axi_test::axi_driver #(.AW(AxiAw ), .DW(AxiDw ), .IW(AxiIw ), .UW(1), .TA(SYS_TA), .TT(SYS_TT)) axi_drv_t;
    axi_drv_t axi_master_drv = new(axi_dv);

    axi_test::axi_ax_beat #(.AW(AxiAw ), .IW(AxiIw ), .UW(1)) ar_beat = new();
    axi_test::axi_r_beat  #(.DW(AxiDw ), .IW(AxiIw ), .UW(1)) r_beat  = new();
    axi_test::axi_ax_beat #(.AW(AxiAw ), .IW(AxiIw ), .UW(1)) aw_beat = new();
    axi_test::axi_w_beat  #(.DW(AxiDw ), .UW(1))              w_beat  = new();
    axi_test::axi_b_beat  #(.IW(AxiIw ), .UW(1))              b_beat  = new();

    // -------------------------- Regbus driver --------------------------

    REG_BUS #(
        .ADDR_WIDTH( RegAw ),
        .DATA_WIDTH( RegDw )
    ) i_rbus (
        .clk_i (sys_clk)
    );

    reg_test::reg_driver #(
        .AW ( RegAw  ),
        .DW ( RegDw  ),
        .TA ( SYS_TA ),
        .TT ( SYS_TT )
    ) i_rmaster = new( i_rbus );

    // Share the passive topology, not the main testbench's driver timing.
    hyperbus_tb_pkg::pad_delay_cfg_t pad_delay_cfg = '0;
    logic [31:0] segment_start_count;
    logic [NumPhys-1:0][NumConnectedChips-1:0][31:0] cs_start_count;

    dut_if #(
        .TbTestTime          ( SYS_TT ),
        .AxiDataWidth        ( AxiDw ),
        .AxiAddrWidth        ( AxiAw ),
        .AxiIdWidth          ( AxiIw ),
        .AxiUserWidth        ( 1 ),
        .HostWriteBufferBytes( HostWriteBufferBytes ),
        .RegAw               ( RegAw ),
        .RegDw               ( RegDw ),
        .NumConnectedChips   ( NumConnectedChips ),
        .NumPhys             ( NumPhys ),
        .AnnotateSdf         ( AnnotateSdf ),
        .DutVariant          ( DutVariant ),
        .PhyCyclTime         ( PHY_TCK ),
`ifdef TARGET_POST_SYNTH_SIM
        .SanitizeRegInputs   ( 1'b1 ),
`endif
        .axi_rule_t          ( axi_pkg::xbar_rule_32_t )
    ) i_dut_if (
        .clk_i                 ( sys_clk ),
        .clk_phy_i             ( phy_clk ),
        .rst_ni                ( rst_n ),
        .end_sim_i             ( eos ),
        .segment_start_count_o ( segment_start_count ),
        .cs_start_count        ( cs_start_count ),
        .pad_delay_cfg_i       ( pad_delay_cfg ),
        .axi_slv_if            ( axi_master ),
        .reg_slv_if            ( i_rbus )
    );

    initial begin
        rst_n = 0;
        axi_master_drv.reset_master();
        i_rmaster.reset_master();
        #(0.25*SYS_TCK);
        #(10*SYS_TCK);
        rst_n = 1;
    end

    initial begin
        while (!eos) begin
            sys_clk = 1;
            #(SYS_TCK/2);
            sys_clk = 0;
            #(SYS_TCK/2);
        end
        // Extra cycle after sim
        sys_clk = 1;
        #(SYS_TCK/2);
        sys_clk = 0;
        #(SYS_TCK/2);
    end

    // This fixture starts the PHY clock high at time zero, unlike the main TB.
    initial begin
        while (!eos) begin
            phy_clk = 1;
            #(PHY_TCK/2);
            phy_clk = 0;
            #(PHY_TCK/2);
        end
        // Extra cycle after sim
        phy_clk = 1;
        #(PHY_TCK/2);
        phy_clk = 0;
        #(PHY_TCK/2);
    end

    task reset_end;
        @(posedge rst_n);
        @(posedge sys_clk);
    endtask

endmodule : fixture_hyperbus
