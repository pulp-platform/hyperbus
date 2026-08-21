// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

`include "common_cells/registers.svh"
`include "common_cells/assertions.svh"

module hyperbus_midend #(
    parameter int unsigned HostAddrWidth = -1,
    parameter int unsigned HostDataWidth = -1,
    parameter int unsigned NumChips      = -1,
    parameter int unsigned NumPhys       = -1,
    parameter type         host_cmd_t    = logic,
    parameter type         host_w_t      = logic,
    parameter type         host_r_t      = logic,
    parameter type         host_wrsp_t   = logic,
    parameter type         host_req_t    = logic,
    parameter type         host_rsp_t    = logic,
    parameter type         hyper_rx_t    = logic,
    parameter type         hyper_tx_t    = logic,
    parameter type         hyper_cmd_t   = logic,
    parameter type         hyper_req_t   = logic,
    parameter type         hyper_rsp_t   = logic,
    parameter type         rule_t        = logic
) (
    input  logic                         clk_i,
    input  logic                         rst_ni,

    input  host_req_t                    host_link_req_i,
    output host_rsp_t                    host_link_rsp_o,

    input  hyperbus_pkg::frontend_cfg_t  frontend_cfg_i,
    input  rule_t [NumChips-1:0]         chip_rules_i,
    output logic                         trans_active_o,
    output logic                         decode_error_o,

    output hyper_req_t                   hyper_link_req_o,
    input  hyper_rsp_t                   hyper_link_rsp_i
);

    localparam int unsigned HostDataBytes    = HostDataWidth / 8;
    localparam int unsigned HostBusAddrWidth = $clog2(HostDataBytes);
    localparam int unsigned PhyDataWidth     = NumPhys * 16;
    localparam int unsigned ChipSelWidth     = cf_math_pkg::idx_width(NumChips);

    `ASSERT_INIT(NumChipsValid, NumChips >= 1 && NumChips <= 8)
    `ASSERT_INIT(NumPhysValid, NumPhys == 1 || NumPhys == 2)
    `ASSERT_INIT(HostAddrWidthValid, HostAddrWidth >= HostBusAddrWidth)
    `ASSERT_INIT(HostDataWidthValid,
        HostDataWidth >= PhyDataWidth && HostDataWidth <= 1024 &&
        (HostDataWidth & (HostDataWidth - 1)) == 0 &&
        (HostDataWidth % PhyDataWidth) == 0)

    typedef logic [HostAddrWidth-1:0]   host_addr_t;
    typedef logic [HostAddrWidth:0]     host_ext_addr_t;
    typedef logic [ChipSelWidth-1:0]    chip_sel_idx_t;

    // Unpack the aggregate links at the midend boundary.
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
    hyper_rx_t                  rx_i;
    logic                       rx_valid_i;
    logic                       rx_ready_o;
    hyper_tx_t                  tx_o;
    logic                       tx_valid_o;
    logic                       tx_ready_i;
    logic                       wrsp_error_i;
    logic                       wrsp_valid_i;
    logic                       wrsp_ready_o;
    hyper_cmd_t                 cmd_o;
    logic                       cmd_valid_o;
    logic                       cmd_ready_i;

    assign host_cmd_i       = host_link_req_i.cmd;
    assign host_req_valid_i = host_link_req_i.cmd_valid;
    assign host_w_i         = host_link_req_i.w;
    assign host_w_valid_i   = host_link_req_i.w_valid;
    assign host_r_ready_i   = host_link_req_i.r_ready;
    assign host_wrsp_ready_i = host_link_req_i.wrsp_ready;

    assign host_link_rsp_o.cmd_ready  = host_req_ready_o;
    assign host_link_rsp_o.w_ready    = host_w_ready_o;
    assign host_link_rsp_o.r          = host_r_o;
    assign host_link_rsp_o.r_valid    = host_r_valid_o;
    assign host_link_rsp_o.wrsp       = host_wrsp_o;
    assign host_link_rsp_o.wrsp_valid = host_wrsp_valid_o;

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
    assign hyper_link_req_o.cmd        = cmd_o;
    assign hyper_link_req_o.cmd_valid  = cmd_valid_o;

    // Command decode and invalid-request response tracking.
    typedef enum logic [1:0] {
        ErrorIdle,
        ErrorRead,
        ErrorWrite,
        ErrorWriteResp
    } error_state_e;

    chip_sel_idx_t              cmd_chip_sel_idx;
    chip_sel_idx_t              cmd_end_chip_sel_idx;
    logic                       command_accepted;
    logic                       adapter_started;
    logic                       cmd_dec_valid;
    logic                       cmd_dec_error;
    logic                       cmd_end_dec_valid;
    logic                       req_range_valid;
    logic                       req_decode_error;
    logic                       error_req_accepted;
    error_state_e               error_state_d, error_state_q;
    hyperbus_pkg::hyper_blen_t  error_beats_d, error_beats_q;

    host_r_t                    converted_host_r;
    logic                       converted_host_r_valid;
    logic                       converted_host_r_ready;
    logic                       converted_host_w_ready;
    host_w_t                    converted_host_w;
    logic                       converted_host_w_valid;

    // Address decode and command segmentation.
    host_cmd_t                  cmd_req;
    host_addr_t                 req_phy_first_addr;
    host_ext_addr_t             req_phy_first_ext;
    host_ext_addr_t             req_phy_end_addr;
    host_ext_addr_t             req_last_addr;
    host_ext_addr_t             req_phy_bytes;
    hyperbus_pkg::hyper_blen_t  req_phy_burst;
    host_ext_addr_t             cmd_rule_end_addr;
    logic                       req_addr_overflow;
    logic                       atomic_range_valid;

    host_cmd_t                  segment_req_d, segment_req_q;
    hyperbus_pkg::hyper_blen_t  segment_remaining_d, segment_remaining_q;
    hyperbus_pkg::hyper_blen_t  cmd_remaining;
    host_ext_addr_t             cmd_rule_capacity;
    hyperbus_pkg::hyper_blen_t  cmd_segment_burst;
    host_addr_t                 cmd_next_addr;
    logic                       segment_pending_d, segment_pending_q;
    logic                       segment_final_d, segment_final_q;
    logic                       segment_wrsp_error_d, segment_wrsp_error_q;
    logic                       cmd_segment_final;
    logic                       normal_cmd_accepted;
    logic                       normal_segment_complete;
    // Atomic requests use the same command and data adapters as normal traffic.
    logic                       atomic_req_accepted;
    logic                       atomic_cmd_valid;
    logic                       atomic_active;
    logic                       atomic_completed;
    logic                       normal_req;
    logic                       atomic_request_valid;
    host_cmd_t                  atomic_cmd;
    host_w_t                    atomic_host_w;
    logic                       atomic_host_w_valid;
    logic                       atomic_host_w_ready;
    host_r_t                    atomic_host_r;
    logic                       atomic_host_r_valid;
    host_wrsp_t                 atomic_host_wrsp;
    logic                       atomic_host_wrsp_valid;
    logic                       atomic_read_ready;
    logic                       atomic_wrsp_ready;

    logic                       adapter_rx_last;

    logic                       trans_active_d;
    logic                       trans_active_q;
    logic                       trans_active_set;
    logic                       trans_active_reset;
    logic                       host_req_accepted;

    assign normal_req = host_cmd_i.atomic_op == hyperbus_pkg::HyperAtomicNone;
    assign atomic_request_valid =
        (host_cmd_i.atomic_op != hyperbus_pkg::HyperAtomicInvalid) &&
        (host_cmd_i.beats == 1) &&
        (host_cmd_i.burst == hyperbus_pkg::HyperBurstIncr) &&
        (host_cmd_i.size <= HostBusAddrWidth) &&
        ((host_cmd_i.atomic_op != hyperbus_pkg::HyperAtomicCompare) ||
         (host_cmd_i.size != '0)) &&
        atomic_range_valid;
    assign cmd_valid_o = atomic_cmd_valid ||
                         segment_pending_q ||
                         (host_req_valid_i && !trans_active_q && cmd_dec_valid &&
                          req_range_valid && normal_req);
    assign host_req_ready_o = !trans_active_q &&
                              (normal_req ?
                               (req_decode_error || (cmd_dec_valid && cmd_ready_i)) : 1'b1);
    assign host_req_accepted   = host_req_valid_i && host_req_ready_o;
    assign command_accepted    = cmd_valid_o && cmd_ready_i;
    assign normal_cmd_accepted = command_accepted && !atomic_cmd_valid;
    assign adapter_started = atomic_cmd_valid ? command_accepted :
                             (normal_cmd_accepted && !segment_pending_q);
    assign error_req_accepted  = host_req_accepted && req_decode_error;
    assign atomic_req_accepted = host_req_accepted && !normal_req;
    assign decode_error_o = error_req_accepted ||
                            (atomic_req_accepted && !atomic_range_valid);
    assign trans_active_o   = trans_active_q;

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
        req_addr_overflow = (req_last_addr > (host_ext_addr_t'(1) << HostAddrWidth)) ||
                            (req_phy_end_addr > (host_ext_addr_t'(1) << HostAddrWidth));
    end

    // Software keeps ranges ordered and non-overlapping; transactions may cross contiguous ranges.
    always_comb begin : proc_req_rule_range
        cmd_chip_sel_idx     = '0;
        cmd_end_chip_sel_idx = '0;
        cmd_dec_valid        = 1'b0;
        cmd_end_dec_valid    = 1'b0;
        cmd_rule_end_addr    = req_phy_first_ext;

        for (int unsigned i = 0; i < NumChips; i++) begin
            host_ext_addr_t rule_start;
            host_ext_addr_t rule_end;

            rule_start = host_ext_addr_t'(chip_rules_i[i].start_addr);
            rule_end = (chip_rules_i[i].end_addr == '0) ?
                       (host_ext_addr_t'(1) << HostAddrWidth) :
                       host_ext_addr_t'(chip_rules_i[i].end_addr);
            if (!cmd_dec_valid && (req_phy_first_ext >= rule_start) &&
                (req_phy_first_ext < rule_end)) begin
                cmd_chip_sel_idx  = chip_sel_idx_t'(i);
                cmd_dec_valid     = 1'b1;
                cmd_rule_end_addr = rule_end;
            end
            if (!cmd_end_dec_valid && ((req_phy_end_addr - 1'b1) >= rule_start) &&
                ((req_phy_end_addr - 1'b1) < rule_end)) begin
                cmd_end_chip_sel_idx = chip_sel_idx_t'(i);
                cmd_end_dec_valid    = 1'b1;
            end
        end

        req_range_valid = !req_addr_overflow && cmd_dec_valid && cmd_end_dec_valid &&
                          (cmd_end_chip_sel_idx >= cmd_chip_sel_idx);
        for (int unsigned i = 0; i < NumChips - 1; i++) begin
            if ((i >= cmd_chip_sel_idx) && (i < cmd_end_chip_sel_idx) &&
                (chip_rules_i[i].end_addr != chip_rules_i[i+1].start_addr)) begin
                req_range_valid = 1'b0;
            end
        end
    end

    assign cmd_dec_error = !cmd_dec_valid;
    assign atomic_range_valid = req_range_valid &&
                                (cmd_chip_sel_idx == cmd_end_chip_sel_idx);

    assign req_decode_error = normal_req &&
                              (cmd_dec_error ||
                               (!atomic_active && !segment_pending_q && !req_range_valid));

    assign cmd_o.trans.write         = cmd_req.write;
    assign cmd_o.trans.burst_type    = 1'b1; // Wrapping HyperBus bursts are not supported.
    assign cmd_o.trans.address_space = frontend_cfg_i.address_space;
    assign cmd_o.trans.address       = (NumPhys == 2) ?
        (frontend_cfg_i.dual_phy ?
         ((req_phy_first_addr &
           ((host_addr_t'(1) << frontend_cfg_i.address_mask_msb) - 1)) >> 2) :
         (((req_phy_first_addr &
            ((host_addr_t'(1) << frontend_cfg_i.address_mask_msb) - 1)) >> 2) << 1)) :
        ((req_phy_first_addr &
          ((host_addr_t'(1) << frontend_cfg_i.address_mask_msb) - 1)) >> 1);

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

    assign adapter_rx_last = rx_i.last && (atomic_active || segment_final_q);

    hyperbus_read_adapter #(
        .HostDataWidth ( HostDataWidth                  ),
        .BurstLength   ( hyperbus_pkg::HyperBurstWidth ),
        .T             ( host_r_t                      ),
        .NumPhys       ( NumPhys                       )
    ) i_read_adapter (
        .clk_i,
        .rst_ni,
        .size_i       ( cmd_req.size                          ),
        .start_i      ( adapter_started && !cmd_req.write     ),
        .dual_phy_i   ( frontend_cfg_i.dual_phy               ),
        .start_addr_i ( cmd_req.addr[HostBusAddrWidth-1:0]    ),
        .burst_len_i  ( cmd_req.beats                         ),
        .phy_valid_i  ( rx_valid_i                            ),
        .phy_ready_o  ( rx_ready_o                            ),
        .data_i       ( rx_i.data                             ),
        .last_i       ( adapter_rx_last                       ),
        .error_i      ( rx_i.error                            ),
        .host_valid_o ( converted_host_r_valid               ),
        .host_ready_i ( converted_host_r_ready               ),
        .data_o       ( converted_host_r                     )
    );

    hyperbus_write_adapter #(
        .HostDataWidth ( HostDataWidth ),
        .T             ( host_w_t      ),
        .NumPhys       ( NumPhys       )
    ) i_write_adapter (
        .clk_i,
        .rst_ni,
        .size_i       ( cmd_req.size                          ),
        .start_i      ( adapter_started && cmd_req.write      ),
        .dual_phy_i   ( frontend_cfg_i.dual_phy               ),
        .start_addr_i ( cmd_req.addr[HostBusAddrWidth-1:0]    ),
        .data_i       ( converted_host_w                      ),
        .host_valid_i ( converted_host_w_valid                ),
        .host_ready_o ( converted_host_w_ready                ),
        .data_o       ( tx_o.data                             ),
        .last_o       ( tx_o.last                             ),
        .strb_o       ( tx_o.strb                             ),
        .phy_valid_o  ( tx_valid_o                            ),
        .phy_ready_i  ( tx_ready_i                            )
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
        .command_ready_i     ( cmd_ready_i              ),
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

    assign normal_segment_complete = trans_active_q && !atomic_active &&
        (segment_req_q.write ? (wrsp_valid_i && wrsp_ready_o) :
                               (rx_valid_i && rx_ready_o && rx_i.last));

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
            ErrorIdle: begin
                if (error_req_accepted) begin
                    error_beats_d = host_cmd_i.beats;
                    error_state_d = host_cmd_i.write ? ErrorWrite : ErrorRead;
                end
            end
            ErrorRead: begin
                if (host_r_valid_o && host_r_ready_i) begin
                    error_beats_d = error_beats_q - 1'b1;
                    if (error_beats_q == 1) begin
                        error_state_d = ErrorIdle;
                    end
                end
            end
            ErrorWrite: begin
                if (host_w_valid_i && host_w_ready_o && host_w_i.last) begin
                    error_state_d = ErrorWriteResp;
                end
            end
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
    assign trans_active_reset = atomic_active ? atomic_completed :
        ((host_r_valid_o && host_r_ready_i && host_r_o.last) ||
         (host_wrsp_valid_o && host_wrsp_ready_i));

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
    `ASSERT(BackendBurstNonzero, command_accepted |-> (cmd_o.trans.burst != '0))

endmodule
