// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Luca Valente <luca.valente@unibo.it>

module axi_hyper_tb 
  import axi_pkg::*;
#(
  parameter int unsigned NumChips = 2,
  parameter int unsigned NumPhys = 2, 
  parameter int unsigned IsClockODelayed = 0,
  parameter int unsigned NB_CH = 1,
  /// ID width of the Full AXI slave port, master port has ID `AxiIdWidthFull + 32'd1`
  parameter int unsigned TbAxiIdWidthFull = 32'd6,
  /// Address width of the full AXI bus
  parameter int unsigned TbAxiAddrWidthFull = 32'd32,
  /// Data width of the full AXI bus
  parameter int unsigned TbAxiDataWidthFull = 32'd64,
  /// Number of random write transactions in a testblock.
  parameter int unsigned TbNumWrites = 32'd1000,
  /// Number of random read transactions in a testblock.
  parameter int unsigned TbNumReads = 32'd1000,
  /// Cycle time for the TB clock generator
  parameter time         TbCyclTime =  5ns,
  /// Application time to the DUT
  parameter time         TbApplTime =  1ns,
  /// Test time of the DUT
  parameter time         TbTestTime =  4ns
);
  import hyperbus_tb_pkg::*;
  /////////////////////////////
  // Axi channel definitions //
  /////////////////////////////
  `include "axi/typedef.svh"
  `include "axi/assign.svh"


  /////////////////////////
  // Clock and Reset gen //
  /////////////////////////
  logic clk, rst_n;
  clk_rst_gen #(
    .ClkPeriod     ( TbCyclTime ),
    .RstClkCycles  ( 32'd5      )
  ) i_clk_rst_gen (
    .clk_o  ( clk   ),
    .rst_no ( rst_n )
  );

  localparam int WaitOneRefCycleBeforeAXI = 1; 
  localparam int unsigned TbAxiUserWidthFull = 32'd1;   
  typedef logic [TbAxiAddrWidthFull-1:0]   axi_addr_t;
  typedef axi_pkg::xbar_rule_32_t rule_t;

  localparam int unsigned RegBusDW = 32;
  localparam int unsigned RegBusAW = 8;            

  localparam int unsigned TbDramDataWidth = 8;
  localparam int unsigned TbDramLenWidth  = 32'h80000;

  logic                  end_of_sim;


  ///////////////////////
  // AXI Random Master //
  ///////////////////////
  // AXI master for random data transactions
  typedef axi_test::axi_rand_master #(
    .AW                   ( TbAxiAddrWidthFull ),
    .DW                   ( TbAxiDataWidthFull ),
    .IW                   ( TbAxiIdWidthFull   ),
    .UW                   ( TbAxiUserWidthFull ),
    .TA                   ( TbApplTime         ),
    .TT                   ( TbTestTime         ),
    .TRAFFIC_SHAPING      ( 0                  ),
    .SIZE_ALIGN           ( 1                  ),
    .MAX_READ_TXNS        ( 8                  ),
    .MAX_WRITE_TXNS       ( 8                  ),
    .AX_MIN_WAIT_CYCLES   ( 0                  ),
    .AX_MAX_WAIT_CYCLES   ( 0                  ),
    .W_MIN_WAIT_CYCLES    ( 0                  ),
    .W_MAX_WAIT_CYCLES    ( 0                  ),
    .RESP_MIN_WAIT_CYCLES ( 0                  ),
    .RESP_MAX_WAIT_CYCLES ( 0                  ),
    .AXI_BURST_FIXED      ( 1'b0               ),
    .AXI_BURST_INCR       ( 1'b1               ),
    .AXI_BURST_WRAP       ( 1'b0               )
  ) axi_rand_master_t;

  typedef axi_test::axi_scoreboard #(
    .IW( TbAxiIdWidthFull   ),
    .AW( TbAxiAddrWidthFull ),
    .DW( TbAxiDataWidthFull ),
    .UW( TbAxiUserWidthFull ),
    .TT( TbTestTime         )
  ) axi_scoreboard_mst_t;

  AXI_BUS_DV #(
    .AXI_ADDR_WIDTH ( TbAxiAddrWidthFull ),
    .AXI_DATA_WIDTH ( TbAxiDataWidthFull ),
    .AXI_ID_WIDTH   ( TbAxiIdWidthFull   ),
    .AXI_USER_WIDTH ( TbAxiUserWidthFull )
  ) axi_rand_intf_dv (
    .clk_i ( clk )
  );

  AXI_BUS_DV #(
    .AXI_ADDR_WIDTH ( TbAxiAddrWidthFull ),
    .AXI_DATA_WIDTH ( TbAxiDataWidthFull ),
    .AXI_ID_WIDTH   ( TbAxiIdWidthFull   ),
    .AXI_USER_WIDTH ( TbAxiUserWidthFull )
  ) score_mst_intf_dv (
    .clk_i ( clk )
  );

  AXI_BUS #(
    .AXI_ADDR_WIDTH ( TbAxiAddrWidthFull ),
    .AXI_DATA_WIDTH ( TbAxiDataWidthFull ),
    .AXI_ID_WIDTH   ( TbAxiIdWidthFull   ),
    .AXI_USER_WIDTH ( TbAxiUserWidthFull )
  ) axi_rand_intf ();

  `AXI_ASSIGN_MONITOR(score_mst_intf_dv, axi_rand_intf_dv)
  `AXI_ASSIGN(axi_rand_intf, axi_rand_intf_dv)



  ////////////////////////
  // AXI Control Master //
  ////////////////////////

  AXI_BUS_DV #(
    .AXI_ADDR_WIDTH ( TbAxiAddrWidthFull ),
    .AXI_DATA_WIDTH ( TbAxiDataWidthFull ),
    .AXI_ID_WIDTH   ( TbAxiIdWidthFull   ),
    .AXI_USER_WIDTH ( TbAxiUserWidthFull )
  ) axi_ctrl_intf_dv (
    .clk_i ( clk )
  );

  AXI_BUS #(
    .AXI_ADDR_WIDTH ( TbAxiAddrWidthFull ),
    .AXI_DATA_WIDTH ( TbAxiDataWidthFull ),
    .AXI_ID_WIDTH   ( TbAxiIdWidthFull   ),
    .AXI_USER_WIDTH ( TbAxiUserWidthFull )
  ) axi_ctrl_intf ();

  typedef axi_test::axi_driver #(
    .AW ( TbAxiAddrWidthFull ),
    .DW ( TbAxiDataWidthFull ),
    .IW ( TbAxiIdWidthFull   ),
    .UW ( TbAxiUserWidthFull ),
    .TA ( TbApplTime         ),
    .TT ( TbTestTime         )
  ) axi_ctrl_master_t;
  axi_ctrl_master_t axi_ctrl_mst = new( axi_ctrl_intf_dv );

  `AXI_ASSIGN(axi_ctrl_intf, axi_ctrl_intf_dv)

  logic s_axi_error;


  //////////////////////////////
  // AXI Control Master Tasks //
  //////////////////////////////
  task automatic axi_write_32(
    input axi_addr_t  addr,
    input bit [31:0] data
  );
    axi_ctrl_master_t::ax_beat_t ax = new();
    axi_ctrl_master_t::w_beat_t w = new();
    axi_ctrl_master_t::b_beat_t b;
    
    @(posedge clk);
    ax.ax_addr  = addr;
    ax.ax_id    = 0;
    ax.ax_len   = 0;
    ax.ax_size  = 2;
    ax.ax_burst = axi_pkg::BURST_INCR;
    axi_ctrl_mst.send_aw(ax);
    w.w_strb = 'h0F;
    w.w_data = data;
    w.w_last = 1;
    axi_ctrl_mst.send_w(w);
    axi_ctrl_mst.recv_b(b);
    if (b.b_resp != axi_pkg::RESP_OKAY)
      $error("[AXI-CTRL] - Write error response: %d!", b.b_resp);
  endtask


  ///////////////////
  // Regbus Master //
  ///////////////////
  typedef reg_test::reg_driver #(
    .AW ( RegBusAW   ),
    .DW ( RegBusDW   ),
    .TT ( TbTestTime )
  ) reg_bus_master_t;   

  logic s_reg_error;

  REG_BUS #(
    .ADDR_WIDTH(RegBusAW),
    .DATA_WIDTH(RegBusDW)
  )  reg_bus_mst (.clk_i (clk));



  ////////////////////
  // AXI Master MUX //
  ////////////////////

  AXI_BUS #(
    .AXI_ADDR_WIDTH ( TbAxiAddrWidthFull  ),
    .AXI_DATA_WIDTH ( TbAxiDataWidthFull  ),
    .AXI_ID_WIDTH   ( TbAxiIdWidthFull +1 ),
    .AXI_USER_WIDTH ( TbAxiUserWidthFull  )
  ) axi_dut_intf ();

  axi_mux_intf #(
    .SLV_AXI_ID_WIDTH ( TbAxiIdWidthFull    ),
    .MST_AXI_ID_WIDTH ( TbAxiIdWidthFull +1 ),
    .AXI_ADDR_WIDTH   ( TbAxiAddrWidthFull  ),
    .AXI_DATA_WIDTH   ( TbAxiDataWidthFull  ),
    .AXI_USER_WIDTH   ( TbAxiUserWidthFull  ),
    .NO_SLV_PORTS     ( 2 )
  ) i_axi_mst_mux (
      .clk_i  ( clk   ),
      .rst_ni ( rst_n ),
      .test_i ( 1'b0  ),
      .slv    ( { axi_ctrl_intf, axi_rand_intf } ),
      .mst    ( axi_dut_intf )
  );

   
  ////////////////////
  // Address Ranges //
  ////////////////////
  localparam axi_addr_t MemRegionStart  = axi_addr_t'(32'h8000_0000);
  localparam axi_addr_t MemRegionLength = axi_addr_t'(TbDramDataWidth * TbDramLenWidth);

  logic s_error;
  logic [31:0] reg_read;
     
  initial begin : proc_sim_crtl

    automatic axi_scoreboard_mst_t mst_scoreboard = new( score_mst_intf_dv );
    automatic axi_rand_master_t    axi_rand_mst   = new( axi_rand_intf_dv  );
    automatic reg_bus_master_t     reg_master     = new( reg_bus_mst       );
    
    automatic s27ks_cfg0_reg_t s27ks_cfg0 = hyperbus_tb_pkg::s27ks_cfg0_default;

    // Reset the AXI drivers and scoreboards
    end_of_sim = 1'b0;
    mst_scoreboard.reset();
    axi_rand_mst.reset();
    axi_ctrl_mst.reset_master();
    reg_master.reset_master();

    // Set some mem regions for rand axi master
    axi_rand_mst.add_memory_region(32'h8000_0000, 32'h8000_0000 + ( TbDramDataWidth * TbDramLenWidth ), axi_pkg::NORMAL_NONCACHEABLE_BUFFERABLE);
     
    mst_scoreboard.enable_all_checks();

    @(posedge rst_n);
    mst_scoreboard.monitor();

    #600350ns;

    // switch memory address space to register space
    reg_master.send_write(32'h7<<2, 1'b1, '1, s_reg_error);
    if (s_reg_error != 1'b0) $error("unexpected error");

    // enable variable latency so we can test RWDS sampling
    s27ks_cfg0.fixed_latency_enable = 1'b0;
    $display("t3est");
    axi_write_32(32'h8000_0000 + S27KS_CFG0_REG_OFFSET, (s27ks_cfg0 | s27ks_cfg0 << 16));

    // switch back to memory address space
    reg_master.send_write(32'h7<<2, 1'b0, '1, s_reg_error);
    if (s_axi_error != 1'b0) $error("unexpected error");

    $display("===========================");
    $display("= Random AXI transactions =");
    $display("===========================");
     
    axi_rand_mst.run(TbNumReads, TbNumWrites);

    $display("===========================");
    $display("=      Test finished      =");
    $display("===========================");

    #50ns;

    if(NumPhys==2) begin

       mst_scoreboard.clear_range(32'h8000_0000, 32'h8000_0000 + ( TbDramDataWidth * TbDramLenWidth ));

       $display("===========================");
       $display("= Use only phy 0          =");
       $display("===========================");

       reg_master.send_write(32'h20,1'b0,'1,s_reg_error);
       reg_master.send_write(32'h24,1'b0,'1,s_reg_error);
       if (s_reg_error != 1'b0) $error("unexpected error");

       axi_rand_mst.reset();

       $display("===========================");
       $display("= Random AXI transactions =");
       $display("===========================");

       axi_rand_mst.run(TbNumReads, TbNumWrites);

       $display("===========================");
       $display("=      Test finished      =");
       $display("===========================");

       mst_scoreboard.clear_range(32'h8000_0000, 32'h8000_0000 + ( TbDramDataWidth * TbDramLenWidth ));

       $display("===========================");
       $display("= Use only phy 1          =");
       $display("===========================");

       reg_master.send_write(32'h24,1'b1,'1,s_reg_error);
       if (s_reg_error != 1'b0) $error("unexpected error");

       axi_rand_mst.reset();

       $display("===========================");
       $display("= Random AXI transactions =");
       $display("===========================");

       axi_rand_mst.run(TbNumReads, TbNumWrites);

       $display("===========================");
       $display("=      Test finished      =");
       $display("===========================");

    end // if (NumPhys==2)

    end_of_sim = 1'b1;
    $finish();
  end

  ///////////////////////
  // Design under test //
  ///////////////////////
  dut_if  #(
    .TbTestTime      ( TbTestTime         ),
    .AxiDataWidth    ( TbAxiDataWidthFull ),
    .AxiAddrWidth    ( TbAxiAddrWidthFull ),
    .AxiIdWidth      ( TbAxiIdWidthFull+1 ),
    .AxiUserWidth    ( TbAxiUserWidthFull ),

    .RegAw           ( RegBusAW           ),
    .RegDw           ( RegBusDW           ),

    .NumChips        ( NumChips           ),
    .NumPhys         ( NumPhys            ),
    .IsClockODelayed ( IsClockODelayed    ),
    .axi_rule_t      ( rule_t             )
  ) i_dut_if (
    // clk and rst signal
    .clk_i      ( clk          ),
    .rst_ni     ( rst_n        ),
    .end_sim_i  ( end_of_sim   ),
    .axi_slv_if ( axi_dut_intf ),
    .reg_slv_if ( reg_bus_mst  )
  );

endmodule
