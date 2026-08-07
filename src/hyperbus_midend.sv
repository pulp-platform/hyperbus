// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

`include "common_cells/registers.svh"
`include "common_cells/assertions.svh"

module hyperbus_midend #(
    parameter int unsigned HostAddrWidth         = -1,
    parameter int unsigned HostDataWidth         = -1,
    parameter int unsigned NumPhys               = -1,
    parameter int unsigned HostCommandDepth      = 8,
    parameter int unsigned HostWriteBufferBytes = 128,
    parameter type         host_cmd_t            = logic,
    parameter type         host_w_t              = logic,
    parameter type         host_r_t              = logic,
    parameter type         host_wrsp_t           = logic,
    parameter type         host_req_t            = logic,
    parameter type         host_rsp_t            = logic,
    parameter type         hyper_rx_t            = logic,
    parameter type         hyper_tx_t            = logic,
    parameter type         hyper_cmd_t           = logic,
    parameter type         hyper_req_t           = logic,
    parameter type         hyper_rsp_t           = logic,
    parameter type         rule_t                = logic
) (
    input  logic                         clk_i,
    input  logic                         rst_ni,

    input  host_req_t                    host_link_req_i,
    output host_rsp_t                    host_link_rsp_o,

    input  hyperbus_pkg::frontend_cfg_t  frontend_cfg_i,
    input  rule_t [hyperbus_pkg::HyperNumChips-1:0] chip_rules_i,
    output logic                         trans_active_o,
    output logic                         decode_error_o,

    output hyper_req_t                   hyper_link_req_o,
    input  hyper_rsp_t                   hyper_link_rsp_i
);

    localparam int unsigned HostDataBytes     = HostDataWidth / 8;
    localparam int unsigned HostBusAddrWidth  = $clog2(HostDataBytes);
    localparam int unsigned PhyDataWidth      = NumPhys * 16;
    localparam int unsigned WriteFifoDepth    = HostWriteBufferBytes / HostDataBytes;
    localparam int unsigned ReadFifoDepth     = 4;
    localparam int unsigned WriteRspFifoDepth = 4;
    localparam int unsigned ChipSelWidth =
        cf_math_pkg::idx_width(hyperbus_pkg::HyperNumChips);

    `ASSERT_INIT(NumPhysValid, NumPhys == 1 || NumPhys == 2)
    `ASSERT_INIT(HostAddrWidthValid, HostAddrWidth >= HostBusAddrWidth)
    `ASSERT_INIT(HostDataWidthValid,
        HostDataWidth >= PhyDataWidth && HostDataWidth <= 1024 &&
        (HostDataWidth & (HostDataWidth - 1)) == 0 &&
        (HostDataWidth % PhyDataWidth) == 0)
    `ASSERT_INIT(HostCommandDepthValid, HostCommandDepth >= 1)
    `ASSERT_INIT(HostWriteBufferSizeValid,
        HostWriteBufferBytes >= HostDataBytes &&
        (HostWriteBufferBytes % HostDataBytes) == 0)

    typedef logic [HostAddrWidth-1:0]   host_addr_t;
    typedef logic [HostAddrWidth:0]     host_ext_addr_t;
    typedef logic [ChipSelWidth-1:0]    chip_sel_idx_t;

    typedef struct packed {
        hyper_cmd_t                     cmd;
        hyperbus_pkg::hyper_host_size_t size;
        logic [HostBusAddrWidth-1:0]    start_addr;
        hyperbus_pkg::hyper_blen_t      beats;
        logic                           write;
        logic                           start_adapter;
    } command_stage_t;

    /////////////////////////
    // Host stream buffers //
    /////////////////////////

    // Buffer the protocol-neutral host streams at the midend boundary.
    host_cmd_t                  host_cmd_i;
    logic                       host_req_valid_i;
    logic                       host_req_ready_o;
    host_w_t                    host_w_i;
    logic                       host_w_valid_i;
    logic                       host_w_ready_o;
    host_r_t                    host_r_o;
    logic                       host_r_valid_o;
    logic                       host_r_ready_i;
    host_wrsp_t                 host_wrsp_o;
    logic                       host_wrsp_valid_o;
    logic                       host_wrsp_ready_i;

    stream_fifo #(
        .FALL_THROUGH ( 1'b0             ),
        .DEPTH        ( HostCommandDepth ),
        .T            ( host_cmd_t       )
    ) i_host_cmd_fifo (
        .clk_i,
        .rst_ni,
        .flush_i    ( 1'b0                       ),
        .testmode_i ( 1'b0                       ),
        .usage_o    (                            ),
        .data_i     ( host_link_req_i.cmd        ),
        .valid_i    ( host_link_req_i.cmd_valid  ),
        .ready_o    ( host_link_rsp_o.cmd_ready  ),
        .data_o     ( host_cmd_i                 ),
        .valid_o    ( host_req_valid_i           ),
        .ready_i    ( host_req_ready_o           )
    );

    stream_fifo #(
        .FALL_THROUGH ( 1'b0           ),
        .DEPTH        ( WriteFifoDepth ),
        .T            ( host_w_t       )
    ) i_host_w_fifo (
        .clk_i,
        .rst_ni,
        .flush_i    ( 1'b0                       ),
        .testmode_i ( 1'b0                       ),
        .usage_o    (                            ),
        .data_i     ( host_link_req_i.w          ),
        .valid_i    ( host_link_req_i.w_valid    ),
        .ready_o    ( host_link_rsp_o.w_ready    ),
        .data_o     ( host_w_i                   ),
        .valid_o    ( host_w_valid_i             ),
        .ready_i    ( host_w_ready_o             )
    );

    stream_fifo #(
        .FALL_THROUGH ( 1'b0          ),
        .DEPTH        ( ReadFifoDepth ),
        .T            ( host_r_t      )
    ) i_host_r_fifo (
        .clk_i,
        .rst_ni,
        .flush_i    ( 1'b0                      ),
        .testmode_i ( 1'b0                      ),
        .usage_o    (                           ),
        .data_i     ( host_r_o                  ),
        .valid_i    ( host_r_valid_o            ),
        .ready_o    ( host_r_ready_i            ),
        .data_o     ( host_link_rsp_o.r          ),
        .valid_o    ( host_link_rsp_o.r_valid    ),
        .ready_i    ( host_link_req_i.r_ready    )
    );

    stream_fifo #(
        .FALL_THROUGH ( 1'b0              ),
        .DEPTH        ( WriteRspFifoDepth ),
        .T            ( host_wrsp_t       )
    ) i_host_wrsp_fifo (
        .clk_i,
        .rst_ni,
        .flush_i    ( 1'b0                         ),
        .testmode_i ( 1'b0                         ),
        .usage_o    (                              ),
        .data_i     ( host_wrsp_o                  ),
        .valid_i    ( host_wrsp_valid_o            ),
        .ready_o    ( host_wrsp_ready_i            ),
        .data_o     ( host_link_rsp_o.wrsp          ),
        .valid_o    ( host_link_rsp_o.wrsp_valid    ),
        .ready_i    ( host_link_req_i.wrsp_ready    )
    );

    //////////////////
    // Backend link //
    //////////////////

    hyper_rx_t  rx_i;
    hyper_tx_t  tx_o;
    hyper_cmd_t cmd_o;
    logic       rx_valid_i, rx_ready_o;
    logic       tx_valid_o, tx_ready_i;
    logic       wrsp_error_i, wrsp_valid_i, wrsp_ready_o;
    logic       cmd_valid_o, cmd_ready_i;
    command_stage_t command_stage_in, command_stage_out;
    logic           command_stage_ready, command_stage_valid;

    assign rx_i         = hyper_link_rsp_i.rx;
    assign rx_valid_i   = hyper_link_rsp_i.rx_valid;
    assign tx_ready_i   = hyper_link_rsp_i.tx_ready;
    assign wrsp_error_i = hyper_link_rsp_i.wrsp.error;
    assign wrsp_valid_i = hyper_link_rsp_i.wrsp_valid;
    assign cmd_ready_i  = hyper_link_rsp_i.cmd_ready;

    assign hyper_link_req_o.rx_ready   = rx_ready_o;
    assign hyper_link_req_o.tx         = tx_o;
    assign hyper_link_req_o.tx_valid   = tx_valid_o;
    assign hyper_link_req_o.wrsp_ready = wrsp_ready_o;
    assign hyper_link_req_o.cmd        = command_stage_out.cmd;
    assign hyper_link_req_o.cmd_valid  = command_stage_valid;

    ///////////////////////
    // Request selection //
    ///////////////////////

    host_cmd_t cmd_req;
    logic      normal_req;
    logic      host_req_accepted;
    logic      command_accepted;
    logic      backend_command_accepted;
    logic      adapter_started;
    logic      normal_cmd_accepted;
    logic      normal_cmd_valid;
    logic      normal_req_ready;

    ////////////////////
    // Address decode //
    ////////////////////

    chip_sel_idx_t             cmd_chip_sel_idx;
    chip_sel_idx_t             cmd_end_chip_sel_idx;
    host_addr_t                req_phy_first_addr;
    host_addr_t                req_phy_last_addr;
    host_ext_addr_t            req_phy_first_ext;
    host_ext_addr_t            req_phy_end_addr;
    host_ext_addr_t            req_last_addr;
    host_ext_addr_t            req_phy_bytes;
    host_ext_addr_t            cmd_rule_end_addr;
    host_ext_addr_t            covered_rule_end_addr;
    hyperbus_pkg::hyper_blen_t req_phy_burst;
    logic                      cmd_dec_valid;
    logic                      cmd_end_dec_valid;
    logic                      req_addr_overflow;
    logic                      req_range_valid;
    logic                      req_decode_error;
    logic                      atomic_range_valid;

    //////////////////////////
    // Command segmentation //
    //////////////////////////

    host_cmd_t                  segment_req_d, segment_req_q;
    hyperbus_pkg::hyper_blen_t  segment_remaining_d, segment_remaining_q;
    hyperbus_pkg::hyper_blen_t  cmd_remaining;
    hyperbus_pkg::hyper_blen_t  cmd_segment_burst;
    host_ext_addr_t             cmd_rule_capacity;
    host_addr_t                 cmd_next_addr;
    logic                       segment_pending_d, segment_pending_q;
    logic                       segment_final_d, segment_final_q;
    logic                       segment_wrsp_error_d, segment_wrsp_error_q;
    logic                       cmd_segment_final;
    logic                       normal_segment_complete;
    logic                       normal_read_segment_complete;
    logic                       normal_write_segment_complete;

    //////////////////
    // Atomic path //
    //////////////////

    host_cmd_t  atomic_cmd;
    host_w_t    atomic_host_w;
    host_r_t    atomic_host_r;
    host_wrsp_t atomic_host_wrsp;
    logic       atomic_req_accepted;
    logic       atomic_request_error;
    logic       atomic_cmd_valid;
    logic       atomic_active;
    logic       atomic_completed;
    logic       atomic_request_valid;
    logic       atomic_host_w_valid, atomic_host_w_ready;
    logic       atomic_host_r_valid;
    logic       atomic_host_wrsp_valid;
    logic       atomic_read_ready, atomic_wrsp_ready;

    ///////////////////
    // Data adapters //
    ///////////////////

    host_r_t converted_host_r;
    host_w_t converted_host_w;
    logic    converted_host_r_valid, converted_host_r_ready;
    logic    converted_host_w_valid, converted_host_w_ready;
    logic    adapter_rx_last;

    /////////////////////
    // Error responses //
    /////////////////////

    typedef enum logic [1:0] {
        ErrorIdle,
        ErrorRead,
        ErrorWrite,
        ErrorWriteResp
    } error_state_e;

    error_state_e              error_state_d, error_state_q;
    hyperbus_pkg::hyper_blen_t error_beats_d, error_beats_q;
    logic                      error_req_accepted;

    //////////////////////////
    // Transaction lifetime //
    //////////////////////////

    logic trans_active_d, trans_active_q;
    logic trans_active_set, trans_active_reset;
    logic normal_transaction_completed;

    assign normal_req = host_cmd_i.atomic_op == hyperbus_pkg::HyperAtomicNone;
    assign atomic_request_valid =
        (host_cmd_i.atomic_op != hyperbus_pkg::HyperAtomicInvalid) &&
        (host_cmd_i.beats == 1) &&
        (host_cmd_i.burst == hyperbus_pkg::HyperBurstIncr) &&
        (host_cmd_i.size <= HostBusAddrWidth) &&
        ((host_cmd_i.atomic_op != hyperbus_pkg::HyperAtomicCompare) ||
         (host_cmd_i.size != '0)) &&
        atomic_range_valid;
    assign normal_cmd_valid = host_req_valid_i && !trans_active_q && cmd_dec_valid &&
                              req_range_valid && normal_req;
    assign normal_req_ready = req_decode_error || (cmd_dec_valid && command_stage_ready);
    assign cmd_valid_o      = atomic_cmd_valid || segment_pending_q || normal_cmd_valid;
    assign host_req_ready_o = !trans_active_q && (!normal_req || normal_req_ready);
    assign host_req_accepted   = host_req_valid_i && host_req_ready_o;
    assign command_accepted    = cmd_valid_o && command_stage_ready;
    assign backend_command_accepted = command_stage_valid && cmd_ready_i;
    assign normal_cmd_accepted = command_accepted && !atomic_cmd_valid;
    assign adapter_started = backend_command_accepted && command_stage_out.start_adapter;
    assign error_req_accepted  = host_req_accepted && req_decode_error;
    assign atomic_req_accepted = host_req_accepted && !normal_req;
    assign atomic_request_error = atomic_req_accepted && !atomic_request_valid;
    assign decode_error_o = error_req_accepted || atomic_request_error;
    assign trans_active_o = trans_active_q || host_req_valid_i || host_w_valid_i ||
                            host_link_rsp_o.r_valid || host_link_rsp_o.wrsp_valid ||
                            command_stage_valid;

    always_comb begin : proc_cmd_cs
        cmd_o.cs = '0;
        if (cmd_dec_valid) begin
            cmd_o.cs[cmd_chip_sel_idx] = 1'b1;
        end
    end

    always_comb begin : proc_cmd_req
        cmd_req = host_cmd_i;
        if (segment_pending_q) begin
            cmd_req = segment_req_q;
        end
        if (atomic_active) begin
            cmd_req = atomic_cmd;
        end
    end

    // Cover every aligned PHY group touched by the host transaction.
    always_comb begin : proc_req_phy_range
        req_phy_first_addr = (cmd_req.addr >> NumPhys) << NumPhys;
        req_phy_first_ext = host_ext_addr_t'(req_phy_first_addr);
        req_last_addr = (host_ext_addr_t'(cmd_req.addr >> cmd_req.size) << cmd_req.size) +
                        (host_ext_addr_t'(cmd_req.beats) << cmd_req.size);
        req_phy_bytes = ((req_last_addr - req_phy_first_ext) +
                         ((host_ext_addr_t'(1) << NumPhys) - 1)) >> NumPhys;
        req_phy_bytes = req_phy_bytes << NumPhys;
        req_phy_burst = hyperbus_pkg::hyper_blen_t'(req_phy_bytes >> 1);
        req_phy_end_addr = req_phy_first_ext + req_phy_bytes;
        req_phy_last_addr = host_addr_t'(req_phy_end_addr - 1'b1);
        req_addr_overflow = (req_last_addr > (host_ext_addr_t'(1) << HostAddrWidth)) ||
                            (req_phy_end_addr > (host_ext_addr_t'(1) << HostAddrWidth));
    end

    // Decode only enabled rules; common_cells addr_decode has no per-rule enable.
    always_comb begin : proc_chip_decode
        cmd_chip_sel_idx = '0;
        cmd_end_chip_sel_idx = '0;
        cmd_dec_valid = 1'b0;
        cmd_end_dec_valid = 1'b0;

        for (int unsigned i = 0; i < hyperbus_pkg::HyperNumChips; i++) begin
            if (frontend_cfg_i.chip[i].enable &&
                (req_phy_first_addr >= chip_rules_i[i].start_addr) &&
                ((req_phy_first_addr < chip_rules_i[i].end_addr) ||
                 (chip_rules_i[i].end_addr == '0))) begin
                cmd_chip_sel_idx = chip_sel_idx_t'(i);
                cmd_dec_valid = 1'b1;
            end
            if (frontend_cfg_i.chip[i].enable &&
                (req_phy_last_addr >= chip_rules_i[i].start_addr) &&
                ((req_phy_last_addr < chip_rules_i[i].end_addr) ||
                 (chip_rules_i[i].end_addr == '0))) begin
                cmd_end_chip_sel_idx = chip_sel_idx_t'(i);
                cmd_end_dec_valid = 1'b1;
            end
        end
    end

    // Software keeps ranges ordered and non-overlapping; transactions may cross contiguous ranges.
    always_comb begin : proc_req_rule_range
        cmd_rule_end_addr = req_phy_first_ext;
        if (cmd_dec_valid) begin
            cmd_rule_end_addr = (chip_rules_i[cmd_chip_sel_idx].end_addr == '0) ?
                                (host_ext_addr_t'(1) << HostAddrWidth) :
                                host_ext_addr_t'(
                                    chip_rules_i[cmd_chip_sel_idx].end_addr);
        end
        covered_rule_end_addr = cmd_rule_end_addr;

        req_range_valid = !req_addr_overflow && cmd_dec_valid && cmd_end_dec_valid &&
                          (cmd_end_chip_sel_idx >= cmd_chip_sel_idx) &&
                          frontend_cfg_i.chip[cmd_chip_sel_idx].enable &&
                          frontend_cfg_i.chip[cmd_end_chip_sel_idx].enable;
        for (int unsigned i = 0; i < hyperbus_pkg::HyperNumChips; i++) begin
            if ((i > cmd_chip_sel_idx) && (i <= cmd_end_chip_sel_idx) &&
                frontend_cfg_i.chip[i].enable) begin
                if (host_ext_addr_t'(chip_rules_i[i].start_addr) !=
                    covered_rule_end_addr) begin
                    req_range_valid = 1'b0;
                end
                covered_rule_end_addr = (chip_rules_i[i].end_addr == '0) ?
                    (host_ext_addr_t'(1) << HostAddrWidth) :
                    host_ext_addr_t'(chip_rules_i[i].end_addr);
            end
        end
    end

    assign atomic_range_valid = req_range_valid &&
                                (cmd_chip_sel_idx == cmd_end_chip_sel_idx);

    assign req_decode_error = normal_req &&
                              (!cmd_dec_valid ||
                               (!atomic_active && !segment_pending_q && !req_range_valid));

    assign cmd_o.trans.write         = cmd_req.write;
    assign cmd_o.trans.burst_type    = 1'b1; // Wrapping HyperBus bursts are not supported.
    assign cmd_o.trans.address_space = cmd_dec_valid ?
        frontend_cfg_i.chip[cmd_chip_sel_idx].address_space : 1'b0;
    host_addr_t cmd_phy_address;
    host_addr_t masked_req_address;

    always_comb begin : proc_cmd_address
        masked_req_address = req_phy_first_addr &
                             ((host_addr_t'(1) << (cmd_dec_valid ?
                                frontend_cfg_i.chip[cmd_chip_sel_idx].address_mask_msb : 5'd0)) - 1);
        cmd_phy_address = masked_req_address >> 1;
        if (NumPhys == 2) begin
            cmd_phy_address = masked_req_address >> 2;
            if (!frontend_cfg_i.dual_phy) begin
                cmd_phy_address = cmd_phy_address << 1;
            end
        end
    end

    assign cmd_o.trans.address = cmd_phy_address;

    always_comb begin : proc_cmd_segment
        cmd_remaining = segment_pending_q ? segment_remaining_q : req_phy_burst;
        cmd_rule_capacity = host_ext_addr_t'(cmd_remaining);
        if (cmd_dec_valid) begin
            cmd_rule_capacity = (cmd_rule_end_addr - req_phy_first_ext) >> 1;
        end
        cmd_segment_burst = cmd_remaining;
        if (cmd_rule_capacity < host_ext_addr_t'(cmd_remaining)) begin
            cmd_segment_burst = hyperbus_pkg::hyper_blen_t'(cmd_rule_capacity);
        end
        if (atomic_cmd_valid) begin
            cmd_segment_burst = req_phy_burst;
        end

        cmd_segment_final = atomic_cmd_valid || (cmd_segment_burst == cmd_remaining);
        cmd_next_addr = host_addr_t'(req_phy_first_ext +
                                     (host_ext_addr_t'(cmd_segment_burst) << 1));
        cmd_o.trans.burst = cmd_segment_burst;
    end

    assign command_stage_in.cmd           = cmd_o;
    assign command_stage_in.size          = cmd_req.size;
    assign command_stage_in.start_addr    = cmd_req.addr[HostBusAddrWidth-1:0];
    assign command_stage_in.beats         = cmd_req.beats;
    assign command_stage_in.write         = cmd_req.write;
    assign command_stage_in.start_adapter = atomic_cmd_valid || !segment_pending_q;

    stream_register #(
        .T ( command_stage_t )
    ) i_command_stage (
        .clk_i,
        .rst_ni,
        .clr_i      ( 1'b0               ),
        .testmode_i ( 1'b0               ),
        .valid_i    ( cmd_valid_o         ),
        .ready_o    ( command_stage_ready ),
        .data_i     ( command_stage_in    ),
        .valid_o    ( command_stage_valid ),
        .ready_i    ( cmd_ready_i         ),
        .data_o     ( command_stage_out   )
    );

    assign adapter_rx_last = rx_i.last && (atomic_active || segment_final_q);

    hyperbus_read_adapter #(
        .HostDataWidth ( HostDataWidth                  ),
        .BurstLength   ( hyperbus_pkg::HyperBurstWidth ),
        .T             ( host_r_t                      ),
        .NumPhys       ( NumPhys                       )
    ) i_read_adapter (
        .clk_i,
        .rst_ni,
        .size_i       ( command_stage_out.size                   ),
        .start_i      ( adapter_started && !command_stage_out.write ),
        .dual_phy_i   ( frontend_cfg_i.dual_phy                  ),
        .start_addr_i ( command_stage_out.start_addr             ),
        .burst_len_i  ( command_stage_out.beats                  ),
        .phy_valid_i  ( rx_valid_i                               ),
        .phy_ready_o  ( rx_ready_o                               ),
        .data_i       ( rx_i.data                                ),
        .last_i       ( adapter_rx_last                          ),
        .error_i      ( rx_i.error                               ),
        .host_valid_o ( converted_host_r_valid                  ),
        .host_ready_i ( converted_host_r_ready                  ),
        .data_o       ( converted_host_r                        )
    );

    hyperbus_write_adapter #(
        .HostDataWidth ( HostDataWidth ),
        .T             ( host_w_t      ),
        .NumPhys       ( NumPhys       )
    ) i_write_adapter (
        .clk_i,
        .rst_ni,
        .size_i       ( command_stage_out.size                  ),
        .start_i      ( adapter_started && command_stage_out.write ),
        .dual_phy_i   ( frontend_cfg_i.dual_phy                 ),
        .start_addr_i ( command_stage_out.start_addr            ),
        .data_i       ( converted_host_w                        ),
        .host_valid_i ( converted_host_w_valid                  ),
        .host_ready_o ( converted_host_w_ready                  ),
        .data_o       ( tx_o.data                               ),
        .last_o       ( tx_o.last                               ),
        .strb_o       ( tx_o.strb                               ),
        .phy_valid_o  ( tx_valid_o                              ),
        .phy_ready_i  ( tx_ready_i                              )
    );

    hyperbus_atomic_handler #(
        .HostAddrWidth ( HostAddrWidth ),
        .HostDataWidth ( HostDataWidth ),
        .host_cmd_t    ( host_cmd_t    ),
        .host_w_t      ( host_w_t      ),
        .host_r_t      ( host_r_t      ),
        .host_wrsp_t   ( host_wrsp_t   )
    ) i_atomic_handler (
        .clk_i,
        .rst_ni,
        .start_i             ( atomic_req_accepted      ),
        .request_valid_i     ( atomic_request_valid     ),
        .request_i           ( host_cmd_i               ),
        .active_o            ( atomic_active            ),
        .completed_o         ( atomic_completed         ),
        .command_o           ( atomic_cmd               ),
        .command_valid_o     ( atomic_cmd_valid         ),
        .command_ready_i     ( command_stage_ready      ),
        .host_w_i            ( host_w_i                 ),
        .host_w_valid_i      ( host_w_valid_i           ),
        .host_w_ready_o      ( atomic_host_w_ready      ),
        .host_r_o            ( atomic_host_r            ),
        .host_r_valid_o      ( atomic_host_r_valid      ),
        .host_r_ready_i      ( host_r_ready_i           ),
        .host_wrsp_o         ( atomic_host_wrsp         ),
        .host_wrsp_valid_o   ( atomic_host_wrsp_valid   ),
        .host_wrsp_ready_i   ( host_wrsp_ready_i        ),
        .read_i              ( converted_host_r         ),
        .read_valid_i        ( converted_host_r_valid   ),
        .read_ready_o        ( atomic_read_ready        ),
        .write_o             ( atomic_host_w            ),
        .write_valid_o       ( atomic_host_w_valid      ),
        .write_ready_i       ( converted_host_w_ready   ),
        .write_rsp_error_i   ( wrsp_error_i             ),
        .write_rsp_valid_i   ( wrsp_valid_i             ),
        .write_rsp_ready_o   ( atomic_wrsp_ready        )
    );

    assign normal_read_segment_complete = !segment_req_q.write &&
                                          rx_valid_i && rx_ready_o && rx_i.last;
    assign normal_write_segment_complete = segment_req_q.write &&
                                           wrsp_valid_i && wrsp_ready_o;
    assign normal_segment_complete = trans_active_q && !atomic_active &&
        (normal_read_segment_complete || normal_write_segment_complete);

    always_comb begin : proc_segments
        segment_req_d        = segment_req_q;
        segment_remaining_d  = segment_remaining_q;
        segment_pending_d    = segment_pending_q;
        segment_final_d      = segment_final_q;
        segment_wrsp_error_d = segment_wrsp_error_q;

        if (normal_segment_complete && !segment_final_q) begin
            segment_pending_d = 1'b1;
            if (segment_req_q.write && wrsp_error_i) begin
                segment_wrsp_error_d = 1'b1;
            end
        end
        if (normal_cmd_accepted) begin
            segment_pending_d   = 1'b0;
            segment_final_d     = cmd_segment_final;
            segment_req_d       = cmd_req;
            segment_req_d.addr  = cmd_next_addr;
            segment_remaining_d = cmd_remaining - cmd_segment_burst;
            if (!trans_active_q) begin
                segment_wrsp_error_d = 1'b0;
            end
        end
    end

    `FFARN(segment_req_q, segment_req_d, '0, clk_i, rst_ni)
    `FFARN(segment_remaining_q, segment_remaining_d, '0, clk_i, rst_ni)
    `FFARN(segment_pending_q, segment_pending_d, 1'b0, clk_i, rst_ni)
    `FFARN(segment_final_q, segment_final_d, 1'b1, clk_i, rst_ni)
    `FFARN(segment_wrsp_error_q, segment_wrsp_error_d, 1'b0, clk_i, rst_ni)

    always_comb begin : proc_error_control
        error_state_d = error_state_q;
        error_beats_d = error_beats_q;

        unique case (error_state_q)
            // Capture a rejected command and select its response stream.
            ErrorIdle: begin
                if (error_req_accepted) begin
                    error_beats_d = host_cmd_i.beats;
                    error_state_d = host_cmd_i.write ? ErrorWrite : ErrorRead;
                end
            end
            // Return one decode-error beat per requested read beat.
            ErrorRead: begin
                if (host_r_valid_o && host_r_ready_i) begin
                    error_beats_d = error_beats_q - 1'b1;
                    if (error_beats_q == 1) begin
                        error_state_d = ErrorIdle;
                    end
                end
            end
            // Drain all write data belonging to a rejected write command.
            ErrorWrite: begin
                if (host_w_valid_i && host_w_ready_o && host_w_i.last) begin
                    error_state_d = ErrorWriteResp;
                end
            end
            // Return the final decode-error write response.
            ErrorWriteResp: begin
                if (host_wrsp_valid_o && host_wrsp_ready_i) begin
                    error_state_d = ErrorIdle;
                end
            end
            default: begin
                error_state_d = ErrorIdle;
            end
        endcase
    end

    always_comb begin : proc_host_mux
        converted_host_w       = host_w_i;
        converted_host_w_valid = host_w_valid_i;
        host_w_ready_o          = converted_host_w_ready;
        host_r_o                = converted_host_r;
        host_r_valid_o          = converted_host_r_valid;
        converted_host_r_ready  = host_r_ready_i;
        host_wrsp_o.resp        = (wrsp_error_i || segment_wrsp_error_q) ?
                                  hyperbus_pkg::HyperRespAccessError :
                                  hyperbus_pkg::HyperRespOkay;
        host_wrsp_o.atomic_ok   = 1'b0;
        host_wrsp_valid_o       = wrsp_valid_i && segment_final_q;
        wrsp_ready_o            = segment_final_q ? host_wrsp_ready_i : 1'b1;

        if (atomic_active) begin
            converted_host_w       = atomic_host_w;
            converted_host_w_valid = atomic_host_w_valid;
            host_w_ready_o          = atomic_host_w_ready;
            host_r_o                = atomic_host_r;
            host_r_valid_o          = atomic_host_r_valid;
            converted_host_r_ready  = atomic_read_ready;
            host_wrsp_o             = atomic_host_wrsp;
            host_wrsp_valid_o       = atomic_host_wrsp_valid;
            wrsp_ready_o            = atomic_wrsp_ready;
        end

        if (error_state_q != ErrorIdle) begin
            converted_host_w       = '0;
            converted_host_w_valid = 1'b0;
            host_w_ready_o          = error_state_q == ErrorWrite;
            host_r_o                = '0;
            host_r_o.resp           = hyperbus_pkg::HyperRespDecodeError;
            host_r_o.last           = error_beats_q == 1;
            host_r_valid_o          = error_state_q == ErrorRead;
            converted_host_r_ready  = 1'b0;
            host_wrsp_o             = '0;
            host_wrsp_o.resp        = hyperbus_pkg::HyperRespDecodeError;
            host_wrsp_valid_o       = error_state_q == ErrorWriteResp;
            wrsp_ready_o            = 1'b0;
        end
    end

    `FFARN(error_state_q, error_state_d, ErrorIdle, clk_i, rst_ni)
    `FFARN(error_beats_q, error_beats_d, '0, clk_i, rst_ni)

    assign trans_active_set   = (normal_cmd_accepted && !segment_pending_q) ||
                                error_req_accepted || atomic_req_accepted;
    assign normal_transaction_completed =
        (host_r_valid_o && host_r_ready_i && host_r_o.last) ||
        (host_wrsp_valid_o && host_wrsp_ready_i);
    assign trans_active_reset = (atomic_active && atomic_completed) ||
                                (!atomic_active && normal_transaction_completed);

    always_comb begin : proc_trans_active
        trans_active_d = trans_active_q;

        if (trans_active_reset) begin
            trans_active_d = 1'b0;
        end
        if (trans_active_set) begin
            trans_active_d = 1'b1;
        end
    end

    `FFARN(trans_active_q, trans_active_d, 1'b0, clk_i, rst_ni)

    `ASSERT_KNOWN_IF(HostReqKnown, host_cmd_i, host_req_accepted)
    `ASSERT(HostReqBeatsNonzero, host_req_accepted |-> (host_cmd_i.beats != '0))
    `ASSERT(HostReqSizeValid, host_req_accepted |-> (host_cmd_i.size <= HostBusAddrWidth))
    `ASSERT(HostReqBurstValid, host_req_accepted |->
        ((host_cmd_i.burst == hyperbus_pkg::HyperBurstIncr) ||
         ((host_cmd_i.burst == hyperbus_pkg::HyperBurstFixed) && (host_cmd_i.beats == 1))))
    `ASSERT(HostReqAtomicValid, host_req_accepted |->
        (host_cmd_i.atomic_op <= hyperbus_pkg::HyperAtomicUnsignedMin))
    `ASSERT(HostReqAtomicWrite, (host_req_accepted &&
        (host_cmd_i.atomic_op != hyperbus_pkg::HyperAtomicNone)) |-> host_cmd_i.write)
    `ASSERT(BackendBurstNonzero, backend_command_accepted |->
        (command_stage_out.cmd.trans.burst != '0))

endmodule
