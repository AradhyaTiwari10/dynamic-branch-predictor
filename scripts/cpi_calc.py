#!/usr/bin/env python3
"""
cpi_calc.py - CPI impact of the branch predictors.
Author : Aradhya Tiwari
Project: Dynamic Branch Prediction Unit (MCA Project 5)

Reads the simulation results (results/accuracy.csv) and estimates the CPI of a
5-stage pipeline for every trace and predictor mode:

    CPI = CPI_BASE + BRANCH_FREQ * mispredict_rate * PENALTY

Writes results/cpi.csv and prints a Markdown table for the README / report.

Usage (from the repo root):  python3 scripts/cpi_calc.py
"""
import csv
import os

# Ideal pipeline: one instruction completes every cycle.
CPI_BASE = 1.0
# Fraction of instructions that are conditional branches (typical value 15-25%).
BRANCH_FREQ = 0.20
# Cycles lost per misprediction: branch resolved in EX -> 2 wrong-path instructions flushed.
PENALTY = 2

MODE_NAMES = {0: "static", 1: "1-bit", 2: "2-bit"}

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
IN_FILE = os.path.join(ROOT, "results", "accuracy.csv")
OUT_FILE = os.path.join(ROOT, "results", "cpi.csv")


def cpi(mispredict_rate):
    return CPI_BASE + BRANCH_FREQ * mispredict_rate * PENALTY


def main():
    with open(IN_FILE, newline="") as f:
        rows = list(csv.DictReader(f))

    # CPI of the static predictor for each trace, used as the baseline for speed-up.
    static_cpi = {}
    results = []
    for r in rows:
        branches = int(r["branches"])
        mispredicts = int(r["mispredicts"])
        mode = int(r["mode"])
        rate = mispredicts / branches
        c = cpi(rate)
        if mode == 0:
            static_cpi[r["trace"]] = c
        results.append({"trace": r["trace"], "mode": mode, "rate": rate, "cpi": c})

    with open(OUT_FILE, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["trace", "mode", "mispredict_rate", "cpi", "speedup_vs_static"])
        for r in results:
            speedup = static_cpi[r["trace"]] / r["cpi"]
            r["speedup"] = speedup
            w.writerow([r["trace"], r["mode"], f"{r['rate']:.4f}", f"{r['cpi']:.3f}", f"{speedup:.3f}"])

    print(f"CPI = {CPI_BASE} + {BRANCH_FREQ} x mispredict_rate x {PENALTY}\n")
    print("| Trace | Mode | Mispredict rate | CPI | Speed-up vs static |")
    print("|---|---|---|---|---|")
    for r in results:
        print(f"| {r['trace']} | {MODE_NAMES.get(r['mode'], r['mode'])} | "
              f"{r['rate'] * 100:.1f}% | {r['cpi']:.3f} | {r['speedup']:.3f}x |")
    print(f"\nWritten: {os.path.relpath(OUT_FILE, ROOT)}")


if __name__ == "__main__":
    main()
