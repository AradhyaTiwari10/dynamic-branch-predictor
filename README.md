# Dynamic Branch Prediction Unit (Verilog)

**Modern Computer Architecture — MCA Project 5**

Design and evaluation of a hardware branch-prediction unit that reduces control-hazard
penalties in a pipelined processor. Three strategies are implemented and compared on the
same branch traces:

1. **Static always-not-taken** (baseline)
2. **1-bit predictor** (last outcome)
3. **2-bit saturating counter**

## Team

| Member | Responsibility |
|---|---|
| Aradhya Tiwari | Project lead, integration (top module), pipeline flush interface, performance counters, CPI analysis, synthesis |
| Mouli | Core RTL — static, 1-bit and 2-bit predictor logic, predictor core |
| Yashvi | Core RTL — Branch History Table; branch trace generation and reference model |
| Anuj | Verification — unit and system testbenches, simulation runs, waveforms |
| Chaitanya | Documentation — IEEE report, diagrams, demo video |

## Architecture

```
                 ┌──────────────────── branch_predictor_top ────────────────────┐
 br_pc ─────────►│ idx = pc[5:2] ─► BHT (16 × 2-bit) ─► state ─► predictor_core  │──► predict_taken
 br_taken ──────►│                    ▲                          (mode 0/1/2)    │
 mode ──────────►│                    └──── next_state ◄─────────────┘          │
 br_valid ──────►│ mispredict = predict != taken ─► flush_ctrl ──────────────────│──► flush
                 │ perf_counter ×2 (branches, mispredicts)                       │──► counters
                 └───────────────────────────────────────────────────────────────┘
```

Full module contract: [docs/interface_spec.md](docs/interface_spec.md)

## Repository structure

```
rtl/        Synthesizable Verilog RTL
tb/         Testbenches (unit + system)
traces/     Branch traces (.mem) and expected results
scripts/    Trace generator, run scripts, CPI calculator
results/    Simulation results (CSV) and VCD waveforms
docs/       Interface spec, diagrams, waveforms, IEEE report
synth/      Synthesis scripts and reports
```

## How to run

> Requires Icarus Verilog and Python 3. (Run instructions will be finalised once the testbench lands.)

```bash
python3 scripts/gen_traces.py     # generate traces + expected results
bash scripts/run_all.sh           # run all traces x all modes, compare with expected
python3 scripts/cpi_calc.py       # compute CPI impact
```

## Status

- [x] Project structure and interface specification
- [ ] Predictor RTL (static, 1-bit, 2-bit)
- [ ] Branch History Table
- [ ] Top-level integration, counters, flush control
- [ ] Traces and reference model
- [ ] Testbenches and results
- [ ] IEEE report (Phase 1)
- [ ] Demo video (Phase 1)

## Phase 1 deliverables

- IEEE report: [Phase1_IEEE_Report.pdf](docs/report/Phase1_IEEE_Report.pdf) (source: [docs/report/](docs/report/))
- Prototype video: _link to be added_
