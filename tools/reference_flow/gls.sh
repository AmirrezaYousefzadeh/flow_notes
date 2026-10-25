#!/usr/bin/env bash
# Gate-level simulation of a hardened run on a token stream (Icarus Verilog): cell delays of the typical corner annotated
# from the SDF, the waveform streamed through a FIFO into the toggle counter (per-signal transition counts and high
# times; the waveform itself is never stored).
#
# Usage: flow/gls.sh <run dir> <submission dir> <session> <stream.hex> <out dir> [n_bins (default 5000)] [--zero-delay]
# Output in <out dir>: out.txt (bin x y latency_ns), sim.log, toggles.tsv, rt.json (the real-time summary, with the count
# of SDF annotation errors), and the renamed copies design.nl.v / design.sdf / design.spef that the simulation and the
# power analysis (flow/power.sh) both use: hierarchical names are made plain first (flow/tools/legal_names.py), because
# Icarus cannot annotate cells whose names contain a dot.
# Not modelled: wire delays (the SDF interconnect delays are dropped; cell delays include the load of the wires).
set -euo pipefail
[[ $# -ge 5 ]] || { sed -n '6p' "$0"; exit 2; }
F="$(cd "$(dirname "$0")" && pwd)"
source "$F/../env/env.sh" > /dev/null
RUN="$(cd "$1" && pwd -P)"
SUB="$(cd "$2" && pwd)"
SESSION="$3"
STREAM="$(cd "$(dirname "$4")" && pwd)/$(basename "$4")"
OUT="$5"
NB="${6:-5000}"
MODE="${7:-sdf}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
eval "$("$NEAT_PYTHON" "$F/../evaluate/subm.py" "$SUB/submission.json" "$SESSION")"   # INCDIR CLK_NS TOP MACRO_*
LIB=sky130_fd_sc_hd
MODELS="$PDK_ROOT/$PDK/libs.ref/$LIB/verilog"
PIN=("${NEAT_LOWPRI[@]}")
cd "$OUT"

# the toggle counter, built once (atomically: parallel measurements may start together) and rebuilt when its source changes
TOG="$F/tools/vcd_toggles"
if [[ ! "$TOG" -nt "$TOG.c" ]]; then cc -O2 -o "$TOG.$$" "$TOG.c" && mv -f "$TOG.$$" "$TOG"; fi

# plain names in the netlist, the SDF and the SPEF of the run
SDF="$(ls "$RUN"/final/sdf/nom_tt_025C_1v80/*.sdf | head -n 1)"
"$NEAT_PYTHON" "$F/tools/legal_names.py" "$RUN/final/nl/$TOP.nl.v" "$SDF" "$RUN/final/spef/nom/$TOP.nom.spef" "$OUT"
# physical-only cells of the routed netlist (taps, fill, diodes) have no simulation model: empty modules
MACRO_MODEL=()
[[ -z "$MACRO_INSTANCES" ]] || MACRO_MODEL=("$F/macros/$MACRO_CELL/$MACRO_CELL.v")
"$NEAT_PYTHON" "$F/tools/gen_phys_stubs.py" design.nl.v phys_stubs.v "$MODELS/primitives.v" "$MODELS/$LIB.v" \
  ${MACRO_MODEL[@]+"${MACRO_MODEL[@]}"}

DEFS=(-DUNIT_DELAY='#1' -DCLK_PERIOD_NS="$CLK_NS" -DN_BINS="$NB" -DPROGRESS -I "$INCDIR"
      -DSTREAM_HEX="\"$STREAM\"" -DOUT_FILE="\"$OUT/out.txt\""
      -DDUMP_PATH="\"$OUT/wave.vcd\"" -DDUMP_LEVEL=0 -DDUMP_MODULE=tb_neat.u_dut)
IMAGE="${LOAD_HEX_OVERRIDE:-$INCDIR/neat_weights.hex}"
[[ -f "$IMAGE" ]] || { echo "no configuration image $IMAGE (a design with nothing to configure ships an empty one)"; exit 1; }
[[ -s "$IMAGE" ]] && DEFS+=(-DLOAD_HEX="\"$IMAGE\"")
FLAGS=(-g2012)
# source order matters: the Icarus fixes define the include guards of the broken timing cells before the library is read
SRCS=("$MODELS/primitives.v")
if [[ "$MODE" == "--zero-delay" ]]; then
  DEFS+=(-DFUNCTIONAL)
else
  "$NEAT_PYTHON" "$F/tools/sdf_sanitize_for_icarus.py" design.sdf -o design.icarus.sdf > sdf_sanitize.log
  DEFS+=(-DSDF_ANNOTATE="\"$OUT/design.icarus.sdf\"")
  FLAGS+=(-gspecify -Ttyp)
  SRCS+=("$F/tools/sky130_timing_icarus_fixes.v")
fi
# the SRAM22 model of a declared macro: functional for zero-delay runs, with the output delay for annotated runs
if [[ -n "$MACRO_INSTANCES" ]]; then
  if [[ "$MODE" == "--zero-delay" ]]; then SRCS+=("$F/macros/$MACRO_CELL/$MACRO_CELL.v")
  else SRCS+=("$F/macros/$MACRO_CELL/${MACRO_CELL}_tdout.v"); fi
fi
SRCS+=("$MODELS/$LIB.v" phys_stubs.v design.nl.v "$F/../tb/tb_neat.v")

echo "==> compiling the gate-level simulation ($MODE, $NB bins, clock $CLK_NS ns)"
"${PIN[@]}" iverilog "${FLAGS[@]}" -o gls.vvp "${DEFS[@]}" "${SRCS[@]}" 2> iverilog.log ||
  { tail -n 20 iverilog.log; exit 1; }
rm -f wave.vcd; mkfifo wave.vcd
"${PIN[@]}" "$TOG" -o toggles.tsv wave.vcd 2> toggles.log &
TPID=$!
echo "==> running ($(date +%H:%M:%S))"
( time "${PIN[@]}" vvp -n gls.vvp ) > sim.log 2>&1 || true
# a simulation that ended before opening the waveform leaves the counter waiting on the FIFO: release it
if kill -0 $TPID 2> /dev/null && ! grep -q "window start" sim.log; then
  timeout 10 bash -c ': > wave.vcd' || kill $TPID 2> /dev/null
fi
wait $TPID || true
rm -f wave.vcd
grep -E "^TB: clock|^RT:|^PASS|^FAIL|^real" sim.log || true
cat toggles.log
# every delay of the SDF must reach its cell: an annotation error leaves cells without delays and invalidates the run
SDF_ERRORS=$(grep -c -E "SDF ERROR|Unable to match ModPath" sim.log || true)
[[ "$SDF_ERRORS" -eq 0 ]] || echo "ERROR: $SDF_ERRORS SDF annotation errors (see sim.log): the measurement is not valid"
"$NEAT_PYTHON" "$F/tools/rt_stats.py" sim.log -o rt.json --extra sdf_errors="$SDF_ERRORS" > /dev/null
[[ "$SDF_ERRORS" -eq 0 ]] && grep -q "^PASS" sim.log
