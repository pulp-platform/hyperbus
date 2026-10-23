// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Luca Valente <luca.valente@unibo.it>

`timescale 1 ns/1 ps

`include "axi/typedef.svh"
`include "axi/assign.svh"
`include "register_interface/typedef.svh"
`include "register_interface/assign.svh"

module dut_if 
#(
  parameter time TbTestTime      = 4ns,
  parameter int  AxiDataWidth    = -1,
  parameter int  AxiAddrWidth    = -1,
  parameter int  AxiIdWidth      = -1,
  parameter int  AxiUserWidth    = -1,
  parameter int unsigned AxiMaxReadTxns = 4,
  parameter int unsigned AxiMaxWriteTxns = 4,
  parameter int unsigned HostWriteBufferBytes = 64,
                                  
  parameter int  RegAw           = -1,
  parameter int  RegDw           = -1,
                 
  parameter int  NumConnectedChips = 2,
  parameter int  NumPhys         = -1,
  parameter bit  AnnotateSdf     = 1'b1,
  parameter int  IsClockODelayed = -1,
  parameter int unsigned DutVariant = 0,
  parameter time PhyCyclTime     = 6ns,
  parameter time PadDelayTickCyclTime = 5ns,
  parameter type axi_rule_t      = logic
)(
 input logic clk_i,
 input logic rst_ni,
 input logic end_sim_i,
 output logic [31:0] segment_start_count_o,
 output logic [NumPhys-1:0][NumConnectedChips-1:0][31:0] cs_start_count,
 input hyperbus_tb_pkg::pad_delay_cfg_t pad_delay_cfg_i,

 AXI_BUS.Slave axi_slv_if,
 REG_BUS.in    reg_slv_if
);
  localparam int unsigned DRAM_DB_WIDTH = 16;
   
  typedef logic [AxiIdWidth-1:0] axi_id_t;
  typedef logic [AxiAddrWidth-1:0] axi_addr_t;
  typedef logic [AxiDataWidth-1:0] axi_data_t;
  typedef logic [AxiDataWidth/8-1:0] axi_strb_t;
  typedef logic [AxiUserWidth-1:0] axi_user_t;

  `AXI_TYPEDEF_AW_CHAN_T(axi_aw_chan_t, axi_addr_t, axi_id_t, axi_user_t)
  `AXI_TYPEDEF_W_CHAN_T(axi_w_chan_t, axi_data_t, axi_strb_t, axi_user_t)
  `AXI_TYPEDEF_B_CHAN_T(axi_b_chan_t, axi_id_t, axi_user_t)
  `AXI_TYPEDEF_AR_CHAN_T(axi_ar_chan_t, axi_addr_t, axi_id_t, axi_user_t)
  `AXI_TYPEDEF_R_CHAN_T(axi_r_chan_t, axi_data_t, axi_id_t, axi_user_t)
  `AXI_TYPEDEF_REQ_T(axi_req_t, axi_aw_chan_t, axi_w_chan_t, axi_ar_chan_t)
  `AXI_TYPEDEF_RESP_T(axi_resp_t, axi_b_chan_t, axi_r_chan_t)

   axi_req_t axi_req;
   axi_resp_t axi_resp;
     
  `AXI_ASSIGN_TO_REQ(axi_req, axi_slv_if)
  `AXI_ASSIGN_FROM_RESP(axi_slv_if, axi_resp)

  // Check handshakes at the DUT boundary, independently of the test drivers.
  localparam int unsigned NumAxiIds = 1 << AxiIdWidth;
  localparam int unsigned MonitorDepth = 256;
  axi_id_t aw_id_fifo [MonitorDepth];
  int unsigned aw_beats_fifo [MonitorDepth];
  int unsigned aw_head, aw_tail;
  int unsigned w_beats_fifo [MonitorDepth];
  int unsigned w_head, w_tail, w_current_beats;
  int unsigned write_complete_count [NumAxiIds];
  int unsigned b_response_count [NumAxiIds];
  int unsigned read_len_fifo [NumAxiIds][MonitorDepth];
  int unsigned read_head [NumAxiIds];
  int unsigned read_tail [NumAxiIds];
  bit aw_stalled_q, w_stalled_q, ar_stalled_q, b_stalled_q, r_stalled_q;
  axi_aw_chan_t aw_hold_q;
  axi_w_chan_t w_hold_q;
  axi_ar_chan_t ar_hold_q;
  axi_b_chan_t b_hold_q;
  axi_r_chan_t r_hold_q;
  always @(posedge clk_i or negedge rst_ni) begin : proc_axi_protocol_monitor
    int unsigned id;
    if (!rst_ni) begin
      aw_head = 0;
      aw_tail = 0;
      w_head = 0;
      w_tail = 0;
      w_current_beats = 0;
      aw_stalled_q = 0;
      w_stalled_q = 0;
      ar_stalled_q = 0;
      b_stalled_q = 0;
      r_stalled_q = 0;
      for (int i = 0; i < NumAxiIds; i++) begin
        write_complete_count[i] = 0;
        b_response_count[i] = 0;
        read_head[i] = 0;
        read_tail[i] = 0;
      end
    end else begin
      if (aw_stalled_q && (axi_req.aw_valid !== 1'b1 || axi_req.aw !== aw_hold_q))
        $fatal(1, "[AXI-PROTOCOL] AW changed while stalled");
      if (w_stalled_q && (axi_req.w_valid !== 1'b1 || axi_req.w !== w_hold_q))
        $fatal(1, "[AXI-PROTOCOL] W changed while stalled");
      if (ar_stalled_q && (axi_req.ar_valid !== 1'b1 || axi_req.ar !== ar_hold_q))
        $fatal(1, "[AXI-PROTOCOL] AR changed while stalled");
      if (b_stalled_q && (axi_resp.b_valid !== 1'b1 || axi_resp.b !== b_hold_q))
        $fatal(1, "[AXI-PROTOCOL] B changed while stalled");
      if (r_stalled_q && (axi_resp.r_valid !== 1'b1 || axi_resp.r !== r_hold_q))
        $fatal(1, "[AXI-PROTOCOL] R changed while stalled");

      aw_stalled_q = axi_req.aw_valid && !axi_resp.aw_ready;
      w_stalled_q = axi_req.w_valid && !axi_resp.w_ready;
      ar_stalled_q = axi_req.ar_valid && !axi_resp.ar_ready;
      b_stalled_q = axi_resp.b_valid && !axi_req.b_ready;
      r_stalled_q = axi_resp.r_valid && !axi_req.r_ready;
      aw_hold_q = axi_req.aw;
      w_hold_q = axi_req.w;
      ar_hold_q = axi_req.ar;
      b_hold_q = axi_resp.b;
      r_hold_q = axi_resp.r;

      // BVALID must depend on write handshakes from earlier clock edges.
      if (axi_resp.b_valid) begin
        id = int'(axi_resp.b.id);
        if (b_response_count[id] >= write_complete_count[id])
          $fatal(1, "[AXI-PROTOCOL] BVALID id=%0d preceded W completion or exceeded accepted writes", id);
      end
      if (axi_resp.b_valid && axi_req.b_ready) begin
        id = int'(axi_resp.b.id);
        b_response_count[id]++;
      end

      if (axi_req.aw_valid && axi_resp.aw_ready) begin
        if (aw_tail - aw_head >= MonitorDepth) $fatal(1, "[AXI-PROTOCOL] AW monitor queue overflow");
        aw_id_fifo[aw_tail % MonitorDepth] = axi_req.aw.id;
        aw_beats_fifo[aw_tail % MonitorDepth] = int'(axi_req.aw.len) + 1;
        aw_tail++;
        if (axi_req.aw.atop[axi_pkg::ATOP_R_RESP]) begin
          id = int'(axi_req.aw.id);
          if (read_tail[id] - read_head[id] >= MonitorDepth)
            $fatal(1, "[AXI-PROTOCOL] Atomic R monitor queue overflow for id=%0d", id);
          // AXI atomics return one old-value beat even when malformed AWLEN is drained.
          read_len_fifo[id][read_tail[id] % MonitorDepth] = 1;
          read_tail[id]++;
        end
      end
      if (axi_req.w_valid && axi_resp.w_ready) begin
        w_current_beats++;
        if (axi_req.w.last) begin
          if (w_tail - w_head >= MonitorDepth) $fatal(1, "[AXI-PROTOCOL] W monitor queue overflow");
          w_beats_fifo[w_tail % MonitorDepth] = w_current_beats;
          w_tail++;
          w_current_beats = 0;
        end
      end
      while (aw_head < aw_tail && w_head < w_tail) begin
        if (aw_beats_fifo[aw_head % MonitorDepth] != w_beats_fifo[w_head % MonitorDepth])
          $fatal(1, "[AXI-PROTOCOL] W beat count does not match accepted AW length");
        id = int'(aw_id_fifo[aw_head % MonitorDepth]);
        write_complete_count[id]++;
        aw_head++;
        w_head++;
      end
      if (axi_req.ar_valid && axi_resp.ar_ready) begin
        id = int'(axi_req.ar.id);
        if (read_tail[id] - read_head[id] >= MonitorDepth)
          $fatal(1, "[AXI-PROTOCOL] AR monitor queue overflow for id=%0d", id);
        read_len_fifo[id][read_tail[id] % MonitorDepth] = int'(axi_req.ar.len) + 1;
        read_tail[id]++;
      end
      if (axi_resp.r_valid) begin
        id = int'(axi_resp.r.id);
        if (read_head[id] == read_tail[id])
          $fatal(1, "[AXI-PROTOCOL] RVALID id=%0d has no accepted AR or atomic read request", id);
        if ((read_len_fifo[id][read_head[id] % MonitorDepth] == 1) != axi_resp.r.last)
          $fatal(1, "[AXI-PROTOCOL] RLAST mismatch for id=%0d", id);
        if (axi_req.r_ready) begin
          if (axi_resp.r.last) read_head[id]++;
          else read_len_fifo[id][read_head[id] % MonitorDepth]--;
        end
      end
    end
  end

  always @(posedge end_sim_i) begin : proc_axi_end_check
    if (aw_head != aw_tail || w_head != w_tail || w_current_beats != 0)
      $fatal(1, "[AXI-PROTOCOL] Test ended with incomplete write traffic");
    for (int i = 0; i < NumAxiIds; i++) begin
      if (b_response_count[i] != write_complete_count[i])
        $fatal(1, "[AXI-PROTOCOL] Test ended with unmatched B count for id=%0d", i);
      if (read_head[i] != read_tail[i])
        $fatal(1, "[AXI-PROTOCOL] Test ended with unmatched R count for id=%0d", i);
    end
  end
   
  typedef logic [RegAw-1:0]   reg_addr_t;
  typedef logic [RegDw-1:0]   reg_data_t;
  typedef logic [RegDw/8-1:0] reg_strb_t;

  `REG_BUS_TYPEDEF_REQ(reg_req_t, reg_addr_t, reg_data_t, reg_strb_t)
  `REG_BUS_TYPEDEF_RSP(reg_rsp_t, reg_data_t)

  reg_req_t reg_req;
  reg_rsp_t reg_resp;

  `REG_BUS_ASSIGN_TO_REQ(reg_req,reg_slv_if)
  `REG_BUS_ASSIGN_FROM_RSP(reg_slv_if,reg_resp)   
   

    logic [NumPhys-1:0][hyperbus_pkg::HyperNumChips-1:0] hyper_cs_n_wire;
    logic [NumPhys-1:0]               hyper_ck_wire;
    logic [NumPhys-1:0]               hyper_ck_n_wire;
    logic [NumPhys-1:0]               hyper_rwds_o;
    logic [NumPhys-1:0]               hyper_rwds_i;
    logic [NumPhys-1:0]               hyper_rwds_oe;
    logic [NumPhys-1:0][7:0]          hyper_dq_i;
    logic [NumPhys-1:0][7:0]          hyper_dq_o;
    logic [NumPhys-1:0]               hyper_dq_oe;
    logic [NumPhys-1:0]               hyper_reset_n_wire;
    logic                             phy_clk;
    logic                             pad_delay_tick_clk;
    logic [NumPhys-1:0][hyperbus_pkg::HyperNumChips-1:0] hyper_cs_n_q;
    logic                             segment_start;

    logic [NumPhys-1:0][hyperbus_pkg::HyperNumChips-1:0] hyper_cs_n_pad;
    logic [NumPhys-1:0]               hyper_ck_pad;
    logic [NumPhys-1:0]               hyper_ck_n_pad;
    logic [NumPhys-1:0]               hyper_rwds_o_pad;
    logic [NumPhys-1:0]               hyper_rwds_oe_pad;
    logic [NumPhys-1:0][7:0]          hyper_dq_o_pad;
    logic [NumPhys-1:0]               hyper_dq_oe_pad;
    logic [NumPhys-1:0]               hyper_reset_n_pad;
    logic [NumPhys-1:0]               hyper_rwds_i_pad;
    logic [NumPhys-1:0][7:0]          hyper_dq_i_pad;
             
    wire  [NumPhys-1:0][NumConnectedChips-1:0] pad_hyper_csn;
    wire  [NumPhys-1:0]                pad_hyper_ck;
    wire  [NumPhys-1:0]                pad_hyper_ckn;
    wire  [NumPhys-1:0]                pad_hyper_rwds;
    wire  [NumPhys-1:0]                pad_hyper_reset;
    wire  [NumPhys-1:0][7:0]           pad_hyper_dq;

    hyperbus_pad_delay #(
      .NumPhys            ( NumPhys            ),
      .NumConnectedChips  ( NumConnectedChips  ),
      .NumChips           ( hyperbus_pkg::HyperNumChips )
    ) i_pad_delay (
      .tick_i       ( pad_delay_tick_clk    ),
      .rst_ni       ( rst_ni                ),
      .cfg_i        ( pad_delay_cfg_i       ),
      .cs_n_i       ( hyper_cs_n_wire       ),
      .ck_i         ( hyper_ck_wire         ),
      .ck_n_i       ( hyper_ck_n_wire       ),
      .rwds_o_i     ( hyper_rwds_o          ),
      .dq_o_i       ( hyper_dq_o            ),
      .reset_n_i    ( hyper_reset_n_wire    ),
      .dq_oe_i      ( hyper_dq_oe           ),
      .rwds_oe_i    ( hyper_rwds_oe         ),
      .cs_n_o       ( hyper_cs_n_pad        ),
      .ck_o         ( hyper_ck_pad          ),
      .ck_n_o       ( hyper_ck_n_pad        ),
      .rwds_o_o     ( hyper_rwds_o_pad      ),
      .dq_o_o       ( hyper_dq_o_pad        ),
      .reset_n_o    ( hyper_reset_n_pad     ),
      .dq_oe_o      ( hyper_dq_oe_pad       ),
      .rwds_oe_o    ( hyper_rwds_oe_pad     ),
      .rwds_i_pad   ( hyper_rwds_i_pad      ),
      .dq_i_pad     ( hyper_dq_i_pad        ),
      .rwds_i       ( hyper_rwds_i           ),
      .dq_i         ( hyper_dq_i             )
    );
   
  axi_chan_logger #(
    .aw_chan_t ( axi_aw_chan_t ),
    .w_chan_t  ( axi_w_chan_t  ),
    .b_chan_t  ( axi_b_chan_t  ),
    .ar_chan_t ( axi_ar_chan_t ),
    .r_chan_t  ( axi_r_chan_t  ),
    .TestTime  ( TbTestTime    )
  ) i_chan_logger
    (
    .clk_i      ( clk_i             ),
    .rst_ni     ( rst_ni            ),
    .end_sim_i  ( end_sim_i         ),

    .aw_chan_i  ( axi_req.aw        ),
    .aw_valid_i ( axi_req.aw_valid  ),
    .aw_ready_i ( axi_resp.aw_ready ),

    .w_chan_i   ( axi_req.w         ),
    .w_valid_i  ( axi_req.w_valid   ),
    .w_ready_i  ( axi_resp.w_ready  ),

    .b_chan_i   ( axi_resp.b        ),
    .b_valid_i  ( axi_resp.b_valid  ),
    .b_ready_i  ( axi_req.b_ready   ),

    .ar_chan_i  ( axi_req.ar        ),
    .ar_valid_i ( axi_req.ar_valid  ),
    .ar_ready_i ( axi_resp.ar_ready ),

    .r_chan_i   ( axi_resp.r        ),
    .r_valid_i  ( axi_resp.r_valid  ),
    .r_ready_i  ( axi_req.r_ready   )
     );

    initial begin
        phy_clk = 1'b0;
        forever begin
            #(PhyCyclTime/2);
            phy_clk = ~phy_clk;
        end
    end

    initial begin
        pad_delay_tick_clk = 1'b0;
        #(real'(PadDelayTickCyclTime) / 8.0);
        forever begin
            #(real'(PadDelayTickCyclTime) / 4.0);
            pad_delay_tick_clk = ~pad_delay_tick_clk;
        end
    end

    assign segment_start = |(hyper_cs_n_q & ~hyper_cs_n_wire);

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            hyper_cs_n_q          <= '1;
            segment_start_count_o <= '0;
            cs_start_count        <= '0;
        end else begin
            hyper_cs_n_q <= hyper_cs_n_wire;
            if (segment_start) begin
                segment_start_count_o <= segment_start_count_o + 1;
            end
            for (int p = 0; p < NumPhys; p++) begin
                for (int c = 0; c < NumConnectedChips; c++) begin
                    if (hyper_cs_n_q[p][c] && !hyper_cs_n_wire[p][c])
                        cs_start_count[p][c] <= cs_start_count[p][c] + 1'b1;
                end
            end
        end
    end

    // DUT
    hyperbus_test_dut #(
        .DutVariant       ( DutVariant   ),
        .NumPhys          ( NumPhys       ),
        .AxiAddrWidth     ( AxiAddrWidth  ),
        .AxiDataWidth     ( AxiDataWidth  ),
        .AxiIdWidth       ( AxiIdWidth    ),
        .AxiUserWidth     ( AxiUserWidth  ),
        .AxiMaxReadTxns   ( AxiMaxReadTxns ),
        .AxiMaxWriteTxns  ( AxiMaxWriteTxns ),
        .HostWriteBufferBytes ( HostWriteBufferBytes ),
        .axi_req_t        ( axi_req_t     ),
        .axi_rsp_t        ( axi_resp_t    ),
        .RegDataWidth     ( RegDw         ),
        .RegAddrWidth     ( RegAw         ),
        .reg_req_t        ( reg_req_t     ),
        .reg_rsp_t        ( reg_rsp_t     ),
        .axi_rule_t       ( axi_rule_t    )
    ) i_dut (
        .clk_sys_i              ( clk_i              ),
        .rst_sys_ni             ( rst_ni             ),
        .clk_phy_i              ( phy_clk            ),
        .rst_phy_ni             ( rst_ni             ),
`ifdef TARGET_XILINX
        .clk_ref200_i           ( clk_i              ),
`endif
        .test_mode_i            ( 1'b0               ),
        .axi_req_i              ( axi_req            ),
        .axi_rsp_o              ( axi_resp           ),
        .reg_req_i              ( reg_req            ),
        .reg_rsp_o              ( reg_resp           ),

        .hyper_cs_no            ( hyper_cs_n_wire    ),
        .hyper_ck_o             ( hyper_ck_wire      ),
        .hyper_ck_no            ( hyper_ck_n_wire    ),
        .hyper_rwds_o           ( hyper_rwds_o       ),
        .hyper_rwds_i           ( hyper_rwds_i       ),
        .hyper_rwds_oe_o        ( hyper_rwds_oe      ),
        .hyper_dq_i             ( hyper_dq_i         ),
        .hyper_dq_o             ( hyper_dq_o         ),
        .hyper_dq_oe_o          ( hyper_dq_oe        ),
        .hyper_reset_no         ( hyper_reset_n_wire )

    );

    
    generate
       for (genvar i=0; i<NumPhys; i++) begin : hyperrams
          for (genvar j=0; j<NumConnectedChips; j++) begin : chips

             s27ks0641 #(
                  /*.mem_file_name ( "s27ks0641.mem"    ),*/
                  .TimingModel   ( "S27KS0641DPBHI020"    )
                ) dut (
                  .DQ7           ( pad_hyper_dq[i][7]  ),
                  .DQ6           ( pad_hyper_dq[i][6]  ),
                  .DQ5           ( pad_hyper_dq[i][5]  ),
                  .DQ4           ( pad_hyper_dq[i][4]  ),
                  .DQ3           ( pad_hyper_dq[i][3]  ),
                  .DQ2           ( pad_hyper_dq[i][2]  ),
                  .DQ1           ( pad_hyper_dq[i][1]  ),
                  .DQ0           ( pad_hyper_dq[i][0]  ),
                  .RWDS          ( pad_hyper_rwds[i]   ),
                  .CSNeg         ( pad_hyper_csn[i][j] ),
                  .CK            ( pad_hyper_ck[i]     ),
                  .CKNeg         ( pad_hyper_ckn[i]    ),
                  .RESETNeg      ( pad_hyper_reset[i]  )
             );
          end // block: chips
       end // block: hyperrams
    endgenerate
   
    if (AnnotateSdf) begin : gen_sdf_annotation
       for (genvar p=0; p<NumPhys; p++) begin : sdf_annotation
          for (genvar l=0; l<NumConnectedChips; l++) begin : sdf_annotation
             initial begin
                string sdf_file_path;
                if (!$value$plusargs("HYPERRAM_SDF=%s", sdf_file_path)) begin
                  sdf_file_path = "./models/s27ks0641/s27ks0641.sdf";
                end
                $sdf_annotate(sdf_file_path, hyperrams[p].chips[l].dut);
                $display("Mem (%0d,%0d)", p, l);
             end
          end
       end
    end

   for (genvar i = 0 ; i<NumPhys; i++) begin: pad_gen
    for (genvar j = 0; j<NumConnectedChips; j++) begin
       pad_functional_pd padinst_hyper_csno   (.OEN( 1'b0            ), .I( hyper_cs_n_pad[i][j] ), .O(                  ), .PAD( pad_hyper_csn[i][j] ), .PEN( 1'b0 ));
    end
    pad_functional_pd padinst_hyper_ck     (.OEN( 1'b0            ), .I( hyper_ck_pad[i]      ), .O(                  ), .PAD( pad_hyper_ck[i]     ), .PEN( 1'b0 ) );
    pad_functional_pd padinst_hyper_ckno   (.OEN( 1'b0            ), .I( hyper_ck_n_pad[i]    ), .O(                  ), .PAD( pad_hyper_ckn[i]    ), .PEN( 1'b0 ) );
    pad_functional_pd padinst_hyper_rwds   (.OEN(~hyper_rwds_oe_pad[i]), .I( hyper_rwds_o_pad[i] ), .O( hyper_rwds_i_pad[i] ), .PAD( pad_hyper_rwds[i] ), .PEN( 1'b0 ) );
    pad_functional_pd padinst_hyper_resetn (.OEN( 1'b0            ), .I( hyper_reset_n_pad[i] ), .O(                  ), .PAD( pad_hyper_reset[i]  ), .PEN( 1'b0 ) );
    pad_functional_pd padinst_hyper_dqio0  (.OEN(~hyper_dq_oe_pad[i]), .I( hyper_dq_o_pad[i][0] ), .O( hyper_dq_i_pad[i][0] ), .PAD( pad_hyper_dq[i][0] ), .PEN( 1'b0 ) );
    pad_functional_pd padinst_hyper_dqio1  (.OEN(~hyper_dq_oe_pad[i]), .I( hyper_dq_o_pad[i][1] ), .O( hyper_dq_i_pad[i][1] ), .PAD( pad_hyper_dq[i][1] ), .PEN( 1'b0 ) );
    pad_functional_pd padinst_hyper_dqio2  (.OEN(~hyper_dq_oe_pad[i]), .I( hyper_dq_o_pad[i][2] ), .O( hyper_dq_i_pad[i][2] ), .PAD( pad_hyper_dq[i][2] ), .PEN( 1'b0 ) );
    pad_functional_pd padinst_hyper_dqio3  (.OEN(~hyper_dq_oe_pad[i]), .I( hyper_dq_o_pad[i][3] ), .O( hyper_dq_i_pad[i][3] ), .PAD( pad_hyper_dq[i][3] ), .PEN( 1'b0 ) );
    pad_functional_pd padinst_hyper_dqio4  (.OEN(~hyper_dq_oe_pad[i]), .I( hyper_dq_o_pad[i][4] ), .O( hyper_dq_i_pad[i][4] ), .PAD( pad_hyper_dq[i][4] ), .PEN( 1'b0 ) );
    pad_functional_pd padinst_hyper_dqio5  (.OEN(~hyper_dq_oe_pad[i]), .I( hyper_dq_o_pad[i][5] ), .O( hyper_dq_i_pad[i][5] ), .PAD( pad_hyper_dq[i][5] ), .PEN( 1'b0 ) );
    pad_functional_pd padinst_hyper_dqio6  (.OEN(~hyper_dq_oe_pad[i]), .I( hyper_dq_o_pad[i][6] ), .O( hyper_dq_i_pad[i][6] ), .PAD( pad_hyper_dq[i][6] ), .PEN( 1'b0 ) );
    pad_functional_pd padinst_hyper_dqio7  (.OEN(~hyper_dq_oe_pad[i]), .I( hyper_dq_o_pad[i][7] ), .O( hyper_dq_i_pad[i][7] ), .PAD( pad_hyper_dq[i][7] ), .PEN( 1'b0 ) );
   end
                        
endmodule
