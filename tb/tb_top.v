`timescale 1ns/1ps
//------------------------------------------------------------------------------
// File    : tb_top.v
// Module  : tb_top
// Author  : Anuj
// Project : Dynamic Branch Prediction Unit (MCA Project 5)
//
// Purpose : Trace-driven system testbench for branch_predictor_top.
//           Reads a branch trace (traces/*.mem), feeds one branch per clock
//           cycle to the predictor unit and reports how many branches were
//           mispredicted.
//
//           Trace line format (interface_spec section 4): 9 hex digits
//             {PC[31:0], 3'b000, taken}      last line FFFFFFFFF = end marker
//
// Plusargs: +trace=<file>   trace to run          (default traces/loop.mem)
//           +mode=<0|1|2>   0 static, 1 1-bit, 2 2-bit (default 2)
//           +vcd=<file>     optional: dump a waveform to this VCD file
//           +table          optional: also print the first 12 branches
//
// Output  : exactly one result line (interface_spec section 5), e.g.
//   RESULT trace=traces/loop.mem mode=2 branches=200 mispredicts=21 accuracy=89.50
//           Lines starting with "ERROR" mean a self-check failed.
//
// Run     : mkdir -p build && iverilog -g2012 -o build/sim tb/tb_top.v rtl/*.v
//           vvp build/sim +trace=traces/loop.mem +mode=2
//------------------------------------------------------------------------------
module tb_top;

    localparam [35:0] END_MARKER = 36'hFFFFFFFFF;
    localparam        MAX_LINES  = 4096;

    // ---------------------------------------------------------------------
    // DUT signals
    // ---------------------------------------------------------------------
    reg         clk;
    reg         rst;
    reg  [1:0]  mode;
    reg         br_valid;
    reg  [31:0] br_pc;
    reg         br_taken;
    wire        predict_taken;
    wire        mispredict;
    wire        flush;
    wire [31:0] branch_count;
    wire [31:0] mispredict_count;
    wire [31:0] penalty_cycles;

    branch_predictor_top #(
        .IDX_BITS(4),
        .PENALTY (2)
    ) dut (
        .clk             (clk),
        .rst             (rst),
        .mode            (mode),
        .br_valid        (br_valid),
        .br_pc           (br_pc),
        .br_taken        (br_taken),
        .predict_taken   (predict_taken),
        .mispredict      (mispredict),
        .flush           (flush),
        .branch_count    (branch_count),
        .mispredict_count(mispredict_count),
        .penalty_cycles  (penalty_cycles)
    );

    // 10 ns clock
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // ---------------------------------------------------------------------
    // Trace memory and run settings
    // ---------------------------------------------------------------------
    reg [35:0]      trace_mem [0:MAX_LINES-1];
    reg [8*256-1:0] trace_file;
    reg [8*256-1:0] vcd_file;
    integer         mode_arg;
    integer         show_table;

    integer i;
    integer tb_branches;       // branches counted by the testbench itself
    integer tb_mispredicts;    // mispredictions counted by the testbench itself
    integer acc_x100;          // accuracy x 100, e.g. 8950 means 89.50 %

    initial begin
        // ---- read the plusargs -------------------------------------------
        if (!$value$plusargs("trace=%s", trace_file))
            trace_file = "traces/loop.mem";
        if (!$value$plusargs("mode=%d", mode_arg))
            mode_arg = 2;
        show_table = $test$plusargs("table");

        if ($value$plusargs("vcd=%s", vcd_file)) begin
            $dumpfile(vcd_file);
            $dumpvars(0, dut);                      // every signal inside the predictor unit
            $dumpvars(0, dut.u_bht.table_mem[0]);   // memory words are not dumped by default:
            $dumpvars(0, dut.u_bht.table_mem[1]);   // entries 0, 1 and 4 hold the PCs of the
            $dumpvars(0, dut.u_bht.table_mem[4]);   // loop / nested_loop / random traces
        end

        // ---- load the trace ----------------------------------------------
        // Unused lines are pre-filled with the end marker. The trace has fewer
        // lines than trace_mem, so the simulator prints a harmless
        // "Not enough words in the file" warning here.
        for (i = 0; i < MAX_LINES; i = i + 1)
            trace_mem[i] = END_MARKER;
        $readmemh(trace_file, trace_mem);
        if (trace_mem[0] === END_MARKER) begin
            $display("ERROR: trace %0s is missing or empty", trace_file);
            $finish;
        end

        // ---- reset for 2 clock cycles ------------------------------------
        mode     = mode_arg[1:0];
        rst      = 1'b1;
        br_valid = 1'b0;
        br_pc    = 32'd0;
        br_taken = 1'b0;
        tb_branches    = 0;
        tb_mispredicts = 0;
        repeat (2) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        if (show_table) begin
            $display("first 12 branches (mode %0d):", mode);
            $display("   #  pc        state  taken  predict  mispredict");
        end

        // ---- feed one branch per clock -----------------------------------
        // Inputs change just after a falling edge, so they are stable at the
        // next rising edge, where the BHT entry and the counters are updated.
        i = 0;
        while (i < MAX_LINES && trace_mem[i] !== END_MARKER) begin
            br_valid = 1'b1;
            br_pc    = trace_mem[i][35:4];
            br_taken = trace_mem[i][0];
            #1;                                     // combinational outputs settle

            // Independent checks, done by the testbench itself:
            //  - the prediction is 0 in mode 0, and the MSB of the BHT entry
            //    in modes 1 and 2
            //  - mispredict is 1 exactly when prediction != actual outcome
            //  - the testbench keeps its own branch/mispredict counts, which
            //    are compared with the hardware counters at the end
            if (predict_taken !== ((mode == 2'd0) ? 1'b0 : dut.u_bht.rd_state[1]))
                $display("ERROR: branch %0d: predict=%b but BHT state=%b (mode %0d)",
                         i, predict_taken, dut.u_bht.rd_state, mode);
            if (mispredict !== (predict_taken !== br_taken))
                $display("ERROR: branch %0d: mispredict=%b but predict=%b taken=%b",
                         i, mispredict, predict_taken, br_taken);
            tb_branches = tb_branches + 1;
            if (predict_taken !== br_taken)
                tb_mispredicts = tb_mispredicts + 1;

            if (show_table && i < 12)
                $display("%4d  %h  %b     %b      %b        %b",
                         i, br_pc, dut.u_bht.rd_state, br_taken, predict_taken, mispredict);

            @(negedge clk);
            i = i + 1;
        end

        // ---- drain: no branch, let the last update finish ----------------
        br_valid = 1'b0;
        repeat (2) @(posedge clk);
        #1;

        // ---- self-checks: hardware counters vs testbench counts ----------
        if (branch_count !== tb_branches)
            $display("ERROR: branch_count=%0d but the trace has %0d branches",
                     branch_count, tb_branches);
        if (mispredict_count !== tb_mispredicts)
            $display("ERROR: mispredict_count=%0d but the testbench counted %0d",
                     mispredict_count, tb_mispredicts);
        if (penalty_cycles !== 2 * mispredict_count)
            $display("ERROR: penalty_cycles=%0d, expected 2 x %0d",
                     penalty_cycles, mispredict_count);

        // ---- result line -------------------------------------------------
        if (branch_count == 0)
            acc_x100 = 0;
        else
            acc_x100 = (branch_count - mispredict_count) * 10000 / branch_count;

        $display("RESULT trace=%0s mode=%0d branches=%0d mispredicts=%0d accuracy=%0d.%02d",
                 trace_file, mode, branch_count, mispredict_count,
                 acc_x100 / 100, acc_x100 % 100);
        $finish;
    end

endmodule
