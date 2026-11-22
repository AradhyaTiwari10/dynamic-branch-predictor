`timescale 1ns/1ps
`default_nettype none
//------------------------------------------------------------------------------
// File    : branch_unit.v
// Module  : branch_unit
// Author  : Mouli Srivastava
// Project : Dynamic Branch Prediction Unit (MCA Project 5) - Phase 2
//
// Purpose : Branch resolution in the EX stage.
//           Decides whether a conditional branch is taken and computes its
//           target address. The pipeline compares this real outcome with the
//           prediction made in IF; if they differ, it flushes.
//
//   br_funct3 | branch | taken when
//   ----------+--------+------------------------
//      000    | BEQ    | a == b
//      001    | BNE    | a != b
//      100    | BLT    | a <  b (signed)
//      101    | BGE    | a >= b (signed)
//
// Ports   :
//   is_branch  in   1 = the instruction in EX is a conditional branch
//   br_funct3  in   branch type
//   a, b       in   rs1 and rs2 values (after forwarding)
//   pc         in   PC of the branch
//   imm        in   B-type immediate (byte offset)
//   taken      out  1 = branch is taken (0 if not a branch)
//   target     out  pc + imm
//------------------------------------------------------------------------------
module branch_unit (
    input  wire        is_branch,
    input  wire [2:0]  br_funct3,
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire [31:0] pc,
    input  wire [31:0] imm,
    output reg         taken,
    output wire [31:0] target
);

    assign target = pc + imm;

    always @(*) begin
        if (!is_branch) begin
            taken = 1'b0;
        end else begin
            case (br_funct3)
                3'b000:  taken = (a == b);
                3'b001:  taken = (a != b);
                3'b100:  taken = ($signed(a) <  $signed(b));
                3'b101:  taken = ($signed(a) >= $signed(b));
                default: taken = 1'b0;
            endcase
        end
    end

endmodule
`default_nettype wire
