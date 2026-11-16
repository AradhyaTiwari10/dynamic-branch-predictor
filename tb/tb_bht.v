`timescale 1ns/1ps
//------------------------------------------------------------------------------
// File    : tb_bht.v
// Module  : tb_bht
// Author  : Anuj
// Project : Dynamic Branch Prediction Unit (MCA Project 5)
//
// Purpose : Directed unit tests for the Branch History Table (rtl/bht.v).
//           16 entries (IDX_BITS = 4), reset value INIT = 2'b01 (WNT).
//
//           Test 1  after reset every entry reads 01
//           Test 2  write 11 to entry 3 -> reads back 11, entry 2 still 01
//           Test 3  a write with wr_en = 0 changes nothing
//           Test 4  a second reset restores every entry to 01
//           Test 5  the read is combinational: rd_state follows rd_idx
//                   immediately, with no clock edge in between
//
//           Prints one PASS/FAIL line per check and a final summary line:
//             ALL BHT TESTS PASSED           or
//             BHT TESTS FAILED: <n> of <m>
//           Waveform: build/tb_bht.vcd
//
// Run     : mkdir -p build && iverilog -g2012 -o build/tb_bht tb/tb_bht.v rtl/bht.v \
//             && vvp build/tb_bht
//------------------------------------------------------------------------------
module tb_bht;

    localparam IDX_BITS = 4;
    localparam ENTRIES  = 1 << IDX_BITS;

    // ---------------------------------------------------------------------
    // DUT signals
    // ---------------------------------------------------------------------
    reg                 clk;
    reg                 rst;
    reg  [IDX_BITS-1:0] rd_idx;
    wire [1:0]          rd_state;
    reg                 wr_en;
    reg  [IDX_BITS-1:0] wr_idx;
    reg  [1:0]          wr_state;

    bht #(
        .IDX_BITS(IDX_BITS),
        .INIT    (2'b01)
    ) dut (
        .clk     (clk),
        .rst     (rst),
        .rd_idx  (rd_idx),
        .rd_state(rd_state),
        .wr_en   (wr_en),
        .wr_idx  (wr_idx),
        .wr_state(wr_state)
    );

    // 10 ns clock (rising edges at 5, 15, 25, ... ns)
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // Counts rising clock edges, used by test 5 to prove that no edge happened.
    integer posedges;
    initial posedges = 0;
    always @(posedge clk) posedges = posedges + 1;

    // ---------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------
    integer tests;
    integer errors;
    integer i;
    integer bad;
    integer edges_before;

    // Compare the current rd_state with an expected value.
    task check;
        input [8*40-1:0] what;
        input [1:0]      expected;
        begin
            tests = tests + 1;
            if (rd_state === expected)
                $display("PASS  %0s : idx=%0d read=%b", what, rd_idx, rd_state);
            else begin
                errors = errors + 1;
                $display("FAIL  %0s : idx=%0d read=%b (expected %b)", what, rd_idx, rd_state, expected);
            end
        end
    endtask

    // Read all entries and check that every one equals `expected` (one result line).
    task check_all;
        input [8*40-1:0] what;
        input [1:0]      expected;
        begin
            tests = tests + 1;
            bad   = 0;
            for (i = 0; i < ENTRIES; i = i + 1) begin
                rd_idx = i[IDX_BITS-1:0];
                #1;
                if (rd_state !== expected) begin
                    bad = bad + 1;
                    $display("      entry %0d reads %b (expected %b)", i, rd_state, expected);
                end
            end
            if (bad == 0)
                $display("PASS  %0s : all %0d entries read %b", what, ENTRIES, expected);
            else begin
                errors = errors + 1;
                $display("FAIL  %0s : %0d of %0d entries wrong", what, bad, ENTRIES);
            end
        end
    endtask

    // Present a write just after a falling edge; it is stored at the next rising edge.
    task write_entry;
        input                enable;
        input [IDX_BITS-1:0] idx;
        input [1:0]          value;
        begin
            @(negedge clk);
            wr_en    = enable;
            wr_idx   = idx;
            wr_state = value;
            @(negedge clk);                // rising edge in between performs the write
            wr_en    = 1'b0;
        end
    endtask

    // Hold reset high for one rising edge.
    task do_reset;
        begin
            @(negedge clk);
            rst = 1'b1;
            @(negedge clk);
            rst = 1'b0;
        end
    endtask

    // ---------------------------------------------------------------------
    // Test sequence
    // ---------------------------------------------------------------------
    initial begin
        $dumpfile("build/tb_bht.vcd");
        $dumpvars(0, tb_bht);

        tests    = 0;
        errors   = 0;
        rst      = 1'b0;
        rd_idx   = 0;
        wr_en    = 1'b0;
        wr_idx   = 0;
        wr_state = 2'b00;

        // Test 1: reset -> every entry is WNT (01)
        do_reset;
        check_all("T1 after reset", 2'b01);

        // Test 2: write 11 to entry 3, neighbours untouched
        write_entry(1'b1, 4'd3, 2'b11);
        rd_idx = 4'd3; #1; check("T2 write 11 to idx 3, read back", 2'b11);
        rd_idx = 4'd2; #1; check("T2 idx 2 unchanged",               2'b01);
        rd_idx = 4'd4; #1; check("T2 idx 4 unchanged",               2'b01);

        // Test 3: wr_en = 0 must not write
        write_entry(1'b0, 4'd5, 2'b10);
        rd_idx = 4'd5; #1; check("T3 wr_en=0, idx 5 not written",   2'b01);
        write_entry(1'b0, 4'd3, 2'b00);
        rd_idx = 4'd3; #1; check("T3 wr_en=0, idx 3 keeps 11",      2'b11);

        // Test 4: a second reset clears the written entry back to 01
        do_reset;
        check_all("T4 second reset", 2'b01);

        // Test 5: combinational read. Store different values in 3 entries,
        // then change rd_idx several times inside ONE half clock period.
        write_entry(1'b1, 4'd7,  2'b10);
        write_entry(1'b1, 4'd8,  2'b00);
        write_entry(1'b1, 4'd15, 2'b11);
        @(negedge clk);
        edges_before = posedges;
        rd_idx = 4'd7;  #1; check("T5 async read idx 7",  2'b10);
        rd_idx = 4'd8;  #1; check("T5 async read idx 8",  2'b00);
        rd_idx = 4'd15; #1; check("T5 async read idx 15", 2'b11);
        rd_idx = 4'd0;  #1; check("T5 async read idx 0",  2'b01);
        tests = tests + 1;
        if (posedges == edges_before)
            $display("PASS  T5 no clock edge during the 4 reads (read is combinational)");
        else begin
            errors = errors + 1;
            $display("FAIL  T5 a clock edge happened during the reads");
        end

        if (errors == 0)
            $display("ALL BHT TESTS PASSED (%0d checks)", tests);
        else
            $display("BHT TESTS FAILED: %0d of %0d", errors, tests);
        $finish;
    end

endmodule
