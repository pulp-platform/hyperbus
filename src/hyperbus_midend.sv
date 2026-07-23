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
    parameter type         host_req_t    = logic,
    parameter type         host_w_t      = logic,
    parameter type         host_r_t      = logic,
    parameter type         host_wrsp_t   = logic,
    parameter type         hyper_rx_t    = logic,
    parameter type         hyper_tx_t    = logic,
    parameter type         hyper_cmd_t   = logic,
    parameter type         rule_t        = logic
) (
    input  logic                         clk_i,
    input  logic                         rst_ni,

    input  host_req_t                    host_req_i,
    input  logic                         host_req_valid_i,
    output logic                         host_req_ready_o,

    input  host_w_t                      host_w_i,
    input  logic                         host_w_valid_i,
    output logic                         host_w_ready_o,

    output host_r_t                      host_r_o,
    output logic                         host_r_valid_o,
    input  logic                         host_r_ready_i,

    output host_wrsp_t                   host_wrsp_o,
    output logic                         host_wrsp_valid_o,
    input  logic                         host_wrsp_ready_i,

    input  hyperbus_pkg::frontend_cfg_t  frontend_cfg_i,
    input  rule_t [NumChips-1:0]         chip_rules_i,
    output logic                         trans_active_o,
    output logic                         decode_error_o,

    input  hyper_rx_t                    rx_i,
    input  logic                         rx_valid_i,
    output logic                         rx_ready_o,

    output hyper_tx_t                    tx_o,
    output logic                         tx_valid_o,
    input  logic                         tx_ready_i,

    input  logic                         wrsp_error_i,
    input  logic                         wrsp_valid_i,
    output logic                         wrsp_ready_o,

    output hyper_cmd_t                   cmd_o,
    output logic                         cmd_valid_o,
    input  logic                         cmd_ready_i
);

    localparam int unsigned HostDataBytes    = HostDataWidth / 8;
    localparam int unsigned HostBusAddrWidth = $clog2(HostDataBytes);
    localparam int unsigned PhyDataWidth     = NumPhys * 16;
    localparam int unsigned PhyDataBytes     = PhyDataWidth / 8;
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

    typedef enum logic [1:0] {
        ErrorIdle,
        ErrorRead,
        ErrorWrite,
        ErrorWriteResp
    } error_state_e;

    typedef enum logic [2:0] {
        AtomicIdle,
        AtomicWaitWriteData,
        AtomicReadCmd,
        AtomicReadData,
        AtomicWriteCmd,
        AtomicWriteData,
        AtomicWriteResp,
        AtomicReturn
    } atomic_state_e;

    typedef logic [HostDataWidth-1:0]   host_data_t;
    typedef logic [HostDataBytes-1:0]   host_strb_t;

    chip_sel_idx_t              cmd_chip_sel_idx;
    logic                       cmd_fire;
    logic                       converter_cmd_fire;
    logic                       cmd_dec_valid;
    logic                       cmd_dec_error;
    logic                       req_range_valid;
    logic                       req_decode_error;
    logic                       error_req_fire;
    error_state_e               error_state_d, error_state_q;
    hyperbus_pkg::hyper_blen_t  error_beats_d, error_beats_q;

    host_r_t                    converted_host_r;
    logic                       converted_host_r_valid;
    logic                       converted_host_r_ready;
    logic                       converted_host_w_ready;
    host_w_t                    converted_host_w;
    logic                       converted_host_w_valid;

    host_req_t                  cmd_req;
    host_addr_t                 req_phy_first_addr;
    host_ext_addr_t             req_phy_first_ext;
    host_ext_addr_t             req_phy_end_addr;
    host_ext_addr_t             req_last_addr;
    host_ext_addr_t             req_phy_bytes;
    hyperbus_pkg::hyper_blen_t  req_phy_burst;
    host_ext_addr_t             range_cursor;
    host_ext_addr_t             cmd_rule_end_addr;
    logic                       req_addr_overflow;
    logic                       atomic_range_valid;

    host_req_t                  segment_req_d, segment_req_q;
    hyperbus_pkg::hyper_blen_t  segment_remaining_d, segment_remaining_q;
    hyperbus_pkg::hyper_blen_t  cmd_remaining;
    host_ext_addr_t             cmd_rule_capacity;
    hyperbus_pkg::hyper_blen_t  cmd_segment_burst;
    host_addr_t                 cmd_next_addr;
    logic                       segment_pending_d, segment_pending_q;
    logic                       segment_final_d, segment_final_q;
    logic                       segment_wrsp_error_d, segment_wrsp_error_q;
    logic                       cmd_segment_final;
    logic                       normal_cmd_fire;
    logic                       normal_segment_complete;
    host_req_t                  atomic_req_d, atomic_req_q;
    host_w_t                    atomic_operand_d, atomic_operand_q;
    host_w_t                    atomic_write_d, atomic_write_q;
    host_r_t                    atomic_read_d, atomic_read_q;
    hyperbus_pkg::hyper_resp_e  atomic_resp_d, atomic_resp_q;
    atomic_state_e              atomic_state_d, atomic_state_q;
    logic                       atomic_r_pending_d, atomic_r_pending_q;
    logic                       atomic_b_pending_d, atomic_b_pending_q;
    logic                       atomic_req_fire;
    logic                       atomic_cmd_valid;
    logic                       atomic_active;
    logic                       normal_req;
    logic                       atomic_request_valid;
    host_data_t                 atomic_result;
    host_data_t                 atomic_old_value;
    host_data_t                 atomic_operand_value;
    host_data_t                 atomic_swap_value;
    host_data_t                 atomic_value_mask;
    host_data_t                 atomic_result_value;
    int unsigned                atomic_byte_offset;
    int unsigned                atomic_operand_bytes;
    int unsigned                atomic_operand_bits;

    logic [PhyDataWidth-1:0]    rx_data;
    logic [PhyDataWidth/2-1:0]  rx_data_lower_d;
    logic [PhyDataWidth/2-1:0]  rx_data_lower_q;
    logic                       rx_error;
    logic                       rx_last;
    logic                       rx_valid;
    logic                       rx_ready;
    logic                       merge_r_d;
    logic                       merge_r_q;

    logic [PhyDataWidth-1:0]    tx_data;
    logic [PhyDataBytes-1:0]    tx_strb;
    logic                       tx_last;
    logic                       tx_valid;
    logic                       tx_ready;
    logic                       split_w_d;
    logic                       split_w_q;

    logic                       trans_active_d;
    logic                       trans_active_q;
    logic                       trans_active_set;
    logic                       trans_active_reset;
    logic                       host_req_fire;

    assign atomic_active = atomic_state_q != AtomicIdle;
    assign normal_req = host_req_i.atomic_op == hyperbus_pkg::HyperAtomicNone;
    assign atomic_request_valid =
        (host_req_i.atomic_op != hyperbus_pkg::HyperAtomicInvalid) &&
        (host_req_i.beats == 1) &&
        (host_req_i.burst == hyperbus_pkg::HyperBurstIncr) &&
        (host_req_i.size <= HostBusAddrWidth) &&
        ((host_req_i.atomic_op != hyperbus_pkg::HyperAtomicCompare) ||
         (host_req_i.size != '0)) &&
        atomic_range_valid;
    assign atomic_cmd_valid = (atomic_state_q == AtomicReadCmd) ||
                              (atomic_state_q == AtomicWriteCmd);
    assign cmd_valid_o = atomic_cmd_valid ||
                         segment_pending_q ||
                         (host_req_valid_i && !trans_active_q && cmd_dec_valid &&
                          req_range_valid && normal_req);
    assign host_req_ready_o = !trans_active_q &&
                              (normal_req ?
                               (req_decode_error || (cmd_dec_valid && cmd_ready_i)) : 1'b1);
    assign host_req_fire    = host_req_valid_i && host_req_ready_o;
    assign cmd_fire         = cmd_valid_o && cmd_ready_i;
    assign normal_cmd_fire  = cmd_fire && !atomic_cmd_valid;
    assign converter_cmd_fire = atomic_cmd_valid ? cmd_fire :
                                (normal_cmd_fire && !segment_pending_q);
    assign error_req_fire   = host_req_valid_i && host_req_ready_o && req_decode_error;
    assign atomic_req_fire  = host_req_valid_i && host_req_ready_o && !normal_req;
    assign decode_error_o   = error_req_fire ||
                              (atomic_req_fire && !atomic_range_valid);
    assign trans_active_o   = trans_active_q;

    addr_decode #(
        .NoIndices ( NumChips    ),
        .NoRules   ( NumChips    ),
        .addr_t    ( host_addr_t ),
        .rule_t    ( rule_t      )
    ) i_addr_decode_chip_sel (
        .addr_i           ( req_phy_first_addr ),
        .addr_map_i       ( chip_rules_i       ),
        .idx_o            ( cmd_chip_sel_idx   ),
        .dec_valid_o      ( cmd_dec_valid      ),
        .dec_error_o      ( cmd_dec_error      ),
        .en_default_idx_i ( 1'b0               ),
        .default_idx_i    ( '0                 )
    );

    always_comb begin : proc_cmd_cs
        cmd_o.cs = '0;
        if (cmd_dec_valid) begin
            cmd_o.cs[cmd_chip_sel_idx] = 1'b1;
        end
    end

    always_comb begin : proc_cmd_req
        cmd_req = host_req_i;
        if (segment_pending_q) begin
            cmd_req = segment_req_q;
        end
        if (atomic_active) begin
            cmd_req       = atomic_req_q;
            cmd_req.write = atomic_state_q != AtomicReadCmd;
        end
        if (cmd_req.atomic_op != hyperbus_pkg::HyperAtomicNone) begin
            cmd_req.beats = 1;
            if ((cmd_req.atomic_op == hyperbus_pkg::HyperAtomicCompare) &&
                (cmd_req.size != '0)) begin
                cmd_req.size = cmd_req.size - 1'b1;
            end
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

    // Follow decoder priority across the request and find the first segment boundary.
    always_comb begin : proc_req_rule_range
        range_cursor      = req_phy_first_ext;
        cmd_rule_end_addr = req_phy_first_ext;
        req_range_valid   = !req_addr_overflow;

        for (int unsigned step = 0; step < (2 * NumChips); step++) begin
            logic rule_found;
            int unsigned selected_rule_idx;
            host_ext_addr_t selected_rule_end;
            host_ext_addr_t next_transition;

            rule_found = 1'b0;
            selected_rule_idx = 0;
            selected_rule_end = range_cursor;
            for (int unsigned rule_idx = 0; rule_idx < NumChips; rule_idx++) begin
                host_ext_addr_t rule_end;

                rule_end = (chip_rules_i[rule_idx].end_addr == '0) ?
                           (host_ext_addr_t'(1) << HostAddrWidth) :
                           host_ext_addr_t'(chip_rules_i[rule_idx].end_addr);
                if ((range_cursor >= host_ext_addr_t'(chip_rules_i[rule_idx].start_addr)) &&
                    (range_cursor < rule_end)) begin
                    rule_found = 1'b1;
                    selected_rule_idx = rule_idx;
                    selected_rule_end = rule_end;
                end
            end
            next_transition = selected_rule_end;
            for (int unsigned rule_idx = 0; rule_idx < NumChips; rule_idx++) begin
                host_ext_addr_t rule_start;

                rule_start = host_ext_addr_t'(chip_rules_i[rule_idx].start_addr);
                if ((rule_idx > selected_rule_idx) && (rule_start > range_cursor) &&
                    (rule_start < next_transition)) begin
                    next_transition = rule_start;
                end
            end
            if (step == 0) begin
                cmd_rule_end_addr = next_transition;
            end
            if (range_cursor < req_phy_end_addr) begin
                if (rule_found) begin
                    if ((req_phy_end_addr > next_transition) &&
                        (next_transition[NumPhys-1:0] != '0)) begin
                        req_range_valid = 1'b0;
                    end
                    range_cursor = (req_phy_end_addr < next_transition) ?
                                   req_phy_end_addr : next_transition;
                end else begin
                    req_range_valid = 1'b0;
                end
            end
        end
        if (range_cursor < req_phy_end_addr) begin
            req_range_valid = 1'b0;
        end
    end

    assign atomic_range_valid = cmd_dec_valid && !req_addr_overflow &&
                                (req_phy_end_addr <= cmd_rule_end_addr);

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

    always_comb begin : proc_rx_merge
        rx_valid        = rx_valid_i;
        rx_ready_o      = rx_ready;
        rx_data         = rx_i.data;
        rx_last         = rx_i.last;
        rx_error        = rx_i.error;
        rx_data_lower_d = rx_data_lower_q;
        merge_r_d       = merge_r_q;

        if ((NumPhys == 2) && !frontend_cfg_i.dual_phy) begin
            if (rx_valid_i && rx_ready) begin
                merge_r_d = merge_r_q + 1;
            end
            rx_data  = {rx_i.data[PhyDataWidth/2-1:0], rx_data_lower_q};
            rx_valid   = rx_valid_i && merge_r_q;
            rx_last    = rx_i.last && merge_r_q;
            rx_error   = rx_i.error;
            if (!merge_r_q) begin
                rx_data_lower_d = rx_i.data[PhyDataWidth/2-1:0];
            end
        end
        if (!atomic_active) begin
            rx_last = rx_last && segment_final_q;
        end
    end

    hyperbus_phy2r #(
        .HostDataWidth ( HostDataWidth                  ),
        .BurstLength   ( hyperbus_pkg::HyperBurstWidth ),
        .T             ( host_r_t                      ),
        .NumPhys       ( NumPhys                       )
    ) i_hyperbus_phy2r (
        .clk_i,
        .rst_ni,
        .size_i       ( cmd_req.size                          ),
        .cmd_fire_i   ( converter_cmd_fire                    ),
        .start_addr_i ( cmd_req.addr[HostBusAddrWidth-1:0]    ),
        .burst_len_i  ( cmd_req.beats                         ),
        .is_read_i    ( !cmd_req.write                        ),
        .phy_valid_i  ( rx_valid                              ),
        .phy_ready_o  ( rx_ready                              ),
        .data_i       ( rx_data                               ),
        .last_i       ( rx_last                               ),
        .error_i      ( rx_error                              ),
        .host_valid_o ( converted_host_r_valid               ),
        .host_ready_i ( converted_host_r_ready               ),
        .data_o       ( converted_host_r                     )
    );

    `FFARN(merge_r_q, merge_r_d, 1'b0, clk_i, rst_ni)
    `FFARN(rx_data_lower_q, rx_data_lower_d, '0, clk_i, rst_ni)

    hyperbus_w2phy #(
        .HostDataWidth ( HostDataWidth ),
        .T             ( host_w_t      ),
        .NumPhys       ( NumPhys       )
    ) i_hyperbus_w2phy (
        .clk_i,
        .rst_ni,
        .size_i       ( cmd_req.size                          ),
        .is_write_i   ( cmd_req.write                         ),
        .cmd_fire_i   ( converter_cmd_fire                    ),
        .start_addr_i ( cmd_req.addr[HostBusAddrWidth-1:0]    ),
        .data_i       ( converted_host_w                      ),
        .host_valid_i ( converted_host_w_valid                ),
        .host_ready_o ( converted_host_w_ready                ),
        .data_o       ( tx_data                               ),
        .last_o       ( tx_last                               ),
        .strb_o       ( tx_strb                               ),
        .phy_valid_o  ( tx_valid                              ),
        .phy_ready_i  ( tx_ready                              )
    );

    always_comb begin : proc_tx_split
        tx_o.data  = tx_data;
        tx_o.strb  = tx_strb;
        tx_o.last  = tx_last;
        tx_valid_o = tx_valid;
        tx_ready   = tx_ready_i;
        split_w_d  = split_w_q;

        if ((NumPhys == 2) && !frontend_cfg_i.dual_phy) begin
            if (tx_valid && tx_ready_i) begin
                split_w_d = split_w_q + 1;
            end
            tx_o.last  = tx_last && split_w_q;
            tx_valid_o = tx_valid;
            tx_ready   = tx_ready_i && split_w_q;
            tx_o.data  = {tx_data[PhyDataWidth/2-1:0], tx_data[PhyDataWidth/2-1:0]};
            tx_o.strb  = {tx_strb[NumPhys-1:0], tx_strb[NumPhys-1:0]};
            if (split_w_q) begin
                tx_o.data = {tx_data[PhyDataWidth-1:PhyDataWidth/2],
                             tx_data[PhyDataWidth-1:PhyDataWidth/2]};
                tx_o.strb = {tx_strb[NumPhys*2-1:NumPhys], tx_strb[NumPhys*2-1:NumPhys]};
            end
        end
    end

    `FFARN(split_w_q, split_w_d, 1'b0, clk_i, rst_ni)

    always_comb begin : proc_atomic_alu
        atomic_byte_offset   = 0;
        atomic_operand_bytes = 1;
        atomic_operand_bits  = 8;
        atomic_value_mask = '1;
        atomic_old_value     = atomic_read_q.data;
        atomic_operand_value = atomic_operand_q.data;
        atomic_swap_value    = atomic_operand_q.data >> 8;
        atomic_result_value = atomic_old_value;
        atomic_result       = atomic_read_q.data;

        // Malformed atomics are drained and returned without evaluating invalid widths.
        if (atomic_resp_q == hyperbus_pkg::HyperRespOkay) begin
            atomic_byte_offset = unsigned'(atomic_req_q.addr[HostBusAddrWidth-1:0]);
            atomic_operand_bytes = 1 << ((atomic_req_q.atomic_op ==
                                         hyperbus_pkg::HyperAtomicCompare) ?
                                        (atomic_req_q.size - 1'b1) : atomic_req_q.size);
            atomic_operand_bits = atomic_operand_bytes * 8;

            if (atomic_operand_bits < HostDataWidth) begin
                atomic_value_mask = atomic_value_mask >> (HostDataWidth - atomic_operand_bits);
            end

            atomic_old_value = atomic_read_q.data >> (atomic_byte_offset * 8);
            atomic_operand_value = atomic_operand_q.data >> (atomic_byte_offset * 8);
            atomic_swap_value = atomic_operand_value >> atomic_operand_bits;
            atomic_result_value = atomic_old_value;

            unique case (atomic_req_q.atomic_op)
                hyperbus_pkg::HyperAtomicSwap: begin
                    atomic_result_value = atomic_operand_value;
                end
                hyperbus_pkg::HyperAtomicCompare: begin
                    if ((atomic_old_value & atomic_value_mask) ==
                        (atomic_operand_value & atomic_value_mask)) begin
                        atomic_result_value = atomic_swap_value;
                    end
                end
                hyperbus_pkg::HyperAtomicAdd: begin
                    atomic_result_value = atomic_old_value + atomic_operand_value;
                end
                hyperbus_pkg::HyperAtomicClear: begin
                    atomic_result_value = atomic_old_value & ~atomic_operand_value;
                end
                hyperbus_pkg::HyperAtomicXor: begin
                    atomic_result_value = atomic_old_value ^ atomic_operand_value;
                end
                hyperbus_pkg::HyperAtomicSet: begin
                    atomic_result_value = atomic_old_value | atomic_operand_value;
                end
                hyperbus_pkg::HyperAtomicSignedMax: begin
                    if (atomic_old_value[atomic_operand_bits-1] !=
                        atomic_operand_value[atomic_operand_bits-1]) begin
                        if (atomic_old_value[atomic_operand_bits-1]) begin
                            atomic_result_value = atomic_operand_value;
                        end
                    end else if ((atomic_old_value & atomic_value_mask) <
                                 (atomic_operand_value & atomic_value_mask)) begin
                        atomic_result_value = atomic_operand_value;
                    end
                end
                hyperbus_pkg::HyperAtomicSignedMin: begin
                    if (atomic_old_value[atomic_operand_bits-1] !=
                        atomic_operand_value[atomic_operand_bits-1]) begin
                        if (atomic_operand_value[atomic_operand_bits-1]) begin
                            atomic_result_value = atomic_operand_value;
                        end
                    end else if ((atomic_old_value & atomic_value_mask) >
                                 (atomic_operand_value & atomic_value_mask)) begin
                        atomic_result_value = atomic_operand_value;
                    end
                end
                hyperbus_pkg::HyperAtomicUnsignedMax: begin
                    if ((atomic_old_value & atomic_value_mask) <
                        (atomic_operand_value & atomic_value_mask)) begin
                        atomic_result_value = atomic_operand_value;
                    end
                end
                hyperbus_pkg::HyperAtomicUnsignedMin: begin
                    if ((atomic_old_value & atomic_value_mask) >
                        (atomic_operand_value & atomic_value_mask)) begin
                        atomic_result_value = atomic_operand_value;
                    end
                end
                default:;
            endcase

            atomic_result = atomic_read_q.data &
                            ~(atomic_value_mask << (atomic_byte_offset * 8));
            atomic_result |= (atomic_result_value & atomic_value_mask) <<
                             (atomic_byte_offset * 8);
        end
    end

    always_comb begin : proc_atomic_control
        atomic_state_d     = atomic_state_q;
        atomic_req_d       = atomic_req_q;
        atomic_operand_d   = atomic_operand_q;
        atomic_write_d     = atomic_write_q;
        atomic_read_d      = atomic_read_q;
        atomic_resp_d      = atomic_resp_q;
        atomic_r_pending_d = atomic_r_pending_q;
        atomic_b_pending_d = atomic_b_pending_q;

        unique case (atomic_state_q)
            AtomicIdle: begin
                if (atomic_req_fire) begin
                    atomic_req_d  = host_req_i;
                    atomic_resp_d = hyperbus_pkg::HyperRespOkay;
                    if (!atomic_request_valid) begin
                        atomic_resp_d = hyperbus_pkg::HyperRespAtomicError;
                    end
                    atomic_state_d = AtomicWaitWriteData;
                end
            end
            AtomicWaitWriteData: begin
                if (host_w_valid_i && host_w_ready_o) begin
                    atomic_operand_d = host_w_i;
                    if (atomic_resp_q == hyperbus_pkg::HyperRespOkay) begin
                        atomic_state_d = AtomicReadCmd;
                    end else if (host_w_i.last) begin
                        atomic_r_pending_d = atomic_req_q.atomic_return;
                        atomic_b_pending_d = 1'b1;
                        atomic_state_d     = AtomicReturn;
                    end
                end
            end
            AtomicReadCmd: begin
                if (cmd_fire) begin
                    atomic_state_d = AtomicReadData;
                end
            end
            AtomicReadData: begin
                if (converted_host_r_valid && converted_host_r_ready) begin
                    atomic_read_d = converted_host_r;
                    if (converted_host_r.resp != hyperbus_pkg::HyperRespOkay) begin
                        atomic_resp_d      = converted_host_r.resp;
                        atomic_r_pending_d = atomic_req_q.atomic_return;
                        atomic_b_pending_d = 1'b1;
                        atomic_state_d     = AtomicReturn;
                    end else begin
                        atomic_state_d = AtomicWriteCmd;
                    end
                end
            end
            AtomicWriteCmd: begin
                atomic_write_d.data = atomic_result;
                atomic_write_d.strb = '0;
                atomic_write_d.last = 1'b1;
                for (int unsigned i = 0; i < HostDataBytes; i++) begin
                    if ((i >= atomic_byte_offset) &&
                        (i < atomic_byte_offset + atomic_operand_bytes)) begin
                        atomic_write_d.strb[i] = 1'b1;
                    end
                end
                if (cmd_fire) begin
                    atomic_state_d = AtomicWriteData;
                end
            end
            AtomicWriteData: begin
                if (converted_host_w_valid && converted_host_w_ready) begin
                    atomic_state_d = AtomicWriteResp;
                end
            end
            AtomicWriteResp: begin
                if (wrsp_valid_i && wrsp_ready_o) begin
                    atomic_resp_d = wrsp_error_i ? hyperbus_pkg::HyperRespAccessError :
                                                  hyperbus_pkg::HyperRespOkay;
                    atomic_r_pending_d = atomic_req_q.atomic_return;
                    atomic_b_pending_d = 1'b1;
                    atomic_state_d = AtomicReturn;
                end
            end
            AtomicReturn: begin
                if (host_r_valid_o && host_r_ready_i) begin
                    atomic_r_pending_d = 1'b0;
                end
                if (host_wrsp_valid_o && host_wrsp_ready_i) begin
                    atomic_b_pending_d = 1'b0;
                end
                if ((!atomic_r_pending_q || (host_r_valid_o && host_r_ready_i)) &&
                    (!atomic_b_pending_q || (host_wrsp_valid_o && host_wrsp_ready_i))) begin
                    atomic_state_d = AtomicIdle;
                end
            end
            default: begin
                atomic_state_d = AtomicIdle;
            end
        endcase
    end

    `FFARN(atomic_state_q, atomic_state_d, AtomicIdle, clk_i, rst_ni)
    `FFARN(atomic_req_q, atomic_req_d, '0, clk_i, rst_ni)
    `FFARN(atomic_operand_q, atomic_operand_d, '0, clk_i, rst_ni)
    `FFARN(atomic_write_q, atomic_write_d, '0, clk_i, rst_ni)
    `FFARN(atomic_read_q, atomic_read_d, '0, clk_i, rst_ni)
    `FFARN(atomic_resp_q, atomic_resp_d, hyperbus_pkg::HyperRespOkay, clk_i, rst_ni)
    `FFARN(atomic_r_pending_q, atomic_r_pending_d, 1'b0, clk_i, rst_ni)
    `FFARN(atomic_b_pending_q, atomic_b_pending_d, 1'b0, clk_i, rst_ni)

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
        if (normal_cmd_fire) begin
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
                if (error_req_fire) begin
                    error_beats_d = host_req_i.beats;
                    error_state_d = host_req_i.write ? ErrorWrite : ErrorRead;
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
            converted_host_w       = '0;
            converted_host_w_valid = 1'b0;
            host_w_ready_o          = 1'b0;
            host_r_o                = '0;
            host_r_valid_o          = 1'b0;
            converted_host_r_ready  = 1'b0;
            host_wrsp_o             = '0;
            host_wrsp_valid_o       = 1'b0;
            wrsp_ready_o            = 1'b0;

            unique case (atomic_state_q)
                AtomicWaitWriteData: begin
                    host_w_ready_o = 1'b1;
                end
                AtomicReadData: begin
                    converted_host_r_ready = 1'b1;
                end
                AtomicWriteData: begin
                    converted_host_w       = atomic_write_q;
                    converted_host_w_valid = 1'b1;
                end
                AtomicWriteResp: begin
                    wrsp_ready_o = 1'b1;
                end
                AtomicReturn: begin
                    host_r_o                = atomic_read_q;
                    host_r_o.resp           = atomic_resp_q;
                    host_r_o.last           = 1'b1;
                    host_r_o.atomic_ok      = atomic_resp_q == hyperbus_pkg::HyperRespOkay;
                    host_r_valid_o          = atomic_r_pending_q;
                    host_wrsp_o.resp        = atomic_resp_q;
                    host_wrsp_o.atomic_ok   = atomic_resp_q == hyperbus_pkg::HyperRespOkay;
                    host_wrsp_valid_o       = atomic_b_pending_q;
                end
                default:;
            endcase
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

    assign trans_active_set   = (normal_cmd_fire && !segment_pending_q) ||
                                error_req_fire || atomic_req_fire;
    assign trans_active_reset = atomic_active ?
        ((atomic_state_q == AtomicReturn) &&
         (!atomic_r_pending_q || (host_r_valid_o && host_r_ready_i)) &&
         (!atomic_b_pending_q || (host_wrsp_valid_o && host_wrsp_ready_i))) :
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

    `ASSERT_KNOWN_IF(HostReqKnown, host_req_i, host_req_fire)
    `ASSERT(HostReqBeatsNonzero, host_req_fire |-> (host_req_i.beats != '0))
    `ASSERT(HostReqSizeValid, host_req_fire |-> (host_req_i.size <= HostBusAddrWidth))
    `ASSERT(HostReqBurstValid, host_req_fire |->
        ((host_req_i.burst == hyperbus_pkg::HyperBurstIncr) ||
         ((host_req_i.burst == hyperbus_pkg::HyperBurstFixed) && (host_req_i.beats == 1))))
    `ASSERT(HostReqAtomicValid, host_req_fire |->
        (host_req_i.atomic_op <= hyperbus_pkg::HyperAtomicUnsignedMin))
    `ASSERT(HostReqAtomicWrite, (host_req_fire &&
        (host_req_i.atomic_op != hyperbus_pkg::HyperAtomicNone)) |-> host_req_i.write)
    `ASSERT(BackendBurstNonzero, cmd_fire |-> (cmd_o.trans.burst != '0))

endmodule
