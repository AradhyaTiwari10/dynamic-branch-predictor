# Interface Specification — Dynamic Branch Prediction Unit (Phase 1)

This file is the **contract** between all modules. Every module MUST use exactly these
module names, file names, port names, widths and behaviours, so that the pieces written
by different team members compile together on the first try.

- Language: **Verilog-2005** (synthesizable RTL). Testbenches may use Verilog-2005 system tasks.
- Simulator: **Icarus Verilog** (`iverilog -g2012`). Waveforms: GTKWave or Surfer (VCD files).
- Clock: single clock `clk`, all state updates on `posedge clk`.
- Reset: `rst`, **active-high, synchronous**.
- Default parameters: `IDX_BITS = 4` (16-entry table).
- `timescale 1ns/1ps` at the top of every file.

---

## 1. Prediction modes

| `mode` | Strategy | Prediction | Next state stored in BHT |
|---|---|---|---|
| `2'd0` | Static always-not-taken (baseline) | always `0` | unchanged (`next_state = state`) |
| `2'd1` | 1-bit predictor | `state[1]` | `taken ? 2'b11 : 2'b00` |
| `2'd2` | 2-bit saturating counter | `state[1]` | `taken ? sat_inc(state) : sat_dec(state)` |
| `2'd3` | (reserved) treat exactly like `2'd2` | | |

2-bit states: `2'b00` Strongly Not-Taken (SNT), `2'b01` Weakly Not-Taken (WNT),
`2'b10` Weakly Taken (WT), `2'b11` Strongly Taken (ST).
`sat_inc`: 00→01→10→11→11. `sat_dec`: 11→10→01→00→00.

In 1-bit mode the entry only ever holds `00` or `11` after its first update, so only one bit of
information is used — this lets the same 2-bit BHT serve all three modes.

---

## 2. BHT indexing

```
index = pc[IDX_BITS+1 : 2]      // instructions are word aligned, so pc[1:0] is ignored
```
With `IDX_BITS = 4`: `index = pc[5:2]`. All BHT entries reset to `2'b01` (WNT).

---

## 3. Modules (file → owner)

### 3.1 `rtl/pred_static.v` — Mouli
```verilog
module pred_static (
    input  wire [1:0] state,
    input  wire       taken,
    output wire       predict_taken,   // always 1'b0
    output wire [1:0] next_state       // = state
);
```

### 3.2 `rtl/pred_1bit.v` — Mouli
```verilog
module pred_1bit (
    input  wire [1:0] state,
    input  wire       taken,
    output wire       predict_taken,   // = state[1]
    output wire [1:0] next_state       // = {taken, taken}
);
```

### 3.3 `rtl/pred_2bit.v` — Mouli
```verilog
module pred_2bit (
    input  wire [1:0] state,
    input  wire       taken,
    output wire       predict_taken,   // = state[1]
    output wire [1:0] next_state       // saturating increment if taken, else saturating decrement
);
```

### 3.4 `rtl/predictor_core.v` — Mouli
Instantiates `pred_static`, `pred_1bit`, `pred_2bit` and selects outputs by `mode` (combinational).
```verilog
module predictor_core (
    input  wire [1:0] mode,
    input  wire [1:0] state,
    input  wire       taken,
    output wire       predict_taken,
    output wire [1:0] next_state
);
```

### 3.5 `rtl/bht.v` — Yashvi
```verilog
module bht #(
    parameter IDX_BITS = 4,
    parameter [1:0] INIT = 2'b01
) (
    input  wire                clk,
    input  wire                rst,       // sync, active-high: all entries <= INIT
    input  wire [IDX_BITS-1:0] rd_idx,
    output wire [1:0]          rd_state,  // ASYNCHRONOUS (combinational) read
    input  wire                wr_en,
    input  wire [IDX_BITS-1:0] wr_idx,
    input  wire [1:0]          wr_state   // written on posedge clk when wr_en
);
```
Storage: `reg [1:0] table_mem [0:(1<<IDX_BITS)-1];` Reset uses a `for` loop (integer loop variable).

### 3.6 `rtl/perf_counter.v` — Aradhya
```verilog
module perf_counter (
    input  wire        clk,
    input  wire        rst,     // sync: count <= 0
    input  wire        inc,     // count <= count + 1 on posedge clk when inc
    output reg  [31:0] count
);
```

### 3.7 `rtl/flush_ctrl.v` — Aradhya
```verilog
module flush_ctrl #(
    parameter PENALTY = 2       // cycles lost per misprediction (branch resolved in EX)
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        mispredict,
    output wire        flush,           // = mispredict (combinational)
    output reg  [31:0] penalty_cycles   // += PENALTY on posedge clk when mispredict
);
```

