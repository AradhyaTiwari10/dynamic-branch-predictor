`timescale 1ns/1ps
`default_nettype none
//------------------------------------------------------------------------------
// File    : btb.v
// Module  : btb
// Author  : Yashvi
// Project : Dynamic Branch Prediction Unit (MCA Project 5) - Phase 2
//
// Purpose : Branch Target Buffer (BTB), direct mapped, 2^IDX_BITS entries.
//           The direction predictor only says "taken / not taken". To fetch
//           from the target in the very next cycle, the IF stage also needs
//           the target address before the branch is even decoded. The BTB
//           remembers the target of every taken branch it has seen.
//
//           Entry = {valid, tag, target}
//             index = pc[IDX_BITS+1:2]
//             tag   = pc[31:IDX_BITS+2]   (the remaining upper PC bits)
//           hit   = valid[index] && tag[index] == pc tag
//
//           - Asynchronous read (IF stage, same cycle).
//           - Synchronous write (EX stage): when a branch is resolved taken,
//             its PC and target are stored.
//           - Synchronous reset clears all valid bits (no hits after reset).
//
// Ports   :
//   clk, rst    clock, synchronous active-high reset
//   rd_pc       PC being fetched
//   hit         1 = rd_pc is a known taken branch
//   rd_target   stored target (valid only when hit = 1)
//   wr_en       write enable (taken branch resolved in EX)
//   wr_pc       PC of that branch
//   wr_target   its target address
//------------------------------------------------------------------------------
module btb #(
    parameter IDX_BITS = 4
) (
    input  wire        clk,
    input  wire        rst,
    input  wire [31:0] rd_pc,
    output wire        hit,
    output wire [31:0] rd_target,
    input  wire        wr_en,
    input  wire [31:0] wr_pc,
    input  wire [31:0] wr_target
);

    localparam ENTRIES  = 1 << IDX_BITS;
    localparam TAG_BITS = 32 - IDX_BITS - 2;

    reg                valid_mem  [0:ENTRIES-1];
    reg [TAG_BITS-1:0] tag_mem    [0:ENTRIES-1];
    reg [31:0]         target_mem [0:ENTRIES-1];

    wire [IDX_BITS-1:0] rd_idx = rd_pc[IDX_BITS+1:2];
    wire [TAG_BITS-1:0] rd_tag = rd_pc[31:IDX_BITS+2];
    wire [IDX_BITS-1:0] wr_idx = wr_pc[IDX_BITS+1:2];
    wire [TAG_BITS-1:0] wr_tag = wr_pc[31:IDX_BITS+2];

    // Asynchronous read
    assign hit       = valid_mem[rd_idx] && (tag_mem[rd_idx] == rd_tag);
    assign rd_target = target_mem[rd_idx];

    // Synchronous write and reset
    integer i;
    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < ENTRIES; i = i + 1)
                valid_mem[i] <= 1'b0;
        end else if (wr_en) begin
            valid_mem[wr_idx]  <= 1'b1;
            tag_mem[wr_idx]    <= wr_tag;
            target_mem[wr_idx] <= wr_target;
        end
    end

endmodule
`default_nettype wire
