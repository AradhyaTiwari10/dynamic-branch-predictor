# Interface Specification — Dynamic Branch Prediction Unit (Phase 1 + Phase 2)

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
| `2'd3` | gshare (Phase 2) | `state[1]` | same as `2'd2`; only the BHT index differs (section 2) |

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

Phase 2, mode 3 (gshare): `index = pc[IDX_BITS+1:2] ^ history`, where `history` is the
`IDX_BITS`-bit global history register (newest outcome in bit 0, reset to 0).

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
    input  wire [IDX_BITS-1:0] rd2_idx,   // Phase 2: second read port (EX stage)
    output wire [1:0]          rd2_state, // Phase 2: ASYNCHRONOUS read
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
- `idx = br_pc[IDX_BITS+1:2]` (Phase 2: from `gshare_index`, XOR with `ghr` history in mode 3;
  `ghr.upd_en = br_valid`, `ghr.taken = br_taken`; `bht.rd2_idx` tied to 0)
- `bht.rd_idx = idx`, `bht.wr_idx = idx`, `bht.wr_en = br_valid`, `bht.wr_state = core.next_state`
- `core.state = bht.rd_state`, `core.taken = br_taken`, `core.mode = mode`

**Timing (Phase 1, trace-driven):** one branch per clock. Prediction and mispredict are
combinational in the same cycle; the BHT entry is updated at the following `posedge clk`.
(Phase 2 adds the delayed EX-stage update, BTB and pipeline integration: section 7.)

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
`scripts/run_all.sh` runs all 4 traces × 4 modes (Phase 2: modes 0–3) and writes `results/accuracy.csv`
with header `trace,mode,branches,mispredicts,accuracy`, then compares against
`traces/expected_accuracy.csv` and prints PASS/FAIL per row.

---

## 6. CPI model — Aradhya (`scripts/cpi_calc.py`)

```
CPI = CPI_base + f_branch × misprediction_rate × penalty
CPI_base = 1.0, f_branch = 0.20 (20% of instructions are branches), penalty = 2 cycles
```
Reads `results/accuracy.csv`, writes `results/cpi.csv` and prints a Markdown table.

---

## 7. Phase 2 additions

### 7.1 New modules (file → owner)

| File | Module | Owner | Function |
|---|---|---|---|
| `rtl/ghr.v` | `ghr #(HIST_BITS=4)(clk, rst, upd_en, taken, history)` | Mouli | global history, `history <= {history[HIST_BITS-2:0], taken}` when `upd_en` |
| `rtl/gshare_index.v` | `gshare_index #(IDX_BITS=4)(mode, pc, history, idx)` | Mouli | `idx = pc[IDX_BITS+1:2]`, XOR `history` when `mode == 3` |
| `rtl/btb.v` | `btb #(IDX_BITS=4)(clk, rst, rd_pc, hit, rd_target, wr_en, wr_pc, wr_target)` | Yashvi | direct-mapped BTB, tag = `pc[31:IDX_BITS+2]`, async read, sync write, reset clears valid bits |
| `rtl/bp_unit.v` | see 7.2 | Aradhya | pipeline prediction unit (BHT + BTB + GHR, predict in IF, update in EX) |
| `rtl/cpu/alu.v` | `alu(a, b, alu_op[2:0], y)` | Mouli | ADD 000, SUB 001, AND 010, OR 011, XOR 100, SLT 101 |
| `rtl/cpu/regfile.v` | `regfile(clk, rst, ra1, ra2, rd1, rd2, we, wa, wd, dbg_addr, dbg_data)` | Mouli | 32×32, x0 = 0, write-through bypass |
| `rtl/cpu/decoder.v` | `decoder(instr, rs1, rs2, rd, imm, alu_op, alu_src_imm, reg_write, is_branch, br_funct3, is_halt)` | Mouli | RV32I subset decoder |
| `rtl/cpu/branch_unit.v` | `branch_unit(is_branch, br_funct3, a, b, pc, imm, taken, target)` | Mouli | BEQ/BNE/BLT/BGE resolution, `target = pc + imm` |
| `rtl/cpu/pipeline_cpu.v` | see 7.3 | Aradhya | 5-stage pipeline |

### 7.2 `rtl/bp_unit.v`
```verilog
module bp_unit #(parameter IDX_BITS = 4) (
    input  wire                clk, rst,
    input  wire [1:0]          mode,
    input  wire [31:0]         if_pc,          // IF: PC being fetched
    output wire                if_pred_taken,  // = direction prediction & BTB hit
    output wire [31:0]         if_pred_target, // BTB target
    output wire [IDX_BITS-1:0] if_idx,         // BHT index used, carried to EX
    input  wire                ex_upd,         // EX: conditional branch resolved
    input  wire [31:0]         ex_pc,
    input  wire [IDX_BITS-1:0] ex_idx,
    input  wire                ex_taken,
    input  wire [31:0]         ex_target
);
```
BHT port 1 = `if_idx` (prediction), port 2 = `ex_idx` (state for the update), write = `ex_idx`.
BTB written when `ex_upd & ex_taken`. GHR shifted when `ex_upd` (non-speculative history).

### 7.3 `rtl/cpu/pipeline_cpu.v`
Parameters `IDX_BITS = 4`, `IMEM_WORDS = 256`, `PENALTY = 2`. Ports: `clk, rst, mode, halted, flush,
cycle_count, instret_count, branch_count, mispredict_count, penalty_cycles, dbg_reg_addr, dbg_reg_data`.
Instruction memory `imem` (`reg [31:0] imem [0:IMEM_WORDS-1]`) is loaded by the testbench.
Branches resolve in EX; on a misprediction IF/ID and ID/EX are flushed (2 cycles) and fetch is
redirected. Forwarding EX/MEM and MEM/WB → EX. EBREAK (`0x00100073`) retiring in WB sets `halted`.
Invariant checked by the testbench: `cycles = instret + 4 + 2 × mispredicts`.

### 7.4 Programs — Yashvi (`programs/`)
- Supported instructions: `add sub and or xor slt addi andi ori xori slti beq bne blt bge ebreak`
  (+ pseudo `nop li mv`). Code starts at address 0.
- `scripts/asm.py`: `programs/<name>.s` → `programs/<name>.mem` (one 32-bit hex word per line).
- `scripts/iss.py`: golden instruction-set simulator; writes `programs/<name>_branches.mem`
  (branch stream, section 4 format) and `programs/expected_programs.csv`
  (`program,idx_bits,mode,instret,branches,taken,x10,ideal_mispredicts`).
- Every program leaves its result in `x10`.

### 7.5 Pipeline testbench output — Anuj
`tb/tb_cpu.v`, plusargs `+prog=programs/loop.mem +mode=2 [+vcd=...]`, parameter `IDX_BITS`:
```
RESULT prog=programs/loop.mem mode=2 idx_bits=4 cycles=934 instret=884 branches=220 mispredicts=23 penalty=46 cpi=1.057 x10=900
```
`scripts/run_all.sh` writes `results/accuracy.csv`, `results/program_traces.csv` and
`results/pipeline.csv` (`program,idx_bits,mode,cycles,instret,branches,mispredicts,cpi,ideal_mispredicts`).

### 7.6 Analysis and synthesis — Aradhya
- `scripts/cpi_calc.py` also writes `results/cpi_pipeline.csv` (measured vs model CPI).
- `synth/run_synth.sh` (Yosys) writes `synth/yosys_summary.csv`
  (`module,idx_bits,entries,lut,ff,lutram,carry,mux,lut_levels`) and `synth/reports/*.txt`.
