// Copyright 2026 Fondazione Chips-IT
//
// Andrea Di Ruzza <andrea.diruzza@chips.it>
// Luca Colombo <luca.colombo@chips.it>
// This module creates a Hyperloop delay to obtain the delay line required to shiftby 90 degrees the clk

(* no_ungroup *)
(* no_boundary_optimization *)
(* keep_hierarchy = "yes" *)
module hyperloop_delay (
    input  logic        in_i,
    input  logic [4:0]  delay_i,
    output logic        out_o
);

    // For the PD implementationt, the total delay is 5.82ns, with a step of 0.182ns, allowing
    // to cover a clock cycle at 200MHz.
    // The number of taps can be changed to cover a clock cycle for lower clocm frequencies.
    configurable_delay #(
      .NUM_STEPS(32)
    ) i_delay (
        .clk_i      ( in_i         ),
        .delay_i    ( delay_i[4:0] ),
        .clk_o      ( out_o        )
    );

endmodule : hyperloop_delay
