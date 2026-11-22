`timescale 1ns/1ps
`default_nettype none
//------------------------------------------------------------------------------
// File    : bht.v
// Module  : bht
// Author  : Yashvi
// Project : Dynamic Branch Prediction Unit (MCA Project 5)
//
// Purpose : Branch History Table (BHT).
//           Stores 2-bit prediction state for each branch entry.
//           - Asynchronous (combinational) read: rd_state is immediately
//             available from rd_idx in the same clock cycle.
//           - Synchronous write: updates entry wr_idx with wr_state on posedge clk.
//           - Synchronous active-high reset: initializes all entries to INIT (2'b01 = WNT).
//           - Phase 2: second asynchronous read port (rd2_idx / rd2_state).
//             In the pipeline, port 1 is read by IF to predict, and port 2
//             is read by EX to get the current state of the entry being
//             updated. The trace-driven top ties rd2_idx to 0.
//
// Parameters:
//   IDX_BITS : Width of table index (default 4 -> 16 entries)
//   INIT     : Initial 2-bit state on reset (default 2'b01 = Weakly Not-Taken)
//
// Ports:
//   clk      : Clock
//   rst      : Synchronous active-high reset
//   rd_idx   : Read index into table [IDX_BITS-1:0]
//   rd_state : Asynchronously read 2-bit state [1:0]
//   rd2_idx  : Second read index (Phase 2) [IDX_BITS-1:0]
//   rd2_state: Second asynchronously read 2-bit state [1:0]
//   wr_en    : Write enable
//   wr_idx   : Write index into table [IDX_BITS-1:0]
//   wr_state : 2-bit state to write [1:0]
//------------------------------------------------------------------------------
module bht #(
    parameter IDX_BITS = 4,
    parameter [1:0] INIT = 2'b01
) (
    input  wire                clk,
    input  wire                rst,
    input  wire [IDX_BITS-1:0] rd_idx,
    output wire [1:0]          rd_state,
    input  wire [IDX_BITS-1:0] rd2_idx,
    output wire [1:0]          rd2_state,
    input  wire                wr_en,
    input  wire [IDX_BITS-1:0] wr_idx,
    input  wire [1:0]          wr_state
);

    // Table storage: 2^IDX_BITS entries of 2 bits each
    reg [1:0] table_mem [0:(1<<IDX_BITS)-1];

    // Asynchronous (combinational) read
    assign rd_state  = table_mem[rd_idx];
    assign rd2_state = table_mem[rd2_idx];

    // Synchronous write and synchronous reset
    integer i;

    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < (1 << IDX_BITS); i = i + 1) begin
                table_mem[i] <= INIT;
            end
        end else if (wr_en) begin
            table_mem[wr_idx] <= wr_state;
        end
    end

endmodule
`default_nettype wire
