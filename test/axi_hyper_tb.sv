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

  ////////////////////////////////
  // Stimuli generator typedefs //
  ////////////////////////////////
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

  typedef reg_test::reg_driver #(
    .AW ( RegBusAW   ),
    .DW ( RegBusDW   ),
    .TT ( TbTestTime )
  ) reg_bus_master_t;   

  logic s_reg_error;
   
  AXI_BUS_DV #(
    .AXI_ADDR_WIDTH ( TbAxiAddrWidthFull ),
    .AXI_DATA_WIDTH ( TbAxiDataWidthFull ),
    .AXI_ID_WIDTH   ( TbAxiIdWidthFull   ),
    .AXI_USER_WIDTH ( TbAxiUserWidthFull )
  ) axi_mst_intf_dv (
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

  `AXI_ASSIGN_MONITOR(score_mst_intf_dv, axi_mst_intf_dv)

  REG_BUS #(
    .ADDR_WIDTH(RegBusAW),
    .DATA_WIDTH(RegBusDW)
  )  reg_bus_mst (.clk_i (clk));
   
  ////////////////////
  // Address Ranges //
  ////////////////////
  localparam axi_addr_t MemRegionStart  = axi_addr_t'(32'h8000_0000);
  localparam axi_addr_t MemRegionLength = axi_addr_t'(TbDramDataWidth * TbDramLenWidth);

  logic s_error;
  logic [31:0] reg_read;
     
  initial begin : proc_sim_crtl

    automatic axi_scoreboard_mst_t   mst_scoreboard  = new( score_mst_intf_dv );
    automatic axi_rand_master_t      axi_master      = new( axi_mst_intf_dv   );
    automatic reg_bus_master_t       reg_master      = new( reg_bus_mst       );

    // Reset the AXI drivers and scoreboards
    end_of_sim = 1'b0;
    mst_scoreboard.reset();
    axi_master.reset();
    reg_master.reset_master();

    // Set some mem regions for rand axi master
    axi_master.add_memory_region(32'h8000_0000, 32'h8000_0000 + ( TbDramDataWidth * TbDramLenWidth ), axi_pkg::NORMAL_NONCACHEABLE_BUFFERABLE);
     
    mst_scoreboard.enable_all_checks();

    @(posedge rst_n);
    mst_scoreboard.monitor();

    #600350ns;

    $display("===========================");
    $display("= Random AXI transactions =");
    $display("===========================");
     
    axi_master.run(TbNumReads, TbNumWrites);

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

       axi_master.reset();

       $display("===========================");
       $display("= Random AXI transactions =");
       $display("===========================");

       axi_master.run(TbNumReads, TbNumWrites);

       $display("===========================");
       $display("=      Test finished      =");
       $display("===========================");

       mst_scoreboard.clear_range(32'h8000_0000, 32'h8000_0000 + ( TbDramDataWidth * TbDramLenWidth ));

       $display("===========================");
       $display("= Use only phy 1          =");
       $display("===========================");

       reg_master.send_write(32'h24,1'b1,'1,s_reg_error);
       if (s_reg_error != 1'b0) $error("unexpected error");

       axi_master.reset();

       $display("===========================");
       $display("= Random AXI transactions =");
       $display("===========================");

       axi_master.run(TbNumReads, TbNumWrites);

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
    .AxiIdWidth      ( TbAxiIdWidthFull   ),
    .AxiUserWidth    ( TbAxiUserWidthFull ),

    .RegAw           ( RegBusAW           ),
    .RegDw           ( RegBusDW           ),

    .NumChips        ( NumChips           ),
    .NumPhys         ( NumPhys            ),
    .IsClockODelayed ( IsClockODelayed    ),
    .axi_rule_t      ( rule_t             )
  ) i_dut_if (
    // clk and rst signal
    .clk_i      ( clk             ),
    .rst_ni     ( rst_n           ),
    .end_sim_i  ( end_of_sim      ),
    .axi_slv_if ( axi_mst_intf_dv ),
    .reg_slv_if ( reg_bus_mst     )
  );

endmodule
