`timescale 1ns/1ps
`default_nettype none
//------------------------------------------------------------------------------
// File    : pred_static.v
// Module  : pred_static
// Author  : Mouli
// Project : Dynamic Branch Prediction Unit (MCA Project 5)
//
// Purpose : Static always-not-taken predictor (Mode 0, baseline).
//           predict_taken is always 0 — the simplest possible strategy.
//           next_state = state (unchanged) so the BHT history written by
//           other modes is preserved when mode switches.
//
// Ports   :
//   state          in  [1:0]  current 2-bit BHT entry for this PC
//   taken          in         actual branch outcome
//                             (unused here — exists to match the common
//                              interface shared by pred_1bit and pred_2bit)
//   predict_taken  out        prediction = always 1'b0 (never taken)
//   next_state     out  [1:0] BHT entry to write back = state (no learning)
//------------------------------------------------------------------------------
module pred_static (
    input  wire [1:0] state,
    input  wire       taken,        // unused; kept for interface consistency
    output wire       predict_taken,
    output wire [1:0] next_state
);

    // Always predict not-taken regardless of history
    assign predict_taken = 1'b0;

    // Static predictor never updates the BHT entry
    assign next_state = state;

endmodule
`default_nettype wire

