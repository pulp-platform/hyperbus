// Copyright 2026 Chips-IT, ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Andrea Di Ruzza

`include "register_interface/typedef.svh"

module hyperbus_wrap
#(
  parameter int unsigned NumChips        = -1,
  parameter int unsigned NumPhys         = 2,
  parameter bit          UsePhyClkDivider = 1,
  parameter int unsigned AxiAddrWidth    = -1,
  parameter int unsigned AxiDataWidth    = -1,
  parameter int unsigned AxiIdWidth      = -1,
  parameter int unsigned AxiUserWidth    = -1,
  parameter int unsigned AxiMaxTrans     = 0 ,
  parameter type         axi_req_t       = logic,
  parameter type         axi_rsp_t       = logic,
  parameter type         axi_w_chan_t    = logic,
  parameter type         axi_b_chan_t    = logic,
  parameter type         axi_ar_chan_t   = logic,
  parameter type         axi_r_chan_t    = logic,
  parameter type         axi_aw_chan_t   = logic,
  parameter int unsigned RegAddrWidth    = -1,
  parameter int unsigned RegDataWidth    = -1,
  parameter int unsigned  MinFreqMHz     = 100,
  parameter type         reg_req_t       = logic,
  parameter type         reg_rsp_t       = logic,
  // The below have sensible defaults, but should be set on integration!
  parameter int unsigned RxFifoLogDepth  = 2,
  parameter int unsigned TxFifoLogDepth  = 2,
  parameter logic [RegDataWidth-1:0] RstChipBase  = 'h0,      // Base address for all chips
  parameter logic [RegDataWidth-1:0] RstChipSpace = 'h1_0000, // 64 KiB: Current maximum H
                                                              // yperBus device size
  parameter int unsigned PhyStartupCycles = 300 * 200, /* us*MHz */
                                                       // Conservative maximum
                                                       // frequency estimate
  parameter hyperbus_pkg::hyper_cfg_t RstCfg = hyperbus_pkg::gen_RstCfg(NumPhys, MinFreqMHz),
  parameter int unsigned AxiLogDepth     = 3,
  parameter int unsigned AxiSlaveArWidth = 0,
  parameter int unsigned AxiSlaveAwWidth = 0,
  parameter int unsigned AxiSlaveBWidth  = 0,
  parameter int unsigned AxiSlaveRWidth  = 0,
  parameter int unsigned AxiSlaveWWidth  = 0,
  parameter int unsigned CdcSyncStages   = 0
)(
  input  logic clk_i     ,
  input  logic rst_ni        ,
  input  logic test_mode_i   ,
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

  // Physical interace that connects to hyperbus module
  // No pads
  output logic [NumPhys-1:0][NumChips-1:0] hyper_cs_no,
  output logic [NumPhys-1:0]               hyper_ck_o,
  output logic [NumPhys-1:0]               hyper_ck_no,
  output logic [NumPhys-1:0]               hyper_rwds_o,
  input  logic [NumPhys-1:0]               hyper_rwds_i,
  output logic [NumPhys-1:0]               hyper_rwds_oe_o,
  input  logic [NumPhys-1:0][7:0]          hyper_dq_i,
  output logic [NumPhys-1:0][7:0]          hyper_dq_o,
  output logic [NumPhys-1:0][7:0]          hyper_dq_oe_o,
  output logic [NumPhys-1:0]               hyper_reset_no,
  output logic [NumPhys-1:0][7:0]          hyper_pad_cfg_o
);

logic rst_n;
logic clk_phy;
logic ph_phy;

reg_req_t   reg_req;
reg_rsp_t   reg_rsp;

typedef struct packed {
  logic [31:0]             idx;
  logic [AxiAddrWidth-1:0] start_addr;
  logic [AxiAddrWidth-1:0] end_addr;
} addr_rule_t;

axi_req_t hyper_req;
axi_rsp_t hyper_rsp;

axi_cdc_dst      #(
  .LogDepth       ( AxiLogDepth   ),
  .SyncStages     ( CdcSyncStages ),
  .aw_chan_t      ( axi_aw_chan_t ),
  .w_chan_t       ( axi_w_chan_t  ),
  .b_chan_t       ( axi_b_chan_t  ),
  .ar_chan_t      ( axi_ar_chan_t ),
  .r_chan_t       ( axi_r_chan_t  ),
  .axi_req_t      ( axi_req_t     ),
  .axi_resp_t     ( axi_rsp_t     )
) i_hyper_axi_cdc_dst (
  // asynchronous slave port
  .async_data_slave_aw_data_i ( axi_slave_aw_data_i ),
  .async_data_slave_aw_wptr_i ( axi_slave_aw_wptr_i ),
  .async_data_slave_aw_rptr_o ( axi_slave_aw_rptr_o ),
  .async_data_slave_w_data_i  ( axi_slave_w_data_i  ),
  .async_data_slave_w_wptr_i  ( axi_slave_w_wptr_i  ),
  .async_data_slave_w_rptr_o  ( axi_slave_w_rptr_o  ),
  .async_data_slave_b_data_o  ( axi_slave_b_data_o  ),
  .async_data_slave_b_wptr_o  ( axi_slave_b_wptr_o  ),
  .async_data_slave_b_rptr_i  ( axi_slave_b_rptr_i  ),
  .async_data_slave_ar_data_i ( axi_slave_ar_data_i ),
  .async_data_slave_ar_wptr_i ( axi_slave_ar_wptr_i ),
  .async_data_slave_ar_rptr_o ( axi_slave_ar_rptr_o ),
  .async_data_slave_r_data_o  ( axi_slave_r_data_o  ),
  .async_data_slave_r_wptr_o  ( axi_slave_r_wptr_o  ),
  .async_data_slave_r_rptr_i  ( axi_slave_r_rptr_i  ),
  // synchronous master port
  .dst_clk_i                  ( clk_phy ),
  .dst_rst_ni                 ( rst_n ),
  .dst_req_o                  ( hyper_req ),
  .dst_resp_i                 ( hyper_rsp )
);

reg_cdc_dst #(
  .CDC_KIND ( "cdc_4phase" ),
  .req_t    ( reg_req_t ),
  .rsp_t    ( reg_rsp_t )
) i_hyper_reg_cdc_dst (
  .dst_clk_i   ( clk_phy ),
  .dst_rst_ni  ( rst_n ),
  .dst_req_o   ( reg_req ),
  .dst_rsp_i   ( reg_rsp ),

  .async_req_i (reg_async_mst_req_i),
  .async_ack_o (reg_async_mst_ack_o),
  .async_data_i(reg_async_mst_data_i),

  .async_req_o (reg_async_mst_req_o),
  .async_ack_i (reg_async_mst_ack_i),
  .async_data_o(reg_async_mst_data_o)
);

rstgen i_hyper_rstgen (
  .clk_i   ( clk_i ),
  .rst_ni,
  .test_mode_i,
  .rst_no  ( rst_n ),
  .init_no ( )
);

hyperbus_clk_gen i_hyper_clk_gen (
    .clk_i    ( clk_i ),
    .rst_ni   ( rst_n ),
    .clk_phy_o ( clk_phy ),
    .ph_phy_o  ( ph_phy )
);


hyperbus           #(
  .NumChips         ( NumChips         ),
  .NumPhys          ( NumPhys          ),
  .UsePhyClkDivider ( UsePhyClkDivider ),
  .AxiAddrWidth     ( AxiAddrWidth     ),
  .AxiDataWidth     ( AxiDataWidth     ),
  .AxiIdWidth       ( AxiIdWidth       ),
  .AxiUserWidth     ( AxiUserWidth     ),
  .axi_req_t        ( axi_req_t        ),
  .axi_rsp_t        ( axi_rsp_t        ),
  .RegAddrWidth     ( RegAddrWidth     ),
  .RegDataWidth     ( RegDataWidth     ),
  .reg_req_t        ( reg_req_t        ),
  .reg_rsp_t        ( reg_rsp_t        ),
  .axi_rule_t       ( addr_rule_t      ),

  .MinFreqMHz       ( MinFreqMHz ),
  .RxFifoLogDepth   ( RxFifoLogDepth   ),
  .TxFifoLogDepth   ( TxFifoLogDepth   ),
  .RstChipBase      ( RstChipBase      ),
  .RstChipSpace     ( RstChipSpace     ),
  .PhyStartupCycles ( PhyStartupCycles ),
  .RstCfg           ( RstCfg           ),
  .SyncStages       ( CdcSyncStages    )
) i_hyperbus        (
  .clk_phy_x2_i     ( clk_i              ),
  .clk_phy_i        ( clk_phy            ),
  .rst_ni           ( rst_n              ),
  .ph_phy_i         ( ph_phy              ),
  .test_mode_i      ( test_mode_i        ),
  .axi_req_i        ( hyper_req          ),
  .axi_rsp_o        ( hyper_rsp          ),
  .reg_req_i        ( reg_req            ),
  .reg_rsp_o        ( reg_rsp            ),
  // PHY signals go diectly to the hyperbus interface, same names
  .hyper_cs_no      ( hyper_cs_no       ),
  .hyper_ck_o       ( hyper_ck_o         ),
  .hyper_ck_no      ( hyper_ck_no        ),
  .hyper_rwds_o     ( hyper_rwds_o       ),
  .hyper_rwds_i     ( hyper_rwds_i       ),
  .hyper_rwds_oe_o  ( hyper_rwds_oe_o    ),
  .hyper_dq_i       ( hyper_dq_i         ),
  .hyper_dq_o       ( hyper_dq_o         ),
  .hyper_dq_oe_o    ( hyper_dq_oe_o      ),
  .hyper_reset_no   ( hyper_reset_no     ),
  .hyper_pad_cfg_o  ( hyper_pad_cfg_o    )
);


endmodule: hyperbus_wrap
