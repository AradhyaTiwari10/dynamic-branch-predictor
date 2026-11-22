`timescale 1ns/1ps
`default_nettype none
//------------------------------------------------------------------------------
// File    : alu.v
// Module  : alu
// Author  : Mouli Srivastava
// Project : Dynamic Branch Prediction Unit (MCA Project 5) - Phase 2
//
// Purpose : 32-bit ALU of the 5-stage pipeline (EX stage).
//           Supports the integer operations of our RV32I subset.
//
//   alu_op | operation | used by
//   -------+-----------+--------------------
//    000   | a + b     | ADD, ADDI
//    001   | a - b     | SUB
//    010   | a & b     | AND, ANDI
//    011   | a | b     | OR,  ORI
//    100   | a ^ b     | XOR, XORI
//    101   | a < b ?1:0| SLT, SLTI (signed)
//
// Ports   :
//   a, b     in   operands (b is rs2 or the immediate, chosen in EX)
//   alu_op   in   operation select (table above)
//   y        out  result
//------------------------------------------------------------------------------
module alu (
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire [2:0]  alu_op,
    output reg  [31:0] y
);

    localparam OP_ADD = 3'b000;
    localparam OP_SUB = 3'b001;
    localparam OP_AND = 3'b010;
    localparam OP_OR  = 3'b011;
    localparam OP_XOR = 3'b100;
    localparam OP_SLT = 3'b101;

    always @(*) begin
        case (alu_op)
            OP_ADD:  y = a + b;
            OP_SUB:  y = a - b;
            OP_AND:  y = a & b;
            OP_OR:   y = a | b;
            OP_XOR:  y = a ^ b;
            OP_SLT:  y = ($signed(a) < $signed(b)) ? 32'd1 : 32'd0;
            default: y = 32'd0;
        endcase
    end

endmodule
`default_nettype wire
