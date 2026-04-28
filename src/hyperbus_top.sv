// Copyright 2026 Chips-IT, ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Andrea Di Ruzza <andrea.diruzza@chips.it>

`include "axi/typedef.svh"
`include "register_interface/typedef.svh"

package hyperbus_top_pkg;

  localparam NumChips = 2;
  localparam NumPhys = 2;
  localparam UsePhyClkDivider = 1;
  localparam AxiAddrWidth = 48; // default for Cheshire SoCs
  localparam AxiDataWidth = 64; // default for Cheshire SoCs
  localparam AxiIdWidth = 6; // currently serialized internally
  localparam AxiUserWidth = 10; // TODO: it should be 1, it is not supported in Hyperbus
  localparam AxiMaxTrans = 64;
  localparam RegAddrWidth = 32; // TODO it is 48 in Flamingo (default for Cheshire SoCs)
  localparam RegDataWidth = 32;
  localparam MinFreqMHz = 50;
  localparam RxFifoLogDepth = 3; // 2^x must be larger than 2*SyncStages
  localparam TxFifoLogDepth = 3; // 2^x must be larger than 2*SyncStages
  localparam RstChipBase = 32'h8000_0000;
  localparam RstChipSpace = NumPhys * NumChips * 'h800_0000; //TODO: check, in Flamingo it is 8*1024; // S27KS0641 is 64 Mib (Mebibit)
  localparam PhyStartupCycles = 300 * 200; /* us*MHz */ // Conservative maximum frequency estimate;
  localparam AxiLogDepth = 3;
  localparam AxiSlaveArWidth = 744; //'h000002e8,
  localparam AxiSlaveAwWidth = 792; //'h00000318,
  localparam AxiSlaveBWidth = 144; //'h00000090,
  localparam AxiSlaveRWidth = 664; //'h00000298,
  localparam AxiSlaveWWidth = 664; //'h00000298,
  localparam CdcSyncStages = 3; //'h00000003,

  localparam type reg_addr_t = logic [RegAddrWidth-1:0];
  localparam type reg_data_t = logic [RegDataWidth-1:0];
  localparam type reg_strb_t = logic [3:0];
  `REG_BUS_TYPEDEF_ALL(reg, reg_addr_t, reg_data_t, reg_strb_t)


  localparam type axi_addr_t = logic [AxiAddrWidth   -1:0];
  localparam type axi_data_t = logic [AxiDataWidth   -1:0];
  localparam type axi_strb_t = logic [AxiDataWidth/8 -1:0];
  localparam type axi_user_t = logic [AxiUserWidth   -1:0];
  localparam type axi_id_t   = logic [AxiIdWidth     -1:0];
  `AXI_TYPEDEF_ALL_CT(axi, axi_req_t, axi_rsp_t,
    axi_addr_t, axi_id_t, axi_data_t, axi_strb_t, axi_user_t)

endpackage


module hyperbus_top 
  import hyperbus_top_pkg::*;
