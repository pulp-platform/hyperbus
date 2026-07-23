// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

`include "common_cells/registers.svh"

module hyperbus_atomic_handler #(
    parameter int unsigned HostAddrWidth = -1,
    parameter int unsigned HostDataWidth = -1,
    parameter type         host_cmd_t    = logic,
    parameter type         host_w_t      = logic,
    parameter type         host_r_t      = logic,
    parameter type         host_wrsp_t   = logic
) (
    input  logic             clk_i,
    input  logic             rst_ni,

    input  logic             start_i,
    input  logic             request_valid_i,
    input  host_cmd_t        request_i,
    output logic             active_o,
    output logic             completed_o,

    output host_cmd_t        command_o,
    output logic             command_valid_o,
    input  logic             command_ready_i,

    input  host_w_t          host_w_i,
    input  logic             host_w_valid_i,
    output logic             host_w_ready_o,
    output host_r_t          host_r_o,
    output logic             host_r_valid_o,
    input  logic             host_r_ready_i,
    output host_wrsp_t       host_wrsp_o,
    output logic             host_wrsp_valid_o,
    input  logic             host_wrsp_ready_i,

    input  host_r_t          read_i,
    input  logic             read_valid_i,
    output logic             read_ready_o,
    output host_w_t          write_o,
    output logic             write_valid_o,
    input  logic             write_ready_i,
    input  logic             write_rsp_error_i,
    input  logic             write_rsp_valid_i,
    output logic             write_rsp_ready_o
);

    localparam int unsigned HostDataBytes    = HostDataWidth / 8;
    localparam int unsigned HostBusAddrWidth = $clog2(HostDataBytes);

    typedef logic [HostAddrWidth-1:0] host_addr_t;
    typedef logic [HostDataWidth-1:0] host_data_t;

    typedef enum logic [2:0] {
        Idle,
        WaitWriteData,
        ReadCommand,
        ReadData,
        WriteCommand,
        WriteData,
        WriteResponse,
        ReturnResponse
    } atomic_state_e;

    typedef struct packed {
        host_addr_t                      addr;
        hyperbus_pkg::hyper_host_size_t size;
        hyperbus_pkg::hyper_atomic_op_e atomic_op;
        logic                            atomic_return;
    } atomic_request_t;

    atomic_state_e             state_d, state_q;
    atomic_request_t           request_d, request_q;
    host_data_t                operand_d, operand_q;
    host_data_t                read_data_d, read_data_q;
    hyperbus_pkg::hyper_resp_e response_d, response_q;
    logic                      read_pending_d, read_pending_q;
    logic                      write_pending_d, write_pending_q;

    host_data_t                value_mask;
    host_data_t                old_value;
    host_data_t                operand_value;
    host_data_t                swap_value;
    host_data_t                result_value;
    host_data_t                write_data;
    int unsigned               byte_offset;
    int unsigned               operand_bytes;
    int unsigned               operand_bits;

    assign active_o        = state_q != Idle;
    assign command_valid_o = (state_q == ReadCommand) || (state_q == WriteCommand);
    assign completed_o = (state_q == ReturnResponse) &&
        (!read_pending_q || (host_r_valid_o && host_r_ready_i)) &&
        (!write_pending_q || (host_wrsp_valid_o && host_wrsp_ready_i));

    always_comb begin : proc_command
        command_o               = '0;
        command_o.write         = state_q == WriteCommand;
        command_o.addr          = request_q.addr;
        command_o.beats         = 1;
        command_o.size          = request_q.size;
        command_o.burst         = hyperbus_pkg::HyperBurstIncr;
        command_o.atomic_op     = hyperbus_pkg::HyperAtomicNone;
        command_o.atomic_return = 1'b0;
        command_o.ordered       = 1'b1;
        if ((request_q.atomic_op == hyperbus_pkg::HyperAtomicCompare) &&
            (request_q.size != '0)) begin
            command_o.size = request_q.size - 1'b1;
        end
    end

    always_comb begin : proc_alu
        byte_offset  = 0;
        operand_bytes = 1;
        operand_bits = 8;
        value_mask   = '1;
        old_value    = read_data_q;
        operand_value = operand_q;
        swap_value   = operand_q >> 8;
        result_value = old_value;
        write_data   = read_data_q;

        if (response_q == hyperbus_pkg::HyperRespOkay) begin
            byte_offset = unsigned'(request_q.addr[HostBusAddrWidth-1:0]);
            operand_bytes = 1 << ((request_q.atomic_op == hyperbus_pkg::HyperAtomicCompare) ?
                                  (request_q.size - 1'b1) : request_q.size);
            operand_bits = operand_bytes * 8;
            if (operand_bits < HostDataWidth) begin
                value_mask = value_mask >> (HostDataWidth - operand_bits);
            end

            old_value     = read_data_q >> (byte_offset * 8);
            operand_value = operand_q >> (byte_offset * 8);
            swap_value    = operand_value >> operand_bits;
            result_value  = old_value;

            unique case (request_q.atomic_op)
                hyperbus_pkg::HyperAtomicSwap: result_value = operand_value;
                hyperbus_pkg::HyperAtomicCompare: begin
                    if ((old_value & value_mask) == (operand_value & value_mask)) begin
                        result_value = swap_value;
                    end
                end
                hyperbus_pkg::HyperAtomicAdd: result_value = old_value + operand_value;
                hyperbus_pkg::HyperAtomicClear: result_value = old_value & ~operand_value;
                hyperbus_pkg::HyperAtomicXor: result_value = old_value ^ operand_value;
                hyperbus_pkg::HyperAtomicSet: result_value = old_value | operand_value;
                hyperbus_pkg::HyperAtomicSignedMax: begin
                    if ((old_value[operand_bits-1] && !operand_value[operand_bits-1]) ||
                        ((old_value[operand_bits-1] == operand_value[operand_bits-1]) &&
                         ((old_value & value_mask) < (operand_value & value_mask)))) begin
                        result_value = operand_value;
                    end
                end
                hyperbus_pkg::HyperAtomicSignedMin: begin
                    if ((!old_value[operand_bits-1] && operand_value[operand_bits-1]) ||
                        ((old_value[operand_bits-1] == operand_value[operand_bits-1]) &&
                         ((old_value & value_mask) > (operand_value & value_mask)))) begin
                        result_value = operand_value;
                    end
                end
                hyperbus_pkg::HyperAtomicUnsignedMax: begin
                    if ((old_value & value_mask) < (operand_value & value_mask)) begin
                        result_value = operand_value;
                    end
                end
                hyperbus_pkg::HyperAtomicUnsignedMin: begin
                    if ((old_value & value_mask) > (operand_value & value_mask)) begin
                        result_value = operand_value;
                    end
                end
                default:;
            endcase

            write_data = read_data_q & ~(value_mask << (byte_offset * 8));
            write_data |= (result_value & value_mask) << (byte_offset * 8);
        end
    end

    always_comb begin : proc_outputs
        host_w_ready_o    = state_q == WaitWriteData;
        host_r_o          = '0;
        host_r_o.data     = read_data_q;
        host_r_o.resp     = response_q;
        host_r_o.last     = 1'b1;
        host_r_o.atomic_ok = response_q == hyperbus_pkg::HyperRespOkay;
        host_r_valid_o    = (state_q == ReturnResponse) && read_pending_q;
        host_wrsp_o       = '0;
        host_wrsp_o.resp  = response_q;
        host_wrsp_o.atomic_ok = response_q == hyperbus_pkg::HyperRespOkay;
        host_wrsp_valid_o = (state_q == ReturnResponse) && write_pending_q;
        read_ready_o      = state_q == ReadData;
        write_o           = '0;
        write_o.data      = write_data;
        write_o.last      = 1'b1;
        for (int unsigned i = 0; i < HostDataBytes; i++) begin
            write_o.strb[i] = (i >= byte_offset) && (i < byte_offset + operand_bytes);
        end
        write_valid_o     = state_q == WriteData;
        write_rsp_ready_o = state_q == WriteResponse;
    end

    always_comb begin : proc_state
        state_d         = state_q;
        request_d       = request_q;
        operand_d       = operand_q;
        read_data_d     = read_data_q;
        response_d      = response_q;
        read_pending_d  = read_pending_q;
        write_pending_d = write_pending_q;

        unique case (state_q)
            Idle: begin
                if (start_i) begin
                    request_d.addr          = request_i.addr;
                    request_d.size          = request_i.size;
                    request_d.atomic_op     = request_i.atomic_op;
                    request_d.atomic_return = request_i.atomic_return;
                    response_d = request_valid_i ? hyperbus_pkg::HyperRespOkay :
                                                   hyperbus_pkg::HyperRespAtomicError;
                    state_d = WaitWriteData;
                end
            end
            WaitWriteData: begin
                if (host_w_valid_i && host_w_ready_o) begin
                    operand_d = host_w_i.data;
                    if (response_q == hyperbus_pkg::HyperRespOkay) begin
                        state_d = ReadCommand;
                    end else if (host_w_i.last) begin
                        read_pending_d  = request_q.atomic_return;
                        write_pending_d = 1'b1;
                        state_d = ReturnResponse;
                    end
                end
            end
            ReadCommand: if (command_valid_o && command_ready_i) state_d = ReadData;
            ReadData: begin
                if (read_valid_i && read_ready_o) begin
                    read_data_d = read_i.data;
                    if (read_i.resp == hyperbus_pkg::HyperRespOkay) begin
                        state_d = WriteCommand;
                    end else begin
                        response_d      = read_i.resp;
                        read_pending_d  = request_q.atomic_return;
                        write_pending_d = 1'b1;
                        state_d         = ReturnResponse;
                    end
                end
            end
            WriteCommand: if (command_valid_o && command_ready_i) state_d = WriteData;
            WriteData: if (write_valid_o && write_ready_i) state_d = WriteResponse;
            WriteResponse: begin
                if (write_rsp_valid_i && write_rsp_ready_o) begin
                    response_d = write_rsp_error_i ? hyperbus_pkg::HyperRespAccessError :
                                                    hyperbus_pkg::HyperRespOkay;
                    read_pending_d  = request_q.atomic_return;
                    write_pending_d = 1'b1;
                    state_d = ReturnResponse;
                end
            end
            ReturnResponse: begin
                if (host_r_valid_o && host_r_ready_i) read_pending_d = 1'b0;
                if (host_wrsp_valid_o && host_wrsp_ready_i) write_pending_d = 1'b0;
                if (completed_o) state_d = Idle;
            end
            default: state_d = Idle;
        endcase
    end

    `FFARN(state_q, state_d, Idle, clk_i, rst_ni)
    `FFARN(request_q, request_d, '0, clk_i, rst_ni)
    `FFARN(operand_q, operand_d, '0, clk_i, rst_ni)
    `FFARN(read_data_q, read_data_d, '0, clk_i, rst_ni)
    `FFARN(response_q, response_d, hyperbus_pkg::HyperRespOkay, clk_i, rst_ni)
    `FFARN(read_pending_q, read_pending_d, 1'b0, clk_i, rst_ni)
    `FFARN(write_pending_q, write_pending_d, 1'b0, clk_i, rst_ni)

endmodule : hyperbus_atomic_handler
