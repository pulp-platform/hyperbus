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
  localparam logic [31:0] BaseAddress = 32'h0000_6800;
  localparam logic [31:0] PartialBaseAddress = 32'h0000_7000;
  // A regular stable-map configuration write starts the automatic drain/apply
  // barrier in point5.  The staged COMMAND/STATUS interface is not enabled.
  localparam logic [31:0] DrainConfigAddr = 32'h410;
  localparam logic [31:0] DrainConfigValue = 32'd350;

  bit complete_config_done;
  bit partial_w_fifo_full;
  bit partial_config_busy;
  bit partial_config_done;
  bit partial_w_done;

  fixture_hyperbus #(
      .NumConnectedChips   ( 2                      ),
      .NumPhys             ( 2                      ),
      .DutVariant          ( 1                      ),
      .HostWriteBufferBytes( HostWriteBufferBytes    ),
      .SysClkPeriod        ( 10ns                   ),
      .AnnotateSdf         ( 1'b1                   )
  ) fix ();

  initial begin
    fix.reset_end();

    // Fill all 16 entries of the 128-byte host W FIFO without presenting AW.
    for (int unsigned transaction = 0; transaction < NumTransactions; transaction++) begin
      fix.w_beat.w_data = 64'hd15e_a5e5_0000_0000 ^
                          (BaseAddress + transaction * AxiDataBytes);
      fix.w_beat.w_strb = '1;
      fix.w_beat.w_last = 1'b1;
      fix.axi_master_drv.send_w(fix.w_beat);
    end

    // Start the automatic configuration barrier, then verify it remains busy until the
    // matching AW requests have made the buffered W beats actionable.
    complete_config_done = 1'b0;
    fork
      begin : config_complete_w_bursts
        logic config_error;
        fix.i_rmaster.send_write(DrainConfigAddr, DrainConfigValue, '1, config_error);
        if (config_error) $fatal(1, "drain configuration write failed");
        complete_config_done = 1'b1;
      end
    join_none
    repeat (4) @(posedge fix.sys_clk);
    if (complete_config_done) begin
      $fatal(1, "drain configuration write completed before buffered W bursts drained");
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

    wait (complete_config_done);

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
    // sender must stop at the 16-beat FIFO capacity while the drain barrier is
    // entered, then resume only after the matching AW is accepted.
    partial_w_fifo_full = 1'b0;
    partial_config_busy   = 1'b0;
    partial_config_done   = 1'b0;
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
      begin : config_partial_w_burst
        logic partial_error;

        wait (partial_w_fifo_full);
        repeat (2) @(posedge fix.sys_clk);
        if (fix.axi_dv.w_ready !== 1'b0) begin
          $fatal(1, "partial W burst did not reach FIFO backpressure");
        end

        partial_config_busy = 1'b1;
        fix.i_rmaster.send_write(DrainConfigAddr, DrainConfigValue, '1, partial_error);
        if (partial_error) $fatal(1, "partial drain configuration write failed");
        partial_config_done = 1'b1;
      end
    join_none

    wait (partial_config_busy);
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
    wait (partial_config_done);

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
