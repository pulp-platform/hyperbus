// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

`include "hyperbus/typedef.svh"

module hyperbus_atomic_handler_tb #(
    parameter int unsigned HostDataWidth = 64
);

    localparam int unsigned HostAddrWidth = 32;

    typedef logic [HostAddrWidth-1:0]   host_addr_t;
    typedef logic [HostDataWidth-1:0]   host_data_t;
    typedef logic [HostDataWidth/8-1:0] host_strb_t;

    `HYPERBUS_TYPEDEF_HOST_ALL_CT(tb_host, host_addr_t, host_data_t, host_strb_t)

    logic          clk;
    logic          rst_n;
    logic          start;
    logic          request_valid;
    tb_host_cmd_t  request;
    logic          active;
    logic          completed;
    tb_host_cmd_t  command;
    logic          command_valid;
    logic          command_ready;
    tb_host_w_t    host_w;
    logic          host_w_valid;
    logic          host_w_ready;
    tb_host_r_t    host_r;
    logic          host_r_valid;
    logic          host_r_ready;
    tb_host_wrsp_t host_wrsp;
    logic          host_wrsp_valid;
    logic          host_wrsp_ready;
    tb_host_r_t    read;
    logic          read_valid;
    logic          read_ready;
    tb_host_w_t    write;
    logic          write_valid;
    logic          write_ready;
    logic          write_rsp_error;
    logic          write_rsp_valid;
    logic          write_rsp_ready;

    hyperbus_atomic_handler #(
        .HostAddrWidth ( HostAddrWidth  ),
        .HostDataWidth ( HostDataWidth  ),
        .host_cmd_t    ( tb_host_cmd_t  ),
        .host_w_t      ( tb_host_w_t    ),
        .host_r_t      ( tb_host_r_t    ),
        .host_wrsp_t   ( tb_host_wrsp_t )
    ) i_dut (
        .clk_i                  ( clk                 ),
        .rst_ni                 ( rst_n               ),
        .start_i                ( start               ),
        .request_valid_i        ( request_valid       ),
        .request_i              ( request             ),
        .active_o               ( active              ),
        .completed_o            ( completed           ),
        .command_o              ( command             ),
        .command_valid_o        ( command_valid       ),
        .command_ready_i        ( command_ready       ),
        .host_w_i               ( host_w              ),
        .host_w_valid_i         ( host_w_valid        ),
        .host_w_ready_o         ( host_w_ready        ),
        .host_r_o               ( host_r              ),
        .host_r_valid_o         ( host_r_valid        ),
        .host_r_ready_i         ( host_r_ready        ),
        .host_wrsp_o            ( host_wrsp           ),
        .host_wrsp_valid_o      ( host_wrsp_valid     ),
        .host_wrsp_ready_i      ( host_wrsp_ready     ),
        .read_i                 ( read                ),
        .read_valid_i           ( read_valid          ),
        .read_ready_o           ( read_ready          ),
        .write_o                ( write               ),
        .write_valid_o          ( write_valid         ),
        .write_ready_i          ( write_ready         ),
        .write_rsp_error_i      ( write_rsp_error     ),
        .write_rsp_valid_i      ( write_rsp_valid     ),
        .write_rsp_ready_o      ( write_rsp_ready     )
    );

    initial begin
        clk = 1'b0;
        forever #5ns clk = ~clk;
    end

    task automatic send_host_w(input tb_host_w_t payload);
        @(negedge clk);
        host_w = payload;
        host_w_valid = 1'b1;
        do @(posedge clk); while (!host_w_ready);
        @(negedge clk);
        host_w_valid = 1'b0;
    endtask

    task automatic send_read(input tb_host_r_t payload);
        @(negedge clk);
        read = payload;
        read_valid = 1'b1;
        do @(posedge clk); while (!read_ready);
        @(negedge clk);
        read_valid = 1'b0;
    endtask

    task automatic send_write_rsp(input logic error);
        @(negedge clk);
        write_rsp_error = error;
        write_rsp_valid = 1'b1;
        do @(posedge clk); while (!write_rsp_ready);
        @(negedge clk);
        write_rsp_valid = 1'b0;
        write_rsp_error = 1'b0;
    endtask

    // A bit-serial reference adder and sign-extended comparisons are independent
    // of the RTL's full-bus masked arithmetic and sign-bit selection.
    function automatic logic [127:0] reference_result(
        input hyperbus_pkg::hyper_atomic_op_e op,
        input int unsigned bits,
        input logic [127:0] old_value, operand, replacement
    );
        logic [127:0] result;
        logic carry;
        logic signed [128:0] signed_old, signed_operand;
        result = old_value;
        carry = 0;
        signed_old = old_value[bits-1] ? '1 : '0;
        signed_operand = operand[bits-1] ? '1 : '0;
        for (int i = 0; i < bits; i++) begin
            signed_old[i] = old_value[i];
            signed_operand[i] = operand[i];
        end
        case (op)
            hyperbus_pkg::HyperAtomicSwap: result = operand;
            hyperbus_pkg::HyperAtomicCompare:
                if (old_value == operand) result = replacement;
            hyperbus_pkg::HyperAtomicAdd:
                for (int i = 0; i < bits; i++) begin
                    result[i] = old_value[i] ^ operand[i] ^ carry;
                    carry = (old_value[i] && operand[i]) ||
                            (carry && (old_value[i] || operand[i]));
                end
            hyperbus_pkg::HyperAtomicAnd: result = old_value & operand;
            hyperbus_pkg::HyperAtomicClear: result = old_value & ~operand;
            hyperbus_pkg::HyperAtomicXor: result = old_value ^ operand;
            hyperbus_pkg::HyperAtomicSet: result = old_value | operand;
            hyperbus_pkg::HyperAtomicSignedMax:
                result = (signed_old > signed_operand) ? old_value : operand;
            hyperbus_pkg::HyperAtomicSignedMin:
                result = (signed_old < signed_operand) ? old_value : operand;
            hyperbus_pkg::HyperAtomicUnsignedMax:
                result = (old_value > operand) ? old_value : operand;
            hyperbus_pkg::HyperAtomicUnsignedMin:
                result = (old_value < operand) ? old_value : operand;
            default: $fatal(1, "Unknown reference operation");
        endcase
        return result;
    endfunction

    task automatic check_lanes(
        input hyperbus_pkg::hyper_atomic_op_e op,
        input int unsigned bytes, offset, pattern
    );
        host_data_t old_data, operand_data, expected_data;
        host_strb_t expected_strb, operand_strb;
        logic [127:0] old_value, operand, replacement, result;
        int unsigned pair_base, replacement_offset;
        logic [31:0] seed;
        bit compare, failed_compare;
        compare = op == hyperbus_pkg::HyperAtomicCompare;
        old_value = '0;
        operand = '0;
        replacement = '0;
        seed = 32'h5eeda701 ^ (bytes << 16) ^ (offset << 8) ^ pattern ^ int'(op);
        for (int i = 0; i < HostDataWidth / 8; i++) begin
            old_data[i*8 +: 8] = 8'(32'h6d + 17*i + pattern);
            operand_data[i*8 +: 8] = 8'(32'hc3 - 11*i);
        end
        for (int i = 0; i < bytes; i++) begin
            old_value[i*8 +: 8] = 8'(32'h31 + 23*i + pattern*19);
            operand[i*8 +: 8] = 8'(32'h97 - 13*i + pattern*7);
            replacement[i*8 +: 8] = 8'(32'hf1 - 31*i - pattern*3);
            if (pattern >= 4) begin
                seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5;
                old_value[i*8 +: 8] = seed[7:0];
                operand[i*8 +: 8] = seed[15:8];
                replacement[i*8 +: 8] = seed[23:16] | 8'h01;
            end
        end
        if (pattern == 0) begin
            for (int i = 0; i < bytes*8; i++) old_value[i] = 1'b1;
            operand = 1; // carry and modulo overflow
        end else if (pattern == 1) begin
            old_value = '0;
            old_value[bytes*8-1] = 1'b1; // signed minimum versus positive maximum
            operand = '0;
            for (int i = 0; i < bytes*8-1; i++) operand[i] = 1'b1;
        end else if (pattern == 2) begin
            old_value = '0;
            operand = '0;
            for (int i = 0; i < bytes*8-1; i++) old_value[i] = 1'b1;
            operand[bytes*8-1] = 1'b1;
        end else if (pattern == 3) begin
            old_value = '0;
            operand = '0;
            for (int i = 0; i < bytes*8; i++) old_value[i] = 1'b1;
        end
        if (compare && pattern % 2 == 0) operand = old_value;
        failed_compare = compare && operand != old_value;
        // Place operands by the transaction's lower/upper half, not using the
        // RTL's XOR expression. Both placements use distinct nonzero replacements.
        pair_base = (offset / (2*bytes)) * (2*bytes);
        replacement_offset = (offset == pair_base) ? pair_base + bytes : pair_base;
        expected_strb = '0;
        operand_strb = '0;
        for (int i = 0; i < bytes; i++) begin
            old_data[(offset+i)*8 +: 8] = old_value[i*8 +: 8];
            operand_data[(offset+i)*8 +: 8] = operand[i*8 +: 8];
            if (compare) operand_data[(replacement_offset+i)*8 +: 8] =
                replacement[i*8 +: 8];
            expected_strb[offset+i] = 1'b1;
            operand_strb[offset+i] = 1'b1;
        end
        if (compare)
            for (int i = 0; i < bytes; i++) operand_strb[replacement_offset+i] = 1'b1;
        for (int i = 0; i < HostDataWidth/8; i++)
            if (!operand_strb[i]) operand_data[i*8 +: 8] = '0;
        result = reference_result(op, bytes*8, old_value, operand, replacement);
        expected_data = old_data;
        for (int i = 0; i < bytes; i++) expected_data[(offset+i)*8 +: 8] = result[i*8 +: 8];

        @(negedge clk);
        request = '0;
        request.write = 1;
        request.addr = 32'h8000_1000 + offset;
        request.beats = 1;
        request.size = 3'($clog2(bytes) + int'(compare));
        request.burst = hyperbus_pkg::HyperBurstIncr;
        request.atomic_op = op;
        request.atomic_return = 1;
        request_valid = 1;
        start = 1;
        @(negedge clk);
        start = 0;
        request_valid = 0;
        repeat (pattern % 3) @(negedge clk);
        send_host_w('{data: operand_data, strb: operand_strb, last: 1'b1});
        wait (command_valid);
        #1ps;
        if (command.write || command.addr != request.addr || command.size != 3'($clog2(bytes)))
            $fatal(1, "Invalid read command for %s/%0d/%0d", op.name(), bytes, offset);
        send_read('{data: old_data, resp: hyperbus_pkg::HyperRespOkay,
                   last: 1'b1, atomic_ok: 1'b0});
        if (failed_compare) begin
            wait (command_valid || (host_r_valid && host_wrsp_valid));
            if (command_valid) begin
                #1ps;
                if (!command.write || command.addr != request.addr ||
                    command.size != 3'($clog2(bytes)))
                    $fatal(1, "Invalid failed-Compare write command");
                wait (write_valid);
                #1ps;
                for (int i = 0; i < HostDataWidth/8; i++) begin
                    if (expected_strb[i] && write.data[i*8 +: 8] != expected_data[i*8 +: 8])
                        $fatal(1, "Failed Compare changed active lane %0d", i);
                end
                if (write.strb != expected_strb || !write.last)
                    $fatal(1, "Failed Compare writeback had incorrect strobes or LAST");
                send_write_rsp(1'b0);
            end
        end else begin
            wait (command_valid);
            #1ps;
            if (!command.write || command.addr != request.addr ||
                command.size != 3'($clog2(bytes)))
                $fatal(1, "Invalid write command for %s/%0d/%0d", op.name(), bytes, offset);
            wait (write_valid);
            #1ps;
            for (int i = 0; i < HostDataWidth/8; i++) begin
                if (expected_strb[i] && write.data[i*8 +: 8] != expected_data[i*8 +: 8])
                    $fatal(1, "%s bytes=%0d offset=%0d pattern=%0d active lane %0d mismatch",
                        op.name(), bytes, offset, pattern, i);
            end
            if (write.strb != expected_strb || !write.last)
                $fatal(1, "%s bytes=%0d offset=%0d pattern=%0d got=%h/%h expected=%h/%h",
                    op.name(), bytes, offset, pattern, write.data, write.strb,
                    expected_data, expected_strb);
            send_write_rsp(1'b0);
        end
        wait (host_r_valid && host_wrsp_valid);
        #1ps;
        for (int i = 0; i < HostDataWidth/8; i++)
            if (expected_strb[i] && host_r.data[i*8 +: 8] != old_data[i*8 +: 8])
                $fatal(1, "Invalid original response lane %0d", i);
        if (host_r.resp != hyperbus_pkg::HyperRespOkay ||
            host_wrsp.resp != hyperbus_pkg::HyperRespOkay) $fatal(1, "Invalid original response");
        repeat (pattern % 4) @(negedge clk);
        @(negedge clk);
        if (pattern % 2 != 0) host_wrsp_ready = 1; else host_r_ready = 1;
        @(negedge clk);
        repeat (2) @(negedge clk);
        host_wrsp_ready = 1;
        host_r_ready = 1;
        @(negedge clk);
        host_wrsp_ready = 0;
        host_r_ready = 0;
        wait (!active);
    endtask

    task automatic check_operation(
        input hyperbus_pkg::hyper_atomic_op_e operation,
        input logic [31:0]                    old_value,
        input logic [31:0]                    operand,
        input logic [31:0]                    expected,
        input logic [31:0]                    swap_value = '0,
        input logic                           compare = 1'b0,
        input logic                           write_error = 1'b0,
        input logic                           upper_compare = 1'b0
    );
        localparam logic [31:0] UpperWord = 32'ha5a5_5a5a;
        host_data_t old_data;
        host_data_t operand_data;
        host_data_t expected_data;
        bit failed_compare;

        old_data      = upper_compare ? {old_value, UpperWord} : {UpperWord, old_value};
        operand_data  = compare ? (upper_compare ? {operand, swap_value} :
                                                  {swap_value, operand}) : host_data_t'(operand);
        expected_data = upper_compare ? {expected, UpperWord} : {UpperWord, expected};
        failed_compare = compare && (old_value != operand);

        @(negedge clk);
        request               = '0;
        request.write         = 1'b1;
        request.addr          = upper_compare ? 32'h8000_0104 : 32'h8000_0100;
        request.beats         = 1;
        request.size          = compare ? 3'd3 : 3'd2;
        request.burst         = hyperbus_pkg::HyperBurstIncr;
        request.atomic_op     = operation;
        request.atomic_return = 1'b1;
        request.ordered       = 1'b1;
        request_valid         = 1'b1;
        start                 = 1'b1;

        @(negedge clk);
        request_valid = 1'b0;
        start         = 1'b0;

        send_host_w('{data: operand_data,
                     strb: compare ? host_strb_t'(8'hff) : '1,
                     last: 1'b1});

        wait (command_valid);
        #1ps;
        if (command.write || (command.size != 2) || command.addr != request.addr) begin
            $fatal(1, "Atomic %s issued an invalid read command", operation.name());
        end

        send_read('{data: old_data, resp: hyperbus_pkg::HyperRespOkay,
                   last: 1'b1, atomic_ok: 1'b0});

        if (failed_compare) begin
            wait (command_valid || (host_r_valid && host_wrsp_valid));
            if (command_valid) begin
                #1ps;
                if (!command.write || command.size != 2 || command.addr != request.addr)
                    $fatal(1, "Failed Compare issued an invalid command");
                wait (write_valid);
                #1ps;
                for (int lane = 0; lane < HostDataWidth/8; lane++)
                    if ((upper_compare ? (lane >= 4 && lane < 8) : (lane < 4)) &&
                        write.data[lane*8 +: 8] != old_data[lane*8 +: 8])
                        $fatal(1, "Failed Compare changed active lane %0d", lane);
                if (write.strb != (upper_compare ? host_strb_t'(8'hf0) :
                                                 host_strb_t'(8'h0f)) || !write.last)
                    $fatal(1, "Failed Compare writeback had invalid strobes or LAST");
                send_write_rsp(write_error);
            end
        end else begin
            wait (command_valid);
            #1ps;
            if (!command.write || (command.size != 2) || command.addr != request.addr)
                $fatal(1, "Atomic %s issued an invalid write command", operation.name());
            wait (write_valid);
            #1ps;
            for (int lane = 0; lane < HostDataWidth/8; lane++)
                if ((upper_compare ? (lane >= 4 && lane < 8) : (lane < 4)) &&
                    write.data[lane*8 +: 8] != expected_data[lane*8 +: 8])
                    $fatal(1, "Atomic %s active write lane %0d mismatch", operation.name(), lane);
            if ((write.strb != (upper_compare ? host_strb_t'(8'hf0) :
                                                host_strb_t'(8'h0f))) || !write.last)
                $fatal(1, "Atomic %s produced invalid write strobes or LAST", operation.name());
            send_write_rsp(write_error);
        end

        wait (host_r_valid && host_wrsp_valid);
        #1ps;
        for (int i = 0; i < 4; i++) begin
            int lane;
            lane = (upper_compare ? 4 : 0) + i;
            if (host_r.data[lane*8 +: 8] != old_data[lane*8 +: 8])
                $fatal(1, "Atomic %s returned incorrect active read lane %0d", operation.name(), lane);
        end
        if (!host_r.last ||
            (host_r.resp != (write_error ? hyperbus_pkg::HyperRespAccessError :
                                           hyperbus_pkg::HyperRespOkay)) ||
            (host_wrsp.resp != (write_error ? hyperbus_pkg::HyperRespAccessError :
                                              hyperbus_pkg::HyperRespOkay)) ||
            (host_r.atomic_ok == write_error) || (host_wrsp.atomic_ok == write_error)) begin
            $fatal(1, "Atomic %s returned an invalid host response", operation.name());
        end

        // Accept the read response first and ensure the write response remains stable.
        @(negedge clk);
        host_r_ready = 1'b1;
        #1ps;
        if (completed) begin
            $fatal(1, "Atomic %s completed before both host responses were accepted",
                   operation.name());
        end
        @(negedge clk);
        host_r_ready = 1'b0;
        #1ps;
        if (host_r_valid || !host_wrsp_valid || !active || completed) begin
            $fatal(1, "Atomic %s did not hold its pending write response", operation.name());
        end

        host_wrsp_ready = 1'b1;
        #1ps;
        if (!completed) begin
            $fatal(1, "Atomic %s did not complete with its final response", operation.name());
        end
        @(negedge clk);
        host_wrsp_ready = 1'b0;
        wait (!active);
    endtask

    task automatic check_read_error;
        @(negedge clk);
        request               = '0;
        request.write         = 1'b1;
        request.addr          = 32'h8000_0200;
        request.beats         = 1;
        request.size          = 3'd2;
        request.burst         = hyperbus_pkg::HyperBurstIncr;
        request.atomic_op     = hyperbus_pkg::HyperAtomicAdd;
        request.atomic_return = 1'b1;
        request.ordered       = 1'b1;
        request_valid         = 1'b1;
        start                 = 1'b1;

        @(negedge clk);
        request_valid = 1'b0;
        start         = 1'b0;
        send_host_w('{data: 64'h1, strb: '1, last: 1'b1});

        send_read('{data: '0, resp: hyperbus_pkg::HyperRespAccessError,
                   last: 1'b1, atomic_ok: 1'b0});

        wait (host_r_valid && host_wrsp_valid);
        #1ps;
        if (command_valid || write_valid ||
            (host_r.resp != hyperbus_pkg::HyperRespAccessError) ||
            (host_wrsp.resp != hyperbus_pkg::HyperRespAccessError) ||
            host_r.atomic_ok || host_wrsp.atomic_ok) begin
            $fatal(1, "Atomic backend read error was not returned without a write");
        end

        host_r_ready    = 1'b1;
        host_wrsp_ready = 1'b1;
        @(negedge clk);
        host_r_ready    = 1'b0;
        host_wrsp_ready = 1'b0;
        wait (!active);
    endtask

    task automatic check_invalid_operand_drain;
        @(negedge clk);
        request               = '0;
        request.write         = 1'b1;
        request.addr          = 32'h8000_0300;
        request.beats         = 2;
        request.size          = 3'd2;
        request.burst         = hyperbus_pkg::HyperBurstIncr;
        request.atomic_op     = hyperbus_pkg::HyperAtomicAdd;
        request.atomic_return = 1'b1;
        request_valid         = 1'b0;
        start                 = 1'b1;

        @(negedge clk);
        start = 1'b0;
        send_host_w('{data: 64'hdead_beef, strb: '1, last: 1'b0});
        #1ps;
        if (!active || command_valid || host_r_valid || host_wrsp_valid) begin
            $fatal(1, "Rejected atomic did not continue draining its operand stream");
        end

        send_host_w('{data: 64'hfeed_cafe, strb: '1, last: 1'b1});
        wait (host_r_valid && host_wrsp_valid);
        #1ps;
        if (command_valid || write_valid ||
            (host_r.resp != hyperbus_pkg::HyperRespAtomicError) ||
            (host_wrsp.resp != hyperbus_pkg::HyperRespAtomicError)) begin
            $fatal(1, "Rejected atomic operand drain returned an invalid response");
        end

        host_r_ready    = 1'b1;
        host_wrsp_ready = 1'b1;
        @(negedge clk);
        host_r_ready    = 1'b0;
        host_wrsp_ready = 1'b0;
        wait (!active);
    endtask

    initial begin
        rst_n            = 1'b0;
        start            = 1'b0;
        request_valid    = 1'b0;
        request          = '0;
        command_ready    = 1'b1;
        host_w           = '0;
        host_w_valid     = 1'b0;
        host_r_ready     = 1'b0;
        host_wrsp_ready  = 1'b0;
        read             = '0;
        read_valid       = 1'b0;
        write_ready      = 1'b1;
        write_rsp_error  = 1'b0;
        write_rsp_valid  = 1'b0;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        if (HostDataWidth >= 64) begin
        check_operation(hyperbus_pkg::HyperAtomicCompare,
                        32'h1234_5678, 32'h1234_5678, 32'hfeed_cafe,
                        32'hfeed_cafe, 1'b1, 1'b0, 1'b1);

        check_operation(hyperbus_pkg::HyperAtomicSwap,
                        32'h1234_5678, 32'h89ab_cdef, 32'h89ab_cdef);
        check_operation(hyperbus_pkg::HyperAtomicCompare,
                        32'h1234_5678, 32'h1234_5678, 32'hfeed_cafe, 32'hfeed_cafe, 1'b1);
        check_operation(hyperbus_pkg::HyperAtomicCompare,
                        32'h1234_5678, 32'h8765_4321, 32'h1234_5678, 32'hfeed_cafe, 1'b1);
        check_operation(hyperbus_pkg::HyperAtomicAdd,
                        32'h1234_5678, 32'h0102_0304, 32'h1336_597c);
        check_operation(hyperbus_pkg::HyperAtomicAnd,
                        32'hf0f0_55aa, 32'h0ff0_f00f, 32'h00f0_500a);
        check_operation(hyperbus_pkg::HyperAtomicClear,
                        32'hffff_55aa, 32'h0ff0_f00f, 32'hf00f_05a0);
        check_operation(hyperbus_pkg::HyperAtomicXor,
                        32'hf0f0_55aa, 32'h0ff0_f00f, 32'hff00_a5a5);
        check_operation(hyperbus_pkg::HyperAtomicSet,
                        32'hf0f0_55aa, 32'h0ff0_f00f, 32'hfff0_f5af);
        check_operation(hyperbus_pkg::HyperAtomicSignedMax,
                        32'hffff_fffb, 32'h0000_0003, 32'h0000_0003);
        check_operation(hyperbus_pkg::HyperAtomicSignedMin,
                        32'h0000_0003, 32'hffff_fffb, 32'hffff_fffb);
        check_operation(hyperbus_pkg::HyperAtomicUnsignedMax,
                        32'h0000_0002, 32'hffff_fff0, 32'hffff_fff0);
        check_operation(hyperbus_pkg::HyperAtomicUnsignedMin,
                        32'h0000_0002, 32'hffff_fff0, 32'h0000_0002);
        check_operation(hyperbus_pkg::HyperAtomicAdd,
                        32'h1234_5678, 32'h0102_0304, 32'h1336_597c,
                        '0, 1'b0, 1'b1);
        check_read_error();
        check_invalid_operand_drain();
        end

        for (int bytes = 1; bytes <= HostDataWidth/8 && bytes <= 16; bytes *= 2) begin
            for (int offset = 0; offset < HostDataWidth/8; offset += bytes) begin
                for (int op = int'(hyperbus_pkg::HyperAtomicSwap);
                     op <= int'(hyperbus_pkg::HyperAtomicUnsignedMin); op++) begin
                    if ((op == int'(hyperbus_pkg::HyperAtomicCompare) &&
                         bytes*2 <= HostDataWidth/8) ||
                        (op != int'(hyperbus_pkg::HyperAtomicCompare) && bytes <= 8)) begin
                        for (int pattern = 0; pattern < 6; pattern++) begin
                            check_lanes(hyperbus_pkg::hyper_atomic_op_e'(op), bytes, offset, pattern);
                        end
                    end
                end
            end
        end

        $display("Atomic handler operation and protocol tests passed");
        $finish;
    end

    initial begin
        // The exhaustive operation/lane matrix grows with the host word width.
        #(2ms * ((HostDataWidth + 511) / 512));
        $fatal(1, "Atomic handler test timed out");
    end

endmodule : hyperbus_atomic_handler_tb
