`timescale 1ns/1ps
`default_nettype none
//------------------------------------------------------------------------------
// File    : branch_predictor_top.v
// Module  : branch_predictor_top
// Author  : Aradhya Tiwari
// Project : Dynamic Branch Prediction Unit (MCA Project 5)
//
// Purpose : Top-level integration of the branch prediction unit.
//
//   br_pc --> u_idx: idx = br_pc[IDX_BITS+1:2]  (mode 3: XOR u_ghr history)
//                 --> u_bht (2-bit state per entry)
//                                              |
//                                            state
//                                              v
//   mode, br_taken ---------------------> u_core (static / 1-bit / 2-bit)
//                                          |            |
//                                    predict_taken   next_state --> written back to u_bht
//                                          |
//   mispredict = predict != actual --> u_flush (flush, penalty cycles)
//   u_cnt_branch / u_cnt_mispred count branches and mispredictions
//   u_ghr shifts in every branch outcome (global history for gshare)
//
// Timing (Phase 1, trace-driven): one branch per clock. The prediction and the
// mispredict signal are combinational in the same cycle; the BHT entry and the
// counters are updated on the next rising clock edge.
//
// Ports   :
//   clk, rst          clock, synchronous active-high reset
//   mode              0 = static not-taken, 1 = 1-bit, 2 = 2-bit, 3 = gshare
//   br_valid          a branch is presented this cycle
//   br_pc             PC of the branch
//   br_taken          actual outcome of the branch (from the trace)
//   predict_taken     predicted direction
//   mispredict        prediction was wrong
//   flush             flush request to the pipeline
//   branch_count      total branches seen
//   mispredict_count  total mispredictions
//   penalty_cycles    total cycles lost (mispredictions x PENALTY)
//------------------------------------------------------------------------------
module branch_predictor_top #(
    parameter IDX_BITS = 4,     // BHT has 2^IDX_BITS entries (16)
    parameter PENALTY  = 2      // cycles lost per misprediction
) (
    input  wire        clk,
    input  wire        rst,
    input  wire [1:0]  mode,
    input  wire        br_valid,
    input  wire [31:0] br_pc,
    input  wire        br_taken,
    output wire        predict_taken,
    output wire        mispredict,
    output wire        flush,
    output wire [31:0] branch_count,
    output wire [31:0] mispredict_count,
    output wire [31:0] penalty_cycles
);

    // Global history (Phase 2): outcome of every branch, newest in bit 0.
    wire [IDX_BITS-1:0] history;

    ghr #(
        .HIST_BITS (IDX_BITS)
    ) u_ghr (
        .clk     (clk),
        .rst     (rst),
        .upd_en  (br_valid),
        .taken   (br_taken),
        .history (history)
    );

    // BHT index: pc[IDX_BITS+1:2] (pc[1:0] skipped, word aligned);
    // in mode 3 (gshare) XOR-ed with the global history.
    wire [IDX_BITS-1:0] idx;

    gshare_index #(
        .IDX_BITS (IDX_BITS)
    ) u_idx (
        .mode    (mode),
        .pc      (br_pc),
        .history (history),
        .idx     (idx)
    );

    wire [1:0] bht_state;       // state read from the BHT for this branch
    wire [1:0] core_next_state; // updated state to write back
    wire       core_predict;    // raw prediction from the selected predictor

    // Branch History Table: combinational read, write on clock edge.
    bht #(
        .IDX_BITS (IDX_BITS),
        .INIT     (2'b01)        // all entries start as Weakly Not-Taken
    ) u_bht (
        .clk      (clk),
        .rst      (rst),
        .rd_idx   (idx),
        .rd_state (bht_state),
        .rd2_idx  ({IDX_BITS{1'b0}}),  // second read port only used by the pipeline
        .rd2_state(),
        .wr_en    (br_valid),
        .wr_idx   (idx),
        .wr_state (core_next_state)
    );

    // Prediction + update logic for the selected mode.
    predictor_core u_core (
        .mode          (mode),
        .state         (bht_state),
        .taken         (br_taken),
        .predict_taken (core_predict),
        .next_state    (core_next_state)
    );

    // Outputs are only meaningful when a branch is present.
    assign predict_taken = br_valid & core_predict;
    assign mispredict    = br_valid & (core_predict != br_taken);

    // Pipeline flush interface and penalty accounting.
    flush_ctrl #(
        .PENALTY (PENALTY)
    ) u_flush (
        .clk            (clk),
        .rst            (rst),
        .mispredict     (mispredict),
        .flush          (flush),
        .penalty_cycles (penalty_cycles)
    );

    // Performance counters.
    perf_counter u_cnt_branch (
        .clk   (clk),
        .rst   (rst),
        .inc   (br_valid),
        .count (branch_count)
    );

    perf_counter u_cnt_mispred (
        .clk   (clk),
        .rst   (rst),
        .inc   (mispredict),
        .count (mispredict_count)
    );

endmodule
`default_nettype wire
