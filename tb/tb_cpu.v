`timescale 1ns/1ps
//------------------------------------------------------------------------------
// File    : tb_cpu.v
// Module  : tb_cpu
// Author  : Anuj
// Project : Dynamic Branch Prediction Unit (MCA Project 5) - Phase 2
//
// Purpose : System testbench for the 5-stage pipeline (rtl/cpu/pipeline_cpu.v).
//           Loads a program (programs/*.mem) into instruction memory, runs it
//           until EBREAK retires, and prints one RESULT line with the measured
//           cycles, retired instructions, branches, mispredictions and CPI.
//
//           Self-checks (print "ERROR ..." if they fail):
//             1. the program halts before the timeout
//             2. penalty_cycles == 2 x mispredictions
//             3. cycles == instret + 4 + 2 x mispredictions
//                (4 = pipeline fill, 2 = flush penalty; there are no stalls)
//           run_all.sh additionally compares instret, branches and x10 with
//           the instruction-set simulator (programs/expected_programs.csv).
//
// Plusargs: +prog=<file>    program to run       (default programs/loop.mem)
//           +mode=<0..3>    0 static, 1 1-bit, 2 2-bit, 3 gshare (default 2)
//           +vcd=<file>     optional: dump a waveform
// Parameter: IDX_BITS (predictor table size), e.g. iverilog -Ptb_cpu.IDX_BITS=8
//
// Output  : RESULT prog=programs/loop.mem mode=2 idx_bits=4 cycles=.. instret=..
//                  branches=.. mispredicts=.. penalty=.. cpi=1.xxx x10=..
//
// Run     : mkdir -p build && iverilog -g2012 -o build/cpu tb/tb_cpu.v rtl/*.v rtl/cpu/*.v
//           vvp build/cpu +prog=programs/loop.mem +mode=2
//------------------------------------------------------------------------------
module tb_cpu;

    parameter IDX_BITS    = 4;
    localparam MAX_CYCLES = 200000;

    reg        clk = 1'b0;
    reg        rst = 1'b1;
    reg  [1:0] mode;
    wire       halted, flush;
    wire [31:0] cycles, instret, branches, mispredicts, penalty;
    wire [31:0] x10;

    pipeline_cpu #(
        .IDX_BITS (IDX_BITS)
    ) dut (
        .clk              (clk),
        .rst              (rst),
        .mode             (mode),
        .halted           (halted),
        .flush            (flush),
        .cycle_count      (cycles),
        .instret_count    (instret),
        .branch_count     (branches),
        .mispredict_count (mispredicts),
        .penalty_cycles   (penalty),
        .dbg_reg_addr     (5'd10),
        .dbg_reg_data     (x10)
    );

    always #5 clk = ~clk;   // 100 MHz simulation clock

    reg [8*256-1:0] prog_file, vcd_file;
    integer m, n, errors, cpi_x1000;

    initial begin
        errors = 0;
        if (!$value$plusargs("prog=%s", prog_file)) prog_file = "programs/loop.mem";
        if (!$value$plusargs("mode=%d", m)) m = 2;
        mode = m[1:0];
        if ($value$plusargs("vcd=%s", vcd_file)) begin
            $dumpfile(vcd_file);
            $dumpvars(1, tb_cpu);          // testbench signals
            $dumpvars(1, tb_cpu.dut);      // pipeline registers and control
            $dumpvars(1, tb_cpu.dut.u_bp); // predictor interface
        end

        // instructions not in the file read as 0 = NOP
        for (n = 0; n < 256; n = n + 1) dut.imem[n] = 32'd0;
        $readmemh(prog_file, dut.imem);

        repeat (2) @(posedge clk);
        rst = 1'b0;

        n = 0;
        while (!halted && n < MAX_CYCLES) begin
            @(posedge clk);
            n = n + 1;
        end
        #1;

        if (!halted) begin
            $display("ERROR timeout: program did not halt in %0d cycles", MAX_CYCLES);
            errors = errors + 1;
        end
        if (penalty != 2 * mispredicts) begin
            $display("ERROR penalty=%0d but 2 x mispredicts=%0d", penalty, 2 * mispredicts);
            errors = errors + 1;
        end
        if (cycles != instret + 4 + 2 * mispredicts) begin
            $display("ERROR cycles=%0d but instret + 4 + 2 x mispredicts = %0d",
                     cycles, instret + 4 + 2 * mispredicts);
            errors = errors + 1;
        end

        cpi_x1000 = (cycles * 1000 + instret / 2) / instret;
        $display("RESULT prog=%0s mode=%0d idx_bits=%0d cycles=%0d instret=%0d branches=%0d mispredicts=%0d penalty=%0d cpi=%0d.%03d x10=%0d",
                 prog_file, mode, IDX_BITS, cycles, instret, branches, mispredicts,
                 penalty, cpi_x1000 / 1000, cpi_x1000 % 1000, x10);
        $finish;
    end

endmodule
