// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

`include "hyperbus/typedef.svh"

module hyperbus_atomic_handler_tb;

    localparam int unsigned HostAddrWidth = 32;
    localparam int unsigned HostDataWidth = 64;

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

    task automatic check_operation(
        input hyperbus_pkg::hyper_atomic_op_e operation,
        input logic [31:0]                    old_value,
        input logic [31:0]                    operand,
        input logic [31:0]                    expected,
        input logic [31:0]                    swap_value = '0,
        input logic                           compare = 1'b0,
        input logic                           write_error = 1'b0
    );
        localparam logic [31:0] UpperWord = 32'ha5a5_5a5a;
        host_data_t old_data;
        host_data_t operand_data;
        host_data_t expected_data;

        old_data      = {UpperWord, old_value};
        operand_data  = compare ? {swap_value, operand} : host_data_t'(operand);
        expected_data = {UpperWord, expected};

        @(negedge clk);
        request               = '0;
        request.write         = 1'b1;
        request.addr          = 32'h8000_0100;
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

        wait (host_w_ready);
        @(negedge clk);
        host_w       = '{data: operand_data, strb: '1, last: 1'b1};
        host_w_valid = 1'b1;
        @(negedge clk);
        host_w_valid = 1'b0;

        wait (command_valid);
        #1ps;
        if (command.write || (command.size != 2)) begin
            $error("Atomic %s issued an invalid read command", operation.name());
        end

        wait (read_ready);
        @(negedge clk);
        read         = '0;
        read.data    = old_data;
        read.resp    = hyperbus_pkg::HyperRespOkay;
        read.last    = 1'b1;
        read_valid   = 1'b1;
        @(negedge clk);
        read_valid   = 1'b0;

        wait (command_valid);
        #1ps;
        if (!command.write || (command.size != 2)) begin
            $error("Atomic %s issued an invalid write command", operation.name());
        end

        wait (write_valid);
        #1ps;
        if ((write.data != expected_data) || (write.strb != 8'h0f) || !write.last) begin
            $error("Atomic %s produced data 0x%016h strb 0x%02h, expected 0x%016h/0x0f",
                   operation.name(), write.data, write.strb, expected_data);
        end

        wait (write_rsp_ready);
        @(negedge clk);
        write_rsp_error = write_error;
        write_rsp_valid = 1'b1;
        @(negedge clk);
        write_rsp_error = 1'b0;
        write_rsp_valid = 1'b0;

        wait (host_r_valid && host_wrsp_valid);
        #1ps;
        if ((host_r.data != old_data) || !host_r.last ||
            (host_r.resp != (write_error ? hyperbus_pkg::HyperRespAccessError :
                                           hyperbus_pkg::HyperRespOkay)) ||
            (host_wrsp.resp != (write_error ? hyperbus_pkg::HyperRespAccessError :
                                              hyperbus_pkg::HyperRespOkay)) ||
            (host_r.atomic_ok == write_error) || (host_wrsp.atomic_ok == write_error)) begin
            $error("Atomic %s returned an invalid host response", operation.name());
        end

        // Accept the read response first and ensure the write response remains stable.
        @(negedge clk);
        host_r_ready = 1'b1;
        #1ps;
        if (completed) begin
            $error("Atomic %s completed before both host responses were accepted",
                   operation.name());
        end
        @(negedge clk);
        host_r_ready = 1'b0;
        #1ps;
        if (host_r_valid || !host_wrsp_valid || !active || completed) begin
            $error("Atomic %s did not hold its pending write response", operation.name());
        end

        host_wrsp_ready = 1'b1;
        #1ps;
        if (!completed) begin
            $error("Atomic %s did not complete with its final response", operation.name());
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
        wait (host_w_ready);
        @(negedge clk);
        host_w       = '{data: 64'h1, strb: '1, last: 1'b1};
        host_w_valid = 1'b1;
        @(negedge clk);
        host_w_valid = 1'b0;

        wait (read_ready);
        @(negedge clk);
        read         = '0;
        read.resp    = hyperbus_pkg::HyperRespAccessError;
        read.last    = 1'b1;
        read_valid   = 1'b1;
        @(negedge clk);
        read_valid   = 1'b0;

        wait (host_r_valid && host_wrsp_valid);
        #1ps;
        if (command_valid || write_valid ||
            (host_r.resp != hyperbus_pkg::HyperRespAccessError) ||
            (host_wrsp.resp != hyperbus_pkg::HyperRespAccessError) ||
            host_r.atomic_ok || host_wrsp.atomic_ok) begin
            $error("Atomic backend read error was not returned without a write");
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
        wait (host_w_ready);
        @(negedge clk);
        host_w       = '{data: 64'hdead_beef, strb: '1, last: 1'b0};
        host_w_valid = 1'b1;
        @(negedge clk);
        host_w_valid = 1'b0;
        #1ps;
        if (!active || command_valid || host_r_valid || host_wrsp_valid) begin
            $error("Rejected atomic did not continue draining its operand stream");
        end

        @(negedge clk);
        host_w       = '{data: 64'hfeed_cafe, strb: '1, last: 1'b1};
        host_w_valid = 1'b1;
        @(negedge clk);
        host_w_valid = 1'b0;
        wait (host_r_valid && host_wrsp_valid);
        #1ps;
        if (command_valid || write_valid ||
            (host_r.resp != hyperbus_pkg::HyperRespAtomicError) ||
            (host_wrsp.resp != hyperbus_pkg::HyperRespAtomicError)) begin
            $error("Rejected atomic operand drain returned an invalid response");
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

        $display("Atomic handler operation and protocol tests passed");
        $finish;
    end

    initial begin
        #100us;
        $fatal(1, "Atomic handler test timed out");
    end

endmodule : hyperbus_atomic_handler_tb