### 3.8 `rtl/branch_predictor_top.v` — Aradhya
```verilog
module branch_predictor_top #(
    parameter IDX_BITS = 4,
    parameter PENALTY  = 2
) (
    input  wire        clk,
    input  wire        rst,
    input  wire [1:0]  mode,
    input  wire        br_valid,        // a branch is presented this cycle
    input  wire [31:0] br_pc,           // its PC
    input  wire        br_taken,        // its ACTUAL outcome (from the trace)
    output wire        predict_taken,   // combinational: br_valid & core prediction
    output wire        mispredict,      // combinational: br_valid & (predict_taken != br_taken)
    output wire        flush,           // from flush_ctrl
    output wire [31:0] branch_count,    // perf_counter, inc = br_valid
    output wire [31:0] mispredict_count,// perf_counter, inc = mispredict
    output wire [31:0] penalty_cycles   // from flush_ctrl
);
```
Internal wiring:
- `idx = br_pc[IDX_BITS+1:2]`
- `bht.rd_idx = idx`, `bht.wr_idx = idx`, `bht.wr_en = br_valid`, `bht.wr_state = core.next_state`
- `core.state = bht.rd_state`, `core.taken = br_taken`, `core.mode = mode`

**Timing (Phase 1, trace-driven):** one branch per clock. Prediction and mispredict are
combinational in the same cycle; the BHT entry is updated at the following `posedge clk`.
(Phase 2 will add the delayed EX-stage update, BTB and pipeline integration.)

---

## 4. Trace file format — Yashvi (`traces/*.mem`)

Read with `$readmemh` into `reg [35:0] trace_mem [0:4095];`

Each line = **9 hex digits** = `{PC[31:0], 3'b000, taken}`:
```
000000401   // PC 0x00000040, taken
000000400   // PC 0x00000040, not taken
FFFFFFFFF   // END MARKER (always the last line)
```
Lines starting with `//` are comments (allowed by `$readmemh`).

| File | PC(s) | Pattern | Branches |
|---|---|---|---|
| `traces/loop.mem` | 0x40 | 20 runs of a 10-iteration loop: T×9, N×1 | 200 |
| `traces/nested_loop.mem` | 0x80 inner, 0x90 outer | 4 repeats × 10 outer iterations; each: inner T,T,T,N then outer T (N on the 10th) | 200 |
| `traces/alternating.mem` | 0x100 | T,N,T,N… starting with T | 200 |
| `traces/random.mem` | 0x200 (50% taken), 0x204 (90% taken) | interleaved 100 each, Python `random.seed(42)` | 200 |

`traces/expected_accuracy.csv` (generated by the Python reference model in `scripts/gen_traces.py`):
```
trace,mode,branches,mispredicts,accuracy
loop,0,200,180,10.00
...
```

### Expected results (reference model, IDX_BITS=4, INIT=01)

| Trace | Mode 0 (static) | Mode 1 (1-bit) | Mode 2 (2-bit) |
|---|---|---|---|
| loop | 180 mis / 10.00% | 40 mis / 80.00% | 21 mis / 89.50% |
| nested_loop | 156 mis / 22.00% | 88 mis / 56.00% | 46 mis / 77.00% |
| alternating | 100 mis / 50.00% | 200 mis / 0.00% | 200 mis / 0.00% |
| random | (depends on generator) | | |

If the RTL simulation gives these exact numbers, the design is correct.

---

## 5. Testbench output format — Anuj

`tb/tb_top.v` takes plusargs: `+trace=traces/loop.mem +mode=2 [+vcd=results/loop_m2.vcd]` and prints
exactly one line:
```
RESULT trace=traces/loop.mem mode=2 branches=200 mispredicts=21 accuracy=89.50
```
`scripts/run_all.sh` runs all 4 traces × 3 modes and writes `results/accuracy.csv`
with header `trace,mode,branches,mispredicts,accuracy`, then compares against
`traces/expected_accuracy.csv` and prints PASS/FAIL per row.

---

## 6. CPI model — Aradhya (`scripts/cpi_calc.py`)

```
CPI = CPI_base + f_branch × misprediction_rate × penalty
CPI_base = 1.0, f_branch = 0.20 (20% of instructions are branches), penalty = 2 cycles
```
Reads `results/accuracy.csv`, writes `results/cpi.csv` and prints a Markdown table.
