#!/usr/bin/env python3
"""
cpi_calc.py - CPI impact of the branch predictors.
Author : Aradhya Tiwari
Project: Dynamic Branch Prediction Unit (MCA Project 5)

Reads the simulation results (results/accuracy.csv) and estimates the CPI of a
5-stage pipeline for every trace and predictor mode:

    CPI = CPI_BASE + BRANCH_FREQ * mispredict_rate * PENALTY

Writes results/cpi.csv and prints a Markdown table for the README / report.

Phase 2: also reads the 5-stage pipeline results (results/pipeline.csv), where
the CPI is MEASURED (cycles / retired instructions), and compares it with the
same formula using the measured branch frequency of each program:

    model CPI    = 1 + (branches / instret) * (mispredicts / branches) * PENALTY
    measured CPI = cycles / instret

The two differ only by the pipeline fill (4 cycles / instret), which checks
that the formula is right for this pipeline. Writes results/cpi_pipeline.csv.

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

MODE_NAMES = {0: "static", 1: "1-bit", 2: "2-bit", 3: "gshare"}

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
IN_FILE = os.path.join(ROOT, "results", "accuracy.csv")
OUT_FILE = os.path.join(ROOT, "results", "cpi.csv")
PIPE_IN = os.path.join(ROOT, "results", "pipeline.csv")
PIPE_OUT = os.path.join(ROOT, "results", "cpi_pipeline.csv")


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

    if os.path.exists(PIPE_IN):
        pipeline_cpi()


def pipeline_cpi():
    """Phase 2: measured CPI of the 5-stage pipeline vs the formula."""
    with open(PIPE_IN, newline="") as f:
        rows = list(csv.DictReader(f))

    static = {}
    for r in rows:
        if int(r["mode"]) == 0:
            static[(r["program"], r["idx_bits"])] = int(r["cycles"]) / int(r["instret"])

    out = []
    for r in rows:
        cycles, instret = int(r["cycles"]), int(r["instret"])
        branches, mis = int(r["branches"]), int(r["mispredicts"])
        measured = cycles / instret
        model = CPI_BASE + (branches / instret) * (mis / branches) * PENALTY
        out.append({
            "program": r["program"], "idx_bits": int(r["idx_bits"]), "mode": int(r["mode"]),
            "branch_freq": branches / instret, "accuracy": 100.0 * (branches - mis) / branches,
            "model": model, "measured": measured,
            "speedup": static[(r["program"], r["idx_bits"])] / measured,
        })

    with open(PIPE_OUT, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["program", "idx_bits", "mode", "branch_freq", "accuracy",
                    "cpi_model", "cpi_measured", "speedup_vs_static"])
        for o in out:
            w.writerow([o["program"], o["idx_bits"], o["mode"], f"{o['branch_freq']:.3f}",
                        f"{o['accuracy']:.2f}", f"{o['model']:.3f}", f"{o['measured']:.3f}",
                        f"{o['speedup']:.3f}"])

    print("\nPhase 2: 5-stage pipeline, measured CPI = cycles / instret\n")
    print("| Program | Entries | Predictor | Branch freq | Accuracy | CPI (model) | CPI (measured) | Speed-up vs static |")
    print("|---|---|---|---|---|---|---|---|")
    for o in out:
        print(f"| {o['program']} | {1 << o['idx_bits']} | {MODE_NAMES[o['mode']]} | "
              f"{o['branch_freq']:.3f} | {o['accuracy']:.1f}% | {o['model']:.3f} | "
              f"{o['measured']:.3f} | {o['speedup']:.3f}x |")
    print(f"\nWritten: {os.path.relpath(PIPE_OUT, ROOT)}")


if __name__ == "__main__":
    main()
