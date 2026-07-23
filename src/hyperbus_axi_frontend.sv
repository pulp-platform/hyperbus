// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

`include "axi/typedef.svh"
`include "common_cells/registers.svh"
`include "common_cells/assertions.svh"

module hyperbus_axi_frontend #(
    parameter int unsigned AxiDataWidth = -1,
    parameter int unsigned AxiAddrWidth = -1,
    parameter int unsigned AxiIdWidth   = -1,
    parameter int unsigned AxiUserWidth = -1,
    parameter type         axi_req_t    = logic,
    parameter type         axi_rsp_t    = logic,
    parameter type         host_req_t   = logic,
    parameter type         host_rsp_t   = logic
) (
    input  logic       clk_i,
    input  logic       rst_ni,

    input  logic       drain_i,
    output logic       idle_o,

    input  axi_req_t   axi_req_i,
    output axi_rsp_t   axi_rsp_o,

    output host_req_t  host_req_o,
    input  host_rsp_t  host_rsp_i
);

    `ASSERT_INIT(AxiAddrWidthValid, AxiAddrWidth >= 1)
    `ASSERT_INIT(AxiDataWidthValid,
        AxiDataWidth >= 16 && AxiDataWidth <= 1024 &&
        (AxiDataWidth & (AxiDataWidth - 1)) == 0)
    `ASSERT_INIT(AxiIdWidthValid, AxiIdWidth >= 1)
    `ASSERT_INIT(AxiUserWidthValid, AxiUserWidth >= 1)

    typedef logic [AxiAddrWidth-1:0] axi_addr_t;

    // IDs stay in the AXI serializer; the neutral stream is single-outstanding.
    typedef struct packed {
        axi_addr_t       addr;
        axi_pkg::len_t   len;
        axi_pkg::burst_t burst;
        axi_pkg::size_t  size;
        axi_pkg::atop_t  atop;
    } axi_ax_t;

    typedef struct packed {
        axi_ax_t ax_data;
        logic    write;
    } ax_channel_t;

    ///////////////////////////
    // Serialized AXI stream //
    ///////////////////////////

    axi_req_t ser_in_req;
    axi_rsp_t ser_in_rsp;
    axi_req_t ser_out_req;
    axi_rsp_t ser_out_rsp;

    axi_ax_t     ser_out_req_aw;
    axi_ax_t     ser_out_req_ar;
    ax_channel_t ser_out_req_aw_channel;
    ax_channel_t ser_out_req_ar_channel;
    ax_channel_t arbitrated_ax;
    ax_channel_t selected_ax;

    logic ax_arb_valid;
    logic ax_arb_ready;

    //////////////////////
    // Drain accounting //
    //////////////////////

    localparam int unsigned PendingWidth = 8;
    typedef logic [PendingWidth-1:0] pending_cnt_t;
    typedef logic signed [PendingWidth-1:0] write_balance_t;

    pending_cnt_t  read_pending_d, read_pending_q;
    pending_cnt_t  write_pending_d, write_pending_q;
    write_balance_t write_balance_d, write_balance_q;
    logic           w_partial_d, w_partial_q;
    logic           allow_aw, allow_w;
    logic           axi_ar_accepted, axi_aw_accepted, axi_w_accepted;
    logic           axi_atomic_read_started;
    logic           axi_r_completed, axi_b_accepted;

    always_comb begin : proc_axi_drain
        allow_aw = !drain_i;
        allow_w  = !drain_i;

        if (drain_i) begin
            // Complete only channel fragments accepted before the barrier.
            allow_aw = !w_partial_q && (write_balance_q < 0);
            allow_w  = w_partial_q || (write_balance_q > 0);
        end

        ser_in_req          = axi_req_i;
        ser_in_req.ar_valid = axi_req_i.ar_valid && !drain_i;
        ser_in_req.aw_valid = axi_req_i.aw_valid && allow_aw;
        ser_in_req.w_valid  = axi_req_i.w_valid && allow_w;

        axi_rsp_o          = ser_in_rsp;
        axi_rsp_o.ar_ready = ser_in_rsp.ar_ready && !drain_i;
        axi_rsp_o.aw_ready = ser_in_rsp.aw_ready && allow_aw;
        axi_rsp_o.w_ready  = ser_in_rsp.w_ready && allow_w;
    end

    assign axi_ar_accepted = axi_req_i.ar_valid && axi_rsp_o.ar_ready;
    assign axi_aw_accepted = axi_req_i.aw_valid && axi_rsp_o.aw_ready;
    assign axi_w_accepted  = axi_req_i.w_valid && axi_rsp_o.w_ready;
    assign axi_atomic_read_started = axi_aw_accepted &&
                               axi_req_i.aw.atop[axi_pkg::ATOP_R_RESP];
    assign axi_r_completed = axi_rsp_o.r_valid && axi_req_i.r_ready && axi_rsp_o.r.last;
    assign axi_b_accepted  = axi_rsp_o.b_valid && axi_req_i.b_ready;

    always_comb begin : proc_pending_counts
        read_pending_d  = read_pending_q;
        write_pending_d = write_pending_q;
        write_balance_d = write_balance_q;
        w_partial_d     = w_partial_q;

        read_pending_d = read_pending_q + pending_cnt_t'(axi_ar_accepted) +
                         pending_cnt_t'(axi_atomic_read_started) -
                         pending_cnt_t'(axi_r_completed);

        unique case ({axi_aw_accepted, axi_b_accepted})
            2'b10: write_pending_d = write_pending_q + 1'b1;
            2'b01: write_pending_d = write_pending_q - 1'b1;
            default:;
        endcase

        if (axi_aw_accepted) begin
            write_balance_d = write_balance_d + 1'b1;
        end
        if (axi_w_accepted && axi_req_i.w.last) begin
            write_balance_d = write_balance_d - 1'b1;
        end
        if (axi_w_accepted) begin
            w_partial_d = !axi_req_i.w.last;
        end
    end

    `FFARN(read_pending_q, read_pending_d, '0, clk_i, rst_ni)
    `FFARN(write_pending_q, write_pending_d, '0, clk_i, rst_ni)
    `FFARN(write_balance_q, write_balance_d, '0, clk_i, rst_ni)
    `FFARN(w_partial_q, w_partial_d, 1'b0, clk_i, rst_ni)

    assign idle_o = (read_pending_q == '0) && (write_pending_q == '0) &&
                    (write_balance_q == '0) && !w_partial_q;

    /////////////////////////
    // Command arbitration //
    /////////////////////////

    axi_serializer #(
        .MaxReadTxns  ( 4          ),
        .MaxWriteTxns ( 4          ),
        .AxiIdWidth   ( AxiIdWidth ),
        .axi_req_t    ( axi_req_t  ),
        .axi_resp_t   ( axi_rsp_t  )
    ) i_axi_serializer (
        .clk_i,
        .rst_ni,
        .slv_req_i  ( ser_in_req   ),
        .slv_resp_o ( ser_in_rsp   ),
        .mst_req_o  ( ser_out_req  ),
        .mst_resp_i ( ser_out_rsp  )
    );

    assign ser_out_req_ar.addr  = ser_out_req.ar.addr;
    assign ser_out_req_ar.len   = ser_out_req.ar.len;
    assign ser_out_req_ar.burst = ser_out_req.ar.burst;
    assign ser_out_req_ar.size  = ser_out_req.ar.size;
    assign ser_out_req_ar.atop  = '0;

    assign ser_out_req_aw.addr  = ser_out_req.aw.addr;
    assign ser_out_req_aw.len   = ser_out_req.aw.len;
    assign ser_out_req_aw.burst = ser_out_req.aw.burst;
    assign ser_out_req_aw.size  = ser_out_req.aw.size;
    assign ser_out_req_aw.atop  = ser_out_req.aw.atop;

    assign ser_out_req_ar_channel = '{ax_data: ser_out_req_ar, write: 1'b0};
    assign ser_out_req_aw_channel = '{ax_data: ser_out_req_aw, write: 1'b1};

    rr_arb_tree #(
        .NumIn     ( 2            ),
        .DataType  ( ax_channel_t ),
        .AxiVldRdy ( 1'b1         )
    ) i_rr_arb_tree_ax (
        .clk_i,
        .rst_ni,
        .flush_i ( 1'b0                                         ),
        .rr_i    ( '0                                           ),
        .req_i   ( {ser_out_req.aw_valid, ser_out_req.ar_valid} ),
        .gnt_o   ( {ser_out_rsp.aw_ready, ser_out_rsp.ar_ready} ),
        .data_i  ( {ser_out_req_aw_channel, ser_out_req_ar_channel} ),
        .req_o   ( ax_arb_valid                                ),
        .gnt_i   ( ax_arb_ready                                ),
        .data_o  ( arbitrated_ax                               ),
        .idx_o   (                                             )
    );

    stream_register #(
        .T ( ax_channel_t )
    ) i_ax_register (
        .clk_i,
        .rst_ni,
        .clr_i      ( 1'b0                  ),
        .testmode_i ( 1'b0                  ),
        .valid_i    ( ax_arb_valid           ),
        .ready_o    ( ax_arb_ready           ),
        .data_i     ( arbitrated_ax          ),
        .valid_o    ( host_req_o.cmd_valid  ),
        .ready_i    ( host_rsp_i.cmd_ready  ),
        .data_o     ( selected_ax            )
    );

    //////////////////////////
    // Host command mapping //
    //////////////////////////

    assign host_req_o.cmd.write = selected_ax.write;
    assign host_req_o.cmd.addr  = selected_ax.ax_data.addr;
    assign host_req_o.cmd.beats = hyperbus_pkg::hyper_blen_t'(selected_ax.ax_data.len) +
                                  hyperbus_pkg::hyper_blen_t'(1);
    assign host_req_o.cmd.size  = selected_ax.ax_data.size;
    assign host_req_o.cmd.burst = (selected_ax.ax_data.burst == axi_pkg::BURST_FIXED) ?
                                  hyperbus_pkg::HyperBurstFixed :
                                  hyperbus_pkg::HyperBurstIncr;

    logic atomic_arithmetic_class;
    logic atomic_endian_sensitive;
    logic atomic_big_endian_unsupported;

    assign atomic_arithmetic_class =
        (selected_ax.ax_data.atop[5:4] == axi_pkg::ATOP_ATOMICSTORE) ||
        (selected_ax.ax_data.atop[5:4] == axi_pkg::ATOP_ATOMICLOAD);
    assign atomic_endian_sensitive =
        (selected_ax.ax_data.atop[2:0] == axi_pkg::ATOP_ADD) ||
        (selected_ax.ax_data.atop[2:0] >= axi_pkg::ATOP_SMAX);
    assign atomic_big_endian_unsupported =
        selected_ax.ax_data.atop[3] && atomic_endian_sensitive;

    always_comb begin : proc_atomic_decode
        host_req_o.cmd.atomic_op = (selected_ax.ax_data.atop == '0) ?
                                   hyperbus_pkg::HyperAtomicNone :
                                   hyperbus_pkg::HyperAtomicInvalid;
        unique case (selected_ax.ax_data.atop)
            axi_pkg::ATOP_ATOMICSWAP:
                host_req_o.cmd.atomic_op = hyperbus_pkg::HyperAtomicSwap;
            axi_pkg::ATOP_ATOMICCMP:
                host_req_o.cmd.atomic_op = hyperbus_pkg::HyperAtomicCompare;
            default: begin
                if (atomic_arithmetic_class) begin
                    unique case (selected_ax.ax_data.atop[2:0])
                        axi_pkg::ATOP_ADD:
                            host_req_o.cmd.atomic_op = hyperbus_pkg::HyperAtomicAdd;
                        axi_pkg::ATOP_CLR:
                            host_req_o.cmd.atomic_op = hyperbus_pkg::HyperAtomicClear;
                        axi_pkg::ATOP_EOR:
                            host_req_o.cmd.atomic_op = hyperbus_pkg::HyperAtomicXor;
                        axi_pkg::ATOP_SET:
                            host_req_o.cmd.atomic_op = hyperbus_pkg::HyperAtomicSet;
                        axi_pkg::ATOP_SMAX:
                            host_req_o.cmd.atomic_op = hyperbus_pkg::HyperAtomicSignedMax;
                        axi_pkg::ATOP_SMIN:
                            host_req_o.cmd.atomic_op = hyperbus_pkg::HyperAtomicSignedMin;
                        axi_pkg::ATOP_UMAX:
                            host_req_o.cmd.atomic_op = hyperbus_pkg::HyperAtomicUnsignedMax;
                        axi_pkg::ATOP_UMIN:
                            host_req_o.cmd.atomic_op = hyperbus_pkg::HyperAtomicUnsignedMin;
                        default:;
                    endcase
                    // AXI defines bit 3 as endianness for arithmetic atomics.
                    if (atomic_big_endian_unsupported) begin
                        host_req_o.cmd.atomic_op = hyperbus_pkg::HyperAtomicInvalid;
                    end
                end
            end
        endcase
        host_req_o.cmd.atomic_return = selected_ax.ax_data.atop[axi_pkg::ATOP_R_RESP];
        host_req_o.cmd.ordered       = selected_ax.ax_data.atop != '0;
    end

    ///////////////////////
    // Host write stream //
    ///////////////////////

    assign host_req_o.w.data   = ser_out_req.w.data;
    assign host_req_o.w.strb   = ser_out_req.w.strb;
    assign host_req_o.w.last   = ser_out_req.w.last;
    assign host_req_o.w_valid  = ser_out_req.w_valid;
    assign ser_out_rsp.w_ready = host_rsp_i.w_ready;

    //////////////////////
    // Response mapping //
    //////////////////////

    assign ser_out_rsp.r.data  = host_rsp_i.r.data;
    assign ser_out_rsp.r.last  = host_rsp_i.r.last;
    always_comb begin : proc_host_resp
        ser_out_rsp.r.resp = axi_pkg::RESP_OKAY;
        ser_out_rsp.b.resp = axi_pkg::RESP_OKAY;

        if (host_rsp_i.r.resp == hyperbus_pkg::HyperRespDecodeError) begin
            ser_out_rsp.r.resp = axi_pkg::RESP_DECERR;
        end else if (host_rsp_i.r.resp != hyperbus_pkg::HyperRespOkay) begin
            ser_out_rsp.r.resp = axi_pkg::RESP_SLVERR;
        end

        if (host_rsp_i.wrsp.resp == hyperbus_pkg::HyperRespDecodeError) begin
            ser_out_rsp.b.resp = axi_pkg::RESP_DECERR;
        end else if (host_rsp_i.wrsp.resp != hyperbus_pkg::HyperRespOkay) begin
            ser_out_rsp.b.resp = axi_pkg::RESP_SLVERR;
        end
    end

    assign ser_out_rsp.r.id    = '0;
    assign ser_out_rsp.r.user  = '0;
    assign ser_out_rsp.r_valid = host_rsp_i.r_valid;
    assign host_req_o.r_ready  = ser_out_req.r_ready;

    assign ser_out_rsp.b.user  = '0;
    assign ser_out_rsp.b.id    = '0;
    assign ser_out_rsp.b_valid   = host_rsp_i.wrsp_valid;
    assign host_req_o.wrsp_ready = ser_out_req.b_ready;

    `ASSERT(AxiBurstType, (host_req_o.cmd_valid && host_rsp_i.cmd_ready) |->
        ((selected_ax.ax_data.burst == axi_pkg::BURST_INCR) ||
         ((selected_ax.ax_data.burst == axi_pkg::BURST_FIXED) &&
          (selected_ax.ax_data.len == '0))))
    `ASSERT(ReadResponsePending, axi_r_completed |-> (read_pending_q != '0))
    `ASSERT(WriteResponsePending, axi_b_accepted |-> (write_pending_q != '0))

endmodule
