#!/usr/bin/env python3
"""
File    : gen_traces.py
Author  : Yashvi
Project : Dynamic Branch Prediction Unit (MCA Project 5)

Purpose : Generates standard branch trace files (.mem) and computes the golden
          reference prediction accuracy using a software reference model.

Traces generated:
  1. loop.mem         : Simple single loop (PC 0x40), 20 runs of 10 iterations (9T, 1N).
  2. nested_loop.mem  : Nested loop with inner branch (PC 0x80) and outer branch (PC 0x90).
  3. alternating.mem  : Strictly alternating taken/not-taken pattern (PC 0x100).
  4. random.mem       : Biased pseudo-random branches (PC 0x200 @ 50%, PC 0x204 @ 90%, seed 42).

Outputs:
  - traces/*.mem               : Trace files read by Verilog $readmemh
  - traces/expected_accuracy.csv : Golden accuracy table for verification

Phase 2: the reference model also covers mode 3 (gshare): 4-bit global
history, index = pc[5:2] XOR history, 2-bit counters. simulate_reference_model()
can be imported by other scripts (scripts/iss.py uses it for program traces).
"""

import os
import random

def generate_loop_trace():
    """20 runs of a 10-iteration loop: 9 Taken, 1 Not-Taken at PC 0x40 = 200 branches."""
    trace = []
    pc = 0x40
    for _ in range(20):
        for _ in range(9):
            trace.append((pc, 1))
        trace.append((pc, 0))
    return trace

def generate_nested_loop_trace():
    """
    4 repeats of 10 outer iterations.
    Each outer iteration:
      - Inner loop PC 0x80: T, T, T, N (4 branches)
      - Outer loop PC 0x90: T for iterations 0-8, N for iteration 9 (1 branch)
    Total: 4 * 10 * 5 = 200 branches.
    """
    trace = []
    pc_inner = 0x80
    pc_outer = 0x90
    for _ in range(4):
        for outer_iter in range(10):
            # Inner loop: 3 Taken, 1 Not-Taken
            for _ in range(3):
                trace.append((pc_inner, 1))
            trace.append((pc_inner, 0))
            # Outer loop branch: Taken except on the final (10th) iteration
            outer_taken = 0 if outer_iter == 9 else 1
            trace.append((pc_outer, outer_taken))
    return trace

def generate_alternating_trace():
    """200 branches with strictly alternating outcomes: T, N, T, N... at PC 0x100."""
    trace = []
    pc = 0x100
    for i in range(200):
        taken = 1 if (i % 2 == 0) else 0
        trace.append((pc, taken))
    return trace

def generate_random_trace():
    """
    100 iterations of two interleaved branches with random.seed(42):
      - PC 0x200: Taken with probability 0.50
      - PC 0x204: Taken with probability 0.90
    Total: 200 branches.
    """
    random.seed(42)
    trace = []
    pc_a = 0x200
    pc_b = 0x204
    for _ in range(100):
        t_a = 1 if random.random() < 0.5 else 0
        trace.append((pc_a, t_a))
        t_b = 1 if random.random() < 0.9 else 0
        trace.append((pc_b, t_b))
    return trace

def simulate_reference_model(trace, mode, idx_bits=4):
    """
    Simulates the branch predictor reference model.
    Table: 2^idx_bits entries (default 16, IDX_BITS=4), initialized to 1 (2'b01 = Weakly Not-Taken).
    Indexing: idx = (pc >> 2) & (2^idx_bits - 1)
    Modes:
      0: Static always-not-taken (predict 0, no update)
      1: 1-bit predictor (predict state[1], next = 3 if taken else 0)
      2: 2-bit saturating counter (predict state[1], saturating inc/dec)
      3: gshare (2-bit counter, idx = ((pc >> 2) & mask) ^ ghr, idx_bits-bit history)
    """
    mask = (1 << idx_bits) - 1
    bht = [1] * (1 << idx_bits)
    ghr = 0
    mispredicts = 0
    total = len(trace)

    for pc, taken in trace:
        idx = (pc >> 2) & mask
        if mode == 3:
            idx ^= ghr
        state = bht[idx]

        if mode == 0:
            pred = 0
            next_state = state
        elif mode == 1:
            pred = state >> 1
            next_state = 3 if taken else 0
        elif mode in (2, 3):
            pred = state >> 1
            if taken:
                next_state = min(3, state + 1)
            else:
                next_state = max(0, state - 1)
        else:
            raise ValueError(f"Unknown mode: {mode}")

        if pred != taken:
            mispredicts += 1

        bht[idx] = next_state
        ghr = ((ghr << 1) | taken) & mask  # global history, newest outcome in bit 0

    accuracy = ((total - mispredicts) / total) * 100.0
    return total, mispredicts, accuracy

def write_mem_file(filename, comment, trace):
    """Writes a trace to a .mem file formatted for Verilog $readmemh."""
    with open(filename, "w") as f:
        f.write(f"// {comment}\n")
        for pc, taken in trace:
            val = (pc << 4) | (taken & 0xF)
            f.write(f"{val:09X}\n")
        # End marker
        f.write("FFFFFFFFF\n")

def main():
    traces_dir = os.path.join(os.path.dirname(__file__), "..", "traces")
    os.makedirs(traces_dir, exist_ok=True)

    trace_defs = [
        ("loop", "loop.mem", "Loop pattern: PC 0x40, 20 runs of 10 iterations (9T, 1N)", generate_loop_trace()),
        ("nested_loop", "nested_loop.mem", "Nested loop pattern: inner PC 0x80 (3T, 1N), outer PC 0x90", generate_nested_loop_trace()),
        ("alternating", "alternating.mem", "Alternating pattern: PC 0x100, T,N,T,N...", generate_alternating_trace()),
        ("random", "random.mem", "Random pattern: PC 0x200 (50%), PC 0x204 (90%), seed 42", generate_random_trace()),
    ]

    # Write trace .mem files
    for name, filename, comment, trace in trace_defs:
        filepath = os.path.join(traces_dir, filename)
        write_mem_file(filepath, comment, trace)

    # Compute reference model accuracy for modes 0, 1, 2, 3
    csv_rows = []
    csv_path = os.path.join(traces_dir, "expected_accuracy.csv")

    with open(csv_path, "w") as f:
        f.write("trace,mode,branches,mispredicts,accuracy\n")
        for name, _, _, trace in trace_defs:
            for mode in [0, 1, 2, 3]:
                branches, mispredicts, accuracy = simulate_reference_model(trace, mode)
                line = f"{name},{mode},{branches},{mispredicts},{accuracy:.2f}"
                f.write(line + "\n")
                csv_rows.append((name, mode, branches, mispredicts, f"{accuracy:.2f}"))

    # Print summary table
    print("=" * 60)
    print("Branch Predictor Reference Model Results")
    print("=" * 60)
    print(f"{'Trace':<15} {'Mode':<6} {'Branches':<10} {'Mispredicts':<13} {'Accuracy (%)':<12}")
    print("-" * 60)
    for name, mode, branches, mispredicts, acc in csv_rows:
        print(f"{name:<15} {mode:<6} {branches:<10} {mispredicts:<13} {acc:<12}")
    print("=" * 60)
    print(f"Generated trace files and {csv_path} successfully.")

if __name__ == "__main__":
    main()
