#!/usr/bin/env python3
"""
File    : iss.py
Author  : Yashvi
Project : Dynamic Branch Prediction Unit (MCA Project 5) - Phase 2

Purpose : Instruction-set simulator (golden reference) for the programs run on
          the pipeline. For each programs/<name>.mem it:
            1. executes the program one instruction at a time (no pipeline),
            2. records the dynamic branch stream (PC, taken) of every
               conditional branch,
            3. runs the Phase 1 reference predictor model on that stream for
               modes 0-3 and two table sizes, IDX_BITS = 4 (16 entries) and
               IDX_BITS = 8 (256 entries) (ideal: each branch is updated
               before the next one is predicted),
          and writes
            programs/<name>_branches.mem  branch stream in the Phase 1 trace
                                          format (runs on branch_predictor_top)
            programs/expected_programs.csv
              program,idx_bits,mode,instret,branches,taken,x10,ideal_mispredicts

          The pipeline must retire exactly `instret` instructions, resolve
          exactly `branches` branches and end with the same x10. Its
          mispredictions can differ from `ideal_mispredicts` because the real
          pipeline updates the predictor late (in EX) and needs a BTB hit to
          redirect fetch.

Usage (from the repo root, after scripts/asm.py):  python3 scripts/iss.py
"""
import glob
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gen_traces import simulate_reference_model, write_mem_file  # noqa: E402

MAX_STEPS = 100000
IDX_BITS_LIST = (4, 8)   # 16-entry and 256-entry tables
MASK = 0xFFFFFFFF


def sx(v, bits):
    v &= (1 << bits) - 1
    return v - (1 << bits) if v >> (bits - 1) else v


def signed(v):
    return sx(v, 32)


def load_mem(path):
    words = []
    with open(path) as f:
        for line in f:
            line = line.split("//")[0].strip()
            if line:
                words.append(int(line, 16))
    return words


def run(words):
    """Execute until EBREAK. Returns (instret, branch_stream, regs)."""
    x = [0] * 32
    pc, instret, stream = 0, 0, []
    for _ in range(MAX_STEPS):
        ins = words[pc >> 2] if (pc >> 2) < len(words) else 0
        instret += 1
        if ins == 0x00100073:                       # EBREAK
            return instret, stream, x
        op, rd = ins & 0x7F, (ins >> 7) & 0x1F
        f3, rs1, rs2, f7 = (ins >> 12) & 7, (ins >> 15) & 0x1F, (ins >> 20) & 0x1F, ins >> 25
        a, b = x[rs1], x[rs2]
        nxt = (pc + 4) & MASK
        if op in (0b0110011, 0b0010011):            # R-type / I-type ALU
            if op == 0b0010011:
                b = sx(ins >> 20, 12) & MASK
            if f3 == 0b000:
                r = (a - b) if (op == 0b0110011 and f7 == 0b0100000) else (a + b)
            elif f3 == 0b111:
                r = a & b
            elif f3 == 0b110:
                r = a | b
            elif f3 == 0b100:
                r = a ^ b
            elif f3 == 0b010:
                r = 1 if signed(a) < signed(b) else 0
            else:
                r = 0
            if rd:
                x[rd] = r & MASK
        elif op == 0b1100011:                       # branches
            imm = sx(((ins >> 31) << 12) | (((ins >> 7) & 1) << 11) |
                     (((ins >> 25) & 0x3F) << 5) | (((ins >> 8) & 0xF) << 1), 13)
            taken = {0b000: a == b, 0b001: a != b,
                     0b100: signed(a) < signed(b), 0b101: signed(a) >= signed(b)}.get(f3, False)
            stream.append((pc, 1 if taken else 0))
            if taken:
                nxt = (pc + imm) & MASK
        # anything else = NOP (same as rtl/cpu/decoder.v)
        pc = nxt
    raise SystemExit("program did not reach EBREAK")


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    progs = sorted(p for p in glob.glob(os.path.join(root, "programs", "*.mem"))
                   if not p.endswith("_branches.mem"))
    rows = []
    for path in progs:
        name = os.path.splitext(os.path.basename(path))[0]
        instret, stream, regs = run(load_mem(path))
        taken = sum(t for _, t in stream)
        write_mem_file(os.path.join(root, "programs", f"{name}_branches.mem"),
                       f"Branch stream of programs/{name}.s ({len(stream)} branches), from scripts/iss.py",
                       stream)
        for idx_bits in IDX_BITS_LIST:
            for mode in range(4):
                _, mis, _ = simulate_reference_model(stream, mode, idx_bits)
                rows.append((name, idx_bits, mode, instret, len(stream), taken, regs[10], mis))

    out = os.path.join(root, "programs", "expected_programs.csv")
    with open(out, "w") as f:
        f.write("program,idx_bits,mode,instret,branches,taken,x10,ideal_mispredicts\n")
        for r in rows:
            f.write(",".join(str(v) for v in r) + "\n")

    print(f"{'program':<12} {'idx':>3} {'mode':>4} {'instret':>8} {'branches':>9} {'taken':>6} {'x10':>6} {'ideal_mis':>10}")
    for r in rows:
        print(f"{r[0]:<12} {r[1]:>3} {r[2]:>4} {r[3]:>8} {r[4]:>9} {r[5]:>6} {r[6]:>6} {r[7]:>10}")
    print(f"\nWritten: {os.path.relpath(out, root)} and programs/*_branches.mem")


if __name__ == "__main__":
    main()
