#!/usr/bin/env bash
#------------------------------------------------------------------------------
# File    : run_synth.sh
# Author  : Aradhya Tiwari
# Project : Dynamic Branch Prediction Unit (MCA Project 5) - Phase 2
#
# Purpose : Synthesis of the prediction units with Yosys (open source; Vivado
#           does not run on macOS). Two passes per configuration:
#             1. synth_xilinx -family xc7 : map to Xilinx 7-series primitives
#                (LUT1..LUT6, FDRE/FDSE flip-flops, RAM32M LUT-RAM) -> resources
#             2. generic synth -lut 6 + ltp -noff : longest combinational path
#                in 6-input LUT levels (logic depth, a proxy for speed)
#           Yosys does not place and route, so it gives no Fmax; the LUT depth
#           shows how deep the logic is between flip-flops.
#
#   Configurations: branch_predictor_top (trace-driven unit, with counters)
#                   bp_unit (pipeline unit: BHT + BTB + GHR, two ports)
#                   each with IDX_BITS = 4 (16 entries) and 8 (256 entries)
#
# Output  : synth/reports/<module>_idx<N>.txt   full Yosys statistics
#           synth/yosys_summary.csv             one line per configuration
#
# Usage   : bash synth/run_synth.sh     (needs yosys: brew install yosys)
#------------------------------------------------------------------------------
set -e
cd "$(dirname "$0")/.."

PRED="rtl/bht.v rtl/ghr.v rtl/gshare_index.v rtl/pred_static.v rtl/pred_1bit.v \
      rtl/pred_2bit.v rtl/predictor_core.v"
SRC_branch_predictor_top="$PRED rtl/flush_ctrl.v rtl/perf_counter.v rtl/branch_predictor_top.v"
SRC_bp_unit="$PRED rtl/btb.v rtl/bp_unit.v"

mkdir -p synth/reports
SUMMARY=synth/yosys_summary.csv
echo "module,idx_bits,entries,lut,ff,lutram,carry,mux,lut_levels" > "$SUMMARY"

for top in branch_predictor_top bp_unit; do
    src_var="SRC_$top"
    for k in 4 8; do
        rep=synth/reports/${top}_idx$k.txt
        yosys -q -p "read_verilog ${!src_var}; chparam -set IDX_BITS $k $top;
                     synth_xilinx -family xc7 -top $top -flatten;
                     tee -o $rep stat" > /dev/null
        depth=$(yosys -q -p "read_verilog ${!src_var}; chparam -set IDX_BITS $k $top;
                             synth -flatten -top $top -lut 6; tee -o /dev/stdout ltp -noff" \
                | sed -n 's/.*(length=\([0-9]*\)).*/\1/p' | head -1)
        echo "Longest path (generic 6-input LUT mapping): $depth LUT levels" >> "$rep"

        count() {   # sum of the cell counts whose name matches a regex
            awk -v re="$1" '$2 ~ re { s += $1 } END { print s + 0 }' "$rep"
        }
        lut=$(count '^LUT[1-6]$')
        ff=$(count '^FD[RSCP]E$')
        lutram=$(count '^RAM(32|64|128|256)')
        carry=$(count '^CARRY4$')
        mux=$(count '^MUXF[78]$')
        echo "$top,$k,$((1 << k)),$lut,$ff,$lutram,$carry,$mux,$depth" >> "$SUMMARY"
        printf "   %-22s idx=%s  LUT=%-5s FF=%-5s LUTRAM=%-3s CARRY4=%-3s MUXF=%-4s depth=%s\n" \
            "$top" "$k" "$lut" "$ff" "$lutram" "$carry" "$mux" "$depth"
    done
done
echo "   -> $SUMMARY written, full reports in synth/reports/"
