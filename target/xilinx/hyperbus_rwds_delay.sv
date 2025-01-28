// Copyright 2025 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Philippe Sauter <phsauter@iis.ee.ethz.ch>

(* no_ungroup *)
(* no_boundary_optimization *)
(* keep_hierarchy = "yes" *)
module hyperbus_rwds_delay
(
    input  logic       rst_i,
    input  logic       in_i,
    input  logic       clk_i, // control clock used to load delay_i
    input  logic [4:0] delay_i,
    output logic       out_o
);

    (* dont_touch = "true" *) logic out_delayed;

    // "Xilinx 7 Series FPGA and Zynq-7000 All Programmable SoC Libraries Guide for HDL Designs" - page 194
    // Delay a signal coming in from IOs or delay an internal data signal
    // modes:
    // - FIXED: constant delay value from param
    // - VARIABLE: start with param value then increment/decrement
    // - VAR_LOAD: dynamically load tap values
    // - VAR_LOAD_PIPE: pipelines dynamic load
    IDELAYE2 #(
        .CINVCTRL_SEL          ( "FALSE"    ), // "TRUE" actives CINVCTRL functionality
        .DELAY_SRC             ( "IDATAIN"  ), // source to delay chain ("CLKIN" or "IDATAIN")
        .HIGH_PERFORMANCE_MODE ( "TRUE"     ),  // "TRUE" for less jitter; "FALSE" for low power
        .IDELAY_TYPE           ( "VAR_LOAD" ), // mode of operation, see above
        .IDELAY_VALUE          ( 0          ), // delay value 0-31 (used in "VARIABLE" and "FIXED" mode)
        .PIPE_SEL              ( "FALSE"    ), // "TRUE" activates pipelined operation 
        .REFCLK_FREQUENCY      ( 200.0      ), // used for STA and simulation (190.0 - 310.0 MHz)
        .SIGNAL_PATTERN        ( "CLOCK"    ) // "DATA" or "CLOCK" depending on function, used in STA
    ) delay (
        .REGRST      ( rst_i       ), // input: reset delay tap value to IDELAY_VALUE or CNTVALUEIN
        .C           ( clk_i       ), // input: control input clock
        .DATAIN      ( 1'b0        ), // input: signal from FPGA logic to be delayed
        .IDATAIN     ( in_i        ), // input: signal from IO to be delayed
        .DATAOUT     ( out_delayed ), // output: delayed from DATAIN or IDATAIN (drives ISERDESE2 or logic, not IO!)
        .CE          ( 1'b0        ), // input: increment/decrement enable
        .CINVCTRL    ( 1'b0        ), // input: switch clock polarity during operation (glitches!)
        .CNTVALUEIN  ( delay_i     ), // 5 bit input: delay tap
        .CNTVALUEOUT (             ), // 5 bit output: delay tap
        .LD          ( 1'b0        ), // input: load IDELAY_VALUE param or CNTVALUEIN (depends on IDELAY_TYPE)
        .INC         ( 1'b0        ), // input: increment/decrement delay tap
        .LDPIPEEN    ( 1'b0        ) // input: enable the pipeline register to load data from LD
    );

    (* dont_touch = "true" *) IBUF #(
     .IBUF_LOW_PWR ( "FALSE" )
    ) i_const_delay (
        .I  ( out_delayed ),
        .O  ( out_o )
    );

endmodule
