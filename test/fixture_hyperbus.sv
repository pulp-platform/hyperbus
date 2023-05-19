// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Thomas Benz <tbenz@iis.ee.ethz.ch>

`timescale 1 ns/1 ps

`include "axi/assign.svh"
`include "axi/typedef.svh"
`include "register_interface/typedef.svh"

module fixture_hyperbus #(
    parameter int unsigned NumChips = 2,
    parameter int unsigned NumPhys = 2
);

   
    int unsigned            k, j;

    localparam time SYS_TCK  = 4ns;
    localparam time SYS_TA   = 2ns;
    localparam time SYS_TT   = SYS_TCK - 1ns;

    localparam time PHY_TCK  = 6ns;
   
    logic sys_clk      = 0;
    logic phy_clk      = 0;
    logic test_mode    = 0;
    logic rst_n        = 1;
    logic eos          = 0; // end of sim

    // -------------------- AXI drivers --------------------

    localparam AxiAw  = 32;
    localparam AxiDw  = 64;
    localparam AxiMaxSize = $clog2(AxiDw/8);
    localparam AxiIw  = 6;
    localparam RegAw  = 32;
    localparam RegDw  = 32;

    typedef axi_pkg::xbar_rule_32_t rule_t;

    typedef logic [AxiAw-1:0]   axi_addr_t;
    typedef logic [AxiDw-1:0]   axi_data_t;
    typedef logic [AxiDw/8-1:0] axi_strb_t;
    typedef logic [AxiIw-1:0]   axi_id_t;

    `AXI_TYPEDEF_AW_CHAN_T(aw_chan_t, axi_addr_t, axi_id_t, logic [0:0])
    `AXI_TYPEDEF_W_CHAN_T(w_chan_t, axi_data_t, axi_strb_t, logic [0:0])
    `AXI_TYPEDEF_B_CHAN_T(b_chan_t, axi_id_t, logic [0:0])
    `AXI_TYPEDEF_AR_CHAN_T(ar_chan_t, axi_addr_t, axi_id_t, logic [0:0])
    `AXI_TYPEDEF_R_CHAN_T(r_chan_t, axi_data_t, axi_id_t, logic [0:0])
    `AXI_TYPEDEF_REQ_T(req_t, aw_chan_t, w_chan_t, ar_chan_t)
    `AXI_TYPEDEF_RESP_T(resp_t, b_chan_t, r_chan_t)

    req_t   axi_master_req;
    resp_t  axi_master_rsp;

    AXI_BUS_DV #(
        .AXI_ADDR_WIDTH(AxiAw ),
        .AXI_DATA_WIDTH(AxiDw ),
        .AXI_ID_WIDTH  (AxiIw ),
        .AXI_USER_WIDTH(1     )
    ) axi_dv(sys_clk);

    AXI_BUS #(
        .AXI_ADDR_WIDTH(AxiAw ),
        .AXI_DATA_WIDTH(AxiDw ),
        .AXI_ID_WIDTH  (AxiIw ),
        .AXI_USER_WIDTH(1     )
    ) axi_master();

    `AXI_ASSIGN(axi_master, axi_dv)

    `AXI_ASSIGN_TO_REQ(axi_master_req, axi_master)
    `AXI_ASSIGN_FROM_RESP(axi_master, axi_master_rsp)

    typedef axi_test::axi_driver #(.AW(AxiAw ), .DW(AxiDw ), .IW(AxiIw ), .UW(1), .TA(SYS_TA), .TT(SYS_TT)) axi_drv_t;
    axi_drv_t axi_master_drv = new(axi_dv);

    axi_test::axi_ax_beat #(.AW(AxiAw ), .IW(AxiIw ), .UW(1)) ar_beat = new();
    axi_test::axi_r_beat  #(.DW(AxiDw ), .IW(AxiIw ), .UW(1)) r_beat  = new();
    axi_test::axi_ax_beat #(.AW(AxiAw ), .IW(AxiIw ), .UW(1)) aw_beat = new();
    axi_test::axi_w_beat  #(.DW(AxiDw ), .UW(1))              w_beat  = new();
    axi_test::axi_b_beat  #(.IW(AxiIw ), .UW(1))              b_beat  = new();

    // -------------------------- Regbus driver --------------------------

    typedef logic [RegAw-1:0]   reg_addr_t;
    typedef logic [RegDw-1:0]   reg_data_t;
    typedef logic [RegDw/8-1:0] reg_strb_t;

    `REG_BUS_TYPEDEF_REQ(reg_req_t, reg_addr_t, reg_data_t, reg_strb_t)
    `REG_BUS_TYPEDEF_RSP(reg_rsp_t, reg_data_t)

    logic [AxiDw-1:0] trans_wdata;
    logic [AxiDw-1:0] trans_rdata;
    axi_addr_t    temp_waddr;
    axi_addr_t    temp_raddr;
    logic [4:0]   last_waddr;
    logic [4:0]   last_raddr;
    typedef logic [AxiDw-1:0] data_t;   
    data_t        memory[bit [31:0]];
    int           read_index = 0;
    int           write_index = 0;
   
   
    reg_req_t   reg_req;
    reg_rsp_t   reg_rsp;

    REG_BUS #(
        .ADDR_WIDTH( RegAw ),
        .DATA_WIDTH( RegDw )
    ) i_rbus (
        .clk_i (sys_clk)
    );
    integer fr, fw;

    reg_test::reg_driver #(
        .AW ( RegAw  ),
        .DW ( RegDw  ),
        .TA ( SYS_TA ),
        .TT ( SYS_TT )
    ) i_rmaster = new( i_rbus );

