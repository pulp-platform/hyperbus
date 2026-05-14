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
  /// Cycle time for the optional asynchronous PHY clock
  parameter time         TbPhyCyclTime = 6ns,
  /// Application time to the DUT
  parameter time         TbApplTime =  1ns,
  /// Test time of the DUT
  parameter time         TbTestTime =  4ns,
  /// DUT variant: 0 is isochronous, 1 is synchronous, 2 is asynchronous
  parameter int unsigned TbDutVariant = 0,
  /// RX delay-line tap value used by variants with explicit delay lines.
  parameter int unsigned TbRxDelayLineTaps = 16,
  /// TX delay-line tap value used by variants with explicit delay lines.
  parameter int unsigned TbTxDelayLineTaps = 19,
  /// Number of AXI beats in the directed slow read/write stress transactions.
  parameter int unsigned TbSlowNumBeats = 64,
  /// Idle cycles inserted between each accepted AXI beat in the slow stress transactions.
  parameter int unsigned TbSlowGapCycles = 64,
  /// Temporary t_burst_max used to force HyperBus segment restarts in the slow stress phase.
  parameter int unsigned TbSlowBurstMax = 16,
  /// Annotate the HyperRAM timing SDF. Disable for fast RTL regressions.
  parameter bit          TbAnnotateSdf = 1'b1
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
  logic [31:0]           segment_start_count;


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
      .slv    ( '{axi_ctrl_intf, axi_rand_intf} ),
      .mst    ( axi_dut_intf )
  );


  ////////////////////
  // Address Ranges //
  ////////////////////
  localparam axi_addr_t MemRegionStart  = axi_addr_t'(32'h8000_0000);
  localparam axi_addr_t MemRegionLength = axi_addr_t'(TbDramDataWidth * TbDramLenWidth);

  logic s_error;
  logic [31:0] reg_read;

  function automatic logic [TbAxiDataWidthFull/8-1:0] subword_strb(
    input axi_addr_t addr,
    input int unsigned size
  );
    automatic int unsigned num_bytes = 1 << size;
    automatic logic [TbAxiDataWidthFull/8-1:0] strb = '0;
    for (int unsigned i = 0; i < num_bytes; i++) begin
      strb[addr[$clog2(TbAxiDataWidthFull/8)-1:0] + i] = 1'b1;
    end
    return strb;
  endfunction

  function automatic logic [TbAxiDataWidthFull-1:0] subword_data(
    input logic [TbAxiDataWidthFull-1:0] data,
    input axi_addr_t addr
  );
    return data << (8 * addr[$clog2(TbAxiDataWidthFull/8)-1:0]);
  endfunction

  function automatic logic [TbAxiDataWidthFull-1:0] slow_stress_data(
    input axi_addr_t addr,
    input int unsigned beat
  );
    automatic logic [TbAxiDataWidthFull-1:0] data = '0;
    for (int unsigned byte_idx = 0; byte_idx < TbAxiDataWidthFull/8; byte_idx++) begin
      data[8*byte_idx +: 8] = 8'(addr[7:0] + beat + (byte_idx * 17));
    end
    return data;
  endfunction

  task automatic axi_write_subword(
    input axi_ctrl_master_t axi_drv,
    input axi_addr_t addr,
    input logic [TbAxiDataWidthFull-1:0] data,
    input int unsigned size
  );
    axi_ctrl_master_t::ax_beat_t ax = new();
    axi_ctrl_master_t::w_beat_t w = new();
    axi_ctrl_master_t::b_beat_t b;

    ax.ax_addr  = addr;
    ax.ax_id    = '0;
    ax.ax_len   = '0;
    ax.ax_size  = size;
    ax.ax_burst = axi_pkg::BURST_INCR;
    axi_drv.send_aw(ax);

    w.w_data = subword_data(data, addr);
    w.w_strb = subword_strb(addr, size);
    w.w_last = 1'b1;
    axi_drv.send_w(w);
    axi_drv.recv_b(b);
    if (b.b_resp != axi_pkg::RESP_OKAY) begin
      $error("[AXI] Write to 0x%08x returned response %0d", addr, b.b_resp);
    end
  endtask

  task automatic axi_check_subword(
    input axi_ctrl_master_t axi_drv,
    input axi_addr_t addr,
    input logic [TbAxiDataWidthFull-1:0] expected,
    input int unsigned size
  );
    axi_ctrl_master_t::ax_beat_t ax = new();
    axi_ctrl_master_t::r_beat_t r;
    logic [TbAxiDataWidthFull-1:0] mask;
    logic [TbAxiDataWidthFull-1:0] actual;
    int unsigned num_bytes;

    ax.ax_addr  = addr;
    ax.ax_id    = '0;
    ax.ax_len   = '0;
    ax.ax_size  = size;
    ax.ax_burst = axi_pkg::BURST_INCR;
    axi_drv.send_ar(ax);
    axi_drv.recv_r(r);

    num_bytes = 1 << size;
    mask = '0;
    for (int unsigned i = 0; i < num_bytes; i++) begin
      mask[i*8 +: 8] = 8'hff;
    end
    actual = r.r_data >> (8 * addr[$clog2(TbAxiDataWidthFull/8)-1:0]);

    if (r.r_resp != axi_pkg::RESP_OKAY || (actual & mask) != (expected & mask)) begin
      $error("[AXI] Read from 0x%08x returned 0x%016x, expected 0x%016x, response %0d",
             addr, actual & mask, expected & mask, r.r_resp);
    end
  endtask

  task automatic check_odd_subword_accesses(input axi_ctrl_master_t axi_drv);
    localparam axi_addr_t BaseAddr = axi_addr_t'(32'h8000_0100);

    axi_write_subword(axi_drv, BaseAddr + 32'h0, 64'h0000_0000_0000_1234, 1);
    axi_write_subword(axi_drv, BaseAddr + 32'h2, 64'h0000_0000_0000_abcd, 1);
    axi_check_subword(axi_drv, BaseAddr + 32'h0, 64'h0000_0000_0000_1234, 1);
    axi_check_subword(axi_drv, BaseAddr + 32'h2, 64'h0000_0000_0000_abcd, 1);

    axi_write_subword(axi_drv, BaseAddr + 32'h4, 64'h0000_0000_0000_005a, 0);
    axi_write_subword(axi_drv, BaseAddr + 32'h5, 64'h0000_0000_0000_00c3, 0);
    axi_check_subword(axi_drv, BaseAddr + 32'h4, 64'h0000_0000_0000_005a, 0);
    axi_check_subword(axi_drv, BaseAddr + 32'h5, 64'h0000_0000_0000_00c3, 0);
  endtask

  task automatic axi_write_slow(
    input axi_ctrl_master_t axi_drv,
    input axi_addr_t addr,
    input int unsigned num_beats,
    input int unsigned gap_cycles
  );
    axi_ctrl_master_t::ax_beat_t ax = new();
    axi_ctrl_master_t::w_beat_t w;
    axi_ctrl_master_t::b_beat_t b;

    if (num_beats == 0 || num_beats > 256) begin
      $fatal(1, "Slow AXI write num_beats must be in [1, 256], got %0d", num_beats);
    end

    ax.ax_addr  = addr;
    ax.ax_id    = '0;
    ax.ax_len   = 8'(num_beats - 1);
    ax.ax_size  = $clog2(TbAxiDataWidthFull/8);
    ax.ax_burst = axi_pkg::BURST_INCR;
    axi_drv.send_aw(ax);

    for (int unsigned beat = 0; beat < num_beats; beat++) begin
      repeat (gap_cycles) @(posedge clk);
      w = new();
      w.w_data = slow_stress_data(addr, beat);
      w.w_strb = '1;
      w.w_last = beat == (num_beats - 1);
      axi_drv.send_w(w);
    end

    axi_drv.recv_b(b);
    if (b.b_resp != axi_pkg::RESP_OKAY) begin
      $error("[AXI-SLOW] Write to 0x%08x returned response %0d", addr, b.b_resp);
    end
  endtask

  task automatic axi_read_slow_check(
    input axi_ctrl_master_t axi_drv,
    input axi_addr_t addr,
    input int unsigned num_beats,
    input int unsigned gap_cycles
  );
    axi_ctrl_master_t::ax_beat_t ax = new();
    axi_ctrl_master_t::r_beat_t r;
    logic [TbAxiDataWidthFull-1:0] expected;

    if (num_beats == 0 || num_beats > 256) begin
      $fatal(1, "Slow AXI read num_beats must be in [1, 256], got %0d", num_beats);
    end

    ax.ax_addr  = addr;
    ax.ax_id    = '0;
    ax.ax_len   = 8'(num_beats - 1);
    ax.ax_size  = $clog2(TbAxiDataWidthFull/8);
    ax.ax_burst = axi_pkg::BURST_INCR;
    axi_drv.send_ar(ax);

    for (int unsigned beat = 0; beat < num_beats; beat++) begin
      repeat (gap_cycles) @(posedge clk);
      axi_drv.recv_r(r);
      expected = slow_stress_data(addr, beat);
      if (r.r_resp != axi_pkg::RESP_OKAY || r.r_data != expected ||
          r.r_last != (beat == (num_beats - 1))) begin
        $error("[AXI-SLOW] Read beat %0d from 0x%08x returned data=0x%016x last=%0b resp=%0d, expected data=0x%016x last=%0b",
               beat, addr, r.r_data, r.r_last, r.r_resp, expected, beat == (num_beats - 1));
      end
    end
  endtask

  task automatic run_slow_backpressure_test(
    input axi_ctrl_master_t axi_drv,
    input reg_bus_master_t reg_drv
  );
    localparam axi_addr_t SlowBaseAddr = axi_addr_t'(32'h8000_4000);
    logic [RegBusDW-1:0] saved_t_burst_max;
    logic [31:0] write_segment_starts;
    logic [31:0] read_segment_starts;
    logic [31:0] segment_start_snapshot;
    logic reg_error;

    $display("===========================");
    $display("= Slow AXI backpressure   =");
    $display("===========================");

    reg_drv.send_read(32'h2 << 2, saved_t_burst_max, reg_error);
    if (reg_error != 1'b0) $error("unexpected error");

    reg_drv.send_write(32'h2 << 2, TbSlowBurstMax, '1, reg_error);
    if (reg_error != 1'b0) $error("unexpected error");

    segment_start_snapshot = segment_start_count;
    axi_write_slow(axi_drv, SlowBaseAddr, TbSlowNumBeats, TbSlowGapCycles);
    write_segment_starts = segment_start_count - segment_start_snapshot;
    if (write_segment_starts <= 1) begin
      $error("[AXI-SLOW] Write observed %0d HyperBus segment start(s), expected at least one restart",
             write_segment_starts);
    end else begin
      $display("[AXI-SLOW] Write observed %0d HyperBus segment starts (%0d restarts)",
               write_segment_starts, write_segment_starts - 1);
    end

    segment_start_snapshot = segment_start_count;
    axi_read_slow_check(axi_drv, SlowBaseAddr, TbSlowNumBeats, TbSlowGapCycles);
    read_segment_starts = segment_start_count - segment_start_snapshot;
    if (read_segment_starts <= 1) begin
      $error("[AXI-SLOW] Read observed %0d HyperBus segment start(s), expected at least one restart",
             read_segment_starts);
    end else begin
      $display("[AXI-SLOW] Read observed %0d HyperBus segment starts (%0d restarts)",
               read_segment_starts, read_segment_starts - 1);
    end

    reg_drv.send_write(32'h2 << 2, saved_t_burst_max, '1, reg_error);
    if (reg_error != 1'b0) $error("unexpected error");
  endtask

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

    if (TbDutVariant != 0) begin
      reg_master.send_write(32'h4 << 2, TbRxDelayLineTaps, '1, s_reg_error);
      if (s_reg_error != 1'b0) $error("unexpected error");
      reg_master.send_write(32'h5 << 2, TbTxDelayLineTaps, '1, s_reg_error);
      if (s_reg_error != 1'b0) $error("unexpected error");
    end

    #600350ns;

    run_slow_backpressure_test(axi_ctrl_mst, reg_master);

    if (TbDutVariant == 0) begin
      // switch memory address space to register space
      reg_master.send_write(32'h7<<2, 1'b1, '1, s_reg_error);
      if (s_reg_error != 1'b0) $error("unexpected error");

      // enable variable latency so we can test RWDS sampling
      s27ks_cfg0.fixed_latency_enable = 1'b0;
      axi_write_32(32'h8000_0000 + S27KS_CFG0_REG_OFFSET, (s27ks_cfg0 | s27ks_cfg0 << 16));

      // switch back to memory address space
      reg_master.send_write(32'h7<<2, 1'b0, '1, s_reg_error);
      if (s_reg_error != 1'b0) $error("unexpected error");
    end

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
       axi_ctrl_mst.reset_master();
       check_odd_subword_accesses(axi_ctrl_mst);

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
       axi_ctrl_mst.reset_master();
       check_odd_subword_accesses(axi_ctrl_mst);

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
    .AnnotateSdf     ( TbAnnotateSdf      ),
    .IsClockODelayed ( IsClockODelayed    ),
    .DutVariant      ( TbDutVariant       ),
    .PhyCyclTime     ( TbPhyCyclTime      ),
    .axi_rule_t      ( rule_t             )
  ) i_dut_if (
    // clk and rst signal
    .clk_i      ( clk          ),
    .rst_ni     ( rst_n        ),
    .end_sim_i  ( end_of_sim   ),
    .segment_start_count_o ( segment_start_count ),
    .axi_slv_if ( axi_dut_intf ),
    .reg_slv_if ( reg_bus_mst  )
  );

endmodule

module axi_hyper_tb_isochronous;
  axi_hyper_tb #(
    .TbDutVariant  ( 0   ),
    .TbCyclTime    ( 5ns ),
    .TbPhyCyclTime ( 6ns )
  ) i_axi_hyper_tb ();
endmodule

module axi_hyper_tb_synchronous;
  axi_hyper_tb #(
    .TbDutVariant      ( 1    ),
    .TbCyclTime        ( 10ns ),
    .TbPhyCyclTime     ( 10ns ),
    .TbRxDelayLineTaps ( 16   ),
    .TbTxDelayLineTaps ( 31   )
  ) i_axi_hyper_tb ();
endmodule

module axi_hyper_tb_asynchronous;
  axi_hyper_tb #(
    .TbDutVariant      ( 2   ),
    .TbCyclTime        ( 5ns ),
    .TbPhyCyclTime     ( 6ns ),
    .TbRxDelayLineTaps ( 16  ),
    .TbTxDelayLineTaps ( 19  )
  ) i_axi_hyper_tb ();
endmodule
