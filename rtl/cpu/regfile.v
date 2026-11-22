`timescale 1ns/1ps
`default_nettype none
//------------------------------------------------------------------------------
// File    : regfile.v
// Module  : regfile
// Author  : Mouli Srivastava
// Project : Dynamic Branch Prediction Unit (MCA Project 5) - Phase 2
//
// Purpose : 32 x 32-bit register file (x0 .. x31) of the pipeline.
//           - Two combinational read ports (ID stage).
//           - One write port, written on the rising clock edge (WB stage).
//           - x0 always reads 0 and is never written.
//           - Write-through bypass: if WB writes the register that ID is
//             reading in the same cycle, the new value is returned, so an
//             instruction 3 positions after its producer gets the right value.
//           - Synchronous reset clears all registers to 0.
//
// Ports   :
//   clk, rst          clock, synchronous active-high reset
//   ra1, ra2          read addresses (rs1, rs2)
//   rd1, rd2          read data
//   we, wa, wd        write enable, write address (rd), write data
//   dbg_addr          debug read address (used by the testbench)
//   dbg_data          debug read data
//------------------------------------------------------------------------------
module regfile (
    input  wire        clk,
    input  wire        rst,
    input  wire [4:0]  ra1,
    input  wire [4:0]  ra2,
    output wire [31:0] rd1,
    output wire [31:0] rd2,
    input  wire        we,
    input  wire [4:0]  wa,
    input  wire [31:0] wd,
    input  wire [4:0]  dbg_addr,
    output wire [31:0] dbg_data
);

    reg [31:0] regs [0:31];
    integer i;

    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < 32; i = i + 1)
                regs[i] <= 32'd0;
        end else if (we && (wa != 5'd0)) begin
            regs[wa] <= wd;
        end
    end

    // Read with x0 = 0 and write-through bypass from the WB stage.
    assign rd1 = (ra1 == 5'd0)              ? 32'd0 :
                 (we && (wa == ra1))        ? wd    : regs[ra1];
    assign rd2 = (ra2 == 5'd0)              ? 32'd0 :
                 (we && (wa == ra2))        ? wd    : regs[ra2];

    assign dbg_data = (dbg_addr == 5'd0) ? 32'd0 : regs[dbg_addr];

endmodule
`default_nettype wire
