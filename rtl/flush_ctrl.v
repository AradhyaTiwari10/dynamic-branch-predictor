`timescale 1ns/1ps
`default_nettype none
//------------------------------------------------------------------------------
// File    : flush_ctrl.v
// Module  : flush_ctrl
// Author  : Aradhya Tiwari
// Project : Dynamic Branch Prediction Unit (MCA Project 5)
//
// Purpose : Pipeline flush / control interface of the predictor.
//           In a 5-stage pipeline (IF-ID-EX-MEM-WB) a conditional branch is
//           resolved in EX. By then the instructions in IF and ID were fetched
//           using the prediction. If the prediction was wrong, those two
//           wrong-path instructions must be flushed, which costs PENALTY
//           (= 2) cycles.
//
//           Phase 1 (trace-driven): `flush` signals a misprediction and
//           `penalty_cycles` accumulates the total cycles lost, which is used
//           for the CPI analysis.
//           Phase 2: `flush` will clear the IF/ID and ID/EX pipeline registers.
//
// Ports   :
//   clk             in   clock
//   rst             in   synchronous, active-high reset (penalty_cycles <= 0)
//   mispredict      in   1 when the current branch was mispredicted
//   flush           out  flush request (combinational, = mispredict)
//   penalty_cycles  out  total cycles lost to mispredictions
//------------------------------------------------------------------------------
module flush_ctrl #(
    parameter PENALTY = 2       // cycles lost per misprediction (branch resolved in EX)
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        mispredict,
    output wire        flush,
    output reg  [31:0] penalty_cycles
);

    // Flush the wrong-path instructions in the same cycle the mispredict is seen.
    assign flush = mispredict;

    // Add PENALTY cycles for every misprediction.
    always @(posedge clk) begin
        if (rst)
            penalty_cycles <= 32'd0;
        else if (mispredict)
            penalty_cycles <= penalty_cycles + PENALTY;
    end

endmodule
`default_nettype wire
