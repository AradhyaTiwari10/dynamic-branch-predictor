#!/usr/bin/env bash
#------------------------------------------------------------------------------
# File    : run_all.sh
# Author  : Anuj
# Project : Dynamic Branch Prediction Unit (MCA Project 5)
#
# Purpose : Full regression in one command.
#           1. Unit tests: predictors, BHT, BTB, GHR + gshare index.
#           2. Trace-driven unit (tb_top): 4 traces x 4 modes, compared with
#              the Python reference model -> results/accuracy.csv
#           3. Program branch streams on the trace-driven unit: 4 programs x
#              4 modes x 2 table sizes (16 and 256 entries), compared with the
#              reference model -> results/program_traces.csv
#           4. 5-stage pipeline (tb_cpu): 4 programs x 4 modes x 2 table
#              sizes; instret, branches and x10 compared with the
#              instruction-set simulator, cycle identity checked inside the
#              testbench -> results/pipeline.csv (measured CPI)
#           5. Waveforms for the report (results/*.vcd).
#           Exit code 0 only if every check passes.
#
# Usage   : bash scripts/run_all.sh        (from anywhere; needs iverilog + vvp)
#------------------------------------------------------------------------------
set -e
cd "$(dirname "$0")/.."                      # always run from the repo root

TRACES="loop nested_loop alternating random"
PROGRAMS="loop nested_loop alternating pattern"
MODES="0 1 2 3"
IDX_SIZES="4 8"
EXPECTED=traces/expected_accuracy.csv
EXPECTED_PROG=programs/expected_programs.csv

failures=0
mkdir -p build results

field() {   # field <name> <text>: value of name=... in a RESULT line
    echo "$2" | sed -n "s/.* $1=\([^ ]*\).*/\1/p"
}

# ---- 1. unit tests ----------------------------------------------------------
echo "== Unit tests"

unit() {    # unit <label> <summary regex> <pass prefix> <iverilog args...>
    label=$1; regex=$2; pass=$3; shift 3
    iverilog -g2012 -Wall -o build/unit_$label "$@"
    summary=$(vvp -n build/unit_$label | grep -E "$regex" || true)
    printf "   %-14s: %s\n" "$label" "${summary:-no summary line (simulation failed)}"
    case "$summary" in "$pass"*) ;; *) failures=$((failures + 1)) ;; esac
}

unit tb_predictors "PREDICTOR TESTS" "ALL PREDICTOR TESTS PASSED" \
    tb/tb_predictors.v rtl/pred_static.v rtl/pred_1bit.v rtl/pred_2bit.v
unit tb_bht "BHT TESTS" "ALL BHT TESTS PASSED" tb/tb_bht.v rtl/bht.v
unit tb_btb "BTB TESTS" "ALL BTB TESTS PASSED" tb/tb_btb.v rtl/btb.v
unit tb_gshare "GSHARE TESTS" "ALL GSHARE TESTS PASSED" \
    tb/tb_gshare.v rtl/ghr.v rtl/gshare_index.v

