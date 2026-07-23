// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

`include "common_cells/registers.svh"

/// Execute one atomic request as an exclusive backend read-modify-write sequence.
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

    //////////////////////
    // Persistent state //
    //////////////////////
    atomic_state_e             state_d, state_q;
    atomic_request_t           request_d, request_q;
    host_data_t                operand_d, operand_q;
    host_data_t                read_data_d, read_data_q;
    hyperbus_pkg::hyper_resp_e response_d, response_q;
    logic                      read_pending_d, read_pending_q;
    logic                      write_pending_d, write_pending_q;

    ////////////////////////
    // Request sequencing //
    ////////////////////////
    atomic_request_t request_in;
    logic operation_valid;
    hyperbus_pkg::hyper_resp_e initial_response, backend_write_response;
    logic atomic_started, operand_accepted;
    logic valid_operand_accepted, invalid_operand_completed;
    logic command_accepted;
    logic backend_read_accepted,  backend_read_succeeded, backend_read_failed;
    logic backend_write_accepted, backend_write_rsp_accepted;
    logic host_read_accepted,     host_write_rsp_accepted;

    assign request_in = '{
        addr:          request_i.addr,
        size:          request_i.size,
        atomic_op:     request_i.atomic_op,
        atomic_return: request_i.atomic_return
    };

    // A start captures the request even when validation failed. In that case the
    // handler only drains its write data and returns an atomic error.
    assign atomic_started   = (state_q == Idle) && start_i;
    assign operation_valid  = response_q == hyperbus_pkg::HyperRespOkay;
    assign initial_response = request_valid_i ? hyperbus_pkg::HyperRespOkay :
                                                hyperbus_pkg::HyperRespAtomicError;
    assign operand_accepted = host_w_valid_i && host_w_ready_o;
    assign valid_operand_accepted = operand_accepted && operation_valid;
    assign invalid_operand_completed = operand_accepted && !operation_valid && host_w_i.last;

    // These events advance the backend read-modify-write sequence.
    // Read errors skip the write, write errors are reported after the write response.
    assign command_accepted           = command_valid_o && command_ready_i;
    assign backend_read_accepted      = read_valid_i && read_ready_o;
    assign backend_read_succeeded     = backend_read_accepted &&
                                        (read_i.resp == hyperbus_pkg::HyperRespOkay);
    assign backend_read_failed        = backend_read_accepted &&
                                        (read_i.resp != hyperbus_pkg::HyperRespOkay);
    assign backend_write_accepted     = write_valid_o && write_ready_i;
    assign backend_write_rsp_accepted = write_rsp_valid_i && write_rsp_ready_o;
    assign backend_write_response = write_rsp_error_i ?
        hyperbus_pkg::HyperRespAccessError : hyperbus_pkg::HyperRespOkay;

    // Hold both host responses until independently accepted.
    // Completion is asserted in the cycle where the final pending response is accepted.
    assign host_read_accepted      = host_r_valid_o && host_r_ready_i;
    assign host_write_rsp_accepted = host_wrsp_valid_o && host_wrsp_ready_i;
    assign completed_o = (state_q == ReturnResponse) &&
        (!read_pending_q || host_read_accepted) &&
        (!write_pending_q || host_write_rsp_accepted);

    assign active_o        = state_q != Idle;
    assign command_valid_o = (state_q == ReadCommand) || (state_q == WriteCommand);

    //////////////////////
    // Backend commands //
    //////////////////////
    // Atomic commands are converted into one backend read followed by one write.
    always_comb begin : proc_command
        command_o               = '0;
        command_o.write         = state_q == WriteCommand;
        command_o.addr          = request_q.addr;
        command_o.beats         = 1;
        command_o.size          = ((request_q.atomic_op == hyperbus_pkg::HyperAtomicCompare) &&
                                   (request_q.size != '0)) ?
                                  request_q.size - 1'b1 : request_q.size;
        command_o.burst         = hyperbus_pkg::HyperBurstIncr;
        command_o.atomic_op     = hyperbus_pkg::HyperAtomicNone;
        command_o.atomic_return = 1'b0;
        command_o.ordered       = 1'b1;
    end

    ////////////////
    // Atomic ALU //
    ////////////////
    // The operation works on one contiguous byte-lane range within the host data word.
    host_data_t value_mask,     write_mask;
    host_data_t alu_operand_a,  alu_operand_b;
    host_data_t compare_value,  swap_value;
    host_data_t alu_result,     shifted_alu_result;
    host_data_t preserved_data, write_data;
    int unsigned byte_offset, operand_bytes, operand_bits;
    logic alu_enable, alu_equal;
    logic alu_signed_less, alu_unsigned_less;

    // Select and align the memory value and write operand before the ALU.
    always_comb begin : proc_alu_operands
        byte_offset   = 0;
        operand_bytes = 1;
        operand_bits  = 8;
        value_mask    = '1;

        if (response_q == hyperbus_pkg::HyperRespOkay) begin
            byte_offset = unsigned'(request_q.addr[HostBusAddrWidth-1:0]);
            operand_bytes = 1 << ((request_q.atomic_op == hyperbus_pkg::HyperAtomicCompare) ?
                                  request_q.size - 1'b1 : request_q.size);
            operand_bits  = operand_bytes * 8;
            value_mask    = value_mask >> (HostDataWidth - operand_bits);
        end

        alu_operand_a = (read_data_q >> (byte_offset * 8)) & value_mask;
        // Compare operations carry the compare value below the replacement value.
        compare_value = (operand_q >> (byte_offset * 8)) & value_mask;
        swap_value    = (operand_q >> ((byte_offset * 8) + operand_bits)) & value_mask;
        alu_operand_b = (request_q.atomic_op == hyperbus_pkg::HyperAtomicCompare) ?
                        swap_value : compare_value;
    end

    assign alu_enable       = (state_q == WriteData) &&
                              (response_q == hyperbus_pkg::HyperRespOkay);
    assign alu_equal        = alu_operand_a == compare_value;
    assign alu_unsigned_less = alu_operand_a < alu_operand_b;
    assign alu_signed_less  = (alu_operand_a[operand_bits-1] !=
                               alu_operand_b[operand_bits-1]) ?
                              alu_operand_a[operand_bits-1] : alu_unsigned_less;

    // Apply the selected operation to the aligned operands.
    always_comb begin : proc_alu
        alu_result = alu_operand_a;
        if (alu_enable) begin
            unique case (request_q.atomic_op)
                hyperbus_pkg::HyperAtomicSwap:        alu_result = alu_operand_b;
                hyperbus_pkg::HyperAtomicCompare:     alu_result = alu_equal ?
                                                                   alu_operand_b : alu_operand_a;
                hyperbus_pkg::HyperAtomicAdd:         alu_result = alu_operand_a + alu_operand_b;
                hyperbus_pkg::HyperAtomicAnd:         alu_result = alu_operand_a & alu_operand_b;
                hyperbus_pkg::HyperAtomicClear:       alu_result = alu_operand_a & ~alu_operand_b;
                hyperbus_pkg::HyperAtomicXor:         alu_result = alu_operand_a ^ alu_operand_b;
                hyperbus_pkg::HyperAtomicSet:         alu_result = alu_operand_a | alu_operand_b;
                hyperbus_pkg::HyperAtomicSignedMax:   alu_result = alu_signed_less ?
                                                                   alu_operand_b : alu_operand_a;
                hyperbus_pkg::HyperAtomicSignedMin:   alu_result = alu_signed_less ?
                                                                   alu_operand_a : alu_operand_b;
                hyperbus_pkg::HyperAtomicUnsignedMax: alu_result = alu_unsigned_less ?
                                                                   alu_operand_b : alu_operand_a;
                hyperbus_pkg::HyperAtomicUnsignedMin: alu_result = alu_unsigned_less ?
                                                                   alu_operand_a : alu_operand_b;
                default:;
            endcase
        end
    end

    assign write_mask         = value_mask << (byte_offset * 8);
    assign preserved_data     = read_data_q & ~write_mask;
    assign shifted_alu_result = (alu_result & value_mask) << (byte_offset * 8);
    assign write_data         = alu_enable ? preserved_data | shifted_alu_result : read_data_q;

    ////////////////////
    // Stream outputs //
    ////////////////////
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

    ///////////////////////////
    // Control state machine //
    ///////////////////////////
    // A valid request consumes one operand, reads the old value, writes the ALU result, and
    // returns both responses. Invalid requests drain their operands; backend errors return early.
    always_comb begin : proc_state
        state_d         = state_q;
        request_d       = request_q;
        operand_d       = operand_q;
        read_data_d     = read_data_q;
        response_d      = response_q;
        read_pending_d  = read_pending_q;
        write_pending_d = write_pending_q;

        unique case (state_q)
            // Capture one validated or rejected atomic request.
            Idle: begin
                if (atomic_started) begin
                    request_d  = request_in;
                    response_d = initial_response;
                    state_d    = WaitWriteData;
                end
            end
            // Buffer the operand, or drain an invalid request through its final beat.
            WaitWriteData: begin
                if (operand_accepted) begin
                    operand_d = host_w_i.data;
                end
                if (valid_operand_accepted) begin
                    state_d = ReadCommand;
                end
                if (invalid_operand_completed) begin
                    read_pending_d  = request_q.atomic_return;
                    write_pending_d = 1'b1;
                    state_d         = ReturnResponse;
                end
            end
            // Issue the backend read for the target word.
            ReadCommand: begin
                if (command_accepted) begin
                    state_d = ReadData;
                end
            end
            // Capture the old value and stop early on a backend read error.
            ReadData: begin
                if (backend_read_accepted) begin
                    read_data_d = read_i.data;
                end
                if (backend_read_succeeded) begin
                    state_d = WriteCommand;
                end
                if (backend_read_failed) begin
                    response_d      = read_i.resp;
                    read_pending_d  = request_q.atomic_return;
                    write_pending_d = 1'b1;
                    state_d         = ReturnResponse;
                end
            end
            // Issue the backend write for the updated word.
            WriteCommand: begin
                if (command_accepted) begin
                    state_d = WriteData;
                end
            end
            // Transfer the ALU result and byte strobes.
            WriteData: begin
                if (backend_write_accepted) begin
                    state_d = WriteResponse;
                end
            end
            // Collect the backend write status.
            WriteResponse: begin
                if (backend_write_rsp_accepted) begin
                    response_d      = backend_write_response;
                    read_pending_d  = request_q.atomic_return;
                    write_pending_d = 1'b1;
                    state_d         = ReturnResponse;
                end
            end
            // Hold the host read and write responses until independently accepted.
            ReturnResponse: begin
                if (host_read_accepted) begin
                    read_pending_d = 1'b0;
                end
                if (host_write_rsp_accepted) begin
                    write_pending_d = 1'b0;
                end
                if (completed_o) begin
                    state_d = Idle;
                end
            end
            default: state_d = Idle;
        endcase
    end

    /////////////////////
    // State registers //
    /////////////////////
    `FFARN(state_q, state_d, Idle, clk_i, rst_ni)
    `FFARN(request_q, request_d, '0, clk_i, rst_ni)
    `FFARN(operand_q, operand_d, '0, clk_i, rst_ni)
    `FFARN(read_data_q, read_data_d, '0, clk_i, rst_ni)
    `FFARN(response_q, response_d, hyperbus_pkg::HyperRespOkay, clk_i, rst_ni)
    `FFARN(read_pending_q, read_pending_d, 1'b0, clk_i, rst_ni)
    `FFARN(write_pending_q, write_pending_d, 1'b0, clk_i, rst_ni)

endmodule : hyperbus_atomic_handler
