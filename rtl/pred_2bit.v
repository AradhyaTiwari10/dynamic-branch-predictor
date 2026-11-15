`timescale 1ns/1ps
`default_nettype none
//------------------------------------------------------------------------------
// File    : pred_2bit.v
// Module  : pred_2bit
// Author  : Mouli
// Project : Dynamic Branch Prediction Unit (MCA Project 5)
//
// Purpose : 2-bit saturating counter predictor (Mode 2).
//
//           Four FSM states (2-bit encoding):
//             SNT = 2'b00  Strongly  Not-Taken
//             WNT = 2'b01  Weakly    Not-Taken
//             WT  = 2'b10  Weakly    Taken
//             ST  = 2'b11  Strongly  Taken
//
//           State-transition table:
//             state | taken=1 | taken=0
//             ------+---------+--------
//             SNT   |   WNT   |  SNT     (saturate at SNT)
//             WNT   |   WT    |  SNT
//             WT    |   ST    |  WNT
//             ST    |   ST    |  WT      (saturate at ST)
//
//           Prediction : state[1] (MSB) — same as 1-bit, but the extra bit
//           of hysteresis means one wrong outcome does NOT flip the prediction.
//           This eliminates the double-mispredict at loop boundaries.
//
// Ports   :
//   state          in  [1:0]  current 2-bit BHT entry for this PC
//   taken          in         actual branch outcome
//   predict_taken  out        prediction = state[1]
//   next_state     out  [1:0] next FSM state per transition table above
//------------------------------------------------------------------------------
module pred_2bit (
    input  wire [1:0] state,
    input  wire       taken,
    output wire       predict_taken,
    output wire [1:0] next_state
);

    // FSM state encodings
    localparam SNT = 2'b00;   // Strongly  Not-Taken
    localparam WNT = 2'b01;   // Weakly    Not-Taken
    localparam WT  = 2'b10;   // Weakly    Taken
    localparam ST  = 2'b11;   // Strongly  Taken

    // Predict using the MSB of the saturating counter
    assign predict_taken = state[1];

    // Combinational next-state logic — exact transition table from spec
    reg [1:0] next_state_r;

    always @(*) begin
        case (state)
            SNT: next_state_r = taken ? WNT : SNT;   // 00: inc→01, dec saturates→00
            WNT: next_state_r = taken ? WT  : SNT;   // 01: inc→10, dec→00
            WT : next_state_r = taken ? ST  : WNT;   // 10: inc→11, dec→01
            ST : next_state_r = taken ? ST  : WT;    // 11: inc saturates→11, dec→10
            default: next_state_r = WNT;              // unreachable; safe default
        endcase
    end

    assign next_state = next_state_r;

endmodule
`default_nettype wire

