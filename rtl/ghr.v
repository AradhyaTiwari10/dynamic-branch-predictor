`timescale 1ns/1ps
`default_nettype none
//------------------------------------------------------------------------------
// File    : ghr.v
// Module  : ghr
// Author  : Mouli Srivastava
// Project : Dynamic Branch Prediction Unit (MCA Project 5) - Phase 2
//
// Purpose : Global History Register (GHR) for the gshare predictor.
//           Holds the outcomes of the last HIST_BITS conditional branches
//           (1 = taken, 0 = not taken), newest outcome in bit 0.
//           Every time a branch outcome is known (upd_en = 1) the register
//           shifts left and the new outcome enters at bit 0:
//               history <= {history[HIST_BITS-2:0], taken}
//
//           gshare index = pc[IDX_BITS+1:2] XOR history  (see gshare_index.v)
//           Because the index depends on the recent outcomes, a branch with a
//           repeating pattern (e.g. T,N,T,N) uses a different BHT counter for
//           each position in the pattern and can be predicted correctly.
//
// Ports   :
//   clk      in   clock
//   rst      in   synchronous, active-high reset (history <= 0)
//   upd_en   in   1 when a branch outcome is available this cycle
//   taken    in   outcome of that branch
//   history  out  current global history [HIST_BITS-1:0]
//------------------------------------------------------------------------------
module ghr #(
    parameter HIST_BITS = 4
) (
    input  wire                 clk,
    input  wire                 rst,
    input  wire                 upd_en,
    input  wire                 taken,
    output reg  [HIST_BITS-1:0] history
);

    always @(posedge clk) begin
        if (rst)
            history <= {HIST_BITS{1'b0}};
        else if (upd_en)
            history <= {history[HIST_BITS-2:0], taken};
    end

endmodule
`default_nettype wire
