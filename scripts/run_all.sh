#!/usr/bin/env bash
#------------------------------------------------------------------------------
# File    : run_all.sh
# Author  : Anuj
# Project : Dynamic Branch Prediction Unit (MCA Project 5)
#
# Purpose : Full regression in one command.
#           1. Compiles and runs the two unit testbenches (predictors, BHT).
#           2. Compiles the system testbench once and runs it for
#              4 traces x 3 modes = 12 configurations.
#           3. Writes results/accuracy.csv and compares every row with the
#              Python reference model in traces/expected_accuracy.csv.
#           4. Dumps two waveforms of the loop trace for the report:
#              results/loop_mode1.vcd (1-bit) and results/loop_mode2.vcd (2-bit).
#           Exit code 0 only if every check passes.
#
# Usage   : bash scripts/run_all.sh        (from anywhere; needs iverilog + vvp)
#------------------------------------------------------------------------------
set -e
cd "$(dirname "$0")/.."                      # always run from the repo root

TRACES="loop nested_loop alternating random"
MODES="0 1 2"
CSV=results/accuracy.csv
EXPECTED=traces/expected_accuracy.csv

failures=0
mkdir -p build results

# ---- 1. unit tests ----------------------------------------------------------
echo "== Unit tests"

iverilog -g2012 -Wall -o build/tb_pred \
    tb/tb_predictors.v rtl/pred_static.v rtl/pred_1bit.v rtl/pred_2bit.v
summary=$(vvp -n build/tb_pred | grep -E "PREDICTOR TESTS" || true)
echo "   tb_predictors : ${summary:-no summary line (simulation failed)}"
case "$summary" in "ALL PREDICTOR TESTS PASSED"*) ;; *) failures=$((failures + 1)) ;; esac

iverilog -g2012 -Wall -o build/tb_bht tb/tb_bht.v rtl/bht.v
summary=$(vvp -n build/tb_bht | grep -E "BHT TESTS" || true)
echo "   tb_bht        : ${summary:-no summary line (simulation failed)}"
case "$summary" in "ALL BHT TESTS PASSED"*) ;; *) failures=$((failures + 1)) ;; esac

# ---- 2. system test: every trace x every mode -------------------------------
echo
echo "== System test (tb_top): traces x modes vs reference model"
iverilog -g2012 -Wall -o build/sim tb/tb_top.v rtl/*.v

echo "trace,mode,branches,mispredicts,accuracy" > "$CSV"
configs=0
printf "   %-6s %-12s %-5s %-9s %-12s %s\n" "check" "trace" "mode" "branches" "mispredicts" "accuracy"

for t in $TRACES; do
    for m in $MODES; do
        configs=$((configs + 1))
        out=$(vvp -n build/sim +trace=traces/$t.mem +mode=$m)
        result=$(echo "$out" | grep "^RESULT" || true)

        # pull the numbers out of:  RESULT trace=... mode=2 branches=200 mispredicts=21 accuracy=89.50
        branches=$(echo "$result"    | sed -n 's/.* branches=\([0-9]*\).*/\1/p')
        mispredicts=$(echo "$result" | sed -n 's/.* mispredicts=\([0-9]*\).*/\1/p')
        accuracy=$(echo "$result"    | sed -n 's/.* accuracy=\([0-9.]*\).*/\1/p')

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

# ---- 3. waveforms for the report --------------------------------------------
echo
echo "== Waveforms"
vvp -n build/sim +trace=traces/loop.mem +mode=1 +vcd=results/loop_mode1.vcd > /dev/null
vvp -n build/sim +trace=traces/loop.mem +mode=2 +vcd=results/loop_mode2.vcd > /dev/null
echo "   results/loop_mode1.vcd  (loop trace, 1-bit)"
echo "   results/loop_mode2.vcd  (loop trace, 2-bit)"

# ---- summary ----------------------------------------------------------------
echo
if [ "$failures" -eq 0 ]; then
    echo "ALL $configs CONFIGURATIONS MATCH THE REFERENCE MODEL (and both unit tests passed)"
else
    echo "REGRESSION FAILED: $failures check(s) failed"
    exit 1
fi
