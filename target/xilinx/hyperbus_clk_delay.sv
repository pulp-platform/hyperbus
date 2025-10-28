// Copyright 2025 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Philippe Sauter <phsauter@iis.ee.ethz.ch>

(* no_ungroup *)
(* no_boundary_optimization *)
(* keep_hierarchy = "yes" *)
module hyperbus_clk_delay
(
    input  logic       rst_i,
    input  logic       clk_ref200_i, // 200 MHz reference clock
    input  logic       clk_i,        // control clock used to load delay_i
    input  logic       in_i,
    input  logic [4:0] delay_i,
    output logic       out_o
);

    // "Xilinx 7 Series FPGA and Zynq-7000 All Programmable SoC Libraries Guide for HDL Designs" - page 192
    // Calibrates delay lines (IDELAYE2 and ODELAYE2) from ref clock (200 MHz)
    IDELAYCTRL i_delayctrl
    (
        .REFCLK ( clk_ref200_i ),
        .RST    ( rst_i ),
        .RDY    ()
    );

    // "Xilinx 7 Series FPGA and Zynq-7000 All Programmable SoC Libraries Guide for HDL Designs" - page 330
    // Delay a signal going out to IOs or delay an internal clock
    // modes:
    // - FIXED: constant delay value from param
    // - VARIABLE: start with param value then increment/decrement
    // - VAR_LOAD: dynamically load tap values
    // - VAR_LOAD_PIPE: pipelines dynamic load
    // ODELAYE2 #(
    //     .CINVCTRL_SEL          ( "FALSE"    ), // "TRUE" actives CINVCTRL functionality
    //     .DELAY_SRC             ( "CLKIN"    ), // source to delay chain ("CLKIN" or "ODATAIN")
    //     .HIGH_PERFORMANCE_MODE ( "TRUE"     ),  // "TRUE" for less jitter; "FALSE" for low power
    //     .ODELAY_TYPE           ( "VAR_LOAD" ), // mode of operation, see above
    //     .ODELAY_VALUE          ( 0          ), // delay value 0-31 (used in "VARIABLE" and "FIXED" mode)
    //     .PIPE_SEL              ( "FALSE"    ), // "TRUE" activates pipelined operation 
    //     .REFCLK_FREQUENCY      ( 200.0      ), // used for STA and simulation (190.0 - 310.0 MHz)
    //     .SIGNAL_PATTERN        ( "CLOCK"    ) // "DATA" or "CLOCK" depending on function, used in STA
    // ) i_delay (
    //     .REGRST      ( rst_i       ), // input: reset delay tap value to ODELAY_VALUE or CNTVALUEIN
    //     .C           ( clk_i       ), // input: control input clock
    //     .CLKIN       ( in_i        ), // input: clock to be delayed
    //     .ODATAIN     ( 1'b0        ), // input: signal to be delayed driven by OSERDESE2 or output reg
    //     .DATAOUT     ( out_o       ), // output: delayed from ODATAIN (drives IO) or CLKIN (back into clock network)
    //     .CE          ( 1'b0        ), // input: increment/decrement enable
    //     .CINVCTRL    ( 1'b0        ), // input: switch clock polarity during operation (glitches!)
    //     .CNTVALUEIN  ( delay_i     ), // 5 bit input: delay tap
    //     .CNTVALUEOUT (             ), // 5 bit output: delay tap
    //     .INC         ( 1'b0        ), // input: increment/decrement delay tap
    //     .LD          ( 1'b0        ), // input: load ODELAY_VALUE param or CNTVALUEIN (depends on IDELAY_TYPE)
    //     .LDPIPEEN    ( 1'b0        ) // input: enable the pipeline register to load data from LD
    // );
    IDELAYE2 #(
        .CINVCTRL_SEL          ( "FALSE"    ), // "TRUE" actives CINVCTRL functionality
        .DELAY_SRC             ( "DATAIN"   ), // source to delay chain ("CLKIN" or "IDATAIN")
        .HIGH_PERFORMANCE_MODE ( "TRUE"     ),  // "TRUE" for less jitter; "FALSE" for low power
        .IDELAY_TYPE           ( "VAR_LOAD" ), // mode of operation, see above
        .IDELAY_VALUE          ( 0          ), // delay value 0-31 (used in "VARIABLE" and "FIXED" mode)
        .PIPE_SEL              ( "FALSE"    ), // "TRUE" activates pipelined operation 
        .REFCLK_FREQUENCY      ( 200.0      ), // used for STA and simulation (190.0 - 310.0 MHz)
        .SIGNAL_PATTERN        ( "CLOCK"    ) // "DATA" or "CLOCK" depending on function, used in STA
    ) i_delay (
        .REGRST      ( rst_i       ), // input: reset delay tap value to IDELAY_VALUE or CNTVALUEIN
        .C           ( clk_i       ), // input: control input clock
        .DATAIN      ( in_i        ), // input: signal from FPGA logic to be delayed
        .IDATAIN     ( 1'b0        ), // input: signal from IO to be delayed
        .DATAOUT     ( out_o       ), // output: delayed from DATAIN or IDATAIN (drives ISERDESE2 or logic, not IO!)
        .CE          ( 1'b0        ), // input: increment/decrement enable
        .CINVCTRL    ( 1'b0        ), // input: switch clock polarity during operation (glitches!)
        .CNTVALUEIN  ( delay_i     ), // 5 bit input: delay tap
        .CNTVALUEOUT (             ), // 5 bit output: delay tap
        .LD          ( 1'b1        ), // input: load IDELAY_VALUE param or CNTVALUEIN (depends on IDELAY_TYPE)
        .INC         ( 1'b0        ), // input: increment/decrement delay tap
        .LDPIPEEN    ( 1'b0        ) // input: enable the pipeline register to load data from LD
    );

endmodule
