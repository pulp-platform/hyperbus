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

    // "Xilinx 7 Series FPGA and Zynq-7000 All Programmable SoC Libraries Guide for HDL Designs" - page 194
    // Delay a signal coming in from IOs or delay an internal data signal
    // modes:
    // - FIXED: constant delay value from param
    // - VARIABLE: start with param value then increment/decrement
    // - VAR_LOAD: dynamically load tap values
    // - VAR_LOAD_PIPE: pipelines dynamic load


    // Ultrascale FGPAs require IDELAY3
    IDELAYE3 #(
        .CASCADE("NONE"),
        .DELAY_FORMAT("COUNT"),
        .DELAY_TYPE("VAR_LOAD"),
        .DELAY_VALUE(0),
        .DELAY_SRC("DATAIN"),
        .REFCLK_FREQUENCY(200.0),
        .UPDATE_MODE("ASYNC"),
        .SIM_DEVICE("ULTRASCALE_PLUS")
    ) i_delay (
        .DATAOUT(out_o_o),
        .DATAIN(in_i),
        .IDATAIN(1'b0),
    
        .CNTVALUEIN(delay_i),
        .CNTVALUEOUT(),
    
        .LOAD(1'b1),
        .CE(1'b0),
        .INC(1'b0),
    
        .CLK(clk_i),
        .RST(rst_i),
    
        .EN_VTC(1'b0),
    
        .CASC_IN(1'b0),
        .CASC_RETURN(1'b0)
    );

    /*  WORKAROUND for Xilinx FPGAs:
        Sometimes, DRC check before place design gives the following error:
        [DRC REQP-1741] IDELAYE3 drives invalid load: IDELAYE3 may not drive a BUFG*
        This may occur even when constraints such as CLOCK_BUFFER_TYPE NONE and CLOCK_DEDICATED_ROUTE FALSE are applied to the IDELAYE3 output, which are intended to prevent the use of global clock buffers.
        Xilinx docs states that the IDELAY3 primitive should not be used to delay a clock.
        A possible workaround is to insert a LUT1 between the IDELAYE3 output and the downstream logic, while preventing its optimization. However, this solution introduces additional delay on the path.
        Another option is to disable the specific DRC check:
        set_property IS_ENABLED 0 [get_drc_checks {REQP-1741}]
    */
    logic       out_o_o;
    (*dont_touch = "yes"*) 
    LUT1#(
    .INIT(2'b10)
    ) LUT1_Inst (
        .O( out_o),
        .I0( out_o_o)
    );

endmodule
