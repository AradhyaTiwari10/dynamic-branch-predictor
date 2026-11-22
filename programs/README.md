# Test Programs for the 5-Stage Pipeline (Phase 2)

Author: Yashvi, Dynamic Branch Prediction Unit (MCA Project 5)

In Phase 1 the predictor was fed branch **traces**. In Phase 2 it sits inside a real
5-stage pipeline ([`rtl/cpu/pipeline_cpu.v`](../rtl/cpu/pipeline_cpu.v)) that runs these small
assembly programs, so the CPI is **measured** in cycles instead of estimated with a formula.

## 1. Flow

```
programs/<name>.s  --scripts/asm.py-->  programs/<name>.mem         (loaded into imem by tb/tb_cpu.v)
                   --scripts/iss.py-->  programs/<name>_branches.mem (branch stream, Phase 1 trace format)
                                        programs/expected_programs.csv (golden results)
```

```bash
python3 scripts/asm.py     # assemble every programs/*.s
python3 scripts/iss.py     # run the instruction-set simulator, write expected results
```

## 2. Instruction subset (RV32I)

| Type | Instructions |
|---|---|
| R-type | `add sub and or xor slt  rd, rs1, rs2` |
| I-type | `addi andi ori xori slti  rd, rs1, imm` (imm −2048..2047) |
| Branch | `beq bne blt bge  rs1, rs2, label` |
| System | `ebreak` — stops the simulation |
| Pseudo | `nop`, `li rd, imm`, `mv rd, rs` |

Code starts at address `0x0`, 4 bytes per instruction. Every program leaves its result in `x10`.

## 3. Programs

| Program | What it does | Branch behaviour | x10 |
|---|---|---|---|
| `loop.s` | 20 runs of a 10-iteration loop | inner branch T×9, N (like `traces/loop.mem`) | 900 |
| `nested_loop.s` | 4 × (outer 10 × inner 4) | inner T,T,T,N; outer taken 9 of 10 | 160 |
| `alternating.s` | if/else on `i & 1`, i = 0..199 | `beq` alternates T,N,T,N | 100 |
| `pattern.s` | counts multiples of 3 with a mod-3 counter | two branches with period-3 patterns (N,T,T and T,T,N) | 50 |

## 4. Golden results (`expected_programs.csv`)

`scripts/iss.py` executes each program one instruction at a time (no pipeline) and records:

| Program | Instructions (incl. `ebreak`) | Branches | Taken |
|---|---|---|---|
| alternating | 1205 | 400 | 299 |
| loop | 884 | 220 | 199 |
| nested_loop | 660 | 204 | 159 |
| pattern | 856 | 450 | 349 |

It then runs the reference predictor model (from `scripts/gen_traces.py`) on each program's
branch stream for modes 0–3 and two table sizes (16 and 256 entries), with an *ideal* update
(every branch updated before the next is predicted). The pipeline must match the instruction
count, branch count and `x10` exactly; its misprediction count can differ from the ideal value
because it updates the predictor in EX, two cycles after the prediction.

**Aliasing example:** in `alternating` with 16 entries, gshare XORs the PC with the history and
the alternating `beq` and the loop `bne` land on the same counter, so the ideal gshare model
mispredicts 203 of 400 branches. With 256 entries (8-bit history) they no longer collide and it
drops to 9.