(
  input  logic clk_i,
  input  logic rst_ni,
  input  logic test_mode_i,
  // AXI bus
  input  logic [AxiSlaveArWidth-1:0] axi_slave_ar_data_i,
  input  logic [      AxiLogDepth:0] axi_slave_ar_wptr_i,
  output logic [      AxiLogDepth:0] axi_slave_ar_rptr_o,
  input  logic [AxiSlaveAwWidth-1:0] axi_slave_aw_data_i,
  input  logic [      AxiLogDepth:0] axi_slave_aw_wptr_i,
  output logic [      AxiLogDepth:0] axi_slave_aw_rptr_o,
  output logic [ AxiSlaveBWidth-1:0] axi_slave_b_data_o,
  output logic [      AxiLogDepth:0] axi_slave_b_wptr_o,
  input  logic [      AxiLogDepth:0] axi_slave_b_rptr_i,
  output logic [ AxiSlaveRWidth-1:0] axi_slave_r_data_o,
  output logic [      AxiLogDepth:0] axi_slave_r_wptr_o,
  input  logic [      AxiLogDepth:0] axi_slave_r_rptr_i,
  input  logic [ AxiSlaveWWidth-1:0] axi_slave_w_data_i,
  input  logic [      AxiLogDepth:0] axi_slave_w_wptr_i,
  output logic [      AxiLogDepth:0] axi_slave_w_rptr_o,
  // Reg bus
  input logic reg_async_mst_req_i,
  output logic reg_async_mst_ack_o,
  input reg_req_t reg_async_mst_data_i,
  output logic reg_async_mst_req_o,
  input logic reg_async_mst_ack_i,
  output reg_rsp_t reg_async_mst_data_o,  

  // Physical interace: HyperBus PADs
  inout wire logic pad_config_tc_pad_internal_signals_0,
  inout wire logic pad_config_tc_pad_internal_signals_1,
  inout wire logic pad_config_tc_pad_internal_signals_2,
  inout wire logic pad_config_tc_pad_internal_signals_3,
  inout wire logic pad_hyper_phy0_cs_n_0_pad,
  inout wire logic pad_hyper_phy0_cs_n_1_pad,
  inout wire logic pad_hyper_phy0_ck_pad,
  inout wire logic pad_hyper_phy0_ck_n_pad,
  inout wire logic pad_hyper_phy0_rwds_pad,
  inout wire logic pad_hyper_phy0_dq_b0_pad,
  inout wire logic pad_hyper_phy0_dq_b1_pad,
  inout wire logic pad_hyper_phy0_dq_b2_pad,
  inout wire logic pad_hyper_phy0_dq_b3_pad,
  inout wire logic pad_hyper_phy0_dq_b4_pad,
  inout wire logic pad_hyper_phy0_dq_b5_pad,
  inout wire logic pad_hyper_phy0_dq_b6_pad,
  inout wire logic pad_hyper_phy0_dq_b7_pad,
  inout wire logic pad_hyper_phy0_reset_n_pad,
  inout wire logic pad_hyper_phy1_cs_n_0_pad,
  inout wire logic pad_hyper_phy1_cs_n_1_pad,
  inout wire logic pad_hyper_phy1_ck_pad,
  inout wire logic pad_hyper_phy1_ck_n_pad,
  inout wire logic pad_hyper_phy1_rwds_pad,
  inout wire logic pad_hyper_phy1_dq_b0_pad,
  inout wire logic pad_hyper_phy1_dq_b1_pad,
  inout wire logic pad_hyper_phy1_dq_b2_pad,
  inout wire logic pad_hyper_phy1_dq_b3_pad,
  inout wire logic pad_hyper_phy1_dq_b4_pad,
  inout wire logic pad_hyper_phy1_dq_b5_pad,
  inout wire logic pad_hyper_phy1_dq_b6_pad,
  inout wire logic pad_hyper_phy1_dq_b7_pad,
  inout wire logic pad_hyper_phy1_reset_n_pad   
);

  // Hyperbus
  hyperbus_wrap #(
    .NumChips         (NumChips),
    .NumPhys          (NumPhys),
    .UsePhyClkDivider (UsePhyClkDivider),
    .AxiAddrWidth     (AxiAddrWidth),
    .AxiDataWidth     (AxiDataWidth),
    .AxiIdWidth       (AxiIdWidth),
    .AxiUserWidth     (AxiUserWidth),
    .AxiMaxTrans      (AxiMaxTrans),
    .axi_req_t        (axi_req_t),
    .axi_rsp_t        (axi_rsp_t),
    .axi_w_chan_t     (axi_w_chan_t),
    .axi_b_chan_t     (axi_b_chan_t),
    .axi_ar_chan_t    (axi_ar_chan_t),
    .axi_r_chan_t     (axi_r_chan_t),
    .axi_aw_chan_t    (axi_aw_chan_t),
    .RegAddrWidth     (RegAddrWidth),
    .RegDataWidth     (RegDataWidth),
    .MinFreqMHz       (MinFreqMHz),
    .reg_req_t        (reg_req_t),
    .reg_rsp_t        (reg_rsp_t),
    .RxFifoLogDepth   (RxFifoLogDepth),
    .TxFifoLogDepth   (TxFifoLogDepth),
    .RstChipBase      (RstChipBase),
    .RstChipSpace     (RstChipSpace),
    .PhyStartupCycles (PhyStartupCycles),
    .AxiLogDepth      (AxiLogDepth),
    .AxiSlaveArWidth  (AxiSlaveArWidth),
    .AxiSlaveAwWidth  (AxiSlaveAwWidth),
    .AxiSlaveBWidth   (AxiSlaveBWidth),
    .AxiSlaveRWidth   (AxiSlaveRWidth),
    .AxiSlaveWWidth   (AxiSlaveWWidth),
    .CdcSyncStages    (CdcSyncStages)
  ) i_hyperbus_wrap (.*);
endmodule
