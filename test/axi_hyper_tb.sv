// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Luca Valente <luca.valente@unibo.it>

module axi_hyper_tb
  import axi_pkg::*;
#(
  parameter int unsigned NumConnectedChips = 2,
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
  /// RX delay-line tap value.
  parameter int unsigned TbRxDelayLineTaps = 16,
  /// TX delay-line tap value.
  parameter int unsigned TbTxDelayLineTaps = 19,
  /// Number of AXI beats in the directed slow read/write stress transactions.
  parameter int unsigned TbSlowNumBeats = 64,
  /// Idle cycles inserted between each accepted AXI beat in the slow stress transactions.
  parameter int unsigned TbSlowGapCycles = 64,
  /// Temporary t_burst_max used to force HyperBus segment restarts in the slow stress phase.
  parameter int unsigned TbSlowBurstMax = 16,
  /// Maximum system-clock cycles before a stalled regression is terminated.
  parameter longint unsigned TbTimeoutCycles = 5_000_000,
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
  logic [63:0]           cycle_count;

  sim_timeout #(
    .Cycles ( TbTimeoutCycles )
  ) i_sim_timeout (
    .clk_i  ( clk   ),
    .rst_ni ( rst_n )
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cycle_count <= '0;
    end else begin
      cycle_count <= cycle_count + 1'b1;
    end
  end


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

  task automatic check_consecutive_reads(input axi_ctrl_master_t axi_drv);
    localparam axi_addr_t BaseAddr = axi_addr_t'(32'h8000_0200);
    localparam int unsigned NumTestWords = 8;
    logic [TbAxiDataWidthFull-1:0] expected;

    for (int unsigned word = 0; word < NumTestWords; word++) begin
      expected = 64'h0123_4567_89ab_cdef ^ (word * 64'h1111_1111_1111_1111);
      axi_write_subword(axi_drv, BaseAddr + word * 8, expected, 3);
    end

    // Keep reads consecutive so no write response can reset the RWDS capture path.
    for (int unsigned pass = 0; pass < 2; pass++) begin
      for (int unsigned word = 0; word < NumTestWords; word++) begin
        expected = 64'h0123_4567_89ab_cdef ^ (word * 64'h1111_1111_1111_1111);
        axi_check_subword(axi_drv, BaseAddr + word * 8, expected, 3);
      end
    end
  endtask

  task automatic check_unaligned_word_access(input axi_ctrl_master_t axi_drv);
    localparam axi_addr_t BaseAddr = axi_addr_t'(32'h8000_0180);
    localparam logic [63:0] InitialData = 64'h8877_6655_4433_2211;
    localparam logic [23:0] UpdatedData = 24'hc3_b2_a1;
    axi_ctrl_master_t::ax_beat_t ax = new();
    axi_ctrl_master_t::w_beat_t w = new();
    axi_ctrl_master_t::b_beat_t b;
    axi_ctrl_master_t::r_beat_t r;

    axi_write_subword(axi_drv, BaseAddr, InitialData, 3);

    ax.ax_addr  = BaseAddr + 1;
    ax.ax_id    = '0;
    ax.ax_len   = '0;
    ax.ax_size  = 2;
    ax.ax_burst = axi_pkg::BURST_INCR;
    axi_drv.send_aw(ax);

    w.w_data = 64'(UpdatedData) << 8;
    w.w_strb = 8'b0000_1110;
    w.w_last = 1'b1;
    axi_drv.send_w(w);
    axi_drv.recv_b(b);
    if (b.b_resp != axi_pkg::RESP_OKAY) begin
      $error("[AXI-UNALIGNED] Write returned response %0d", b.b_resp);
    end

    axi_check_subword(axi_drv, BaseAddr, 64'h8877_6655_c3b2_a111, 3);

    axi_drv.send_ar(ax);
    axi_drv.recv_r(r);
    if ((r.r_resp != axi_pkg::RESP_OKAY) || !r.r_last ||
        (r.r_data[31:8] != UpdatedData)) begin
      $error("[AXI-UNALIGNED] Read returned data=0x%016x last=%0b resp=%0d",
             r.r_data, r.r_last, r.r_resp);
    end
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

  task automatic check_midend_buffering(input axi_ctrl_master_t axi_drv);
    localparam int unsigned NumTransactions = 4;
    localparam int unsigned WriteBeats = 4;
    localparam axi_addr_t BufferBaseAddr = axi_addr_t'(32'h8000_2000);
    axi_ctrl_master_t::ax_beat_t ax;
    axi_ctrl_master_t::w_beat_t w;
    axi_ctrl_master_t::b_beat_t b;
    axi_ctrl_master_t::r_beat_t r;
    axi_addr_t transaction_addr;

    $display("===========================");
    $display("= Midend queue buffering  =");
    $display("===========================");

    // Fill all write contexts and the 128-byte W buffer before accepting responses.
    for (int unsigned transaction = 0; transaction < NumTransactions; transaction++) begin
      ax = new();
      ax.ax_addr  = BufferBaseAddr + axi_addr_t'(transaction * WriteBeats *
                                                (TbAxiDataWidthFull / 8));
      ax.ax_id    = TbAxiIdWidthFull'(transaction + 1);
      ax.ax_len   = WriteBeats - 1;
      ax.ax_size  = $clog2(TbAxiDataWidthFull / 8);
      ax.ax_burst = axi_pkg::BURST_INCR;
      axi_drv.send_aw(ax);
    end

    for (int unsigned transaction = 0; transaction < NumTransactions; transaction++) begin
      transaction_addr = BufferBaseAddr + axi_addr_t'(transaction * WriteBeats *
                                                      (TbAxiDataWidthFull / 8));
      for (int unsigned beat = 0; beat < WriteBeats; beat++) begin
        w = new();
        w.w_data = slow_stress_data(transaction_addr, beat);
        w.w_strb = '1;
        w.w_last = beat == WriteBeats - 1;
        axi_drv.send_w(w);
      end
    end

    for (int unsigned transaction = 0; transaction < NumTransactions; transaction++) begin
      axi_drv.recv_b(b);
      if ((b.b_resp != axi_pkg::RESP_OKAY) ||
          (b.b_id != TbAxiIdWidthFull'(transaction + 1))) begin
        $error("[MIDEND-BUFFER] Write %0d returned id=%0d resp=%0d",
               transaction, b.b_id, b.b_resp);
      end
    end

    // Four one-beat reads can occupy all read contexts and response entries.
    for (int unsigned transaction = 0; transaction < NumTransactions; transaction++) begin
      ax = new();
      ax.ax_addr  = BufferBaseAddr + axi_addr_t'(transaction * WriteBeats *
                                                (TbAxiDataWidthFull / 8));
      ax.ax_id    = TbAxiIdWidthFull'(transaction + 1);
      ax.ax_len   = '0;
      ax.ax_size  = $clog2(TbAxiDataWidthFull / 8);
      ax.ax_burst = axi_pkg::BURST_INCR;
      axi_drv.send_ar(ax);
    end

    for (int unsigned transaction = 0; transaction < NumTransactions; transaction++) begin
      axi_drv.recv_r(r);
      transaction_addr = BufferBaseAddr + axi_addr_t'(transaction * WriteBeats *
                                                      (TbAxiDataWidthFull / 8));
      if ((r.r_resp != axi_pkg::RESP_OKAY) || !r.r_last ||
          (r.r_id != TbAxiIdWidthFull'(transaction + 1)) ||
          (r.r_data != slow_stress_data(transaction_addr, 0))) begin
        $error("[MIDEND-BUFFER] Read %0d returned id=%0d data=0x%016x last=%0b resp=%0d",
               transaction, r.r_id, r.r_data, r.r_last, r.r_resp);
      end
    end
  endtask

  task automatic run_performance_smoke(input axi_ctrl_master_t axi_drv);
    localparam int unsigned NumCases = 5;
    localparam axi_addr_t PerfBaseAddr = axi_addr_t'(32'h8000_8000);
    int unsigned burst_beats [NumCases] = '{1, 4, 16, 64, 256};
    int unsigned write_baseline [NumCases];
    int unsigned read_baseline [NumCases];
    int unsigned segment_limit [NumCases];
    logic [63:0] write_cycles [NumCases];
    logic [63:0] read_cycles [NumCases];
    logic [63:0] cycle_snapshot;
    logic [31:0] segment_snapshot;
    logic [31:0] write_segments;
    logic [31:0] read_segments;
    axi_addr_t burst_addr;
    int unsigned write_cycle_limit;
    int unsigned read_cycle_limit;
    real backend_cycles_per_system_cycle;
    real write_bits_per_phy_cycle;
    real read_bits_per_phy_cycle;

    backend_cycles_per_system_cycle = 1.0;
    if (TbDutVariant == 0) begin
      backend_cycles_per_system_cycle = 0.5;
    end else if (TbDutVariant == 2) begin
      backend_cycles_per_system_cycle = real'(TbCyclTime) / real'(TbPhyCyclTime);
    end

    // Default-configuration baselines in system-clock cycles for each supported top.
    write_baseline = '{44, 55, 103, 295, 1103};
    read_baseline = '{59, 71, 119, 311, 1119};
    segment_limit = '{1, 1, 1, 1, 2};
    if (TbDutVariant == 1) begin
      write_baseline = '{22, 28, 52, 148, 552};
      read_baseline = '{29, 35, 59, 155, 559};
    end else if (TbDutVariant == 2) begin
      write_baseline = '{36, 42, 71, 186, 671};
      read_baseline = '{43, 49, 78, 193, 678};
    end
    if (NumPhys == 1) begin
      write_baseline = '{24, 36, 84, 276, 1084};
      read_baseline = '{30, 42, 90, 282, 1090};
      segment_limit = '{1, 1, 1, 1, 3};
    end

    $display("===========================");
    $display("= AXI performance smoke   =");
    $display("===========================");

    for (int unsigned test_idx = 0; test_idx < NumCases; test_idx++) begin
      burst_addr = PerfBaseAddr + axi_addr_t'(test_idx * 32'h1000);

      cycle_snapshot = cycle_count;
      segment_snapshot = segment_start_count;
      axi_write_slow(axi_drv, burst_addr, burst_beats[test_idx], 0);
      write_cycles[test_idx] = cycle_count - cycle_snapshot;
      write_segments = segment_start_count - segment_snapshot;

      cycle_snapshot = cycle_count;
      segment_snapshot = segment_start_count;
      axi_read_slow_check(axi_drv, burst_addr, burst_beats[test_idx], 0);
      read_cycles[test_idx] = cycle_count - cycle_snapshot;
      read_segments = segment_start_count - segment_snapshot;

      $display("[PERF] variant=%0d phys=%0d beats=%0d write_cycles=%0d read_cycles=%0d write_segments=%0d read_segments=%0d",
               TbDutVariant, NumPhys, burst_beats[test_idx], write_cycles[test_idx],
               read_cycles[test_idx], write_segments, read_segments);

      if (burst_beats[test_idx] == 256) begin
        write_bits_per_phy_cycle = real'(burst_beats[test_idx] * TbAxiDataWidthFull) /
            real'(NumPhys * write_cycles[test_idx]) / backend_cycles_per_system_cycle;
        read_bits_per_phy_cycle = real'(burst_beats[test_idx] * TbAxiDataWidthFull) /
            real'(NumPhys * read_cycles[test_idx]) / backend_cycles_per_system_cycle;
        $display("[PERF-MAX] variant=%0d write_bits_per_phy_cycle=%0.3f read_bits_per_phy_cycle=%0.3f",
                 TbDutVariant, write_bits_per_phy_cycle, read_bits_per_phy_cycle);
      end

      write_cycle_limit = write_baseline[test_idx] + write_baseline[test_idx] / 5 + 2;
      read_cycle_limit = read_baseline[test_idx] + read_baseline[test_idx] / 5 + 2;
      if (write_cycles[test_idx] > write_cycle_limit) begin
        $error("[PERF] %0d-beat write took %0d cycles, limit is %0d",
               burst_beats[test_idx], write_cycles[test_idx], write_cycle_limit);
      end
      if (read_cycles[test_idx] > read_cycle_limit) begin
        $error("[PERF] %0d-beat read took %0d cycles, limit is %0d",
               burst_beats[test_idx], read_cycles[test_idx], read_cycle_limit);
      end
      if ((write_segments != segment_limit[test_idx]) ||
          (read_segments != segment_limit[test_idx])) begin
        $error("[PERF] %0d-beat burst used unexpected segments: write=%0d read=%0d limit=%0d",
               burst_beats[test_idx], write_segments, read_segments,
               segment_limit[test_idx]);
      end
    end

    for (int unsigned test_idx = 1; test_idx < NumCases; test_idx++) begin
      if ((write_cycles[test_idx] * burst_beats[test_idx-1]) >
          (write_cycles[test_idx-1] * burst_beats[test_idx])) begin
        $error("[PERF] Write cycles per beat did not improve from %0d to %0d beats",
               burst_beats[test_idx-1], burst_beats[test_idx]);
      end
      if ((read_cycles[test_idx] * burst_beats[test_idx-1]) >
          (read_cycles[test_idx-1] * burst_beats[test_idx])) begin
        $error("[PERF] Read cycles per beat did not improve from %0d to %0d beats",
               burst_beats[test_idx-1], burst_beats[test_idx]);
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

  task automatic check_config_barrier(
    input axi_ctrl_master_t axi_drv,
    input reg_bus_master_t reg_drv
  );
    localparam axi_addr_t BarrierAddr = axi_addr_t'(32'h8000_6000);
    logic reg_error;
    time write_done_time;
    time flush_done_time;

    write_done_time = 0;
    flush_done_time = 0;
    $display("===========================");
    $display("= Config flush barrier    =");
    $display("===========================");

    fork
      begin
        axi_write_slow(axi_drv, BarrierAddr, 16, 16);
        write_done_time = $time;
      end
      begin
        repeat (32) @(posedge clk);
        reg_drv.send_write(32'h50, '0, '1, reg_error);
        flush_done_time = $time;
        if (reg_error != 1'b0) begin
          $error("[CFG-BARRIER] Flush register write returned an error");
        end
      end
    join

    if ((write_done_time == 0) || (flush_done_time < write_done_time)) begin
      $error("[CFG-BARRIER] Flush completed at %0t before AXI write completed at %0t",
             flush_done_time, write_done_time);
    end
  endtask

  task automatic check_decode_errors(
    input axi_ctrl_master_t axi_drv,
    input reg_bus_master_t reg_drv
  );
    localparam axi_addr_t InvalidAddr = axi_addr_t'(32'h9000_0000);
    axi_ctrl_master_t::ax_beat_t ax = new();
    axi_ctrl_master_t::w_beat_t w = new();
    axi_ctrl_master_t::b_beat_t b;
    axi_ctrl_master_t::r_beat_t r;
    logic [31:0] status;
    logic reg_error;

    $display("===========================");
    $display("= Decode error handling   =");
    $display("===========================");

    ax.ax_addr  = InvalidAddr;
    ax.ax_id    = '0;
    ax.ax_len   = 1;
    ax.ax_size  = 3;
    ax.ax_burst = axi_pkg::BURST_INCR;
    axi_drv.send_ar(ax);
    for (int unsigned beat = 0; beat < 2; beat++) begin
      axi_drv.recv_r(r);
      if ((r.r_resp != axi_pkg::RESP_DECERR) || (r.r_data != '0) ||
          (r.r_last != (beat == 1))) begin
        $error("[DECODE] Invalid read beat %0d returned data=0x%016x last=%0b resp=%0d",
               beat, r.r_data, r.r_last, r.r_resp);
      end
    end

    ax.ax_len = 0;
    axi_drv.send_aw(ax);
    w.w_data = '0;
    w.w_strb = '1;
    w.w_last = 1'b1;
    axi_drv.send_w(w);
    axi_drv.recv_b(b);
    if (b.b_resp != axi_pkg::RESP_DECERR) begin
      $error("[DECODE] Invalid write returned response %0d", b.b_resp);
    end

    reg_drv.send_read(32'h54, status, reg_error);
    if ((reg_error != 1'b0) || !status[0]) begin
      $error("[DECODE] Sticky decode-error status was not set");
    end
    reg_drv.send_write(32'h54, 32'h1, '1, reg_error);
    if (reg_error != 1'b0) $error("unexpected error");
    reg_drv.send_read(32'h54, status, reg_error);
    if ((reg_error != 1'b0) || status[0]) begin
      $error("[DECODE] Sticky decode-error status did not clear");
    end
  endtask

  task automatic check_cross_chip_burst(
    input axi_ctrl_master_t axi_drv,
    input reg_bus_master_t reg_drv
  );
    localparam axi_addr_t Boundary = axi_addr_t'(32'h8040_0000);
    localparam axi_addr_t BurstAddr = Boundary - 16;
    logic [31:0] segment_start_snapshot;
    logic reg_error;

    if (NumConnectedChips < 2) begin
      return;
    end

    $display("===========================");
    $display("= Cross-chip burst        =");
    $display("===========================");

    reg_drv.send_write(32'h34, Boundary, '1, reg_error);
    if (reg_error != 1'b0) $error("unexpected error");
    reg_drv.send_write(32'h38, Boundary, '1, reg_error);
    if (reg_error != 1'b0) $error("unexpected error");

    segment_start_snapshot = segment_start_count;
    axi_write_slow(axi_drv, BurstAddr, 4, 0);
    axi_read_slow_check(axi_drv, BurstAddr, 4, 0);
    if ((segment_start_count - segment_start_snapshot) < 4) begin
      $error("[CROSS-CHIP] Observed %0d segment starts, expected at least four",
             segment_start_count - segment_start_snapshot);
    end

    reg_drv.send_write(32'h38, 32'h8100_0000, '1, reg_error);
    if (reg_error != 1'b0) $error("unexpected error");
    reg_drv.send_write(32'h34, 32'h8100_0000, '1, reg_error);
    if (reg_error != 1'b0) $error("unexpected error");
  endtask

  task automatic check_large_rule_distance(input axi_ctrl_master_t axi_drv);
    localparam axi_addr_t ReadAddr = axi_addr_t'(32'h802f_0002);
    localparam int unsigned NumBeats = 121;
    axi_ctrl_master_t::ax_beat_t ax = new();
    axi_ctrl_master_t::r_beat_t r;

    ax.ax_addr  = ReadAddr;
    ax.ax_id    = '0;
    ax.ax_len   = NumBeats - 1;
    ax.ax_size  = 2;
    ax.ax_burst = axi_pkg::BURST_INCR;
    axi_drv.send_ar(ax);
    for (int unsigned beat = 0; beat < NumBeats; beat++) begin
      axi_drv.recv_r(r);
      if ((r.r_resp != axi_pkg::RESP_OKAY) || (r.r_last != (beat == NumBeats - 1))) begin
        $error("[AXI-RANGE] Beat %0d returned last=%0b resp=%0d",
               beat, r.r_last, r.r_resp);
      end
    end
  endtask

  task automatic check_range_edges(
    input axi_ctrl_master_t axi_drv,
    input reg_bus_master_t reg_drv
  );
    localparam axi_addr_t ValidAddr = axi_addr_t'(32'h8100_0100);
    localparam axi_addr_t OverflowAddr = axi_addr_t'(32'hffff_fff8);
    localparam logic [63:0] TestData = 64'h0123_4567_89ab_cdef;
    axi_ctrl_master_t::ax_beat_t ax = new();
    axi_ctrl_master_t::r_beat_t r;
    logic reg_error;

    if (NumConnectedChips < 2) begin
      return;
    end

    $display("===========================");
    $display("= Address range edges     =");
    $display("===========================");

    // A zero bound extends the final rule through the end of the address space.
    reg_drv.send_write(32'h3c, '0, '1, reg_error);
    if (reg_error != 1'b0) $error("unexpected error");
    axi_write_subword(axi_drv, ValidAddr, TestData, 3);
    axi_check_subword(axi_drv, ValidAddr, TestData, 3);

    // The end address is exclusive; a burst extending beyond it must be rejected.
    ax.ax_addr  = OverflowAddr;
    ax.ax_id    = '0;
    ax.ax_len   = 1;
    ax.ax_size  = 3;
    ax.ax_burst = axi_pkg::BURST_INCR;
    axi_drv.send_ar(ax);
    for (int unsigned beat = 0; beat < 2; beat++) begin
      axi_drv.recv_r(r);
      if ((r.r_resp != axi_pkg::RESP_DECERR) ||
          (r.r_last != (beat == 1))) begin
        $error("[AXI-RANGE] Overflow beat %0d returned last=%0b resp=%0d",
               beat, r.r_last, r.r_resp);
      end
    end

    reg_drv.send_write(32'h3c, 32'h8200_0000, '1, reg_error);
    if (reg_error != 1'b0) $error("unexpected error");
  endtask

  task automatic check_atomic_add(
    input axi_ctrl_master_t axi_drv,
    input reg_bus_master_t reg_drv
  );
    localparam axi_addr_t AtomicAddr = axi_addr_t'(32'h8000_0200);
    localparam logic [31:0] InitialValue = 32'h1234_5678;
    localparam logic [31:0] Addend = 32'h0102_0304;
    axi_ctrl_master_t::ax_beat_t ax = new();
    axi_ctrl_master_t::w_beat_t w = new();
    axi_ctrl_master_t::b_beat_t b;
    axi_ctrl_master_t::r_beat_t r;
    logic [31:0] status;
    logic reg_error;

    $display("===========================");
    $display("= Atomic add              =");
    $display("===========================");

    axi_write_subword(axi_drv, AtomicAddr, InitialValue, 2);

    ax.ax_addr  = AtomicAddr;
    ax.ax_id    = '0;
    ax.ax_len   = '0;
    ax.ax_size  = 2;
    ax.ax_burst = axi_pkg::BURST_INCR;
    ax.ax_atop  = {axi_pkg::ATOP_ATOMICLOAD, axi_pkg::ATOP_LITTLE_END,
                   axi_pkg::ATOP_ADD};
    axi_drv.send_aw(ax);

    w.w_data = subword_data(Addend, AtomicAddr);
    w.w_strb = subword_strb(AtomicAddr, 2);
    w.w_last = 1'b1;
    axi_drv.send_w(w);

    fork
      axi_drv.recv_b(b);
      axi_drv.recv_r(r);
    join

    if ((b.b_resp != axi_pkg::RESP_OKAY) || (r.r_resp != axi_pkg::RESP_OKAY) ||
        (r.r_data[31:0] != InitialValue) || !r.r_last) begin
      $error("[ATOMIC] Add returned old=0x%08x rresp=%0d bresp=%0d last=%0b",
             r.r_data[31:0], r.r_resp, b.b_resp, r.r_last);
    end
    axi_check_subword(axi_drv, AtomicAddr, InitialValue + Addend, 2);

    // Big-endian arithmetic is rejected explicitly and must still drain W.
    ax.ax_atop = {axi_pkg::ATOP_ATOMICLOAD, axi_pkg::ATOP_BIG_END,
                  axi_pkg::ATOP_ADD};
    axi_drv.send_aw(ax);
    axi_drv.send_w(w);
    fork
      axi_drv.recv_b(b);
      axi_drv.recv_r(r);
    join
    if ((b.b_resp != axi_pkg::RESP_SLVERR) || (r.r_resp != axi_pkg::RESP_SLVERR)) begin
      $error("[ATOMIC] Unsupported operation returned rresp=%0d bresp=%0d",
             r.r_resp, b.b_resp);
    end
    reg_drv.send_read(32'h54, status, reg_error);
    if ((reg_error != 1'b0) || !status[0]) begin
      $error("[ATOMIC] Unsupported operation did not set sticky error status");
    end
    reg_drv.send_write(32'h54, 32'h1, '1, reg_error);
    if (reg_error != 1'b0) $error("unexpected error");
    axi_check_subword(axi_drv, AtomicAddr, InitialValue + Addend, 2);

    // A malformed multi-beat atomic must drain all W beats before returning an error.
    ax.ax_len  = 1;
    ax.ax_atop = {axi_pkg::ATOP_ATOMICLOAD, axi_pkg::ATOP_LITTLE_END,
                  axi_pkg::ATOP_ADD};
    axi_drv.send_aw(ax);
    w.w_data = subword_data(32'hdead_beef, AtomicAddr);
    w.w_strb = subword_strb(AtomicAddr, 2);
    w.w_last = 1'b0;
    axi_drv.send_w(w);
    w.w_data = subword_data(32'hfeed_cafe, AtomicAddr);
    w.w_last = 1'b1;
    axi_drv.send_w(w);
    fork
      axi_drv.recv_b(b);
      axi_drv.recv_r(r);
    join
    if ((b.b_resp != axi_pkg::RESP_SLVERR) || (r.r_resp != axi_pkg::RESP_SLVERR)) begin
      $error("[ATOMIC] Multi-beat operation returned rresp=%0d bresp=%0d",
             r.r_resp, b.b_resp);
    end
    reg_drv.send_read(32'h54, status, reg_error);
    if ((reg_error != 1'b0) || !status[0]) begin
      $error("[ATOMIC] Malformed operation did not set sticky error status");
    end
    reg_drv.send_write(32'h54, 32'h1, '1, reg_error);
    if (reg_error != 1'b0) $error("unexpected error");
    axi_write_subword(axi_drv, AtomicAddr, 32'h89ab_cdef, 2);
    axi_check_subword(axi_drv, AtomicAddr, 32'h89ab_cdef, 2);
  endtask

  task automatic check_atomic_range_errors(
    input axi_ctrl_master_t axi_drv,
    input reg_bus_master_t reg_drv
  );
    localparam axi_addr_t InvalidAddr = axi_addr_t'(32'h9000_0000);
    localparam axi_addr_t ZeroEndAddr = axi_addr_t'(32'h8100_0400);
    localparam int unsigned AtomicSize = NumPhys + 1;
    localparam logic [31:0] ZeroEndInitial = 32'h1020_3040;
    localparam logic [31:0] ZeroEndAddend = 32'h0101_0101;
    axi_ctrl_master_t::ax_beat_t ax = new();
    axi_ctrl_master_t::w_beat_t w = new();
    axi_ctrl_master_t::b_beat_t b;
    axi_ctrl_master_t::r_beat_t r;
    logic [31:0] segment_start_snapshot;
    logic reg_error;

    if (NumConnectedChips < 2) begin
      return;
    end

    $display("===========================");
    $display("= Atomic range errors     =");
    $display("===========================");

    ax.ax_addr  = InvalidAddr;
    ax.ax_id    = '0;
    ax.ax_len   = '0;
    ax.ax_size  = AtomicSize;
    ax.ax_burst = axi_pkg::BURST_INCR;
    ax.ax_atop  = {axi_pkg::ATOP_ATOMICLOAD, axi_pkg::ATOP_LITTLE_END,
                   axi_pkg::ATOP_ADD};
    w.w_data = subword_data(64'hfedc_ba98_7654_3210, InvalidAddr);
    w.w_strb = subword_strb(InvalidAddr, AtomicSize);
    w.w_last = 1'b1;

    // Unmapped atomic loads still owe both the AXI R and B responses.
    segment_start_snapshot = segment_start_count;
    axi_drv.send_aw(ax);
    axi_drv.send_w(w);
    fork
      axi_drv.recv_b(b);
      axi_drv.recv_r(r);
    join
    if ((b.b_resp != axi_pkg::RESP_SLVERR) || (r.r_resp != axi_pkg::RESP_SLVERR) ||
        !r.r_last) begin
      $error("[ATOMIC-RANGE] Unmapped operation returned rlast=%0b rresp=%0d bresp=%0d",
             r.r_last, r.r_resp, b.b_resp);
    end
    if (segment_start_count != segment_start_snapshot) begin
      $error("[ATOMIC-RANGE] Rejected unmapped operation issued a HyperBus command");
    end

    // A zero-ended final rule must contain ordinary atomic accesses.
    reg_drv.send_write(32'h3c, '0, '1, reg_error);
    if (reg_error != 1'b0) $error("unexpected error");
    axi_write_subword(axi_drv, ZeroEndAddr, ZeroEndInitial, 2);
    ax.ax_addr = ZeroEndAddr;
    ax.ax_size = 2;
    w.w_data = subword_data(ZeroEndAddend, ZeroEndAddr);
    w.w_strb = subword_strb(ZeroEndAddr, 2);
    axi_drv.send_aw(ax);
    axi_drv.send_w(w);
    fork
      axi_drv.recv_b(b);
      axi_drv.recv_r(r);
    join
    if ((b.b_resp != axi_pkg::RESP_OKAY) || (r.r_resp != axi_pkg::RESP_OKAY) ||
        (r.r_data[31:0] != ZeroEndInitial) || !r.r_last) begin
      $error("[ATOMIC-RANGE] Zero-ended rule returned old=0x%08x rresp=%0d bresp=%0d",
             r.r_data[31:0], r.r_resp, b.b_resp);
    end
    axi_check_subword(axi_drv, ZeroEndAddr, ZeroEndInitial + ZeroEndAddend, 2);
    reg_drv.send_write(32'h3c, 32'h8200_0000, '1, reg_error);
    if (reg_error != 1'b0) $error("unexpected error");
  endtask

  initial begin : proc_sim_crtl

    automatic axi_scoreboard_mst_t mst_scoreboard = new( score_mst_intf_dv );
    automatic axi_rand_master_t    axi_rand_mst   = new( axi_rand_intf_dv  );
    automatic reg_bus_master_t     reg_master     = new( reg_bus_mst       );

    automatic s27ks_cfg0_reg_t s27ks_cfg0 = hyperbus_tb_pkg::s27ks_cfg0_default;
    automatic logic [63:0] divider_cycle_snapshot;
    automatic logic [63:0] div2_write_cycles;
    automatic logic [63:0] div4_write_cycles;
    automatic logic [31:0] iso_saved_t_burst_max;
    automatic int unsigned iso_test_dividers[4] = '{2, 4, 8, 16};

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

    // Map each chip to a distinct 16 MiB host-address window.
    if (NumConnectedChips > 1) begin
      reg_master.send_write(32'h3c, 32'h8200_0000, '1, s_reg_error);
      if (s_reg_error != 1'b0) $error("unexpected error");
      reg_master.send_write(32'h38, 32'h8100_0000, '1, s_reg_error);
      if (s_reg_error != 1'b0) $error("unexpected error");
    end
    reg_master.send_write(32'h34, 32'h8100_0000, '1, s_reg_error);
    if (s_reg_error != 1'b0) $error("unexpected error");
    reg_master.send_write(32'h30, 32'h8000_0000, '1, s_reg_error);
    if (s_reg_error != 1'b0) $error("unexpected error");

    reg_master.send_write(32'h4 << 2, TbRxDelayLineTaps, '1, s_reg_error);
    if (s_reg_error != 1'b0) $error("unexpected error");
    reg_master.send_write(32'h5 << 2, TbTxDelayLineTaps, '1, s_reg_error);
    if (s_reg_error != 1'b0) $error("unexpected error");

    if (TbDutVariant == 0) begin
      reg_master.send_read(32'h78, reg_read, s_reg_error);
      if ((s_reg_error != 1'b0) || (reg_read != 8)) $error("unexpected divider reset value");
      reg_master.send_write(32'h78, 8'd2, '1, s_reg_error);
      if (s_reg_error != 1'b0) $error("unexpected error");
    end

    #600350ns;

    if (TbDutVariant == 0) begin
      // The configuration barrier completes only after the divided clock resumes.
      reg_master.send_write(32'h78, 8'd4, '1, s_reg_error);
      if (s_reg_error != 1'b0) $error("unexpected error");
      reg_master.send_read(32'h78, reg_read, s_reg_error);
      if ((s_reg_error != 1'b0) || (reg_read != 4)) $error("divider update failed");

      divider_cycle_snapshot = cycle_count;
      axi_write_slow(axi_ctrl_mst, 32'h8000_7000, 4, 0);
      div4_write_cycles = cycle_count - divider_cycle_snapshot;

      reg_master.send_write(32'h78, 8'd2, '1, s_reg_error);
      if (s_reg_error != 1'b0) $error("unexpected error");
      reg_master.send_read(32'h78, reg_read, s_reg_error);
      if ((s_reg_error != 1'b0) || (reg_read != 2)) $error("divider restore failed");

      divider_cycle_snapshot = cycle_count;
      axi_write_slow(axi_ctrl_mst, 32'h8000_8000, 4, 0);
      div2_write_cycles = cycle_count - divider_cycle_snapshot;

      if (div4_write_cycles <= div2_write_cycles + div2_write_cycles / 2) begin
        $error("divider did not reduce PHY throughput: div4=%0d cycles, div2=%0d cycles",
               div4_write_cycles, div2_write_cycles);
      end
    end

    check_midend_buffering(axi_ctrl_mst);
    run_performance_smoke(axi_ctrl_mst);
    run_slow_backpressure_test(axi_ctrl_mst, reg_master);
    check_config_barrier(axi_ctrl_mst, reg_master);
    check_decode_errors(axi_ctrl_mst, reg_master);
    check_cross_chip_burst(axi_ctrl_mst, reg_master);
    check_large_rule_distance(axi_ctrl_mst);
    check_range_edges(axi_ctrl_mst, reg_master);
    check_atomic_add(axi_ctrl_mst, reg_master);
    check_atomic_range_errors(axi_ctrl_mst, reg_master);

    if (TbDutVariant == 0) begin
      $display("===========================");
      $display("= Isochronous backpressure =");
      $display("===========================");
      reg_master.send_read(32'h8, iso_saved_t_burst_max, s_reg_error);
      if (s_reg_error != 1'b0) $error("unexpected t_burst_max read error");
      foreach (iso_test_dividers[i]) begin
        // Keep each data phase near 2 us, leaving margin for CA and access latency.
        reg_master.send_write(32'h8, 400 / iso_test_dividers[i], '1, s_reg_error);
        if (s_reg_error != 1'b0) $error("unexpected t_burst_max update error");
        reg_master.send_write(32'h78, iso_test_dividers[i], '1, s_reg_error);
        if (s_reg_error != 1'b0) $error("unexpected divider update error");
        axi_write_slow(axi_ctrl_mst, 32'h8001_0000 + i * 32'h100, 16, 0);
        axi_read_slow_check(axi_ctrl_mst, 32'h8001_0000 + i * 32'h100, 16, 128);
      end

      reg_master.send_write(32'h78, 8'd2, '1, s_reg_error);
      if (s_reg_error != 1'b0) $error("unexpected divider restore error");
      reg_master.send_write(32'h8, iso_saved_t_burst_max, '1, s_reg_error);
      if (s_reg_error != 1'b0) $error("unexpected t_burst_max restore error");
    end

    if (NumPhys == 1) begin
      check_unaligned_word_access(axi_ctrl_mst);
    end

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

    check_consecutive_reads(axi_ctrl_mst);

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

    .NumConnectedChips ( NumConnectedChips ),
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
    .TbDutVariant      ( 0    ),
    .TbCyclTime        ( 5ns  ),
    .TbPhyCyclTime     ( 6ns  ),
    .TbTxDelayLineTaps ( 31   )
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

module axi_hyper_tb_synchronous_one_phy;
  axi_hyper_tb #(
    .NumPhys          ( 1    ),
    .TbNumWrites      ( 0    ),
    .TbNumReads       ( 0    ),
    .TbDutVariant     ( 1    ),
    .TbCyclTime       ( 10ns ),
    .TbPhyCyclTime    ( 10ns ),
    .TbRxDelayLineTaps( 16   ),
    .TbTxDelayLineTaps( 31   )
  ) i_axi_hyper_tb ();
endmodule
