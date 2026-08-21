// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

module hyperbus_tx_clk_delay (
    input  logic       rst_ni,
`ifdef TARGET_XILINX
    input  logic       clk_ref200_i,
`endif
    input  logic       clk_i,
    input  logic       in_i,
    input  logic [7:0] delay_i,
    output logic       out_o
);

`ifdef TARGET_XILINX
    hyperbus_clk_delay i_delay_tx_clk_90 (
        .rst_i         ( ~rst_ni      ),
        .clk_ref200_i  ( clk_ref200_i ),
        .clk_i         ( clk_i        ),
        .in_i          ( in_i         ),
        .delay_i       ( delay_i      ),
        .out_o         ( out_o        )
    );
`else
    hyperbus_delay i_delay_tx_clk_90 (
        .in_i          ( in_i         ),
        .delay_i       ( delay_i      ),
        .out_o         ( out_o        )
    );
`endif

endmodule
