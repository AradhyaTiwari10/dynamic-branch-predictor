`timescale 1ns/1ps
`default_nettype none
//------------------------------------------------------------------------------
// File    : pred_1bit.v
// Module  : pred_1bit
// Author  : Mouli
// Project : Dynamic Branch Prediction Unit (MCA Project 5)
//
// Purpose : 1-bit last-outcome predictor (Mode 1).
//           Predicts whatever happened last time (the MSB of state).
//           After seeing the actual outcome, the entry collapses to either
//           2'b11 (taken) or 2'b00 (not-taken) — only the MSB carries
//           information, so this is effectively a 1-bit predictor reusing
//           the same 2-bit BHT that serves all three modes.
//
//           Why it mispredicts TWICE per loop iteration boundary:
//           Consider a 10-iteration loop (T,T,T,...,T,N). At the last
//           iteration the branch is N — predictor had state=11 (T), mispredict.
//           State goes to 00. Next loop starts with T — state=00 (N), mispredict.
//           State goes to 11. So every loop boundary costs 2 mispredictions.
//
// Ports   :
//   state          in  [1:0]  current 2-bit BHT entry for this PC
//   taken          in         actual branch outcome
//   predict_taken  out        prediction = state[1] (MSB of last outcome)
//   next_state     out  [1:0] taken ? 2'b11 : 2'b00  ({taken, taken})
//------------------------------------------------------------------------------
module pred_1bit (
    input  wire [1:0] state,
    input  wire       taken,
    output wire       predict_taken,
    output wire [1:0] next_state
);

    // Predict using the MSB of the current BHT state
    assign predict_taken = state[1];

    // After resolution, collapse to all-1s (taken) or all-0s (not-taken)
    // Equivalent to: next_state = {taken, taken}
    assign next_state = taken ? 2'b11 : 2'b00;

endmodule
`default_nettype wire

