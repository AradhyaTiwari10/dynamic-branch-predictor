`timescale 1ns/1ps
`default_nettype none
//------------------------------------------------------------------------------
// File    : perf_counter.v
// Module  : perf_counter
// Author  : Aradhya Tiwari
// Project : Dynamic Branch Prediction Unit (MCA Project 5)
//
// Purpose : 32-bit event counter used to measure predictor performance.
//           The top module uses two instances:
//             - u_cnt_branch  : counts every branch presented (inc = br_valid)
//             - u_cnt_mispred : counts every misprediction   (inc = mispredict)
//           Accuracy = (branches - mispredicts) / branches.
//
// Ports   :
//   clk    in   clock
//   rst    in   synchronous, active-high reset (count <= 0)
//   inc    in   when 1, count increments by 1 on the rising clock edge
//   count  out  current 32-bit count value
//------------------------------------------------------------------------------
module perf_counter (
    input  wire        clk,
    input  wire        rst,
    input  wire        inc,
    output reg  [31:0] count
);

    always @(posedge clk) begin
        if (rst)
            count <= 32'd0;
        else if (inc)
            count <= count + 32'd1;
    end

endmodule
`default_nettype wire
