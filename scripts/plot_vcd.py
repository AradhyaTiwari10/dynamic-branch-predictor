#!/usr/bin/env python3
"""
File    : plot_vcd.py
Author  : Anuj
Project : Dynamic Branch Prediction Unit (MCA Project 5) - Phase 2

Purpose : Draws a waveform figure (PNG) from a VCD file, for the report.
          Default: results/cpu_loop_mode2.vcd (pipeline, loop program, 2-bit)
          around the first exit of the inner loop: the branch at 0x20 is
          predicted taken, resolves not taken in EX, `flush` goes high, the two
          wrong-path instructions are squashed and fetch restarts at 0x24.
          (The branch's first flush is the cold start: BTB empty, counter 01.)

Usage   : python3 scripts/plot_vcd.py
          python3 scripts/plot_vcd.py <vcd> <out.png>
Needs   : matplotlib
"""
import os
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# (label, VCD signal path, width)
SIGNALS = [
    ("clk",          "tb_cpu.clk",              1),
    ("pc_f (IF)",    "tb_cpu.dut.pc_f",        32),
    ("pc_d (ID)",    "tb_cpu.dut.pc_d",        32),
    ("valid_d",      "tb_cpu.dut.valid_d",      1),
    ("pc_e (EX)",    "tb_cpu.dut.pc_e",        32),
    ("valid_e",      "tb_cpu.dut.valid_e",      1),
    ("pred_taken_e", "tb_cpu.dut.pred_taken_e", 1),
    ("taken_e",      "tb_cpu.dut.taken_e",      1),
    ("flush",        "tb_cpu.dut.flush",        1),
    ("mispredicts",  "tb_cpu.mispredicts",     32),
]
BRANCH_PC = 0x20     # inner-loop branch in programs/loop.s
EXIT_NUMBER = 2      # 2nd flush of this branch = first loop exit (1st = cold start)


def parse_vcd(path, wanted):
    """Return {path: [(time, value_int_or_None), ...]} for the wanted signal paths."""
    ids, scope, changes, t = {}, [], {}, 0
    with open(path) as f:
        in_defs = True
        for line in f:
            tok = line.split()
            if not tok:
                continue
            if in_defs:
                if tok[0] == "$scope":
                    scope.append(tok[2])
                elif tok[0] == "$upscope":
                    scope.pop()
                elif tok[0] == "$var":
                    full = ".".join(scope + [tok[4]])
                    if full in wanted:
                        ids.setdefault(tok[3], []).append(full)
                        changes[full] = []
                elif tok[0] == "$enddefinitions":
                    in_defs = False
                continue
            c = tok[0]
            if c[0] == "#":
                t = int(c[1:])
            elif c[0] in "01xzXZ" and len(tok) == 1:
                for p in ids.get(c[1:], []):
                    changes[p].append((t, int(c[0]) if c[0] in "01" else None))
            elif c[0] in "bB":
                bits = c[1:]
                val = None if any(ch in "xzXZ" for ch in bits) else int(bits, 2)
                for p in ids.get(tok[1], []):
                    changes[p].append((t, val))
    return changes


def value_at(ch, t):
    v = None
    for tt, vv in ch:
        if tt > t:
            break
        v = vv
    return v


def main():
    vcd = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "results", "cpu_loop_mode2.vcd")
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(ROOT, "docs", "waveforms", "cpu_loop_flush.png")
    ch = parse_vcd(vcd, {s[1] for s in SIGNALS})

    # find the EXIT_NUMBER-th flush while the branch is in EX
    flush_rises = [t for (t, v) in ch["tb_cpu.dut.flush"] if v == 1
                   and value_at(ch["tb_cpu.dut.pc_e"], t) == BRANCH_PC]
    t0 = flush_rises[EXIT_NUMBER - 1]
    period = 10000                          # 10 ns clock in ps (timescale 1ps)
    start, end = t0 - 4 * period, t0 + 5 * period

    fig, ax = plt.subplots(figsize=(12, 0.62 * len(SIGNALS) + 0.8), dpi=200)
    rowh = 1.0
    for i, (label, path, width) in enumerate(SIGNALS):
        y = (len(SIGNALS) - 1 - i) * rowh * 1.4
        pts = [(start, value_at(ch[path], start))] + \
              [(t, v) for (t, v) in ch[path] if start < t < end] + [(end, None)]
        ax.text(start - 0.02 * (end - start), y + 0.4, label, ha="right", va="center",
                fontsize=10, family="monospace")
        for (ta, va), (tb, _) in zip(pts[:-1], pts[1:]):
            if width == 1:
                lvl = y + (0.8 if va == 1 else 0.0)
                col = "#c2410c" if (label == "flush" and va == 1) else "#15803d"
                ax.plot([ta, tb], [lvl, lvl], color=col, lw=1.6)
                ax.plot([tb, tb], [y, y + 0.8], color="#15803d", lw=0.6, alpha=0.5)
            else:
                ax.plot([ta, tb], [y, y], color="#1d4ed8", lw=1.2)
                ax.plot([ta, tb], [y + 0.8, y + 0.8], color="#1d4ed8", lw=1.2)
                ax.plot([tb, tb], [y, y + 0.8], color="#1d4ed8", lw=1.0)
                if va is not None and tb - ta > period * 0.6:
                    txt = f"{va:x}" if label.startswith("pc") else str(va)
                    ax.text((ta + tb) / 2, y + 0.4, txt, ha="center", va="center", fontsize=9)
    ax.axvspan(t0, t0 + period, color="#fed7aa", alpha=0.45, lw=0)
    ax.set_xlim(start - 0.16 * (end - start), end)
    ax.set_ylim(-0.4, len(SIGNALS) * rowh * 1.4)
    ax.axis("off")
    ax.set_title("Pipeline, loop program, 2-bit predictor: misprediction at a loop exit "
                 "(branch 0x20 resolved in EX) -> flush, fetch restarts at 0x24",
                 fontsize=10)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    fig.savefig(out, bbox_inches="tight", facecolor="white")
    print(f"Written: {os.path.relpath(out, ROOT)}  (window {start/1000:.0f}-{end/1000:.0f} ns)")


if __name__ == "__main__":
    main()
