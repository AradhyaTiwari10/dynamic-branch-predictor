`timescale 1ns/1ps
`default_nettype none
//------------------------------------------------------------------------------
// File    : bp_unit.v
// Module  : bp_unit
// Author  : Aradhya Tiwari
// Project : Dynamic Branch Prediction Unit (MCA Project 5) - Phase 2
//
// Purpose : Branch prediction unit as used inside the 5-stage pipeline.
//           Unlike the trace-driven top (one branch predicted AND updated in
//           the same cycle), the pipeline predicts and updates at different
//           times and for different branches:
//
//   IF stage (predict)                     EX stage (update, "delayed update")
//   ------------------                     -----------------------------------
//   if_pc -> u_idx -> BHT port 1 -> u_pred  ex_idx -> BHT port 2 -> u_upd
//   if_pc -> u_btb (hit, target)            u_upd next_state -> BHT write
//   if_pred_taken = direction & BTB hit     taken branch -> BTB write (pc, target)
//   if_idx is carried down the pipeline     outcome -> u_ghr shift
//   so EX updates the same entry
//
//   - The IF stage can only redirect fetch if it knows the target, so a
//     branch is predicted taken only when the direction predictor says taken
//     AND the BTB hits.
//   - The update for a branch happens when it reaches EX, two cycles after it
//     was predicted. A branch fetched in between still sees the old state.
//   - The global history (gshare, mode 3) is also updated in EX
//     (non-speculative history).
//
// Ports   :
//   clk, rst          clock, synchronous active-high reset
//   mode              0 static, 1 1-bit, 2 2-bit, 3 gshare
//   if_pc             PC being fetched
//   if_pred_taken     1 = fetch from if_pred_target next
//   if_pred_target    predicted target (from the BTB)
//   if_idx            BHT index used for this prediction (carried to EX)
//   ex_upd            1 = a conditional branch is resolved in EX this cycle
//   ex_pc             its PC
//   ex_idx            the BHT index it was predicted with (from IF)
//   ex_taken          its real outcome
//   ex_target         its real target
//------------------------------------------------------------------------------
module bp_unit #(
    parameter IDX_BITS = 4
) (
    input  wire                clk,
    input  wire                rst,
    input  wire [1:0]          mode,
    // predict (IF)
    input  wire [31:0]         if_pc,
    output wire                if_pred_taken,
    output wire [31:0]         if_pred_target,
    output wire [IDX_BITS-1:0] if_idx,
    // update (EX)
    input  wire                ex_upd,
    input  wire [31:0]         ex_pc,
    input  wire [IDX_BITS-1:0] ex_idx,
    input  wire                ex_taken,
    input  wire [31:0]         ex_target
);

    wire [IDX_BITS-1:0] history;
    wire [1:0]          if_state;      // BHT port 1: entry of the fetched branch
    wire [1:0]          ex_state;      // BHT port 2: entry of the resolved branch
    wire [1:0]          ex_next_state;
    wire                dir_taken;     // direction prediction
    wire                btb_hit;

    // Global history, updated with the outcome of each resolved branch.
    ghr #(
        .HIST_BITS (IDX_BITS)
    ) u_ghr (
        .clk     (clk),
        .rst     (rst),
        .upd_en  (ex_upd),
        .taken   (ex_taken),
        .history (history)
    );

    // Index of the fetched branch (gshare in mode 3).
    gshare_index #(
        .IDX_BITS (IDX_BITS)
    ) u_idx (
        .mode    (mode),
        .pc      (if_pc),
        .history (history),
        .idx     (if_idx)
    );

    // Pattern table: port 1 read by IF, port 2 read by EX, written by EX.
    bht #(
        .IDX_BITS (IDX_BITS),
        .INIT     (2'b01)
    ) u_bht (
        .clk       (clk),
        .rst       (rst),
        .rd_idx    (if_idx),
        .rd_state  (if_state),
        .rd2_idx   (ex_idx),
        .rd2_state (ex_state),
        .wr_en     (ex_upd),
        .wr_idx    (ex_idx),
        .wr_state  (ex_next_state)
    );

    // Prediction logic (IF). The outcome is not known yet, so taken = 0;
    // only predict_taken is used.
    predictor_core u_pred (
        .mode          (mode),
        .state         (if_state),
        .taken         (1'b0),
        .predict_taken (dir_taken),
        .next_state    ()
    );

    // Update logic (EX): next state of the resolved branch's entry.
    predictor_core u_upd (
        .mode          (mode),
        .state         (ex_state),
        .taken         (ex_taken),
        .predict_taken (),
        .next_state    (ex_next_state)
    );

    // Target prediction.
    btb #(
        .IDX_BITS (IDX_BITS)
    ) u_btb (
        .clk       (clk),
        .rst       (rst),
        .rd_pc     (if_pc),
        .hit       (btb_hit),
        .rd_target (if_pred_target),
        .wr_en     (ex_upd & ex_taken),
        .wr_pc     (ex_pc),
        .wr_target (ex_target)
    );

    assign if_pred_taken = dir_taken & btb_hit;

endmodule
`default_nettype wire
