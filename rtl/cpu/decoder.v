`timescale 1ns/1ps
`default_nettype none
//------------------------------------------------------------------------------
// File    : decoder.v
// Module  : decoder
// Author  : Mouli Srivastava
// Project : Dynamic Branch Prediction Unit (MCA Project 5) - Phase 2
//
// Purpose : Instruction decoder of the ID stage for our RV32I subset.
//
//   Type    | opcode  | instructions
//   --------+---------+----------------------------------------------
//   R-type  | 0110011 | ADD, SUB, AND, OR, XOR, SLT
//   I-type  | 0010011 | ADDI, ANDI, ORI, XORI, SLTI
//   B-type  | 1100011 | BEQ, BNE, BLT, BGE   (conditional branches)
//   SYSTEM  | 1110011 | EBREAK = 0x00100073  (stops the simulation)
//
//   Any other word (including 0x00000000) is decoded as a NOP: it writes no
//   register and is not a branch.
//
//   Immediates (sign-extended to 32 bits):
//     I-type: imm = instr[31:20]
//     B-type: imm = {instr[31], instr[7], instr[30:25], instr[11:8], 1'b0}
//
// Ports   :
//   instr       in   32-bit instruction
//   rs1, rs2    out  source register numbers
//   rd          out  destination register number
//   imm         out  sign-extended immediate
//   alu_op      out  ALU operation (see alu.v)
//   alu_src_imm out  1 = ALU operand b is the immediate, 0 = rs2
//   reg_write   out  1 = instruction writes rd
//   is_branch   out  1 = conditional branch
//   br_funct3   out  branch type (000 BEQ, 001 BNE, 100 BLT, 101 BGE)
//   is_halt     out  1 = EBREAK
//------------------------------------------------------------------------------
module decoder (
    input  wire [31:0] instr,
    output wire [4:0]  rs1,
    output wire [4:0]  rs2,
    output wire [4:0]  rd,
    output reg  [31:0] imm,
    output reg  [2:0]  alu_op,
    output reg         alu_src_imm,
    output reg         reg_write,
    output reg         is_branch,
    output wire [2:0]  br_funct3,
    output reg         is_halt
);

    localparam OPC_R      = 7'b0110011;
    localparam OPC_I      = 7'b0010011;
    localparam OPC_BRANCH = 7'b1100011;
    localparam EBREAK     = 32'h00100073;

    wire [6:0] opcode = instr[6:0];
    wire [2:0] funct3 = instr[14:12];
    wire [6:0] funct7 = instr[31:25];

    assign rs1       = instr[19:15];
    assign rs2       = instr[24:20];
    assign rd        = instr[11:7];
    assign br_funct3 = funct3;

    // funct3 -> ALU operation (shared by R-type and I-type)
    function [2:0] alu_from_funct3;
        input [2:0] f3;
        input       sub;
        begin
            case (f3)
                3'b000:  alu_from_funct3 = sub ? 3'b001 : 3'b000; // ADD/SUB/ADDI
                3'b111:  alu_from_funct3 = 3'b010;                // AND
                3'b110:  alu_from_funct3 = 3'b011;                // OR
                3'b100:  alu_from_funct3 = 3'b100;                // XOR
                3'b010:  alu_from_funct3 = 3'b101;                // SLT
                default: alu_from_funct3 = 3'b000;
            endcase
        end
    endfunction

    always @(*) begin
        // defaults = NOP
        imm         = 32'd0;
        alu_op      = 3'b000;
        alu_src_imm = 1'b0;
        reg_write   = 1'b0;
        is_branch   = 1'b0;
        is_halt     = 1'b0;

        if (instr == EBREAK) begin
            is_halt = 1'b1;
        end else begin
            case (opcode)
                OPC_R: begin
                    alu_op    = alu_from_funct3(funct3, funct7[5]);
                    reg_write = 1'b1;
                end
                OPC_I: begin
                    imm         = {{20{instr[31]}}, instr[31:20]};
                    alu_op      = alu_from_funct3(funct3, 1'b0);
                    alu_src_imm = 1'b1;
                    reg_write   = 1'b1;
                end
                OPC_BRANCH: begin
                    imm       = {{19{instr[31]}}, instr[31], instr[7],
                                 instr[30:25], instr[11:8], 1'b0};
                    is_branch = 1'b1;
                end
                default: ; // NOP
            endcase
        end
    end

endmodule
`default_nettype wire
