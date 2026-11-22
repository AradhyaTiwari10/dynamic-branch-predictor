# Branch Traces & Expected Accuracy

This directory contains standard benchmark branch traces in Verilog hex memory format (`.mem`) along with the golden reference accuracy results.

---

## 1. Trace File Format

Each trace file is formatted for direct loading into Verilog memory using `$readmemh`:

```verilog
reg [35:0] trace_mem [0:4095];
$readmemh("traces/<trace_name>.mem", trace_mem);
```

### Line Structure
- **Comment Lines:** Lines starting with `//` are treated as comments and ignored by `$readmemh`.
- **Branch Entry Lines:** Each branch instruction is encoded as a **9-character hexadecimal string** representing a 36-bit word:
  $$\text{Value} = (\text{PC}[31:0] \ll 4) \mid (\text{taken} \ \& \ \text{0xF})$$
  - Bits `[35:4]` (32 bits): Branch Instruction Program Counter (PC).
  - Bits `[3:1]` (3 bits): Reserved zeros (`3'b000`).
  - Bit `[0]` (1 bit): Actual branch outcome (`1` = Taken, `0` = Not-Taken).
- **End Marker:** The sentinel value `FFFFFFFFF` marks the end of the trace, signaling the testbench to stop simulation.

### Example Decoded Lines

| Encoded Hex Line | Hex PC | Bits `[3:0]` | Outcome | Meaning |
|:---:|:---:|:---:|:---:|:---|
| `000000401` | `0x00000040` | `0001` | Taken (`1`) | Branch at PC `0x40` was **taken** |
| `000000400` | `0x00000040` | `0000` | Not-Taken (`0`) | Branch at PC `0x40` was **not taken** |
| `000002041` | `0x00000204` | `0001` | Taken (`1`) | Branch at PC `0x204` was **taken** |
| `FFFFFFFFF` | — | — | — | **End of Trace Marker** |

---

## 2. Trace Descriptions & Expected Results

All traces contain exactly **200 branch evaluations**.

### 2.1 `loop.mem` — Single Loop
- **Pattern:** 20 executions of a 10-iteration loop (`for (int i = 0; i < 10; i++)`).
- **Structure:** 9 Taken branches followed by 1 Not-Taken branch (the loop exit) at PC `0x00000040`, repeated 20 times.
- **Significance:** Highlights the primary advantage of a 2-bit saturating counter over a 1-bit predictor. A 1-bit predictor mispredicts twice per loop run (exit + re-entry = 40 mispredictions), whereas a 2-bit counter only mispredicts once at exit (20 mispredictions + 1 initial training = 21 mispredictions).

| Mode | Strategy | Branches | Mispredicts | Accuracy |
|:---:|:---|:---:|:---:|:---:|
| `0` | Static (Always-Not-Taken) | 200 | 180 | 10.00% |
| `1` | 1-bit Last-Outcome | 200 | 40 | 80.00% |
| `2` | 2-bit Saturating Counter | 200 | 21 | **89.50%** |

---

### 2.2 `nested_loop.mem` — Nested Loops
- **Pattern:** 4 runs of an outer loop with 10 iterations, where each outer iteration executes an inner loop of 4 iterations:
  ```c
  for (int out = 0; out < 10; out++) {
      for (int in = 0; in < 4; in++) { /* PC 0x80 */ }
      /* PC 0x90 */
  }
  ```
- **Structure:**
  - Inner branch PC `0x00000080`: Outcomes `T, T, T, N` (4 branches per outer iteration).
  - Outer branch PC `0x00000090`: Outcome `T` on outer iterations 0–8, and `N` on outer iteration 9 (1 branch per outer iteration).
  - Total: $4 \times 10 \times 5 = 200$ branches.
- **Significance:** Evaluates predictor performance when multiple active branches with different trip counts execute together without colliding.

| Mode | Strategy | Branches | Mispredicts | Accuracy |
|:---:|:---|:---:|:---:|:---:|
| `0` | Static (Always-Not-Taken) | 200 | 156 | 22.00% |
| `1` | 1-bit Last-Outcome | 200 | 88 | 56.00% |
| `2` | 2-bit Saturating Counter | 200 | 46 | **77.00%** |

---

### 2.3 `alternating.mem` — Strictly Alternating Branch
- **Pattern:** A branch at PC `0x00000100` that alternates outcome every single cycle: `T, N, T, N...` starting with `T`.
- **Structure:** 100 Taken and 100 Not-Taken branches alternating.
- **Significance:** Classic adversarial pattern that defeats standard 1-bit and 2-bit predictors (0.00% accuracy). In this case, static prediction (50.00%) is superior. This motivates two-level correlating branch predictors (e.g., Yeh & Patt), which track global branch history.

| Mode | Strategy | Branches | Mispredicts | Accuracy |
|:---:|:---|:---:|:---:|:---:|
| `0` | Static (Always-Not-Taken) | 200 | 100 | **50.00%** |
| `1` | 1-bit Last-Outcome | 200 | 200 | 0.00% |
| `2` | 2-bit Saturating Counter | 200 | 200 | 0.00% |

