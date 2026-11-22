#!/usr/bin/env python3
"""
File    : asm.py
Author  : Yashvi
Project : Dynamic Branch Prediction Unit (MCA Project 5) - Phase 2

Purpose : Small two-pass assembler for the RV32I subset run by the pipeline
          (rtl/cpu/pipeline_cpu.v). Converts programs/*.s into programs/*.mem
          (one 32-bit instruction per line, hex) for Verilog $readmemh.

Supported instructions
  R-type : add, sub, and, or, xor, slt          rd, rs1, rs2
  I-type : addi, andi, ori, xori, slti          rd, rs1, imm   (-2048..2047)
  Branch : beq, bne, blt, bge                   rs1, rs2, label
  System : ebreak                               (stops the simulation)
  Pseudo : nop  (= addi x0, x0, 0)
           li rd, imm  (= addi rd, x0, imm)
           mv rd, rs   (= addi rd, rs, 0)
Registers are written x0 .. x31. Comments start with '#'. Labels end with ':'.
Code starts at address 0x00000000, 4 bytes per instruction.

Usage (from the repo root):
  python3 scripts/asm.py                 # assemble every programs/*.s
  python3 scripts/asm.py programs/loop.s # assemble one file
"""
import glob
import os
import sys

R_OPS = {  # name: (funct7, funct3)
    "add": (0b0000000, 0b000), "sub": (0b0100000, 0b000),
    "and": (0b0000000, 0b111), "or":  (0b0000000, 0b110),
    "xor": (0b0000000, 0b100), "slt": (0b0000000, 0b010),
}
I_OPS = {"addi": 0b000, "andi": 0b111, "ori": 0b110, "xori": 0b100, "slti": 0b010}
B_OPS = {"beq": 0b000, "bne": 0b001, "blt": 0b100, "bge": 0b101}
EBREAK = 0x00100073


class AsmError(Exception):
    pass


def reg(tok):
    tok = tok.strip()
    if not tok.startswith("x") or not tok[1:].isdigit() or not 0 <= int(tok[1:]) <= 31:
        raise AsmError(f"bad register '{tok}'")
    return int(tok[1:])


def imm_val(tok, lo, hi):
    v = int(tok.strip(), 0)
    if not lo <= v <= hi:
        raise AsmError(f"immediate {v} out of range [{lo}, {hi}]")
    return v


def enc_r(f7, rs2, rs1, f3, rd):
    return (f7 << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | 0b0110011


def enc_i(imm, rs1, f3, rd):
    return ((imm & 0xFFF) << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | 0b0010011


def enc_b(off, rs2, rs1, f3):
    o = off & 0x1FFF
    return (((o >> 12) & 1) << 31) | (((o >> 5) & 0x3F) << 25) | (rs2 << 20) | (rs1 << 15) | \
           (f3 << 12) | (((o >> 1) & 0xF) << 8) | (((o >> 11) & 1) << 7) | 0b1100011


def parse(lines):
    """Pass 1: strip comments, collect labels -> address, list of (addr, mnemonic, args, lineno)."""
    labels, insts, addr = {}, [], 0
    for n, raw in enumerate(lines, 1):
        line = raw.split("#")[0].strip()
        while ":" in line:
            lab, line = line.split(":", 1)
            lab = lab.strip()
            if lab in labels:
                raise AsmError(f"line {n}: duplicate label '{lab}'")
            labels[lab] = addr
            line = line.strip()
        if not line:
            continue
        parts = line.split(None, 1)
        mnem = parts[0].lower()
        args = [a.strip() for a in parts[1].split(",")] if len(parts) > 1 else []
        insts.append((addr, mnem, args, n))
        addr += 4
    return labels, insts


def encode(addr, mnem, args, labels):
    if mnem == "nop":
        return enc_i(0, 0, 0, 0)
    if mnem == "li":
        return enc_i(imm_val(args[1], -2048, 2047), 0, 0, reg(args[0]))
    if mnem == "mv":
        return enc_i(0, reg(args[1]), 0, reg(args[0]))
    if mnem == "ebreak":
        return EBREAK
    if mnem in R_OPS:
        f7, f3 = R_OPS[mnem]
        return enc_r(f7, reg(args[2]), reg(args[1]), f3, reg(args[0]))
    if mnem in I_OPS:
        return enc_i(imm_val(args[2], -2048, 2047), reg(args[1]), I_OPS[mnem], reg(args[0]))
    if mnem in B_OPS:
        if args[2] not in labels:
            raise AsmError(f"unknown label '{args[2]}'")
        off = labels[args[2]] - addr
        if not -4096 <= off <= 4094:
            raise AsmError(f"branch offset {off} out of range")
        return enc_b(off, reg(args[1]), reg(args[0]), B_OPS[mnem])
    raise AsmError(f"unknown instruction '{mnem}'")


def assemble(path):
    with open(path) as f:
        labels, insts = parse(f.readlines())
    words = []
    for addr, mnem, args, n in insts:
        try:
            words.append(encode(addr, mnem, args, labels))
        except (AsmError, IndexError, ValueError) as e:
            raise SystemExit(f"{path}:{n}: {e}")
    return words


def write_mem(words, out_path, src_name):
    with open(out_path, "w") as f:
        f.write(f"// {src_name}: {len(words)} instructions, assembled by scripts/asm.py\n")
        for w in words:
            f.write(f"{w:08X}\n")


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    files = sys.argv[1:] or sorted(glob.glob(os.path.join(root, "programs", "*.s")))
    for src in files:
        words = assemble(src)
        out = os.path.splitext(src)[0] + ".mem"
        write_mem(words, out, os.path.basename(src))
        print(f"{os.path.relpath(src, root):28s} -> {os.path.relpath(out, root)} ({len(words)} instructions)")


if __name__ == "__main__":
    main()
