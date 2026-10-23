// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

`timescale 1 ns/1 ps

module hyperbus_pad_delay_direct_tb;
  import hyperbus_tb_pkg::*;

  localparam int unsigned NumPhys = 2;

  logic tick;
  logic rst_n;
  pad_delay_cfg_t cfg;
  logic [NumPhys-1:0][0:0] cs_i, cs_o;
  logic [NumPhys-1:0] ck_i, ck_n_i, rwds_o_i, reset_i;
  logic [NumPhys-1:0] dq_oe_i, rwds_oe_i;
  logic [NumPhys-1:0] dq_oe_o, rwds_oe_o;
  logic [NumPhys-1:0][7:0] dq_o_i;
  logic [NumPhys-1:0] rwds_pad, rwds_dut;
  logic [NumPhys-1:0][7:0] dq_pad, dq_dut;

  hyperbus_pad_delay #(
    .NumPhys            ( NumPhys ),
    .NumConnectedChips  ( 1       ),
    .NumChips           ( 1       )
  ) dut (
    .tick_i       ( tick       ),
    .rst_ni       ( rst_n      ),
    .cfg_i        ( cfg        ),
    .cs_n_i       ( cs_i       ),
    .ck_i         ( ck_i       ),
    .ck_n_i       ( ck_n_i     ),
    .rwds_o_i     ( rwds_o_i   ),
    .dq_o_i       ( dq_o_i     ),
    .reset_n_i    ( reset_i    ),
    .dq_oe_i      ( dq_oe_i    ),
    .rwds_oe_i    ( rwds_oe_i  ),
    .cs_n_o       ( cs_o       ),
    .ck_o         (             ),
    .ck_n_o       (             ),
    .rwds_o_o     (             ),
    .dq_o_o       (             ),
    .reset_n_o    (             ),
    .dq_oe_o      ( dq_oe_o    ),
    .rwds_oe_o    ( rwds_oe_o  ),
    .rwds_i_pad   ( rwds_pad   ),
    .dq_i_pad     ( dq_pad     ),
    .rwds_i       ( rwds_dut  ),
    .dq_i         ( dq_dut     )
  );

  task automatic step_tick();
    #1 tick = ~tick;
    #0.01;
  endtask

  task automatic reset_adapter();
    rst_n = 1'b0;
    #0.01;
    rst_n = 1'b1;
    #0.01;
  endtask

  initial begin
    tick = 1'b0;
    rst_n = 1'b0;
    cfg = '0;
    cs_i = '1;
    ck_i = '0;
    ck_n_i = '1;
    rwds_o_i = '0;
    dq_o_i = '0;
    reset_i = '0;
    dq_oe_i = '0;
    rwds_oe_i = '0;
    rwds_pad = '0;
    dq_pad = '0;

    // N=0 is a live combinational bypass.
    #1;
    rst_n = 1'b1;
    cfg.output_delay_steps = 0;
    cs_i[0][0] = 1'b0;
    #0.01;
    if (cs_o[0][0] !== 1'b0) $fatal(1, "N=0 output timing");

    // N=1 is non-vacuous: a value stable before the next tick appears there.
    // The first step is a posedge; the following N=4 test begins on a negedge.
    cfg.output_delay_steps = 1;
    cs_i[0][0] = 1'b0;
    #0.01;
    if (cs_o[0][0] !== 1'b1) $fatal(1, "N=1 output changed early");
    step_tick();
    if (cs_o[0][0] !== 1'b0) $fatal(1, "N=1 output timing");

    // N=4 must not release early and must release on the fourth tick.
    reset_adapter();
    cfg.output_delay_steps = 4;
    cs_i[0][0] = 1'b0;
    repeat (3) begin
      step_tick();
      if (cs_o[0][0] !== 1'b1) $fatal(1, "N=4 output changed early");
    end
    step_tick();
    if (cs_o[0][0] !== 1'b0) $fatal(1, "N=4 output timing");

    // Input delay uses the same sampled-bundle convention.
    cfg = '0;
    cfg.input_delay_steps = 4;
    dq_pad[1] = 8'hA5;
    rwds_pad[1] = 1'b1;
    repeat (3) begin
      step_tick();
      if ((dq_dut[1] !== 8'h00) || (rwds_dut[1] !== 1'b0))
        $fatal(1, "N=4 input released early");
    end
    step_tick();
    if ((dq_dut[1] !== 8'hA5) || (rwds_dut[1] !== 1'b1))
      $fatal(1, "N=4 input timing");

    // All six-bit delay values are legal; exercise the maximum output delay.
    reset_adapter();
    cfg = '0;
    cfg.output_delay_steps = 63;
    cs_i[0][0] = 1'b0;
    repeat (62) begin
      step_tick();
      if (cs_o[0][0] !== 1'b1) $fatal(1, "N=63 output released early");
    end
    step_tick();
    if (cs_o[0][0] !== 1'b0) $fatal(1, "N=63 output timing");

    // Zero-delay assertion is combinational and catches up in the next tick.
    cfg = '0;
    cfg.dq_oe_release_steps = 4;
    dq_oe_i = 2'b01;
    #0.01;
    if (dq_oe_o !== 2'b01) $fatal(1, "zero-delay OE assertion");
    step_tick();
    if (dq_oe_o !== 2'b01) $fatal(1, "zero-delay OE state catch-up");

    // A zero-delay rise followed by a non-zero release before the first tick
    // must remain visible while the complete release countdown runs.
    reset_adapter();
    cfg = '0;
    cfg.dq_oe_assert_steps = 0;
    cfg.dq_oe_release_steps = 4;
    dq_oe_i = '0;
    #0.01;
    dq_oe_i[0] = 1'b1;
    #0.01;
    dq_oe_i[0] = 1'b0;
    #0.01;
    if (dq_oe_o[0] !== 1'b1) $fatal(1, "mixed DQ rise was not immediate");
    repeat (4) begin
      if (dq_oe_o[0] !== 1'b1) $fatal(1, "mixed DQ release started early");
      step_tick();
    end
    if (dq_oe_o[0] !== 1'b0) $fatal(1, "mixed DQ release timing");

    // Mirror the mixed reversal: a zero-delay release followed by a delayed
    // assertion must stay released until the full assertion delay elapses.
    reset_adapter();
    cfg = '0;
    cfg.dq_oe_assert_steps = 4;
    cfg.dq_oe_release_steps = 0;
    dq_oe_i = '0;
    #0.01;
    dq_oe_i[0] = 1'b1;
    repeat (4) step_tick();
    if (dq_oe_o[0] !== 1'b1) $fatal(1, "DQ setup for mixed release failed");
    dq_oe_i[0] = 1'b0;
    #0.01;
    dq_oe_i[0] = 1'b1;
    #0.01;
    if (dq_oe_o[0] !== 1'b0) $fatal(1, "mixed DQ release was not immediate");
    repeat (4) begin
      if (dq_oe_o[0] !== 1'b0) $fatal(1, "mixed DQ assertion started early");
      step_tick();
    end
    if (dq_oe_o[0] !== 1'b1) $fatal(1, "mixed DQ assertion timing");

    // Exercise the same two mixed-delay reversals on the RWDS ownership
    // control, independently of DQ.
    reset_adapter();
    cfg = '0;
    cfg.rwds_oe_assert_steps = 0;
    cfg.rwds_oe_release_steps = 4;
    rwds_oe_i = '0;
    #0.01;
    rwds_oe_i[0] = 1'b1;
    #0.01;
    rwds_oe_i[0] = 1'b0;
    #0.01;
    if (rwds_oe_o[0] !== 1'b1) $fatal(1, "mixed RWDS rise was not immediate");
    repeat (4) begin
      if (rwds_oe_o[0] !== 1'b1) $fatal(1, "mixed RWDS release started early");
      step_tick();
    end
    if (rwds_oe_o[0] !== 1'b0) $fatal(1, "mixed RWDS release timing");

    reset_adapter();
    cfg = '0;
    cfg.rwds_oe_assert_steps = 4;
    cfg.rwds_oe_release_steps = 0;
    rwds_oe_i = '0;
    #0.01;
    rwds_oe_i[0] = 1'b1;
    repeat (4) step_tick();
    if (rwds_oe_o[0] !== 1'b1) $fatal(1, "RWDS setup for mixed release failed");
    rwds_oe_i[0] = 1'b0;
    #0.01;
    rwds_oe_i[0] = 1'b1;
    #0.01;
    if (rwds_oe_o[0] !== 1'b0) $fatal(1, "mixed RWDS release was not immediate");
    repeat (4) begin
      if (rwds_oe_o[0] !== 1'b0) $fatal(1, "mixed RWDS assertion started early");
      step_tick();
    end
    if (rwds_oe_o[0] !== 1'b1) $fatal(1, "mixed RWDS assertion timing");

    // Independent lanes: lane 0 reverses while lane 1 completes assertion.
    cfg.dq_oe_assert_steps = 4;
    cfg.dq_oe_release_steps = 4;
    dq_oe_i = 2'b11;
    repeat (3) step_tick();
    dq_oe_i[0] = 1'b0;
    step_tick();
    if (dq_oe_o[1] !== 1'b1) $fatal(1, "lane 1 OE was cancelled");
    if (dq_oe_o[0] !== 1'b1) $fatal(1, "lane 0 OE released early");
    dq_oe_i[0] = 1'b1;
    repeat (4) step_tick();
    if (dq_oe_o !== 2'b11) $fatal(1, "OE reversal cancellation");

    // Completed release and independent RWDS OE timing.
    dq_oe_i = '0;
    repeat (3) begin
      step_tick();
      if (dq_oe_o !== 2'b11) $fatal(1, "OE release completed early");
    end
    step_tick();
    if (dq_oe_o !== 2'b00) $fatal(1, "OE release timing");
    cfg.rwds_oe_assert_steps = 4;
    cfg.rwds_oe_release_steps = 4;
    rwds_oe_i = 2'b11;
    repeat (4) step_tick();
    if (rwds_oe_o !== 2'b11) $fatal(1, "RWDS OE assertion timing");
    rwds_oe_i[0] = 1'b0;
    step_tick();
    rwds_oe_i[0] = 1'b1;
    repeat (4) step_tick();
    if (rwds_oe_o !== 2'b11) $fatal(1, "RWDS OE reversal cancellation");
    rwds_oe_i = '0;
    repeat (3) begin
      step_tick();
      if (rwds_oe_o !== 2'b11) $fatal(1, "RWDS OE release completed early");
    end
    step_tick();
    if (rwds_oe_o !== 2'b00) $fatal(1, "RWDS OE release timing");

    // Reset cancels a pending transition and clears all delayed state.
    cfg = '0;
    cfg.dq_oe_assert_steps = 63;
    dq_oe_i = 2'b01;
    step_tick();
    reset_adapter();
    if (dq_oe_o !== 2'b00) $fatal(1, "reset did not clear OE");
    repeat (62) begin
      step_tick();
      if (dq_oe_o !== 2'b00) $fatal(1, "stale OE survived reset");
    end
    step_tick();
    if (dq_oe_o !== 2'b01) $fatal(1, "post-reset OE timing");

    $display("[PAD-LATENCY] direct pad delay check passed");
    $finish;
  end
endmodule
