// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

`timescale 1 ns / 1 ps

// Directed regression for AXI W-before-AW ordering across a configuration
// drain.  The fixture is connected directly to the DUT so the AXI mux used by
// the larger randomized test cannot impose an AW-before-W ordering.
module axi_pre_aw_drain_tb;

  localparam int unsigned HostWriteBufferBytes = 128;
  localparam int unsigned AxiDataBytes = 8;
  localparam int unsigned NumTransactions = HostWriteBufferBytes / AxiDataBytes;
  localparam int unsigned PartialBurstBeats = 32;
  localparam logic [31:0] BaseAddress = 32'h8000_6800;
  localparam logic [31:0] PartialBaseAddress = 32'h8000_7000;

  bit partial_w_fifo_full;
  bit partial_flush_busy;
  bit partial_w_done;

  fixture_hyperbus #(
      .NumConnectedChips   ( 2                      ),
      .NumPhys             ( 2                      ),
      .DutVariant          ( 1                      ),
      .HostWriteBufferBytes( HostWriteBufferBytes    ),
      .SysClkPeriod        ( 10ns                   ),
      .AnnotateSdf         ( 1'b1                   )
  ) fix ();

  task automatic apply_default_mapping();
    logic [31:0] status;
    logic error;

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

    repeat (4) @(posedge fix.sys_clk);
    for (int unsigned poll = 0; poll < 1000; poll++) begin
      fix.i_rmaster.send_read(32'h010, status, error);
      if (error) $fatal(1, "configuration status read failed");
      if (!status[1]) return;
    end
    $fatal(1, "configuration APPLY did not become idle");
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

  initial begin
    logic [31:0] status;
    logic error;

    fix.reset_end();
    apply_default_mapping();

    // Fill all 16 entries of the 128-byte host W FIFO without presenting AW.
    for (int unsigned transaction = 0; transaction < NumTransactions; transaction++) begin
      fix.w_beat.w_data = 64'hd15e_a5e5_0000_0000 ^
                          (BaseAddress + transaction * AxiDataBytes);
      fix.w_beat.w_strb = '1;
      fix.w_beat.w_last = 1'b1;
      fix.axi_master_drv.send_w(fix.w_beat);
    end

    // Start the existing flush barrier, then verify it remains busy until the
    // matching AW requests have made the buffered W beats actionable.
    fix.i_rmaster.send_write(32'h00c, 32'h1, '1, error);
    if (error) $fatal(1, "configuration FLUSH write failed");
    for (int unsigned poll = 0; poll < 100; poll++) begin
      fix.i_rmaster.send_read(32'h010, status, error);
      if (error) $fatal(1, "configuration status read failed");
      if (status[1]) break;
      if (poll == 99) $fatal(1, "configuration FLUSH did not enter drain state");
    end

    // Pair each AW with its B response to avoid filling the serializer's
    // bounded write-ID queue while the drain is still active.
    for (int unsigned transaction = 0; transaction < NumTransactions; transaction++) begin
      fix.aw_beat.ax_addr  = BaseAddress + transaction * AxiDataBytes;
      fix.aw_beat.ax_id    = transaction + 1;
      fix.aw_beat.ax_len   = '0;
      fix.aw_beat.ax_size  = 3;
      fix.aw_beat.ax_burst = axi_pkg::BURST_INCR;
      fix.aw_beat.ax_atop  = '0;
      fix.axi_master_drv.send_aw(fix.aw_beat);
      fix.axi_master_drv.recv_b(fix.b_beat);
      if ((fix.b_beat.b_resp != axi_pkg::RESP_OKAY) ||
          (fix.b_beat.b_id != transaction + 1)) begin
        $fatal(1, "write %0d returned id=%0d resp=%0d", transaction,
               fix.b_beat.b_id, fix.b_beat.b_resp);
      end
    end

    wait_barrier_idle();

    for (int unsigned transaction = 0; transaction < NumTransactions; transaction++) begin
      fix.ar_beat.ax_addr  = BaseAddress + transaction * AxiDataBytes;
      fix.ar_beat.ax_id    = transaction + 1;
      fix.ar_beat.ax_len   = '0;
      fix.ar_beat.ax_size  = 3;
      fix.ar_beat.ax_burst = axi_pkg::BURST_INCR;
      fix.axi_master_drv.send_ar(fix.ar_beat);
      fix.axi_master_drv.recv_r(fix.r_beat);
      if ((fix.r_beat.r_resp != axi_pkg::RESP_OKAY) || !fix.r_beat.r_last ||
          (fix.r_beat.r_data != (64'hd15e_a5e5_0000_0000 ^
                                 (BaseAddress + transaction * AxiDataBytes)))) begin
        $fatal(1, "read %0d returned data=0x%016x last=%0b resp=%0d", transaction,
               fix.r_beat.r_data, fix.r_beat.r_last, fix.r_beat.r_resp);
      end
    end

    // Start a burst longer than the host W FIFO before presenting its AW.  The
    // sender must stop at the 16-beat FIFO capacity while the flush barrier is
    // entered, then resume only after the matching AW is accepted.
    partial_w_fifo_full = 1'b0;
    partial_flush_busy   = 1'b0;
    partial_w_done       = 1'b0;
    fork
      begin : send_partial_w_burst
        for (int unsigned beat = 0; beat < PartialBurstBeats; beat++) begin
          fix.w_beat.w_data = 64'hd15e_a5e5_0000_0000 ^
                              (PartialBaseAddress + beat * AxiDataBytes);
          fix.w_beat.w_strb = '1;
          fix.w_beat.w_last = (beat == PartialBurstBeats - 1);
          fix.axi_master_drv.send_w(fix.w_beat);
          if (beat + 1 == NumTransactions) partial_w_fifo_full = 1'b1;
        end
        partial_w_done = 1'b1;
      end
      begin : flush_partial_w_burst
        logic [31:0] partial_status;
        logic partial_error;

        wait (partial_w_fifo_full);
        repeat (2) @(posedge fix.sys_clk);
        if (fix.axi_dv.w_ready !== 1'b0) begin
          $fatal(1, "partial W burst did not reach FIFO backpressure");
        end

        fix.i_rmaster.send_write(32'h00c, 32'h1, '1, partial_error);
        if (partial_error) $fatal(1, "partial configuration FLUSH write failed");
        for (int unsigned poll = 0; poll < 100; poll++) begin
          fix.i_rmaster.send_read(32'h010, partial_status, partial_error);
          if (partial_error) $fatal(1, "partial configuration status read failed");
          if (partial_status[1]) begin
            partial_flush_busy = 1'b1;
            break;
          end
        end
        if (!partial_flush_busy) begin
          $fatal(1, "partial configuration FLUSH did not enter drain state");
        end
      end
    join_none

    wait (partial_flush_busy);
    fix.aw_beat.ax_addr  = PartialBaseAddress;
    fix.aw_beat.ax_id    = 6'd32;
    fix.aw_beat.ax_len   = PartialBurstBeats - 1;
    fix.aw_beat.ax_size  = 3;
    fix.aw_beat.ax_burst = axi_pkg::BURST_INCR;
    fix.aw_beat.ax_atop  = '0;
    fix.axi_master_drv.send_aw(fix.aw_beat);
    fix.axi_master_drv.recv_b(fix.b_beat);
    if ((fix.b_beat.b_resp != axi_pkg::RESP_OKAY) || (fix.b_beat.b_id != 6'd32)) begin
      $fatal(1, "partial write returned id=%0d resp=%0d", fix.b_beat.b_id,
             fix.b_beat.b_resp);
    end
    wait (partial_w_done);
    wait_barrier_idle();

    for (int unsigned beat = 0; beat < PartialBurstBeats; beat++) begin
      fix.ar_beat.ax_addr  = PartialBaseAddress + beat * AxiDataBytes;
      fix.ar_beat.ax_id    = beat + 1;
      fix.ar_beat.ax_len   = '0;
      fix.ar_beat.ax_size  = 3;
      fix.ar_beat.ax_burst = axi_pkg::BURST_INCR;
      fix.axi_master_drv.send_ar(fix.ar_beat);
      fix.axi_master_drv.recv_r(fix.r_beat);
      if ((fix.r_beat.r_resp != axi_pkg::RESP_OKAY) || !fix.r_beat.r_last ||
          (fix.r_beat.r_data != (64'hd15e_a5e5_0000_0000 ^
                                 (PartialBaseAddress + beat * AxiDataBytes)))) begin
        $fatal(1, "partial read %0d returned data=0x%016x last=%0b resp=%0d", beat,
               fix.r_beat.r_data, fix.r_beat.r_last, fix.r_beat.r_resp);
      end
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
