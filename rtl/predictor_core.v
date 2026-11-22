`timescale 1ns/1ps
`default_nettype none
//------------------------------------------------------------------------------
// File    : predictor_core.v
// Module  : predictor_core
// Author  : Mouli
// Project : Dynamic Branch Prediction Unit (MCA Project 5)
//
// Purpose : Top-level combinational core that instantiates all three predictor
//           sub-modules and selects the active one via `mode`.
//
//           mode = 2'd0 : Static always-not-taken  (pred_static)
//           mode = 2'd1 : 1-bit last-outcome       (pred_1bit)
//           mode = 2'd2 : 2-bit saturating counter (pred_2bit)
//           mode = 2'd3 : gshare (Phase 2). Uses the same 2-bit saturating
//                         counter; only the BHT index is different
//                         (pc bits XOR global history, see gshare_index.v)
//
//           This module is PURELY COMBINATIONAL. All state storage lives in
//           the BHT (rtl/bht.v, owned by Yashvi). The BHT provides `state`
//           each cycle; predictor_core computes `predict_taken` and
//           `next_state`; the top module writes `next_state` back to the BHT
//           on the next posedge clk.
//
// Ports   :
//   mode           in  [1:0]  predictor mode selector
//   state          in  [1:0]  current 2-bit BHT entry for this PC
//   taken          in         actual branch outcome (from trace / EX stage)
//   predict_taken  out        prediction for the current branch
//   next_state     out  [1:0] BHT value to write back after resolution
//------------------------------------------------------------------------------
module predictor_core (
    input  wire [1:0] mode,
    input  wire [1:0] state,
    input  wire       taken,
    output wire       predict_taken,
    output wire [1:0] next_state
);

    // -----------------------------------------------------------------------
    // Instantiate all three sub-predictors (always active, all combinational)
    // -----------------------------------------------------------------------
    wire       pt_static,  pt_1bit,  pt_2bit;
    wire [1:0] ns_static, ns_1bit, ns_2bit;

    pred_static u_static (
        .state        (state),
        .taken        (taken),
        .predict_taken(pt_static),
        .next_state   (ns_static)
    );

    pred_1bit u_1bit (
        .state        (state),
        .taken        (taken),
        .predict_taken(pt_1bit),
        .next_state   (ns_1bit)
    );

    pred_2bit u_2bit (
        .state        (state),
        .taken        (taken),
        .predict_taken(pt_2bit),
        .next_state   (ns_2bit)
    );

    // -----------------------------------------------------------------------
    // Mux: select outputs from the active predictor based on mode
    // mode 2'd3 is reserved but treated identically to mode 2'd2 (spec §1)
    // -----------------------------------------------------------------------
    reg       pt_sel;
    reg [1:0] ns_sel;

    always @(*) begin
        case (mode)
            2'd0:    begin pt_sel = pt_static; ns_sel = ns_static; end
            2'd1:    begin pt_sel = pt_1bit;   ns_sel = ns_1bit;   end
            2'd2:    begin pt_sel = pt_2bit;   ns_sel = ns_2bit;   end
            2'd3:    begin pt_sel = pt_2bit;   ns_sel = ns_2bit;   end  // gshare: 2-bit counter, gshare index
            default: begin pt_sel = pt_static; ns_sel = ns_static; end
        endcase
    end

    assign predict_taken = pt_sel;
    assign next_state    = ns_sel;

endmodule
`default_nettype wire