# ---- 2. trace-driven unit: traces x modes -----------------------------------
echo
echo "== Trace-driven unit (tb_top): traces x modes vs reference model"
iverilog -g2012 -Wall -o build/sim tb/tb_top.v rtl/*.v

CSV=results/accuracy.csv
echo "trace,mode,branches,mispredicts,accuracy" > "$CSV"
configs=0
printf "   %-6s %-12s %-5s %-9s %-12s %s\n" "check" "trace" "mode" "branches" "mispredicts" "accuracy"

for t in $TRACES; do
    for m in $MODES; do
        configs=$((configs + 1))
        out=$(vvp -n build/sim +trace=traces/$t.mem +mode=$m)
        result=$(echo "$out" | grep "^RESULT" || true)
        branches=$(field branches "$result")
        mispredicts=$(field mispredicts "$result")
        accuracy=$(field accuracy "$result")

        row="$t,$m,$branches,$mispredicts,$accuracy"
        echo "$row" >> "$CSV"

        expected=$(tr -d '\r' < "$EXPECTED" | grep "^$t,$m," || true)
        if [ -n "$result" ] && [ "$row" = "$expected" ] && ! echo "$out" | grep -q "^ERROR"; then
            status=PASS
        else
            status=FAIL
            failures=$((failures + 1))
        fi
        printf "   %-6s %-12s %-5s %-9s %-12s %s%%\n" "$status" "$t" "$m" "$branches" "$mispredicts" "$accuracy"
        if [ "$status" = FAIL ]; then
            echo "$out" | grep "^ERROR" | sed 's/^/          /' || true
            echo "          expected: ${expected:-<no row in $EXPECTED>}"
        fi
    done
done
echo "   -> $CSV written"

# ---- 3. program branch streams on the trace-driven unit ---------------------
echo
echo "== Program branch streams on tb_top (ideal update) vs reference model"
CSV=results/program_traces.csv
echo "program,idx_bits,mode,branches,mispredicts" > "$CSV"
printf "   %-6s %-12s %-4s %-5s %-9s %s\n" "check" "program" "idx" "mode" "branches" "mispredicts"

for k in $IDX_SIZES; do
    iverilog -g2012 -Ptb_top.IDX_BITS=$k -o build/sim_$k tb/tb_top.v rtl/*.v
    for p in $PROGRAMS; do
        for m in $MODES; do
            configs=$((configs + 1))
            out=$(vvp -n build/sim_$k +trace=programs/${p}_branches.mem +mode=$m)
            result=$(echo "$out" | grep "^RESULT" || true)
            branches=$(field branches "$result")
            mispredicts=$(field mispredicts "$result")
            echo "$p,$k,$m,$branches,$mispredicts" >> "$CSV"

            # expected: program,idx_bits,mode,instret,branches,taken,x10,ideal_mispredicts
            exp=$(tr -d '\r' < "$EXPECTED_PROG" | grep "^$p,$k,$m," || true)
            exp_br=$(echo "$exp" | cut -d, -f5)
            exp_mis=$(echo "$exp" | cut -d, -f8)
            if [ -n "$result" ] && [ "$branches" = "$exp_br" ] && [ "$mispredicts" = "$exp_mis" ] \
               && ! echo "$out" | grep -q "^ERROR"; then
                status=PASS
            else
                status=FAIL
                failures=$((failures + 1))
            fi
            printf "   %-6s %-12s %-4s %-5s %-9s %s\n" "$status" "$p" "$k" "$m" "$branches" "$mispredicts"
            [ "$status" = FAIL ] && echo "          expected: branches=$exp_br mispredicts=$exp_mis"
        done
    done
done
echo "   -> $CSV written"

# ---- 4. 5-stage pipeline: programs x modes x table sizes --------------------
echo
echo "== 5-stage pipeline (tb_cpu): programs x modes x table sizes vs ISS"
CSV=results/pipeline.csv
echo "program,idx_bits,mode,cycles,instret,branches,mispredicts,cpi,ideal_mispredicts" > "$CSV"
printf "   %-6s %-12s %-4s %-5s %-7s %-8s %-9s %-12s %s\n" \
    "check" "program" "idx" "mode" "cycles" "instret" "branches" "mispredicts" "cpi"

for k in $IDX_SIZES; do
    iverilog -g2012 -Wall -Ptb_cpu.IDX_BITS=$k -o build/cpu_$k tb/tb_cpu.v rtl/*.v rtl/cpu/*.v
    for p in $PROGRAMS; do
        for m in $MODES; do
            configs=$((configs + 1))
            out=$(vvp -n build/cpu_$k +prog=programs/$p.mem +mode=$m)
            result=$(echo "$out" | grep "^RESULT" || true)
            cycles=$(field cycles "$result")
            instret=$(field instret "$result")
            branches=$(field branches "$result")
            mispredicts=$(field mispredicts "$result")
            cpi=$(field cpi "$result")
            x10=$(field x10 "$result")

            exp=$(tr -d '\r' < "$EXPECTED_PROG" | grep "^$p,$k,$m," || true)
            exp_instret=$(echo "$exp" | cut -d, -f4)
            exp_br=$(echo "$exp" | cut -d, -f5)
            exp_x10=$(echo "$exp" | cut -d, -f7)
            exp_mis=$(echo "$exp" | cut -d, -f8)
            echo "$p,$k,$m,$cycles,$instret,$branches,$mispredicts,$cpi,$exp_mis" >> "$CSV"

            if [ -n "$result" ] && [ "$instret" = "$exp_instret" ] && [ "$branches" = "$exp_br" ] \
               && [ "$x10" = "$exp_x10" ] && ! echo "$out" | grep -q "^ERROR"; then
                status=PASS
            else
                status=FAIL
                failures=$((failures + 1))
            fi
            printf "   %-6s %-12s %-4s %-5s %-7s %-8s %-9s %-12s %s\n" \
                "$status" "$p" "$k" "$m" "$cycles" "$instret" "$branches" "$mispredicts" "$cpi"
            if [ "$status" = FAIL ]; then
                echo "$out" | grep "^ERROR" | sed 's/^/          /' || true
                echo "          expected (ISS): instret=$exp_instret branches=$exp_br x10=$exp_x10"
            fi
        done
    done
done
echo "   -> $CSV written"

# ---- 5. waveforms for the report --------------------------------------------
echo
echo "== Waveforms"
vvp -n build/sim +trace=traces/loop.mem +mode=1 +vcd=results/loop_mode1.vcd > /dev/null
vvp -n build/sim +trace=traces/loop.mem +mode=2 +vcd=results/loop_mode2.vcd > /dev/null
vvp -n build/cpu_4 +prog=programs/loop.mem +mode=2 +vcd=results/cpu_loop_mode2.vcd > /dev/null
echo "   results/loop_mode1.vcd      (trace-driven unit, loop trace, 1-bit)"
echo "   results/loop_mode2.vcd      (trace-driven unit, loop trace, 2-bit)"
echo "   results/cpu_loop_mode2.vcd  (pipeline, loop program, 2-bit: flush at each loop exit)"

# ---- summary ----------------------------------------------------------------
echo
if [ "$failures" -eq 0 ]; then
    echo "ALL $configs CONFIGURATIONS PASS (and all 4 unit tests passed)"
else
    echo "REGRESSION FAILED: $failures check(s) failed"
    exit 1
fi