---

### 2.4 `random.mem` — Biased Pseudo-Random Branches
- **Pattern:** 100 iterations of two interleaved branches generated with `random.seed(42)`:
  - Branch A at PC `0x00000200`: Taken with probability $p = 0.50$ (unbiased).
  - Branch B at PC `0x00000204`: Taken with probability $p = 0.90$ (strongly biased taken).
- **Structure:** 200 branches total.
- **Significance:** Tests predictor resiliency against noisy, data-dependent branch distributions. The 2-bit saturating counter filters out isolated anomalies on the 90%-biased branch, achieving higher accuracy than 1-bit.

| Mode | Strategy | Branches | Mispredicts | Accuracy |
|:---:|:---|:---:|:---:|:---:|
| `0` | Static (Always-Not-Taken) | 200 | 145 | 27.50% |
| `1` | 1-bit Last-Outcome | 200 | 73 | 63.50% |
| `2` | 2-bit Saturating Counter | 200 | 62 | **69.00%** |

---

## 3. Summary of Golden Reference Results

Generated by `scripts/gen_traces.py` and saved in `traces/expected_accuracy.csv`:

| Trace | Total Branches | Mode 0 (Static) Mispredicts (Acc) | Mode 1 (1-bit) Mispredicts (Acc) | Mode 2 (2-bit) Mispredicts (Acc) |
|:---|:---:|:---:|:---:|:---:|
| `loop` | 200 | 180 (10.00%) | 40 (80.00%) | **21 (89.50%)** |
| `nested_loop` | 200 | 156 (22.00%) | 88 (56.00%) | **46 (77.00%)** |
| `alternating` | 200 | **100 (50.00%)** | 200 (0.00%) | 200 (0.00%) |
| `random` | 200 | 145 (27.50%) | 73 (63.50%) | **62 (69.00%)** |

---

## 3a. Phase 2: gshare (mode 3)

`scripts/gen_traces.py` now also models **gshare**: a 4-bit global history register (newest
outcome in bit 0) is XOR-ed with `pc[5:2]` to pick the 2-bit counter. The trace files are
unchanged; `expected_accuracy.csv` has one extra row per trace:

| Trace | Mode 2 (2-bit) | Mode 3 (gshare) | Why |
|:---|:---:|:---:|:---|
| `loop` | 21 (89.50%) | 28 (86.00%) | a 4-bit history cannot see a 10-iteration loop; the loop is spread over several counters that each need training |
| `nested_loop` | 46 (77.00%) | **17 (91.50%)** | the history tells the inner branch where it is in its T,T,T,N pattern |
| `alternating` | 200 (0.00%) | **3 (98.50%)** | the history separates "last was T" from "last was N" |
| `random` | 62 (69.00%) | 80 (60.00%) | random outcomes make the history random too, so training is spread thin |

## 4. BHT Indexing and Aliasing

### 4.1 Index Mapping Formula
For a 16-entry Branch History Table (`IDX_BITS = 4`), the index is computed as:

$$\text{index} = \text{pc}[\text{IDX\_BITS}+1 : 2] = \text{pc}[5:2]$$

Because 32-bit RISC instructions are word-aligned (4 bytes per instruction), the bottom two address bits `pc[1:0]` are always `2'b00` and are ignored.

### 4.2 PC Index Mapping in Benchmark Traces

| Branch PC | Binary Address (lower 8 bits) | Index Bits `pc[5:2]` | Table Index | Trace Used In |
|:---:|:---:|:---:|:---:|:---|
| `0x00000040` | `0100 0000` | `0000` | **0** | `loop.mem` |
| `0x00000080` | `1000 0000` | `0000` | **0** | `nested_loop.mem` (inner) |
| `0x00000090` | `1001 0000` | `0100` | **4** | `nested_loop.mem` (outer) |
| `0x00000100` | `0000 0000` (from `0x100`) | `0000` | **0** | `alternating.mem` |
| `0x00000200` | `0000 0000` (from `0x200`) | `0000` | **0** | `random.mem` (Branch A) |
| `0x00000204` | `0000 0100` (from `0x204`) | `0001` | **1** | `random.mem` (Branch B) |

### 4.3 Analysis of Aliasing
- **Intra-trace Independence:**
  - In `nested_loop.mem`, the inner branch (`0x80`) maps to index `0` while the outer branch (`0x90`) maps to index `4`. They have distinct BHT slots and do not alias.
  - In `random.mem`, Branch A (`0x200`) maps to index `0` while Branch B (`0x204`) maps to index `1`. They do not alias.
- **Inter-trace Aliasing:**
  - Notice that `0x40`, `0x80`, `0x100`, and `0x200` all hash to index `0` because their bits `[5:2]` happen to be `0000`. If these branches were executed simultaneously in a multi-tasking program, they would overwrite each other's 2-bit counter (**destructive aliasing**). In Phase 1, each trace is run separately from a reset state, avoiding inter-trace interference.
