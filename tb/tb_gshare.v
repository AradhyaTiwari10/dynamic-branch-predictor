`timescale 1ns/1ps
//------------------------------------------------------------------------------
// File    : tb_gshare.v
// Module  : tb_gshare
// Author  : Anuj
// Project : Dynamic Branch Prediction Unit (MCA Project 5) - Phase 2
//
// Purpose : Directed unit tests for the global history register (rtl/ghr.v)
//           and the gshare index logic (rtl/gshare_index.v), 4-bit history.
//
//           Test 1  after reset history = 0000
//           Test 2  shift in T,N,T,T -> history = 1011 (newest outcome in bit 0)
//           Test 3  upd_en = 0 keeps the history
//           Test 4  a 5th outcome (N) pushes the oldest bit out -> 0110
//           Test 5  gshare_index, history 0110:
//                     mode 2: idx = pc[5:2]           (pc 0x24 -> 1001)
//                     mode 3: idx = pc[5:2] ^ history (1001 ^ 0110 = 1111)
//                     mode 0 and 1 also ignore the history
//           Test 6  a second reset clears the history
//
//           Prints one PASS/FAIL line per check and a final summary:
//             ALL GSHARE TESTS PASSED (<n> checks)  or  GSHARE TESTS FAILED: <n> of <m>
//
// Run     : mkdir -p build && iverilog -g2012 -o build/tb_gshare tb/tb_gshare.v \
//             rtl/ghr.v rtl/gshare_index.v && vvp build/tb_gshare
//------------------------------------------------------------------------------
module tb_gshare;

    reg        clk = 1'b0;
    reg        rst = 1'b1;
    reg        upd_en = 1'b0;
    reg        taken = 1'b0;
    wire [3:0] history;
    reg  [1:0] mode = 2'd2;
    reg [31:0] pc = 32'd0;
    wire [3:0] idx;

    ghr #(.HIST_BITS(4)) u_ghr (
        .clk     (clk),
        .rst     (rst),
        .upd_en  (upd_en),
        .taken   (taken),
        .history (history)
    );

    gshare_index #(.IDX_BITS(4)) u_idx (
        .mode    (mode),
        .pc      (pc),
        .history (history),
        .idx     (idx)
    );

    always #5 clk = ~clk;

    integer tests = 0, fails = 0;

    task check4;
        input [8*40-1:0] name;
        input [3:0]      got;
        input [3:0]      exp;
        begin
            tests = tests + 1;
            if (got === exp)
                $display("PASS %0s", name);
            else begin
                fails = fails + 1;
                $display("FAIL %0s: got %b expected %b", name, got, exp);
            end
        end
    endtask

    task push;              // one branch outcome on the next clock edge
        input en;
        input t;
        begin
            @(negedge clk);
            upd_en = en; taken = t;
            @(negedge clk);
            upd_en = 1'b0;
        end
    endtask

    initial begin
        @(negedge clk); @(negedge clk);
        rst = 1'b0;

        check4("T1 history after reset", history, 4'b0000);

        push(1, 1); push(1, 0); push(1, 1); push(1, 1);
        check4("T2 T,N,T,T -> 1011", history, 4'b1011);

        push(0, 0);
        check4("T3 upd_en=0 keeps 1011", history, 4'b1011);

        push(1, 0);
        check4("T4 5th outcome N -> 0110", history, 4'b0110);

        pc = 32'h24;
        mode = 2'd2; #1; check4("T5 mode 2 idx = pc[5:2]", idx, 4'b1001);
        mode = 2'd3; #1; check4("T5 mode 3 idx = pc ^ hist", idx, 4'b1111);
        mode = 2'd0; #1; check4("T5 mode 0 ignores history", idx, 4'b1001);
        mode = 2'd1; #1; check4("T5 mode 1 ignores history", idx, 4'b1001);

        @(negedge clk); rst = 1'b1; @(negedge clk); rst = 1'b0;
        check4("T6 second reset -> 0000", history, 4'b0000);

        if (fails == 0)
            $display("ALL GSHARE TESTS PASSED (%0d checks)", tests);
        else
            $display("GSHARE TESTS FAILED: %0d of %0d", fails, tests);
        $finish;
    end

endmodule
