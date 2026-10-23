// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

`timescale 1 ns / 1 ps

// Exercise accepted W data that precedes AW across a configuration barrier.
// Set RequireEarlyW to zero only for an implementation that intentionally
// withholds WREADY until AW; that mode does not claim early-W coverage.
module axi_pre_aw_drain_tb #(
  parameter bit RequireEarlyW = 1'b1
);

  localparam int unsigned BurstBeats = 32;
  localparam int unsigned AxiDataBytes = 8;
  localparam logic [31:0] SingleAddress = 32'h8000_6800;
  localparam logic [31:0] BurstAddress = 32'h8000_7000;
  localparam logic [5:0] SingleId = 6'd31;
  localparam logic [5:0] BurstId = 6'd32;

  int unsigned early_w_accepted;
  bit aw_seen;
  bit single_w_done;
  bit partial_first_w_done;
  bit release_partial_w;
  bit w_producer_done;

  fixture_hyperbus #(
      .NumConnectedChips   ( 2     ),
      .NumPhys             ( 2     ),
      .DutVariant          ( 1     ),
      .HostWriteBufferBytes( 128   ),
      .SysClkPeriod        ( 10ns  ),
      .AnnotateSdf         ( 1'b1  )
  ) fix ();

  always @(posedge fix.sys_clk) begin
    if (fix.rst_n) begin
      if (fix.axi_dv.aw_valid && fix.axi_dv.aw_ready) begin
        aw_seen = 1'b1;
      end else if (fix.axi_dv.w_valid && fix.axi_dv.w_ready && !aw_seen) begin
        early_w_accepted++;
      end
    end
  end

  task automatic send_aw(input logic [31:0] addr, input logic [5:0] id,
                         input logic [7:0] len);
    fix.aw_beat.ax_addr  = addr;
    fix.aw_beat.ax_id    = id;
    fix.aw_beat.ax_len   = len;
    fix.aw_beat.ax_size  = 3;
    fix.aw_beat.ax_burst = axi_pkg::BURST_INCR;
    fix.aw_beat.ax_atop  = '0;
    fix.axi_master_drv.send_aw(fix.aw_beat);
  endtask

  task automatic receive_b(input logic [5:0] expected_id);
    fix.axi_master_drv.recv_b(fix.b_beat);
    if ((fix.b_beat.b_resp != axi_pkg::RESP_OKAY) || (fix.b_beat.b_id != expected_id)) begin
      $fatal(1, "write returned id=%0d resp=%0d expected id=%0d", fix.b_beat.b_id,
             fix.b_beat.b_resp, expected_id);
    end
  endtask

  task automatic check_word(input logic [31:0] addr, input logic [5:0] id,
                            input logic [63:0] expected);
    fix.ar_beat.ax_addr  = addr;
    fix.ar_beat.ax_id    = id;
    fix.ar_beat.ax_len   = '0;
    fix.ar_beat.ax_size  = 3;
    fix.ar_beat.ax_burst = axi_pkg::BURST_INCR;
    fix.axi_master_drv.send_ar(fix.ar_beat);
    fix.axi_master_drv.recv_r(fix.r_beat);
    if ((fix.r_beat.r_resp != axi_pkg::RESP_OKAY) || !fix.r_beat.r_last ||
        (fix.r_beat.r_id != id) || (fix.r_beat.r_data != expected)) begin
      $fatal(1, "read at 0x%08x returned id=%0d data=0x%016x last=%0b resp=%0d",
             addr, fix.r_beat.r_id, fix.r_beat.r_data, fix.r_beat.r_last,
             fix.r_beat.r_resp);
    end
  endtask

  task automatic wait_barrier_busy();
    logic [31:0] status;
    logic error;

    for (int unsigned poll = 0; poll < 100; poll++) begin
      fix.i_rmaster.send_read(32'h010, status, error);
      if (error) $fatal(1, "configuration status read failed");
      if (status[1]) return;
    end
    $fatal(1, "configuration FLUSH did not enter drain state");
  endtask

  task automatic wait_barrier_idle();
    logic [31:0] status;
    logic error;

    repeat (2) @(posedge fix.sys_clk);
    for (int unsigned poll = 0; poll < 1000; poll++) begin
      fix.i_rmaster.send_read(32'h010, status, error);
      if (error) $fatal(1, "configuration status read failed");
      if (!status[1]) return;
    end
    $fatal(1, "configuration barrier did not become idle");
  endtask

  task automatic check_barrier_held();
    logic [31:0] status;
    logic error;
    // AW or the remaining W beats stay withheld throughout these observations.
    repeat (8) begin
      fix.i_rmaster.send_read(32'h010, status, error);
      if (error || !status[1])
        $fatal(1, "configuration FLUSH completed while write debt remained");
    end
  endtask

  initial begin
    logic error;
    int unsigned early_wait_cycles;

    fix.reset_end();

    fix.i_rmaster.send_write(32'h444, 32'h8200_0000, '1, error);
    if (error) $fatal(1, "chip 1 start-address write failed");
    fix.i_rmaster.send_write(32'h440, 32'h8100_0000, '1, error);
    if (error) $fatal(1, "chip 1 end-address write failed");
    fix.i_rmaster.send_write(32'h404, 32'h8100_0000, '1, error);
    if (error) $fatal(1, "chip 0 end-address write failed");
    fix.i_rmaster.send_write(32'h400, 32'h8000_0000, '1, error);
    if (error) $fatal(1, "chip 0 start-address write failed");
    fix.i_rmaster.send_write(32'h00c, 32'h2, '1, error);
    if (error) $fatal(1, "configuration APPLY write failed");
    wait_barrier_idle();

    // A complete single-beat W packet may precede AW and remain outstanding
    // across FLUSH. This is distinct from the partial-burst case below.
    early_w_accepted = 0;
    aw_seen = 1'b0;
    single_w_done = 1'b0;
    fork
      begin : send_complete_w_before_aw
        fix.w_beat.w_data = 64'hd15e_a5e5_0000_0000 ^ SingleAddress;
        fix.w_beat.w_strb = '1;
        fix.w_beat.w_last = 1'b1;
        fix.axi_master_drv.send_w(fix.w_beat);
        #1ps;
        single_w_done = 1'b1;
      end
    join_none
    early_wait_cycles = 0;
    while ((early_w_accepted == 0) && (early_wait_cycles < 20)) begin
      @(posedge fix.sys_clk);
      early_wait_cycles++;
    end
    if (early_w_accepted != 0) begin
      wait (single_w_done);
      fix.i_rmaster.send_write(32'h00c, 32'h1, '1, error);
      if (error) $fatal(1, "configuration FLUSH write failed");
      wait_barrier_busy();
      check_barrier_held();
      $display("Observed complete W packet accepted before AW; FLUSH held its debt");
    end else begin
      if (RequireEarlyW) begin
        $fatal(1, "current early-W-capable implementation accepted no W beat before AW");
      end
      $display("AW-gated mode: complete pre-AW W packet not accepted; coverage not claimed");
      send_aw(SingleAddress, SingleId, '0);
      wait (single_w_done);
    end
    if (early_w_accepted != 0) begin
      send_aw(SingleAddress, SingleId, '0);
    end
    receive_b(SingleId);
    wait_barrier_idle();
    check_word(SingleAddress, SingleId, 64'hd15e_a5e5_0000_0000 ^ SingleAddress);

    // Pause immediately after the first accepted W beat. This establishes an
    // incomplete packet independent of write-buffer capacity while FLUSH starts.
    early_w_accepted = 0;
    aw_seen = 1'b0;
    partial_first_w_done = 1'b0;
    release_partial_w = 1'b0;
    w_producer_done = 1'b0;
    fork
      begin : produce_partial_w_burst
        fix.w_beat.w_data = 64'hd15e_a5e5_0000_0000 ^ BurstAddress;
        fix.w_beat.w_strb = '1;
        fix.w_beat.w_last = 1'b0;
        fix.axi_master_drv.send_w(fix.w_beat);
        #1ps;
        partial_first_w_done = 1'b1;
        wait (release_partial_w);
        for (int unsigned beat = 1; beat < BurstBeats; beat++) begin
          fix.w_beat.w_data = 64'hd15e_a5e5_0000_0000 ^
                              (BurstAddress + beat * AxiDataBytes);
          fix.w_beat.w_strb = '1;
          fix.w_beat.w_last = (beat == BurstBeats - 1);
          fix.axi_master_drv.send_w(fix.w_beat);
        end
        w_producer_done = 1'b1;
      end
    join_none

    early_wait_cycles = 0;
    while (!partial_first_w_done && (early_wait_cycles < 20)) begin
      @(posedge fix.sys_clk);
      early_wait_cycles++;
    end
    if (!partial_first_w_done && RequireEarlyW) begin
      $fatal(1, "current early-W-capable implementation accepted no partial-burst beat before AW");
    end

    if (partial_first_w_done && (early_w_accepted != 0)) begin
      fix.i_rmaster.send_write(32'h00c, 32'h1, '1, error);
      if (error) $fatal(1, "partial-burst configuration FLUSH write failed");
      wait_barrier_busy();
      check_barrier_held();
      if (w_producer_done || (early_w_accepted != 1)) begin
        $fatal(1, "partial burst was not held after exactly its first accepted W beat");
      end
      send_aw(BurstAddress, BurstId, BurstBeats - 1);
      release_partial_w = 1'b1;
      $display("Observed partial W burst across FLUSH before AW");
    end else begin
      // An AW-gated implementation cannot have pre-AW debt. Accept AW first,
      // then hold a deliberately partial burst while the barrier is asserted.
      if (RequireEarlyW) $fatal(1, "partial early-W coverage was not established");
      send_aw(BurstAddress, BurstId, BurstBeats - 1);
      wait (partial_first_w_done);
      fix.i_rmaster.send_write(32'h00c, 32'h1, '1, error);
      if (error) $fatal(1, "AW-gated partial-burst FLUSH write failed");
      wait_barrier_busy();
      check_barrier_held();
      if (w_producer_done) $fatal(1, "AW-gated partial burst completed before barrier check");
      release_partial_w = 1'b1;
      $display("AW-gated mode: tested partial burst across FLUSH; early-W coverage not claimed");
    end

    wait (w_producer_done);
    receive_b(BurstId);
    wait_barrier_idle();

    for (int unsigned beat = 0; beat < BurstBeats; beat++) begin
      check_word(BurstAddress + beat * AxiDataBytes, 6'(beat + 1),
                 64'hd15e_a5e5_0000_0000 ^
                 (BurstAddress + beat * AxiDataBytes));
    end

    fix.eos = 1'b1;
    #100ns;
    $display("Pre-AW W drain regressions passed");
    $finish;
  end

  initial begin
    #2ms;
    $fatal(1, "Pre-AW W drain regression timed out");
  end

endmodule
