`timescale 1ns/1ps
`default_nettype none
//------------------------------------------------------------------------------
// File    : pipeline_cpu.v
// Module  : pipeline_cpu
// Author  : Aradhya Tiwari
// Project : Dynamic Branch Prediction Unit (MCA Project 5) - Phase 2
//
// Purpose : 5-stage in-order pipeline (IF, ID, EX, MEM, WB) for our RV32I
//           subset, with the branch prediction unit in the front end. Used to
//           MEASURE the CPI of each predictor on real programs instead of
//           estimating it from a formula.
//
//   IF : fetch imem[pc]; bp_unit predicts (direction + BTB target);
//        next pc = predicted target or pc + 4
//   ID : decoder + register file read
//   EX : ALU, branch_unit resolves the branch; compare the real next pc with
//        the predicted next pc -> on a mismatch: flush IF/ID and ID/EX
//        (2 wrong-path instructions, PENALTY = 2 cycles) and redirect pc;
//        bp_unit is updated here (delayed update)
//   MEM: no data memory in our subset, the result is passed on
//   WB : register file write; EBREAK here stops the CPU (halted = 1)
//
//   Data hazards: forwarding from EX/MEM and MEM/WB into EX, plus the
//   register file's write-through bypass. There are no loads, so no stalls.
//   Control hazards: handled only by prediction + flush.
//
//   Counters (stop when halted): cycles, retired instructions, resolved
//   branches, mispredictions, penalty cycles.  CPI = cycles / instret.
//   Instruction memory `imem` is loaded by the testbench with $readmemh.
//
// Ports   :
//   clk, rst          clock, synchronous active-high reset
//   mode              predictor: 0 static, 1 1-bit, 2 2-bit, 3 gshare
//   halted            1 after EBREAK has retired
//   flush             1 in a cycle where EX detects a misprediction
//   cycle_count       cycles from reset to halt (inclusive)
//   instret_count     retired instructions (including EBREAK)
//   branch_count      conditional branches resolved
//   mispredict_count  mispredictions (wrong direction or target)
//   penalty_cycles    cycles lost to flushes (mispredictions x PENALTY)
//   dbg_reg_addr/data read any register (for the testbench)
//------------------------------------------------------------------------------
module pipeline_cpu #(
    parameter IDX_BITS   = 4,     // predictor tables: 2^IDX_BITS entries
    parameter IMEM_WORDS = 256,   // instruction memory size (words)
    parameter PENALTY    = 2      // cycles lost per misprediction
) (
    input  wire        clk,
    input  wire        rst,
    input  wire [1:0]  mode,
    output reg         halted,
    output wire        flush,
    output wire [31:0] cycle_count,
    output wire [31:0] instret_count,
    output wire [31:0] branch_count,
    output wire [31:0] mispredict_count,
    output wire [31:0] penalty_cycles,
    input  wire [4:0]  dbg_reg_addr,
    output wire [31:0] dbg_reg_data
);

    localparam IMEM_AW = $clog2(IMEM_WORDS);

    reg [31:0] imem [0:IMEM_WORDS-1];

    // =========================================================================
    // Pipeline registers
    // =========================================================================
    // IF
    reg [31:0] pc_f;
    reg        stop_fetch;            // EBREAK passed ID: fetch nothing more
    // IF/ID
    reg                valid_d;
    reg [31:0]         pc_d, instr_d, pred_target_d;
    reg                pred_taken_d;
    reg [IDX_BITS-1:0] idx_d;
    // ID/EX
    reg                valid_e;
    reg [31:0]         pc_e, rv1_e, rv2_e, imm_e, pred_target_e;
    reg [4:0]          rs1_e, rs2_e, rd_e;
    reg [2:0]          alu_op_e, br_funct3_e;
    reg                alu_src_imm_e, reg_write_e, is_branch_e, is_halt_e, pred_taken_e;
    reg [IDX_BITS-1:0] idx_e;
    // EX/MEM
    reg        valid_m, reg_write_m, is_halt_m;
    reg [4:0]  rd_m;
    reg [31:0] res_m;
    // MEM/WB
    reg        valid_w, reg_write_w, is_halt_w;
    reg [4:0]  rd_w;
    reg [31:0] res_w;

    // =========================================================================
    // IF stage
    // =========================================================================
    wire [31:0]         instr_f = imem[pc_f[IMEM_AW+1:2]];
    wire                pred_taken_f;
    wire [31:0]         pred_target_f;
    wire [IDX_BITS-1:0] idx_f;
    wire [31:0]         next_pc_f = pred_taken_f ? pred_target_f : pc_f + 32'd4;

    // EX-stage signals used by the branch predictor update
    wire        ex_upd;
    wire        taken_e;
    wire [31:0] target_e;

    bp_unit #(
        .IDX_BITS (IDX_BITS)
    ) u_bp (
        .clk            (clk),
        .rst            (rst),
        .mode           (mode),
        .if_pc          (pc_f),
        .if_pred_taken  (pred_taken_f),
        .if_pred_target (pred_target_f),
        .if_idx         (idx_f),
        .ex_upd         (ex_upd),
        .ex_pc          (pc_e),
        .ex_idx         (idx_e),
        .ex_taken       (taken_e),
        .ex_target      (target_e)
    );

    // =========================================================================
    // ID stage
    // =========================================================================
    wire [4:0]  rs1_d, rs2_d, rd_d;
    wire [31:0] imm_d, rv1_d, rv2_d;
    wire [2:0]  alu_op_d, br_funct3_d;
    wire        alu_src_imm_d, reg_write_d, is_branch_d, is_halt_d;

    decoder u_dec (
        .instr       (instr_d),
        .rs1         (rs1_d),
        .rs2         (rs2_d),
        .rd          (rd_d),
        .imm         (imm_d),
        .alu_op      (alu_op_d),
        .alu_src_imm (alu_src_imm_d),
        .reg_write   (reg_write_d),
        .is_branch   (is_branch_d),
        .br_funct3   (br_funct3_d),
        .is_halt     (is_halt_d)
    );

    wire wb_we = valid_w & reg_write_w & ~halted;

    regfile u_rf (
        .clk      (clk),
        .rst      (rst),
        .ra1      (rs1_d),
        .ra2      (rs2_d),
        .rd1      (rv1_d),
        .rd2      (rv2_d),
        .we       (wb_we),
        .wa       (rd_w),
        .wd       (res_w),
        .dbg_addr (dbg_reg_addr),
        .dbg_data (dbg_reg_data)
    );

    // =========================================================================
    // EX stage
    // =========================================================================
    // Forwarding: newest value first (EX/MEM), then MEM/WB, then the register file.
    wire fwd_a_m = valid_m & reg_write_m & (rd_m != 5'd0) & (rd_m == rs1_e);
    wire fwd_a_w = valid_w & reg_write_w & (rd_w != 5'd0) & (rd_w == rs1_e);
    wire fwd_b_m = valid_m & reg_write_m & (rd_m != 5'd0) & (rd_m == rs2_e);
    wire fwd_b_w = valid_w & reg_write_w & (rd_w != 5'd0) & (rd_w == rs2_e);

    wire [31:0] op_a  = fwd_a_m ? res_m : fwd_a_w ? res_w : rv1_e;
    wire [31:0] op_b  = fwd_b_m ? res_m : fwd_b_w ? res_w : rv2_e;
    wire [31:0] alu_b = alu_src_imm_e ? imm_e : op_b;
    wire [31:0] alu_y;

    alu u_alu (
        .a      (op_a),
        .b      (alu_b),
        .alu_op (alu_op_e),
        .y      (alu_y)
    );

    branch_unit u_br (
        .is_branch (valid_e & is_branch_e),
        .br_funct3 (br_funct3_e),
        .a         (op_a),
        .b         (op_b),
        .pc        (pc_e),
        .imm       (imm_e),
        .taken     (taken_e),
        .target    (target_e)
    );

    // Real next pc vs the next pc that IF actually fetched.
    wire [31:0] pc_plus4_e  = pc_e + 32'd4;
    wire [31:0] actual_next = taken_e      ? target_e      : pc_plus4_e;
    wire [31:0] pred_next   = pred_taken_e ? pred_target_e : pc_plus4_e;
    wire        mispredict  = valid_e & ~halted & (actual_next != pred_next);

    assign ex_upd = valid_e & is_branch_e & ~halted;

    // =========================================================================
    // Sequential logic: pc and pipeline registers
    // =========================================================================
    wire halt_in_id = valid_d & is_halt_d;

    always @(posedge clk) begin
        if (rst) begin
            pc_f       <= 32'd0;
            stop_fetch <= 1'b0;
            valid_d    <= 1'b0;
            valid_e    <= 1'b0;
            valid_m    <= 1'b0;
            valid_w    <= 1'b0;
            halted     <= 1'b0;
        end else if (!halted) begin
            // ---- IF -> IF/ID ------------------------------------------------
            if (mispredict) begin
                pc_f    <= actual_next;          // redirect to the correct path
                valid_d <= 1'b0;                 // flush the instruction in IF
            end else if (stop_fetch || halt_in_id) begin
                valid_d <= 1'b0;                 // nothing after EBREAK
            end else begin
                pc_f          <= next_pc_f;
                valid_d       <= 1'b1;
                pc_d          <= pc_f;
                instr_d       <= instr_f;
                pred_taken_d  <= pred_taken_f;
                pred_target_d <= pred_target_f;
                idx_d         <= idx_f;
            end
            // EBREAK in ID is final unless an older branch in EX flushes it now
            if (halt_in_id && !mispredict)
                stop_fetch <= 1'b1;

            // ---- ID -> ID/EX ------------------------------------------------
            valid_e       <= valid_d & ~mispredict;   // flush the instruction in ID
            pc_e          <= pc_d;
            rs1_e         <= rs1_d;
            rs2_e         <= rs2_d;
            rd_e          <= rd_d;
            rv1_e         <= rv1_d;
            rv2_e         <= rv2_d;
            imm_e         <= imm_d;
            alu_op_e      <= alu_op_d;
            alu_src_imm_e <= alu_src_imm_d;
            reg_write_e   <= reg_write_d;
            is_branch_e   <= is_branch_d;
            br_funct3_e   <= br_funct3_d;
            is_halt_e     <= is_halt_d;
            pred_taken_e  <= pred_taken_d;
            pred_target_e <= pred_target_d;
            idx_e         <= idx_d;

            // ---- EX -> EX/MEM -----------------------------------------------
            valid_m     <= valid_e;
            reg_write_m <= reg_write_e;
            is_halt_m   <= is_halt_e;
            rd_m        <= rd_e;
            res_m       <= alu_y;

            // ---- MEM -> MEM/WB ----------------------------------------------
            valid_w     <= valid_m;
            reg_write_w <= reg_write_m;
            is_halt_w   <= is_halt_m;
            rd_w        <= rd_m;
            res_w       <= res_m;

            // ---- WB: EBREAK retires -> stop ---------------------------------
            if (valid_w && is_halt_w)
                halted <= 1'b1;
        end
    end

    // =========================================================================
    // Flush interface and performance counters (reused from Phase 1)
    // =========================================================================
    flush_ctrl #(
        .PENALTY (PENALTY)
    ) u_flush (
        .clk            (clk),
        .rst            (rst),
        .mispredict     (mispredict),
        .flush          (flush),
        .penalty_cycles (penalty_cycles)
    );

    perf_counter u_cnt_cycle (
        .clk (clk), .rst (rst), .inc (~halted), .count (cycle_count)
    );

    perf_counter u_cnt_instret (
        .clk (clk), .rst (rst), .inc (valid_w & ~halted), .count (instret_count)
    );

    perf_counter u_cnt_branch (
        .clk (clk), .rst (rst), .inc (ex_upd), .count (branch_count)
    );

    perf_counter u_cnt_mispred (
        .clk (clk), .rst (rst), .inc (mispredict), .count (mispredict_count)
    );

endmodule
`default_nettype wire