`ifdef TARGET_POST_SYNTH_SIM
    assign reg_req = reg_req_t'{
        addr:   $isunknown(i_rbus.addr ) ? 1'b0 : i_rbus.addr ,
        write:  $isunknown(i_rbus.write) ? 1'b0 : i_rbus.write,
        wdata:  $isunknown(i_rbus.wdata) ? 1'b0 : i_rbus.wdata,
        wstrb:  $isunknown(i_rbus.wstrb) ? 1'b0 : i_rbus.wstrb,
        valid:  $isunknown(i_rbus.valid) ? 1'b0 : i_rbus.valid
    };
`else 
    assign reg_req = reg_req_t'{
        addr:   i_rbus.addr,
        write:  i_rbus.write,
        wdata:  i_rbus.wdata,
        wstrb:  i_rbus.wstrb,
        valid:  i_rbus.valid
    };
`endif
   
    assign i_rbus.rdata = reg_rsp.rdata;
    assign i_rbus.ready = reg_rsp.ready;
    assign i_rbus.error = reg_rsp.error;

    // -------------------------- DUT --------------------------
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
                
    // DUT
    hyperbus #(
        .NumChips       ( NumChips    ),
        .NumPhys        ( NumPhys     ),
        .AxiAddrWidth   ( AxiAw       ),
        .AxiDataWidth   ( AxiDw       ),
        .AxiIdWidth     ( AxiIw       ),
        .AxiUserWidth   ( 1           ),
        .axi_req_t      ( req_t       ),
        .axi_rsp_t      ( resp_t      ),
        .axi_aw_chan_t  ( aw_chan_t   ),
        .axi_w_chan_t   ( w_chan_t    ),
        .axi_b_chan_t   ( b_chan_t    ),
        .axi_ar_chan_t  ( ar_chan_t   ),
        .axi_r_chan_t   ( r_chan_t    ),
        .RegAddrWidth   ( RegAw       ),
        .RegDataWidth   ( RegDw       ),
        .reg_req_t      ( reg_req_t   ),
        .reg_rsp_t      ( reg_rsp_t   ),
        .IsClockODelayed( 0           ),
        .axi_rule_t     ( rule_t      )
    ) i_dut (
        .clk_phy_i              ( phy_clk            ),
        .rst_phy_ni             ( rst_n              ),
        .clk_sys_i              ( sys_clk            ),
        .rst_sys_ni             ( rst_n              ),
        .test_mode_i            ( test_mode          ),
        .axi_req_i              ( axi_master_req     ),
        .axi_rsp_o              ( axi_master_rsp     ),
        .reg_req_i              ( reg_req            ),
        .reg_rsp_o              ( reg_rsp            ),
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
   

    // -------------------------- TB TASKS --------------------------

   
     class SetConfig;
        int cfg_address;
        int cfg_data;
        int cfg_valid = 0;
        int cfg_rwn = 1;

     function new (int cfg_address, int cfg_data);
        this.cfg_address = cfg_address;
        this.cfg_data = cfg_data;
     endfunction

     task write;
        this.cfg_valid = 1;
        this.cfg_rwn = 0;
     endtask : write

     endclass: SetConfig

    SetConfig sconfig;

    // Initial reset
    initial begin
        rst_n = 0;
        // Set all inputs at the beginning    
        axi_master_drv.reset_master();
        fr = $fopen ("axireadvalues.txt","w");
        fw = $fopen ("axiwrotevalues.txt","w");
        i_rmaster.reset_master();
        #(0.25*SYS_TCK);
        #(10*SYS_TCK);
        rst_n = 1;
    end

    // Generate clock
    initial begin
        while (!eos) begin
            sys_clk = 1;
            #(SYS_TCK/2);
            sys_clk = 0;
            #(SYS_TCK/2);
        end
        // Extra cycle after sim
        sys_clk = 1;
        #(SYS_TCK/2);
        sys_clk = 0;
        #(SYS_TCK/2);
    end

    // Generate clock
    initial begin
        while (!eos) begin
            phy_clk = 1;
            #(PHY_TCK/2);
            phy_clk = 0;
            #(PHY_TCK/2);
        end
        // Extra cycle after sim
        phy_clk = 1;
        #(PHY_TCK/2);
        phy_clk = 0;
        #(PHY_TCK/2);
    end
 

    task reset_end;
        @(posedge rst_n);
        @(posedge sys_clk);
    endtask

    // axi read task
    task read_axi;
        input axi_addr_t      raddr;
        input axi_pkg::len_t  burst_len;
        input axi_pkg::size_t size;

        @(posedge sys_clk);

        ar_beat.ax_addr  = raddr;
        ar_beat.ax_len   = burst_len;
        ar_beat.ax_burst = axi_pkg::BURST_INCR;
        ar_beat.ax_size  = size;

        if(ar_beat.ax_size>AxiMaxSize) begin
          $display("Not supported");
        end else begin
                     
          axi_master_drv.send_ar(ar_beat);
          $display("%p", ar_beat);

          temp_raddr = raddr;
          last_raddr = '0;
                
          for(int unsigned i = 0; i < burst_len + 1; i++) begin
              axi_master_drv.recv_r(r_beat);
              `ifdef AXI_VERBOSE
              $display("%p", r_beat);
              $display("%x", r_beat.r_data);
              `endif
              trans_rdata = '1;
              if (i==0) begin
                 for(k =temp_raddr[AxiMaxSize-1:0]; k<((temp_raddr[AxiMaxSize-1:0]>>size)<<size) + (2**size) ; k++) begin 
                   trans_rdata[k*8 +:8] = r_beat.r_data[(k*8) +: 8];
                 end
              end else begin
                 for(j=temp_raddr[AxiMaxSize-1:0]; j<temp_raddr[AxiMaxSize-1:0]+(2**size); j++) begin
                    trans_rdata[j*8 +:8] = r_beat.r_data[(j*8) +: 8];
                 end
              end
              $fwrite(fr, "%x %x %d\n", trans_rdata, temp_raddr, (((temp_raddr[AxiMaxSize-1:0]>>size)<<size) + (2**size)));
              if(memory[read_index]!=trans_rdata) begin
                 $fatal(1,"Error @%x (read_index: %d). Expected: %x, got: %x\n", temp_raddr, read_index, memory[read_index], trans_rdata);
              end
              if($isunknown(trans_rdata)) begin
                 $fatal(1,"Xs @%x\n",temp_raddr);
              end   
              read_index++;
              if(i==0)
                temp_raddr = ((temp_raddr>>size)<<size) + (2**size);
              else
                temp_raddr = temp_raddr + (2**size);    
              last_raddr = temp_raddr[AxiMaxSize-1:0] + (2**size);       
          end // for (int unsigned i = 0; i < burst_len + 1; i++)
        end
       
    endtask

    // axi write task
    task write_axi;
        input axi_addr_t      waddr;
        input axi_pkg::len_t  burst_len;
        input axi_pkg::size_t size;
        input logic           clear;
        input axi_strb_t      wstrb;

        @(posedge sys_clk);

        temp_waddr = waddr;
        aw_beat.ax_addr  = waddr;
        aw_beat.ax_len   = burst_len;
        aw_beat.ax_burst = axi_pkg::BURST_INCR;
        aw_beat.ax_size  = size;
       
        w_beat.w_strb   = wstrb;
        w_beat.w_last   = 1'b0;
        last_waddr = '0;

        if(aw_beat.ax_size>AxiMaxSize) begin
          $display("Not supported");
        end else begin
          $display("%p", aw_beat);

          axi_master_drv.send_aw(aw_beat);
          
          
          for(int unsigned i = 0; i < burst_len + 1; i++) begin
              if (i == burst_len) begin
                  w_beat.w_last = 1'b1;
              end
              if(clear)
                w_beat.w_data = '1;
              else
                randomize(w_beat.w_data);
              axi_master_drv.send_w(w_beat);
              trans_wdata = '1; //the memory regions where we do not write are have all ones in the hyperram.
              `ifdef AXI_VERBOSE
              $display("%p", w_beat);
              $display("%x", w_beat.w_data);
              `endif
              if (i==0) begin
                 for (k = temp_waddr[AxiMaxSize-1:0]; k<(((temp_waddr[AxiMaxSize-1:0]>>size)<<size) + (2**size)) ; k++)  begin
                   trans_wdata[k*8 +:8] = (wstrb[k]) ? w_beat.w_data[(k*8) +: 8] : '1;
                 end
              end else begin
                 for(j=temp_waddr[AxiMaxSize-1:0]; j<temp_waddr[AxiMaxSize-1:0]+(2**size); j++) begin
                    trans_wdata[j*8 +:8] = (wstrb[j]) ? w_beat.w_data[(j*8) +: 8] : '1;
                 end
              end
              $fwrite(fw, "%x %x %x %d %d \n",  w_beat.w_data, trans_wdata, temp_waddr, (((temp_waddr[AxiMaxSize-1:0]>>size)<<size) + (2**size)), write_index);
              memory[write_index]=trans_wdata;
              if($isunknown(trans_wdata)) begin
                 $fatal(1,"Xs @%x\n",temp_waddr);
              end   
              write_index++;
              if(i==0)
                temp_waddr = ((temp_waddr>>size)<<size) + (2**size);
              else
                temp_waddr = temp_waddr + (2**size);
              last_waddr = temp_waddr[AxiMaxSize-1:0] + (2**size);
          end // for (int unsigned i = 0; i < burst_len + 1; i++)
          
          axi_master_drv.recv_b(b_beat);
        end 
       
    endtask

endmodule : fixture_hyperbus


module tristate_shim (
    input  wire out_ena_i,
    input  wire out_i,
    output wire in_o,
    inout  wire line_io
);

    assign line_io = out_ena_i ? out_i : 1'bz;
    assign in_o    = out_ena_i ? 1'bx  : line_io;

endmodule : tristate_shim
