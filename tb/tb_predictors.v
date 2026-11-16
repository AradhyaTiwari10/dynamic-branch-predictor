`timescale 1ns/1ps
//------------------------------------------------------------------------------
// File    : tb_predictors.v
// Module  : tb_predictors
// Author  : Anuj
// Project : Dynamic Branch Prediction Unit (MCA Project 5)
//
// Purpose : Directed unit tests for the three predictor modules
//           (pred_static, pred_1bit, pred_2bit).
//
//           Every predictor is purely combinational: (state, taken) in,
//           (predict_taken, next_state) out. So the test is exhaustive:
//           all 4 states x 2 outcomes = 8 cases per predictor, 24 in total.
//           The expected values are written by hand below from the
//           specification (interface_spec section 1), NOT computed from the
//           design, so a wrong RTL table is caught.
//
//           Prints one PASS/FAIL line per case and a final summary line:
//             ALL PREDICTOR TESTS PASSED          (all 24 cases correct)
//             PREDICTOR TESTS FAILED: <n> of 24   (otherwise)
//           Waveform: build/tb_predictors.vcd
//
// Run     : mkdir -p build && iverilog -g2012 -o build/tb_pred tb/tb_predictors.v \
//             rtl/pred_static.v rtl/pred_1bit.v rtl/pred_2bit.v && vvp build/tb_pred
//------------------------------------------------------------------------------
module tb_predictors;

    // ---------------------------------------------------------------------
    // Stimulus: the same state/taken drive all three predictors
    // ---------------------------------------------------------------------
    reg  [1:0] state;
    reg        taken;

    wire       static_pred, onebit_pred, twobit_pred;
    wire [1:0] static_next, onebit_next, twobit_next;

    pred_static u_static (
        .state        (state),
        .taken        (taken),
        .predict_taken(static_pred),
        .next_state   (static_next)
    );

    pred_1bit u_1bit (
        .state        (state),
        .taken        (taken),
        .predict_taken(onebit_pred),
        .next_state   (onebit_next)
    );

    pred_2bit u_2bit (
        .state        (state),
        .taken        (taken),
        .predict_taken(twobit_pred),
        .next_state   (twobit_next)
    );

    // ---------------------------------------------------------------------
    // Expected-value tables, indexed by {state, taken}.
    // Each function returns {expected predict_taken, expected next_state}.
    // ---------------------------------------------------------------------

    // Static always-not-taken: predict 0, state never changes.
    function [2:0] exp_static;
        input [2:0] st_tk;                 // {state, taken}
        begin
            case (st_tk)
                3'b00_0: exp_static = {1'b0, 2'b00};
                3'b00_1: exp_static = {1'b0, 2'b00};
                3'b01_0: exp_static = {1'b0, 2'b01};
                3'b01_1: exp_static = {1'b0, 2'b01};
                3'b10_0: exp_static = {1'b0, 2'b10};
                3'b10_1: exp_static = {1'b0, 2'b10};
                3'b11_0: exp_static = {1'b0, 2'b11};
                default: exp_static = {1'b0, 2'b11};   // 3'b11_1
            endcase
        end
    endfunction

    // 1-bit: predict state[1]; next state = 11 if taken, 00 if not taken.
    function [2:0] exp_1bit;
        input [2:0] st_tk;
        begin
            case (st_tk)
                3'b00_0: exp_1bit = {1'b0, 2'b00};
                3'b00_1: exp_1bit = {1'b0, 2'b11};
                3'b01_0: exp_1bit = {1'b0, 2'b00};
                3'b01_1: exp_1bit = {1'b0, 2'b11};
                3'b10_0: exp_1bit = {1'b1, 2'b00};
                3'b10_1: exp_1bit = {1'b1, 2'b11};
                3'b11_0: exp_1bit = {1'b1, 2'b00};
                default: exp_1bit = {1'b1, 2'b11};     // 3'b11_1
            endcase
        end
    endfunction

    // 2-bit saturating counter: predict state[1];
    // taken -> count up (stop at 11), not taken -> count down (stop at 00).
    function [2:0] exp_2bit;
        input [2:0] st_tk;
        begin
            case (st_tk)
                3'b00_0: exp_2bit = {1'b0, 2'b00};     // SNT --N--> SNT (saturate)
                3'b00_1: exp_2bit = {1'b0, 2'b01};     // SNT --T--> WNT
                3'b01_0: exp_2bit = {1'b0, 2'b00};     // WNT --N--> SNT
                3'b01_1: exp_2bit = {1'b0, 2'b10};     // WNT --T--> WT
                3'b10_0: exp_2bit = {1'b1, 2'b01};     // WT  --N--> WNT
                3'b10_1: exp_2bit = {1'b1, 2'b11};     // WT  --T--> ST
                3'b11_0: exp_2bit = {1'b1, 2'b10};     // ST  --N--> WT
                default: exp_2bit = {1'b1, 2'b11};     // ST  --T--> ST (saturate)
            endcase
        end
    endfunction

    // ---------------------------------------------------------------------
    // Checker: compares one predictor's outputs with the expected values
    // ---------------------------------------------------------------------
    integer tests;
    integer errors;

    task check;
        input [8*6-1:0] name;              // predictor name, 6 characters
        input           got_pred;
        input [1:0]     got_next;
        input [2:0]     expected;          // {predict, next_state}
        begin
            tests = tests + 1;
            if (got_pred === expected[2] && got_next === expected[1:0]) begin
                $display("PASS  %s  state=%b taken=%b  ->  predict=%b next=%b",
                         name, state, taken, got_pred, got_next);
            end else begin
                errors = errors + 1;
                $display("FAIL  %s  state=%b taken=%b  ->  predict=%b next=%b  (expected predict=%b next=%b)",
                         name, state, taken, got_pred, got_next, expected[2], expected[1:0]);
            end
        end
    endtask

    // ---------------------------------------------------------------------
    // Test sequence: walk through all 8 (state, taken) combinations
    // ---------------------------------------------------------------------
    integer s, t;

    initial begin
        $dumpfile("build/tb_predictors.vcd");
        $dumpvars(0, tb_predictors);

        tests  = 0;
        errors = 0;
        state  = 2'b00;
        taken  = 1'b0;

        for (s = 0; s < 4; s = s + 1) begin
            for (t = 0; t < 2; t = t + 1) begin
                state = s[1:0];
                taken = t[0];
                #10;                       // let the combinational logic settle
                check("static", static_pred, static_next, exp_static({state, taken}));
                check("1-bit ", onebit_pred, onebit_next, exp_1bit  ({state, taken}));
                check("2-bit ", twobit_pred, twobit_next, exp_2bit  ({state, taken}));
            end
        end

        if (errors == 0)
            $display("ALL PREDICTOR TESTS PASSED (%0d cases)", tests);
        else
            $display("PREDICTOR TESTS FAILED: %0d of %0d", errors, tests);
        $finish;
    end

endmodule
