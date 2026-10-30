#!/usr/bin/env bash
# RTL simulation of a validation design with its own testbench: the bit-exact reference for the gate-level runs.
# Usage: rtl_sim.sh <design dir> <out dir> [--golden]     (--golden: copy the output file to the design's GOLDEN)
# Exit status 0 when the testbench passes (PASS_REGEX).
set -euo pipefail
[[ $# -ge 2 ]] || { sed -n '3p' "$0"; exit 2; }
source "$(dirname "$0")/env.sh"
load_design "$1"
mkdir -p "$2"; OUT="$(cd "$2" && pwd)"
tb_defines
SRCS=("$TB" "${RTL[@]}")
[[ -z "${MACRO_INSTANCES:-}" ]] || SRCS+=("$SRAM22/$MACRO_CELL/$MACRO_CELL.v")    # the macro's functional model
CELL_DEFS=()
case "${RTL_SIM_CELLS:-none}" in      # RTL that instantiates library cells (clock gates) needs their models
  sky130) M="$PDK_ROOT/$PDK/libs.ref/sky130_fd_sc_hd/verilog"
          SRCS=("$M/primitives.v" "$M/sky130_fd_sc_hd.v" "${SRCS[@]}"); CELL_DEFS=(-DFUNCTIONAL -DUNIT_DELAY='#1') ;;
  asap7)  SRCS=("$TOOLS/asap7_seq_icarus.v" "${SRCS[@]}") ;;
  none) ;;
  *) echo "unknown RTL_SIM_CELLS $RTL_SIM_CELLS"; exit 2 ;;
esac
INC=(); for i in "${INCDIRS[@]}"; do INC+=(-I "$i"); done
cd "$OUT"
iverilog -g2012 -o rtl.vvp ${INC[@]+"${INC[@]}"} ${CELL_DEFS[@]+"${CELL_DEFS[@]}"} -DCLK_PERIOD_NS="$CLOCK_NS" \
  "${TB_DEFS[@]}" "${SRCS[@]}" \
  2> iverilog.log || { cat iverilog.log; exit 1; }
vvp -n rtl.vvp > sim.log 2>&1 || true
grep -E "^PASS|^FAIL|^MISMATCH|^RT:" sim.log | head -n 5 || true
sim_ok sim.log || { echo "rtl_sim: the testbench did not pass or missed real time (see $OUT/sim.log)"; exit 1; }
if [[ "${3:-}" == "--golden" ]]; then
  [[ -s "$OUT/$OUT_FILE" ]] || { echo "rtl_sim: no output file $OUT_FILE"; exit 1; }
  mkdir -p "$(dirname "$GOLDEN")"; cp "$OUT/$OUT_FILE" "$GOLDEN"; echo "golden output: $GOLDEN"
fi
