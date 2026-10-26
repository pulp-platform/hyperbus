// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Single-PHY byte memory. Physical command addresses count 16-bit words.
module hyperbus_link_mem #(
    parameter type link_req_t = logic,
    parameter type link_rsp_t = logic
) (
    input logic clk_i,
    input logic rst_ni,
    input int unsigned cycle_i,
    input logic inject_write_fault_i,
    input link_req_t link_req_i,
    output link_rsp_t link_rsp_o
);
    byte unsigned memory [128];
    typedef enum logic [2:0] { BackendIdle, ReadDelay, BackendRead,
        BackendWrite, ResponseDelay, BackendResponse } backend_state_e;
    backend_state_e backend_state;
    int unsigned address, remaining, delay_cycles;

    // Preload and observation do not advance time; reset leaves memory intact.
    task automatic write_byte(input int unsigned byte_address, input byte unsigned data);
        if (byte_address >= 128) $fatal(1, "Physical memory preload address out of range");
        memory[byte_address] = data;
    endtask

    function automatic byte unsigned read_byte(input int unsigned byte_address);
        if (byte_address >= 128) $fatal(1, "Physical memory observation address out of range");
        return memory[byte_address];
    endfunction

    always_comb begin
        link_rsp_o = '0;
        link_rsp_o.cmd_ready = backend_state == BackendIdle && cycle_i % 4 == 0;
        link_rsp_o.tx_ready = backend_state == BackendWrite && cycle_i % 3 != 0;
        link_rsp_o.rx_valid = backend_state == BackendRead;
        if (address < 127) link_rsp_o.rx.data = {memory[address+1], memory[address]};
        link_rsp_o.rx.last = remaining == 1;
        link_rsp_o.wrsp_valid = backend_state == BackendResponse;
    end

    always @(posedge clk_i) begin
        if (!rst_ni) begin
            backend_state <= BackendIdle;
            address <= 0;
            remaining <= 0;
            delay_cycles <= 0;
        end else begin
            case (backend_state)
                BackendIdle: if (link_req_i.cmd_valid && link_rsp_o.cmd_ready) begin
                    if (link_req_i.cmd.cs != 1 || !link_req_i.cmd.trans.burst_type ||
                        link_req_i.cmd.trans.burst == 0 ||
                        link_req_i.cmd.trans.address >= 64 ||
                        int'(link_req_i.cmd.trans.burst) >
                        64 - int'(link_req_i.cmd.trans.address))
                        $fatal(1, "Physical command outside the independent memory model");
                    address <= int'(link_req_i.cmd.trans.address)*2;
                    remaining <= int'(link_req_i.cmd.trans.burst);
                    delay_cycles <= 2;
                    backend_state <= link_req_i.cmd.trans.write ? BackendWrite : ReadDelay;
                end
                ReadDelay: if (delay_cycles == 0) backend_state <= BackendRead;
                           else delay_cycles <= delay_cycles - 1;
                BackendRead: if (link_req_i.rx_ready) begin
                    address <= address + 2;
                    remaining <= remaining - 1;
                    delay_cycles <= cycle_i % 3;
                    backend_state <= remaining == 1 ? BackendIdle : ReadDelay;
                end
                BackendWrite: if (link_req_i.tx_valid && link_rsp_o.tx_ready) begin
                    for (int lane = 0; lane < 2; lane++) begin
                        if (link_req_i.tx.strb[lane]) begin
                            if (inject_write_fault_i && address == 0 && lane == 0)
                                memory[address+lane] <= link_req_i.tx.data[lane*8 +: 8] ^ 8'h01;
                            else
                                memory[address+lane] <= link_req_i.tx.data[lane*8 +: 8];
                        end
                    end
                    if (link_req_i.tx.last != (remaining == 1))
                        $fatal(1, "Physical write LAST mismatch");
                    address <= address + 2;
                    remaining <= remaining - 1;
                    if (remaining == 1) begin
                        delay_cycles <= 3;
                        backend_state <= ResponseDelay;
                    end
                end
                ResponseDelay: if (delay_cycles == 0) backend_state <= BackendResponse;
                               else delay_cycles <= delay_cycles - 1;
                BackendResponse: if (link_req_i.wrsp_ready) backend_state <= BackendIdle;
                default: $fatal(1, "Invalid independent backend state");
            endcase
        end
    end
endmodule
