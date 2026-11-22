`timescale 1ns/1ps
//------------------------------------------------------------------------------
// File    : tb_btb.v
// Module  : tb_btb
// Author  : Anuj
// Project : Dynamic Branch Prediction Unit (MCA Project 5) - Phase 2
//
// Purpose : Directed unit tests for the Branch Target Buffer (rtl/btb.v),
//           16 entries (IDX_BITS = 4), index = pc[5:2], tag = pc[31:6].
//
//           Test 1  after reset nothing hits
//           Test 2  write (0x40 -> 0x14): 0x40 hits with target 0x14,
//                   a different index (0x44) still misses
//           Test 3  same index, different tag (0x80 vs 0x40): miss (no false hit)
//           Test 4  a write with wr_en = 0 changes nothing
//           Test 5  overwrite: 0x80 -> 0x1C replaces 0x40 in entry 0;
//                   now 0x80 hits and 0x40 misses
//           Test 6  a second reset clears every entry
//
//           Prints one PASS/FAIL line per check and a final summary:
//             ALL BTB TESTS PASSED (<n> checks)   or   BTB TESTS FAILED: <n> of <m>
//
// Run     : mkdir -p build && iverilog -g2012 -o build/tb_btb tb/tb_btb.v rtl/btb.v \
//             && vvp build/tb_btb
//------------------------------------------------------------------------------
module tb_btb;

    reg         clk = 1'b0;
    reg         rst = 1'b1;
    reg  [31:0] rd_pc = 32'd0;
    wire        hit;
    wire [31:0] rd_target;
    reg         wr_en = 1'b0;
    reg  [31:0] wr_pc = 32'd0;
    reg  [31:0] wr_target = 32'd0;

    btb #(.IDX_BITS(4)) dut (
        .clk       (clk),
        .rst       (rst),
        .rd_pc     (rd_pc),
        .hit       (hit),
        .rd_target (rd_target),
        .wr_en     (wr_en),
        .wr_pc     (wr_pc),
        .wr_target (wr_target)
    );

    always #5 clk = ~clk;

    integer tests = 0, fails = 0;

    // check hit (and the target when a hit is expected)
    task check;
        input [8*40-1:0] name;
        input [31:0]     pc;
        input            exp_hit;
        input [31:0]     exp_target;
        begin
            rd_pc = pc;
            #1;
            tests = tests + 1;
            if (hit === exp_hit && (!exp_hit || rd_target === exp_target))
                $display("PASS %0s", name);
            else begin
                fails = fails + 1;
                $display("FAIL %0s: hit=%b target=%h (expected hit=%b target=%h)",
                         name, hit, rd_target, exp_hit, exp_target);
            end
        end
    endtask

    task write;
        input        en;
        input [31:0] pc;
        input [31:0] target;
        begin
            @(negedge clk);
            wr_en = en; wr_pc = pc; wr_target = target;
            @(negedge clk);
            wr_en = 1'b0;
        end
    endtask

    initial begin
        @(negedge clk); @(negedge clk);
        rst = 1'b0;

        check("T1 after reset 0x40 misses", 32'h40, 1'b0, 32'h0);
        check("T1 after reset 0x80 misses", 32'h80, 1'b0, 32'h0);

        write(1'b1, 32'h40, 32'h14);
        check("T2 0x40 hits, target 0x14",  32'h40, 1'b1, 32'h14);
        check("T2 0x44 (other index) miss", 32'h44, 1'b0, 32'h0);

        check("T3 0x80 same index, miss",   32'h80, 1'b0, 32'h0);

        write(1'b0, 32'h48, 32'h99);
        check("T4 wr_en=0, 0x48 misses",    32'h48, 1'b0, 32'h0);
        check("T4 wr_en=0, 0x40 kept",      32'h40, 1'b1, 32'h14);

        write(1'b1, 32'h80, 32'h1C);
        check("T5 0x80 hits, target 0x1C",  32'h80, 1'b1, 32'h1C);
        check("T5 0x40 replaced, misses",   32'h40, 1'b0, 32'h0);

        @(negedge clk); rst = 1'b1; @(negedge clk); rst = 1'b0;
        check("T6 second reset, 0x80 miss", 32'h80, 1'b0, 32'h0);

        if (fails == 0)
            $display("ALL BTB TESTS PASSED (%0d checks)", tests);
        else
            $display("BTB TESTS FAILED: %0d of %0d", fails, tests);
        $finish;
    end

endmodule
