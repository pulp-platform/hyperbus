// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

`timescale 1 ns/1 ps

module axi_hyper_pad_delay_tb
  import axi_pkg::*;
#(
  parameter int unsigned NumConnectedChips = 1,
  parameter int unsigned NumPhys = 2,
  parameter time         TbCyclTime = 4ns,
  parameter time         TbInitialDelay = 500ns,
  parameter int unsigned TbRxDelayLineTaps = 16,
  parameter int unsigned TbRwdsSampleDelay = 0,
  parameter int unsigned TbTxDelayLineTaps = 16,
  parameter bit          TbReadOnly = 1'b0,
  parameter int unsigned TbCsnToCkCycles = 0,
  parameter int unsigned TbRwdsOeSetupCycles = 1,
  parameter int unsigned TbExpectedRwdsOeWaitCycles = 0,
  parameter int unsigned TbReadWriteRecovery = 6,
  parameter bit          TbAssumeAdditionalLatency = 1'b0,
  // cfg0[11] selects fixed latency; 16'h871f is variable latency with no extra request.
  parameter logic [15:0] TbModelCfg0ResetValue = 16'h8f1f,
  parameter int unsigned TbModelLatencyPolicy = 0,
  parameter int unsigned TbExpectedModelExtraLatencyTransactions = 0,
  parameter logic [31:0] TbBaseAddr = 32'h8000_0000,
  parameter bit          TbVerbose = 1'b0,
  parameter int unsigned TimeoutCycles = 100000
);
  import hyperbus_tb_pkg::*;
  `include "axi/typedef.svh"
  `include "axi/assign.svh"

  localparam int unsigned AxiAddrWidth = 32;
  localparam int unsigned AxiDataWidth = 64;
  localparam int unsigned AxiIdWidth   = 7;
  localparam int unsigned AxiUserWidth = 1;
  localparam int unsigned RegBusAW     = 12;
  localparam int unsigned RegBusDW     = 32;

  typedef logic [AxiAddrWidth-1:0] axi_addr_t;
  typedef axi_pkg::xbar_rule_32_t  rule_t;

  logic clk;
  logic rst_n;
  logic end_of_sim;
  logic [31:0] segment_start_count;
  logic [3:0] phy_state_mon;
  logic [15:0] phy_timer_mon;
  logic [3:0] rwds_sample_countdown_mon;
  logic       rwds_sample_ena_mon;
  logic [2:0] cfg_chip_idx_mon;
  logic       ck_quarter_prev;
  int unsigned rwds_wait_cycles;
  int unsigned rwds_sample_pulse_count;
  int unsigned sample_reload_count;
  int unsigned sample_reload_mismatch_count;
  int unsigned ck_hold_quarters;
  int unsigned ck_max_hold_quarters;
  logic [3:0] rwds_sample_delay_expected [hyperbus_pkg::HyperNumChips];
  pad_delay_cfg_t pad_delay_cfg;

  // A normal HyperBus CK edge interval spans two edges of the 2x model clock.
  localparam int unsigned NormalCkEdgeIntervalQuarters = 2;

  AXI_BUS #(
    .AXI_ADDR_WIDTH ( AxiAddrWidth ),
    .AXI_DATA_WIDTH ( AxiDataWidth ),
    .AXI_ID_WIDTH   ( AxiIdWidth   ),
    .AXI_USER_WIDTH ( AxiUserWidth )
  ) axi_bus ();

  REG_BUS #(
    .ADDR_WIDTH ( RegBusAW ),
    .DATA_WIDTH ( RegBusDW )
  ) reg_bus (
    .clk_i ( clk )
  );

  dut_if #(
    .TbTestTime      ( TbCyclTime - 1ps ),
    .HyperRamModelCfg0ResetValue ( TbModelCfg0ResetValue ),
    .HyperRamModelLatencyPolicy  ( TbModelLatencyPolicy  ),
    .AxiDataWidth    ( AxiDataWidth     ),
    .AxiAddrWidth    ( AxiAddrWidth     ),
    .AxiIdWidth      ( AxiIdWidth       ),
    .AxiUserWidth    ( AxiUserWidth     ),
    .RegAw           ( RegBusAW         ),
    .RegDw           ( RegBusDW         ),
    .NumConnectedChips ( NumConnectedChips ),
    .NumPhys         ( NumPhys          ),
    .AnnotateSdf     ( 1'b0             ),
    .UseBehavioralHyperRamModel ( 1'b1  ),
    .HyperRamModelProtocolCheckSeverity ( 3 ),
    .IsClockODelayed ( 0                ),
    .DutVariant      ( 1                 ),
    .PhyCyclTime     ( TbCyclTime        ),
    .HyperRamModelRefCyclTime ( TbCyclTime ),
    .axi_rule_t      ( rule_t           )
  ) i_dut_if (
    .clk_i                 ( clk                 ),
    .rst_ni                ( rst_n               ),
    .end_sim_i             ( end_of_sim          ),
    .segment_start_count_o ( segment_start_count ),
    .pad_delay_cfg_i       ( pad_delay_cfg        ),
    .axi_slv_if            ( axi_bus             ),
    .reg_slv_if            ( reg_bus             )
  );

  // Monitor the lane carrying the smoke transaction directly at the PHY FSM.
  // Keep both topologies elaboratable for single- and dual-PHY configurations.
  if (NumPhys == 2) begin : gen_wait_monitor_dual
    assign phy_state_mon =
        i_dut_if.i_dut.gen_synchronous.i_dut.i_backend.gen_dual_phy.gen_phy[0].i_phy.state_q;
    assign phy_timer_mon =
        i_dut_if.i_dut.gen_synchronous.i_dut.i_backend.gen_dual_phy.gen_phy[0].i_phy.timer_q;
    assign rwds_sample_countdown_mon =
        i_dut_if.i_dut.gen_synchronous.i_dut.i_backend.gen_dual_phy.gen_phy[0].i_phy.rwds_sample_countdown_q;
    assign rwds_sample_ena_mon =
        i_dut_if.i_dut.gen_synchronous.i_dut.i_backend.gen_dual_phy.gen_phy[0].i_phy.ctl_rwds_sample;
    assign cfg_chip_idx_mon =
        i_dut_if.i_dut.gen_synchronous.i_dut.i_backend.gen_dual_phy.gen_phy[0].i_phy.cfg_chip_idx;
  end else begin : gen_wait_monitor_single
    assign phy_state_mon =
        i_dut_if.i_dut.gen_synchronous.i_dut.i_backend.gen_single_phy.i_phy.state_q;
    assign phy_timer_mon =
        i_dut_if.i_dut.gen_synchronous.i_dut.i_backend.gen_single_phy.i_phy.timer_q;
    assign rwds_sample_countdown_mon =
        i_dut_if.i_dut.gen_synchronous.i_dut.i_backend.gen_single_phy.i_phy.rwds_sample_countdown_q;
    assign rwds_sample_ena_mon =
        i_dut_if.i_dut.gen_synchronous.i_dut.i_backend.gen_single_phy.i_phy.ctl_rwds_sample;
    assign cfg_chip_idx_mon =
        i_dut_if.i_dut.gen_synchronous.i_dut.i_backend.gen_single_phy.i_phy.cfg_chip_idx;
  end

  always @(posedge clk) begin
    if (!rst_n) begin
      rwds_wait_cycles <= 0;
      rwds_sample_pulse_count <= 0;
      sample_reload_count <= 0;
      sample_reload_mismatch_count <= 0;
    end else if (phy_state_mon == hyperbus_pkg::WaitRwdsOe) begin
      rwds_wait_cycles <= rwds_wait_cycles + 1;
    end
    if (rst_n) begin
      if (rwds_sample_ena_mon) begin
        rwds_sample_pulse_count <= rwds_sample_pulse_count + 1;
      end
      if ((phy_state_mon == hyperbus_pkg::SendCA) && (phy_timer_mon == 16'd2)) begin
        sample_reload_count <= sample_reload_count + 1;
        if (rwds_sample_countdown_mon != rwds_sample_delay_expected[cfg_chip_idx_mon]) begin
          sample_reload_mismatch_count <= sample_reload_mismatch_count + 1;
        end
      end
    end
  end

  // Observe CK at quarter-cycle resolution while chip select is active.
  always @(posedge i_dut_if.hyperram_model_clk_2x or
           negedge i_dut_if.hyperram_model_clk_2x) begin
    if (!rst_n) begin
      ck_quarter_prev = i_dut_if.hyper_ck_wire[0];
      ck_hold_quarters = 0;
      ck_max_hold_quarters = 0;
    end else if (!i_dut_if.hyper_cs_n_wire[0][0]) begin
      if (i_dut_if.hyper_ck_wire[0] == ck_quarter_prev) begin
        ck_hold_quarters = ck_hold_quarters + 1;
      end else begin
        if (ck_hold_quarters > ck_max_hold_quarters) begin
          ck_max_hold_quarters = ck_hold_quarters;
        end
        ck_hold_quarters = 0;
      end
      ck_quarter_prev = i_dut_if.hyper_ck_wire[0];
    end
  end

  // Finalize a stopped interval when CS# returns high.
  always @(posedge i_dut_if.hyper_cs_n_wire[0][0]) begin
    if (ck_hold_quarters > ck_max_hold_quarters) begin
      ck_max_hold_quarters = ck_hold_quarters;
    end
    ck_hold_quarters = 0;
  end

  initial begin
    clk = 1'b0;
    #(10 * TbCyclTime);
    forever #(TbCyclTime / 2) clk = ~clk;
  end

  task automatic init_bus();
    axi_bus.aw_id     = '0;
    axi_bus.aw_addr   = '0;
    axi_bus.aw_len    = '0;
    axi_bus.aw_size   = '0;
    axi_bus.aw_burst  = axi_pkg::BURST_INCR;
    axi_bus.aw_lock   = 1'b0;
    axi_bus.aw_cache  = '0;
    axi_bus.aw_prot   = '0;
    axi_bus.aw_qos    = '0;
    axi_bus.aw_region = '0;
    axi_bus.aw_atop   = '0;
    axi_bus.aw_user   = '0;
    axi_bus.aw_valid  = 1'b0;
    axi_bus.w_data    = '0;
    axi_bus.w_strb    = '0;
    axi_bus.w_last    = 1'b0;
    axi_bus.w_user    = '0;
    axi_bus.w_valid   = 1'b0;
    axi_bus.b_ready   = 1'b0;
    axi_bus.ar_id     = '0;
    axi_bus.ar_addr   = '0;
    axi_bus.ar_len    = '0;
    axi_bus.ar_size   = '0;
    axi_bus.ar_burst  = axi_pkg::BURST_INCR;
    axi_bus.ar_lock   = 1'b0;
    axi_bus.ar_cache  = '0;
    axi_bus.ar_prot   = '0;
    axi_bus.ar_qos    = '0;
    axi_bus.ar_region = '0;
    axi_bus.ar_user   = '0;
    axi_bus.ar_valid  = 1'b0;
    axi_bus.r_ready   = 1'b0;

    reg_bus.addr      = '0;
    reg_bus.write     = 1'b0;
    reg_bus.wdata     = '0;
    reg_bus.wstrb     = '0;
    reg_bus.valid     = 1'b0;
  endtask

  task automatic reg_write(input logic [RegBusAW-1:0] addr, input logic [RegBusDW-1:0] data);
    @(negedge clk);
    reg_bus.addr  = addr;
    reg_bus.write = 1'b1;
    reg_bus.wdata = data;
    reg_bus.wstrb = '1;
    reg_bus.valid = 1'b1;
    for (int unsigned i = 0; i < TimeoutCycles; i++) begin
      @(posedge clk);
      if (reg_bus.valid && reg_bus.ready) begin
        @(negedge clk);
        reg_bus.valid = 1'b0;
        if (reg_bus.error) $fatal(1, "[REG] write to 0x%02x returned error", addr);
        return;
      end
    end
    $fatal(1, "[REG] write to 0x%02x timed out", addr);
  endtask

  task automatic reg_read(input logic [RegBusAW-1:0] addr,
                          output logic [RegBusDW-1:0] data);
    @(negedge clk);
    reg_bus.addr  = addr;
    reg_bus.write = 1'b0;
    reg_bus.wdata = '0;
    reg_bus.wstrb = '0;
    reg_bus.valid = 1'b1;
    for (int unsigned i = 0; i < TimeoutCycles; i++) begin
      @(posedge clk);
      if (reg_bus.valid && reg_bus.ready) begin
        data = reg_bus.rdata;
        @(negedge clk);
        reg_bus.valid = 1'b0;
        if (reg_bus.error) $fatal(1, "[REG] read from 0x%03x returned error", addr);
        return;
      end
    end
    $fatal(1, "[REG] read from 0x%03x timed out", addr);
  endtask

  task automatic apply_config();
    logic [RegBusDW-1:0] status;
    reg_write(12'h00c, 32'h2);
    for (int unsigned i = 0; i < TimeoutCycles; i++) begin
      reg_read(12'h010, status);
      if (!status[1]) return;
    end
    $fatal(1, "[REG] configuration APPLY did not clear busy");
  endtask

  task automatic print_model_status(input string label);
    $display("[PAD-LATENCY:%s] segments=%0d cs_n=%0b ck=%0b rwds=%0b dq=%02x",
             label,
             segment_start_count,
             i_dut_if.hyper_cs_n_wire[0][0],
             i_dut_if.hyper_ck_wire[0],
             i_dut_if.hyper_rwds_i[0],
             i_dut_if.hyper_dq_i[0]);
    $display("[PAD-LATENCY:%s] rd_txn=%0d wr_txn=%0d rd_words=%0d wr_words=%0d",
             label,
             i_dut_if.hyperrams[0].chips[0].gen_behavioral_model.metrics.read_transactions,
             i_dut_if.hyperrams[0].chips[0].gen_behavioral_model.metrics.write_transactions,
             i_dut_if.hyperrams[0].chips[0].gen_behavioral_model.metrics.read_words,
             i_dut_if.hyperrams[0].chips[0].gen_behavioral_model.metrics.write_words);
    $display("[PAD-LATENCY:%s] model_extra_latency_transactions=%0d",
             label,
             i_dut_if.hyperrams[0].chips[0].gen_behavioral_model.metrics.extra_latency_transactions);
    $display("[PAD-LATENCY:%s] clock_stop_quarters=%0d",
             label,
             i_dut_if.hyperrams[0].chips[0].gen_behavioral_model.metrics.clock_stop_quarters);
    $display("[PAD-LATENCY:%s] rwds_wait_cycles=%0d expected=%0d",
             label,
             rwds_wait_cycles,
             TbExpectedRwdsOeWaitCycles);
  endtask

  task automatic check_rwds_wait();
    if (rwds_wait_cycles != TbExpectedRwdsOeWaitCycles) begin
      $fatal(1, "[PAD-LATENCY] setup=%0d produced %0d WaitRwdsOe cycles, expected %0d",
             TbRwdsOeSetupCycles, rwds_wait_cycles, TbExpectedRwdsOeWaitCycles);
    end
  endtask

  task automatic check_model_extra_latency();
    if (i_dut_if.hyperrams[0].chips[0].gen_behavioral_model.metrics.extra_latency_transactions !=
        TbExpectedModelExtraLatencyTransactions) begin
      $fatal(1, "[PAD-LATENCY] expected %0d model extra-latency transactions, saw %0d",
             TbExpectedModelExtraLatencyTransactions,
             i_dut_if.hyperrams[0].chips[0].gen_behavioral_model.metrics.extra_latency_transactions);
    end
  endtask

  always @(i_dut_if.hyper_cs_n_wire[0][0] or
           i_dut_if.hyper_ck_wire[0] or
           i_dut_if.hyper_dq_oe[0] or
           i_dut_if.hyper_rwds_oe[0] or
           i_dut_if.hyper_dq_oe_pad[0] or
           i_dut_if.hyper_rwds_oe_pad[0] or
           i_dut_if.hyper_dq_o[0] or
           i_dut_if.pad_hyper_dq[0]) begin
    if (TbVerbose && rst_n && !end_of_sim) begin
      $display("[PAD-LATENCY:PINS] time=%0t cs_n=%0b ck=%0b dq_oe=%0b/%0b rwds_oe=%0b/%0b dq_o=%02x dq=%02x state=%0d latency=%0d/%0d",
               $realtime,
               i_dut_if.hyper_cs_n_wire[0][0],
               i_dut_if.hyper_ck_wire[0],
               i_dut_if.hyper_dq_oe[0],
               i_dut_if.hyper_dq_oe_pad[0],
               i_dut_if.hyper_rwds_oe[0],
               i_dut_if.hyper_rwds_oe_pad[0],
               i_dut_if.hyper_dq_o[0],
               i_dut_if.pad_hyper_dq[0],
               i_dut_if.hyperrams[0].chips[0].gen_behavioral_model.dut.state_q,
               i_dut_if.hyperrams[0].chips[0].gen_behavioral_model.dut.latency_count_q,
               i_dut_if.hyperrams[0].chips[0].gen_behavioral_model.dut.latency_target);
    end
  end

  always @(posedge clk) begin
    if (TbVerbose && rst_n &&
        i_dut_if.i_dut.gen_synchronous.i_dut.backend_req.tx_valid &&
        i_dut_if.i_dut.gen_synchronous.i_dut.backend_rsp.tx_ready) begin
      $display("[PAD-LATENCY:TX] time=%0t data=%08x last=%0b",
               $realtime,
               i_dut_if.i_dut.gen_synchronous.i_dut.backend_req.tx.data,
               i_dut_if.i_dut.gen_synchronous.i_dut.backend_req.tx.last);
    end
    if (TbVerbose && rst_n &&
        i_dut_if.i_dut.gen_synchronous.i_dut.backend_rsp.rx_valid &&
        i_dut_if.i_dut.gen_synchronous.i_dut.backend_req.rx_ready) begin
      $display("[PAD-LATENCY:RX] time=%0t data=%08x last=%0b",
               $realtime,
               i_dut_if.i_dut.gen_synchronous.i_dut.backend_rsp.rx.data,
               i_dut_if.i_dut.gen_synchronous.i_dut.backend_rsp.rx.last);
    end
  end

  task automatic axi_write64(
    input axi_addr_t addr,
    input logic [AxiDataWidth-1:0] data,
    input logic [AxiDataWidth/8-1:0] strb
  );
    @(negedge clk);
    axi_bus.aw_id     = '0;
    axi_bus.aw_addr   = addr;
    axi_bus.aw_len    = '0;
    axi_bus.aw_size   = $clog2(AxiDataWidth / 8);
    axi_bus.aw_burst  = axi_pkg::BURST_INCR;
    axi_bus.aw_valid  = 1'b1;

    for (int unsigned i = 0; i < TimeoutCycles; i++) begin
      @(posedge clk);
      if (axi_bus.aw_valid && axi_bus.aw_ready) begin
        @(negedge clk);
        axi_bus.aw_valid = 1'b0;
        break;
      end
      if (i == TimeoutCycles - 1) begin
        $fatal(1, "[AXI] write address handshake for 0x%08x timed out", addr);
      end
    end

    @(negedge clk);
    axi_bus.w_data    = data;
    axi_bus.w_strb    = strb;
    axi_bus.w_last    = 1'b1;
    axi_bus.w_valid   = 1'b1;
    axi_bus.b_ready   = 1'b1;

    for (int unsigned i = 0; i < TimeoutCycles; i++) begin
      @(posedge clk);
      if (axi_bus.w_valid && axi_bus.w_ready) begin
        @(negedge clk);
        axi_bus.w_valid = 1'b0;
        break;
      end
      if (i == TimeoutCycles - 1) begin
        $fatal(1, "[AXI] write data handshake for 0x%08x timed out", addr);
      end
    end

    for (int unsigned i = 0; i < TimeoutCycles; i++) begin
      @(posedge clk);
      if (axi_bus.b_valid && axi_bus.b_ready) begin
        if (axi_bus.b_resp != axi_pkg::RESP_OKAY) begin
          $fatal(1, "[AXI] write to 0x%08x returned response %0d", addr, axi_bus.b_resp);
        end
        @(negedge clk);
        axi_bus.b_ready = 1'b0;
        if (TbVerbose) print_model_status("after-write");
        return;
      end
    end
    print_model_status("write-timeout");
    $fatal(1, "[AXI] write response for 0x%08x timed out", addr);
  endtask

  task automatic axi_read64(input axi_addr_t addr, output logic [AxiDataWidth-1:0] data);
    @(negedge clk);
    axi_bus.ar_id     = '0;
    axi_bus.ar_addr   = addr;
    axi_bus.ar_len    = '0;
    axi_bus.ar_size   = $clog2(AxiDataWidth / 8);
    axi_bus.ar_burst  = axi_pkg::BURST_INCR;
    axi_bus.ar_valid  = 1'b1;
    axi_bus.r_ready   = 1'b1;

    for (int unsigned i = 0; i < TimeoutCycles; i++) begin
      @(posedge clk);
      if (axi_bus.ar_valid && axi_bus.ar_ready) begin
        @(negedge clk);
        axi_bus.ar_valid = 1'b0;
        break;
      end
      if (i == TimeoutCycles - 1) begin
        $fatal(1, "[AXI] read address handshake for 0x%08x timed out", addr);
      end
    end

    for (int unsigned i = 0; i < TimeoutCycles; i++) begin
      @(posedge clk);
      if (axi_bus.r_valid && axi_bus.r_ready) begin
        data = axi_bus.r_data;
        if (axi_bus.r_resp != axi_pkg::RESP_OKAY || !axi_bus.r_last) begin
          $fatal(1, "[AXI] read from 0x%08x returned data=0x%016x last=%0b resp=%0d",
                 addr, axi_bus.r_data, axi_bus.r_last, axi_bus.r_resp);
        end
        @(negedge clk);
        axi_bus.r_ready = 1'b0;
        if (TbVerbose) print_model_status("after-read");
        return;
      end
    end
    print_model_status("read-timeout");
    $fatal(1, "[AXI] read response for 0x%08x timed out", addr);
  endtask

  task automatic axi_write_burst_slow(
    input axi_addr_t addr,
    input int unsigned beats,
    input int unsigned gap_cycles,
    input logic [AxiDataWidth-1:0] seed
  );
    if ((beats == 0) || (beats > 256)) begin
      $fatal(1, "[AXI] unsupported write burst length %0d", beats);
    end

    @(negedge clk);
    axi_bus.aw_id    = '0;
    axi_bus.aw_addr  = addr;
    axi_bus.aw_len   = beats - 1;
    axi_bus.aw_size  = $clog2(AxiDataWidth / 8);
    axi_bus.aw_burst = axi_pkg::BURST_INCR;
    axi_bus.aw_valid = 1'b1;
    for (int unsigned cycle = 0; cycle < TimeoutCycles; cycle++) begin
      @(posedge clk);
      if (axi_bus.aw_valid && axi_bus.aw_ready) begin
        @(negedge clk);
        axi_bus.aw_valid = 1'b0;
        break;
      end
      if (cycle == TimeoutCycles - 1) begin
        $fatal(1, "[AXI] write burst address handshake timed out");
      end
    end

    axi_bus.b_ready = 1'b1;
    for (int unsigned beat = 0; beat < beats; beat++) begin
      repeat (gap_cycles) @(posedge clk);
      @(negedge clk);
      axi_bus.w_data  = seed + AxiDataWidth'(beat);
      axi_bus.w_strb  = '1;
      axi_bus.w_last  = (beat == beats - 1);
      axi_bus.w_valid = 1'b1;
      for (int unsigned cycle = 0; cycle < TimeoutCycles; cycle++) begin
        @(posedge clk);
        if (axi_bus.w_valid && axi_bus.w_ready) begin
          @(negedge clk);
          axi_bus.w_valid = 1'b0;
          break;
        end
        if (cycle == TimeoutCycles - 1) begin
          $fatal(1, "[AXI] write burst data beat %0d timed out", beat);
        end
      end
    end

    for (int unsigned cycle = 0; cycle < TimeoutCycles; cycle++) begin
      @(posedge clk);
      if (axi_bus.b_valid && axi_bus.b_ready) begin
        if (axi_bus.b_resp != axi_pkg::RESP_OKAY) begin
          $fatal(1, "[AXI] write burst returned response %0d", axi_bus.b_resp);
        end
        @(negedge clk);
        axi_bus.b_ready = 1'b0;
        return;
      end
      if (cycle == TimeoutCycles - 1) begin
        $fatal(1, "[AXI] write burst response timed out");
      end
    end
  endtask

  task automatic axi_read_burst_check(
    input axi_addr_t addr,
    input int unsigned beats,
    input logic [AxiDataWidth-1:0] seed
  );
    if ((beats == 0) || (beats > 256)) begin
      $fatal(1, "[AXI] unsupported read burst length %0d", beats);
    end

    @(negedge clk);
    axi_bus.ar_id    = '0;
    axi_bus.ar_addr  = addr;
    axi_bus.ar_len   = beats - 1;
    axi_bus.ar_size  = $clog2(AxiDataWidth / 8);
    axi_bus.ar_burst = axi_pkg::BURST_INCR;
    axi_bus.ar_valid = 1'b1;
    axi_bus.r_ready  = 1'b1;
    for (int unsigned cycle = 0; cycle < TimeoutCycles; cycle++) begin
      @(posedge clk);
      if (axi_bus.ar_valid && axi_bus.ar_ready) begin
        @(negedge clk);
        axi_bus.ar_valid = 1'b0;
        break;
      end
      if (cycle == TimeoutCycles - 1) begin
        $fatal(1, "[AXI] read burst address handshake timed out");
      end
    end

    for (int unsigned beat = 0; beat < beats; beat++) begin
      for (int unsigned cycle = 0; cycle < TimeoutCycles; cycle++) begin
        @(posedge clk);
        if (axi_bus.r_valid && axi_bus.r_ready) begin
          if ((axi_bus.r_resp != axi_pkg::RESP_OKAY) ||
              (axi_bus.r_data != seed + AxiDataWidth'(beat)) ||
              (axi_bus.r_last != (beat == beats - 1))) begin
            $fatal(1, "[AXI] read burst beat %0d mismatch data=0x%016x last=%0b resp=%0d",
                   beat, axi_bus.r_data, axi_bus.r_last, axi_bus.r_resp);
          end
          break;
        end
        if (cycle == TimeoutCycles - 1) begin
          $fatal(1, "[AXI] read burst beat %0d timed out", beat);
        end
      end
    end
    @(negedge clk);
    axi_bus.r_ready = 1'b0;
  endtask

  task automatic configure_chip(
    input int unsigned chip,
    input axi_addr_t base_addr,
    input axi_addr_t bound_addr,
    input logic [3:0] sample_delay
  );
    logic [11:0] offset;
    offset = 12'h400 + chip * 12'h40;
    rwds_sample_delay_expected[chip] = sample_delay;
    reg_write(offset + 12'h000, base_addr);
    reg_write(offset + 12'h004, bound_addr);
    reg_write(offset + 12'h008, 32'h0001_1900);
    reg_write(offset + 12'h00c, (sample_delay << 8) | 32'd6);
    reg_write(offset + 12'h014, (8'd1 << 8) | 32'd6);
    reg_write(offset + 12'h018, TbRxDelayLineTaps);
  endtask

  task automatic configure_phy_lane(
    input int unsigned phy,
    input int unsigned rwds_setup_cycles
  );
    logic [11:0] offset;
    offset = 12'h300 + phy * 12'h40;
    reg_write(offset, TbTxDelayLineTaps);
    reg_write(offset + 12'h004, rwds_setup_cycles);
  endtask

  initial begin
    logic [AxiDataWidth-1:0] rdata;
    int unsigned pad_steps;
    int unsigned read_write_recovery;
    int unsigned rwds_sample_delay;
    int unsigned segment_snapshot;
    int unsigned sample_snapshot;
    int unsigned pulse_snapshot;
    logic [RegBusDW-1:0] config_readback;
    string scenario;
    localparam axi_addr_t BaseAddr = axi_addr_t'(TbBaseAddr);
    localparam int unsigned ExpectedSegmentStarts = 8;

    scenario = "baseline";
    void'($value$plusargs("scenario=%s", scenario));
    for (int unsigned chip = 0; chip < hyperbus_pkg::HyperNumChips; chip++) begin
      rwds_sample_delay_expected[chip] = '0;
    end
    pad_delay_cfg = '0;
    if ($value$plusargs("pad_out_q=%d", pad_steps)) begin
      if (pad_steps > 63) $fatal(1, "[PAD-LATENCY] pad_out_q must be in 0..63");
      pad_delay_cfg.output_delay_steps = pad_steps[5:0];
    end
    if ($value$plusargs("pad_in_q=%d", pad_steps)) begin
      if (pad_steps > 63) $fatal(1, "[PAD-LATENCY] pad_in_q must be in 0..63");
      pad_delay_cfg.input_delay_steps = pad_steps[5:0];
    end
    if ($value$plusargs("dq_oe_assert_q=%d", pad_steps)) begin
      if (pad_steps > 63) $fatal(1, "[PAD-LATENCY] dq_oe_assert_q must be in 0..63");
      pad_delay_cfg.dq_oe_assert_steps = pad_steps[5:0];
    end
    if ($value$plusargs("dq_oe_release_q=%d", pad_steps)) begin
      if (pad_steps > 63) $fatal(1, "[PAD-LATENCY] dq_oe_release_q must be in 0..63");
      pad_delay_cfg.dq_oe_release_steps = pad_steps[5:0];
    end
    if ($value$plusargs("rwds_oe_assert_q=%d", pad_steps)) begin
      if (pad_steps > 63) $fatal(1, "[PAD-LATENCY] rwds_oe_assert_q must be in 0..63");
      pad_delay_cfg.rwds_oe_assert_steps = pad_steps[5:0];
    end
    if ($value$plusargs("rwds_oe_release_q=%d", pad_steps)) begin
      if (pad_steps > 63) $fatal(1, "[PAD-LATENCY] rwds_oe_release_q must be in 0..63");
      pad_delay_cfg.rwds_oe_release_steps = pad_steps[5:0];
    end
    read_write_recovery = TbReadWriteRecovery;
    if ($value$plusargs("t_read_write_recovery=%d", pad_steps)) begin
      if (pad_steps > 15) $fatal(1, "[PAD-LATENCY] t_read_write_recovery must be in 0..15");
      read_write_recovery = pad_steps;
    end
    rwds_sample_delay = TbRwdsSampleDelay;
    if ($value$plusargs("rwds_sample_q=%d", pad_steps)) begin
      if (pad_steps > 15) $fatal(1, "[PAD-LATENCY] rwds_sample_q must be in 0..15");
      rwds_sample_delay = pad_steps;
    end
    $display("[PAD-LATENCY] out=%0d in=%0d dq_oe=%0d/%0d rwds_oe=%0d/%0d",
             pad_delay_cfg.output_delay_steps,
             pad_delay_cfg.input_delay_steps,
             pad_delay_cfg.dq_oe_assert_steps,
             pad_delay_cfg.dq_oe_release_steps,
             pad_delay_cfg.rwds_oe_assert_steps,
             pad_delay_cfg.rwds_oe_release_steps);

    end_of_sim = 1'b0;
    rst_n = 1'b0;
    init_bus();

    repeat (8) @(posedge clk);
    #(TbCyclTime / 8);
    rst_n = 1'b1;
    repeat (8) @(posedge clk);

    if (scenario != "baseline") begin
      if (scenario == "segment_restart") begin
        $display("[PAD-LATENCY] segment restart scenario");
        configure_chip(0, BaseAddr, BaseAddr + 32'h0040_0000, 4'd1);
        configure_phy_lane(0, 1);
        reg_write(12'h410, 32'd64);
        apply_config();
        reg_read(12'h40c, config_readback);
        if ((config_readback[15:8] != 8'd1) || (config_readback[7:0] != 8'd6)) begin
          $fatal(1, "[PAD-LATENCY] latency config readback mismatch: 0x%08x", config_readback);
        end
        reg_read(12'h410, config_readback);
        if (config_readback[15:0] != 16'd64) begin
          $fatal(1, "[PAD-LATENCY] t_burst_max readback mismatch: 0x%08x", config_readback);
        end
        #(TbInitialDelay);
        segment_snapshot = segment_start_count;
        sample_snapshot = sample_reload_count;
        pulse_snapshot = rwds_sample_pulse_count;
        axi_write_burst_slow(BaseAddr, 256, 0, 64'h1000_0000_0000_0000);
        // 64 timer units represent 32 dual-PHY beats; 256 beats therefore make 8 segments.
        if ((segment_start_count - segment_snapshot) != ExpectedSegmentStarts) begin
          $fatal(1, "[PAD-LATENCY] t_burst_max=64 produced %0d segments, expected %0d",
                 segment_start_count - segment_snapshot, ExpectedSegmentStarts);
        end
        if ((sample_reload_count - sample_snapshot) != ExpectedSegmentStarts) begin
          $fatal(1, "[PAD-LATENCY] RWDS reload count was %0d, expected %0d",
                 sample_reload_count - sample_snapshot, ExpectedSegmentStarts);
        end
        if ((rwds_sample_pulse_count - pulse_snapshot) != ExpectedSegmentStarts) begin
          $fatal(1, "[PAD-LATENCY] RWDS sample count was %0d, expected %0d",
                 rwds_sample_pulse_count - pulse_snapshot, ExpectedSegmentStarts);
        end
        if (sample_reload_mismatch_count != 0) begin
          $fatal(1, "[PAD-LATENCY] observed %0d incorrect RWDS countdown reloads",
                 sample_reload_mismatch_count);
        end
        $display("[PAD-LATENCY] segment_restart passed: segments=%0d samples=%0d",
                 segment_start_count - segment_snapshot,
                 rwds_sample_pulse_count - pulse_snapshot);
        axi_read_burst_check(BaseAddr, 256, 64'h1000_0000_0000_0000);
      end else if (scenario == "late_write_data") begin
        $display("[PAD-LATENCY] late write-data scenario");
        configure_chip(0, BaseAddr, BaseAddr + 32'h0040_0000, 4'd0);
        configure_phy_lane(0, 15);
        reg_write(12'h410, 32'd24);
        apply_config();
        #(TbInitialDelay);
        segment_snapshot = segment_start_count;
        ck_max_hold_quarters = 0;
        ck_hold_quarters = 0;
        axi_write_burst_slow(BaseAddr + 32'h100, 32, 8, 64'h2000_0000_0000_0000);
        if ((segment_start_count - segment_snapshot) < 2) begin
          $fatal(1, "[PAD-LATENCY] late write used only %0d segments",
                 segment_start_count - segment_snapshot);
        end
        if (ck_max_hold_quarters <= NormalCkEdgeIntervalQuarters) begin
          $fatal(1, "[PAD-LATENCY] late write CK stop interval was only %0d quarter cycles",
                 ck_max_hold_quarters);
        end
        if (rwds_wait_cycles == 0) begin
          $fatal(1, "[PAD-LATENCY] late write did not exercise RWDS OE setup wait");
        end
        axi_read_burst_check(BaseAddr + 32'h100, 32, 64'h2000_0000_0000_0000);
        $display("[PAD-LATENCY] late_write_data passed: segments=%0d max_ck_hold_quarters=%0d",
                 segment_start_count - segment_snapshot,
                 ck_max_hold_quarters);
      end else begin
        $fatal(1, "[PAD-LATENCY] unknown scenario '%s'", scenario);
      end
      end_of_sim = 1'b1;
      $finish;
    end

    // Map chip-select zero to the first 4 MiB at the AXI memory base.
    reg_write(12'h400, 32'h8000_0000);
    reg_write(12'h404, 32'h8040_0000);
    reg_write(12'h408, 32'h0001_1900);
    reg_write(12'h40c, (TbAssumeAdditionalLatency ? 32'h0001_0000 : 32'h0) |
                       (rwds_sample_delay << 8) | 32'd6);
    reg_write(12'h414, (TbCsnToCkCycles << 16) | (8'd1 << 8) |
                       read_write_recovery);
    reg_write(12'h418, TbRxDelayLineTaps);
    reg_write(12'h300, TbTxDelayLineTaps);
    reg_write(12'h304, TbRwdsOeSetupCycles);
    apply_config();

    #(TbInitialDelay);

    $display("[PAD-LATENCY] %s/read 64-bit word", TbReadOnly ? "read-only" : "write");
    if (!TbReadOnly) begin
      axi_write64(BaseAddr, 64'h0123_4567_89ab_cdef, '1);
    end
    axi_read64(BaseAddr, rdata);

    if (TbReadOnly) begin
      if (rdata != '1) begin
        $fatal(1, "[PAD-LATENCY] read-only mismatch: got 0x%016x expected all ones", rdata);
      end
    end else if (rdata != 64'h0123_4567_89ab_cdef) begin
      $fatal(1, "[PAD-LATENCY] readback mismatch: got 0x%016x expected 0x0123456789abcdef",
             rdata);
    end

    check_rwds_wait();
    check_model_extra_latency();

    $display("[PAD-LATENCY] passed, segment starts=%0d", segment_start_count);
    end_of_sim = 1'b1;
    $finish;
  end
endmodule
