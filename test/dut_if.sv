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
                                  
  parameter int  RegAw           = -1,
  parameter int  RegDw           = -1,
                 
  parameter int  NumChips        = -1,
  parameter int  NumPhys         = -1,
  parameter int  IsClockODelayed = -1,
  parameter type axi_rule_t      = logic
)(
 input logic clk_i,
 input logic rst_ni,
 input logic end_sim_i,

 AXI_BUS_DV.Slave axi_slv_if,
 REG_BUS.in       reg_slv_if
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
   
  typedef logic [RegAw-1:0]   reg_addr_t;
  typedef logic [RegDw-1:0]   reg_data_t;
  typedef logic [RegDw/8-1:0] reg_strb_t;

  `REG_BUS_TYPEDEF_REQ(reg_req_t, reg_addr_t, reg_data_t, reg_strb_t)
  `REG_BUS_TYPEDEF_RSP(reg_rsp_t, reg_data_t)

  reg_req_t reg_req;
  reg_rsp_t reg_resp;

  `REG_BUS_ASSIGN_TO_REQ(reg_req,reg_slv_if)
  `REG_BUS_ASSIGN_FROM_RSP(reg_slv_if,reg_resp)   
   

    logic [NumPhys-1:0][NumChips-1:0] hyper_cs_n_wire;
    logic [NumPhys-1:0]               hyper_ck_wire;
    logic [NumPhys-1:0]               hyper_ck_n_wire;
    logic [NumPhys-1:0]               hyper_rwds_o;
    logic [NumPhys-1:0]               hyper_rwds_i;
    logic [NumPhys-1:0]               hyper_rwds_oe;
    logic [NumPhys-1:0][7:0]          hyper_dq_i;
    logic [NumPhys-1:0][7:0]          hyper_dq_o;
    logic [NumPhys-1:0]               hyper_dq_oe;
    logic [NumPhys-1:0]               hyper_reset_n_wire;
             
    wire  [NumPhys-1:0][NumChips-1:0]  pad_hyper_csn;
    wire  [NumPhys-1:0]                pad_hyper_ck;
    wire  [NumPhys-1:0]                pad_hyper_ckn;
    wire  [NumPhys-1:0]                pad_hyper_rwds;
    wire  [NumPhys-1:0]                pad_hyper_reset;
    wire  [NumPhys-1:0][7:0]           pad_hyper_dq;
   
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

    // DUT
    hyperbus #(
        .NumChips       ( NumChips      ),
        .NumPhys        ( NumPhys       ),
        .AxiAddrWidth   ( AxiAddrWidth  ),
        .AxiDataWidth   ( AxiDataWidth  ),
        .AxiIdWidth     ( AxiIdWidth    ),
        .AxiUserWidth   ( AxiUserWidth  ),
        .axi_req_t      ( axi_req_t     ),
        .axi_rsp_t      ( axi_resp_t    ),
        .axi_aw_chan_t  ( axi_aw_chan_t ),
        .axi_w_chan_t   ( axi_w_chan_t  ),
        .axi_b_chan_t   ( axi_b_chan_t  ),
        .axi_ar_chan_t  ( axi_ar_chan_t ),
        .axi_r_chan_t   ( axi_r_chan_t  ),
        .RegAddrWidth   ( RegAw         ),
        .RegDataWidth   ( RegDw         ),
        .reg_req_t      ( reg_req_t     ),
        .reg_rsp_t      ( reg_rsp_t     ),
        .IsClockODelayed( 0             ),
        .axi_rule_t     ( axi_rule_t    )
    ) i_dut (
        .clk_phy_i              ( clk_i              ),
        .rst_phy_ni             ( rst_ni             ),
        .clk_sys_i              ( clk_i              ),
        .rst_sys_ni             ( rst_ni             ),
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
          for (genvar j=0; j<NumChips; j++) begin : chips

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
               .CSNeg         ( pad_hyper_csn[i][0] ),
               .CK            ( pad_hyper_ck[i]     ),
               .CKNeg         ( pad_hyper_ckn[i]    ),
               .RESETNeg      ( pad_hyper_reset[i]  )
             );
          end // block: chips
       end // block: hyperrams
    endgenerate
   
    generate
       for (genvar p=0; p<NumPhys; p++) begin : sdf_annotation
          for (genvar l=0; l<NumChips; l++) begin : sdf_annotation
             initial begin
                automatic string sdf_file_path = "./models/s27ks0641/s27ks0641.sdf";
                $sdf_annotate(sdf_file_path, hyperrams[p].chips[l].dut);
                $display("Mem (%d,%d)",p,l);
             end
         end
       end
    endgenerate

   for (genvar i = 0 ; i<NumPhys; i++) begin: pad_gen
    for (genvar j = 0; j<NumChips; j++) begin
       pad_functional_pd padinst_hyper_csno   (.OEN( 1'b0            ), .I( hyper_cs_n_wire[i][j] ), .O(                  ), .PAD( pad_hyper_csn[i][j] ), .PEN( 1'b0 ));
    end
    pad_functional_pd padinst_hyper_ck     (.OEN( 1'b0            ), .I( hyper_ck_wire[i]      ), .O(                  ), .PAD( pad_hyper_ck[i]     ), .PEN( 1'b0 ) );
    pad_functional_pd padinst_hyper_ckno   (.OEN( 1'b0            ), .I( hyper_ck_n_wire[i]    ), .O(                  ), .PAD( pad_hyper_ckn[i]    ), .PEN( 1'b0 ) );
    pad_functional_pd padinst_hyper_rwds   (.OEN(~hyper_rwds_oe[i]), .I( hyper_rwds_o[i]       ), .O( hyper_rwds_i[i]  ), .PAD( pad_hyper_rwds[i]   ), .PEN( 1'b0 ) );
    pad_functional_pd padinst_hyper_resetn (.OEN( 1'b0            ), .I( hyper_reset_n_wire[i] ), .O(                  ), .PAD( pad_hyper_reset[i]  ), .PEN( 1'b0 ) );
    pad_functional_pd padinst_hyper_dqio0  (.OEN(~hyper_dq_oe[i]  ), .I( hyper_dq_o[i][0]      ), .O( hyper_dq_i[i][0] ), .PAD( pad_hyper_dq[i][0]  ), .PEN( 1'b0 ) );
    pad_functional_pd padinst_hyper_dqio1  (.OEN(~hyper_dq_oe[i]  ), .I( hyper_dq_o[i][1]      ), .O( hyper_dq_i[i][1] ), .PAD( pad_hyper_dq[i][1]  ), .PEN( 1'b0 ) );
    pad_functional_pd padinst_hyper_dqio2  (.OEN(~hyper_dq_oe[i]  ), .I( hyper_dq_o[i][2]      ), .O( hyper_dq_i[i][2] ), .PAD( pad_hyper_dq[i][2]  ), .PEN( 1'b0 ) );
    pad_functional_pd padinst_hyper_dqio3  (.OEN(~hyper_dq_oe[i]  ), .I( hyper_dq_o[i][3]      ), .O( hyper_dq_i[i][3] ), .PAD( pad_hyper_dq[i][3]  ), .PEN( 1'b0 ) );
    pad_functional_pd padinst_hyper_dqio4  (.OEN(~hyper_dq_oe[i]  ), .I( hyper_dq_o[i][4]      ), .O( hyper_dq_i[i][4] ), .PAD( pad_hyper_dq[i][4]  ), .PEN( 1'b0 ) );
    pad_functional_pd padinst_hyper_dqio5  (.OEN(~hyper_dq_oe[i]  ), .I( hyper_dq_o[i][5]      ), .O( hyper_dq_i[i][5] ), .PAD( pad_hyper_dq[i][5]  ), .PEN( 1'b0 ) );
    pad_functional_pd padinst_hyper_dqio6  (.OEN(~hyper_dq_oe[i]  ), .I( hyper_dq_o[i][6]      ), .O( hyper_dq_i[i][6] ), .PAD( pad_hyper_dq[i][6]  ), .PEN( 1'b0 ) );
    pad_functional_pd padinst_hyper_dqio7  (.OEN(~hyper_dq_oe[i]  ), .I( hyper_dq_o[i][7]      ), .O( hyper_dq_i[i][7] ), .PAD( pad_hyper_dq[i][7]  ), .PEN( 1'b0 ) );
   end
                        
endmodule
