`timescale 1ns/1ps
`default_nettype none
//------------------------------------------------------------------------------
// File    : gshare_index.v
// Module  : gshare_index
// Author  : Mouli Srivastava
// Project : Dynamic Branch Prediction Unit (MCA Project 5) - Phase 2
//
// Purpose : BHT index selection.
//           mode 0/1/2 (static, 1-bit, 2-bit):  idx = pc[IDX_BITS+1:2]
//           mode 3     (gshare):                idx = pc[IDX_BITS+1:2] ^ history
//
//           pc[1:0] is skipped because instructions are 4-byte aligned.
//           XOR-ing the address bits with the global history (McFarling 1993)
//           spreads the same branch over several counters, one per recent
//           history pattern.
//
// Ports   :
//   mode     in   predictor mode (3 = gshare)
//   pc       in   branch PC
//   history  in   global history from ghr.v
//   idx      out  BHT index
//------------------------------------------------------------------------------
module gshare_index #(
    parameter IDX_BITS = 4
) (
    input  wire [1:0]          mode,
    input  wire [31:0]         pc,
    input  wire [IDX_BITS-1:0] history,
    output wire [IDX_BITS-1:0] idx
);

    wire [IDX_BITS-1:0] pc_bits = pc[IDX_BITS+1:2];

    assign idx = (mode == 2'd3) ? (pc_bits ^ history) : pc_bits;

endmodule
`default_nettype wire
