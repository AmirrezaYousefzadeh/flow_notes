#!/usr/bin/env bash
# Measure a hardened sky130 validation design (sky130 notes 7 and 8): SDF-annotated Icarus gate-level simulation of the
# design's testbench (typical corner), compared bit for bit with the RTL's golden output, activity streamed through a
# FIFO into the toggle counter, per-pin OpenSTA power, the SRAM22 state correction and the root-clock correction.
# Usage: sky130_measure.sh <design dir> <run dir> <out dir>
# Writes <out dir>/measure.json; exit status 0 when every check passed.
set -euo pipefail
[[ $# -eq 3 ]] || { sed -n '5p' "$0"; exit 2; }
source "$(dirname "$0")/env.sh"
load_design "$1"
RUN="$(cd "$2" && pwd -P)"
mkdir -p "$3"; OUT="$(cd "$3" && pwd)"
tb_defines
LIB=sky130_fd_sc_hd
MODELS="$PDK_ROOT/$PDK/libs.ref/$LIB/verilog"
cd "$OUT"

echo "==> $NAME: plain names, simulation stubs, Icarus SDF"
python3 "$TOOLS/legal_names.py" "$RUN/final/nl/$TOP.nl.v" "$(ls "$RUN"/final/sdf/nom_tt_025C_1v80/*.sdf | head -n 1)" \
  "$RUN/final/spef/nom/$TOP.nom.spef" "$OUT" > legal_names.log
MACRO_TDOUT=(); MACRO_V=()
if [[ -n "${MACRO_INSTANCES:-}" ]]; then
  MACRO_V=("$SRAM22/$MACRO_CELL/$MACRO_CELL.v"); MACRO_TDOUT=("$SRAM22/$MACRO_CELL/${MACRO_CELL}_tdout.v")
fi
python3 "$TOOLS/gen_phys_stubs.py" design.nl.v phys_stubs.v "$MODELS/primitives.v" "$MODELS/$LIB.v" \
  ${MACRO_V[@]+"${MACRO_V[@]}"} > /dev/null
cc -O2 -o vcd_toggles "$TOOLS/vcd_toggles.c"
INC=(); for i in "${INCDIRS[@]}"; do INC+=(-I "$i"); done
if [[ "${SIM_MODE:-sdf}" == zero ]]; then          # zero delay: functional models, no glitches (sky130 notes 7.4)
  MODE_ARGS=(-DFUNCTIONAL); MODE_SRCS=("$MODELS/primitives.v" ${MACRO_V[@]+"${MACRO_V[@]}"})
else
  python3 "$TOOLS/sdf_sanitize_for_icarus.py" design.sdf -o design.icarus.sdf > sdf_sanitize.log
  MODE_ARGS=(-gspecify -Ttyp -DSDF_ANNOTATE="\"$OUT/design.icarus.sdf\"")
  MODE_SRCS=("$MODELS/primitives.v" "$TOOLS/sky130_timing_icarus_fixes.v" ${MACRO_TDOUT[@]+"${MACRO_TDOUT[@]}"})
fi

echo "==> gate-level simulation (${SIM_MODE:-sdf}, $UNITS ${UNIT_NAME}s)"
iverilog -g2012 "${MODE_ARGS[@]}" -o gls.vvp -DUNIT_DELAY='#1' -DCLK_PERIOD_NS="$CLOCK_NS" ${INC[@]+"${INC[@]}"} \
  -DDUMP_PATH="\"$OUT/wave.vcd\"" -DDUMP_LEVEL=0 -DDUMP_MODULE="$TB_TOP.$DUT" "${TB_DEFS[@]}" \
  "${MODE_SRCS[@]}" "$MODELS/$LIB.v" phys_stubs.v design.nl.v "$TB" 2> iverilog.log ||
  { tail -n 20 iverilog.log; exit 1; }
rm -f wave.vcd; mkfifo wave.vcd
./vcd_toggles -o toggles.tsv wave.vcd 2> toggles.log &
TPID=$!
T0=$(date +%s)
vvp -n gls.vvp > sim.log 2>&1 || true
# a simulation that ended before opening the waveform leaves the counter waiting on the FIFO: release it
kill -0 $TPID 2> /dev/null && { timeout 10 bash -c ': > wave.vcd' || kill $TPID 2> /dev/null; }
wait $TPID || true
rm -f wave.vcd
SIM_MIN=$(( ($(date +%s) - T0) / 60 ))
SDF_ERRORS=$(grep -c -E "SDF ERROR|Unable to match ModPath" sim.log || true)
PASSED=0; sim_ok sim.log && PASSED=1        # PASS, no FAIL/MISMATCH, no real-time overrun
BITEXACT=null
if [[ -n "${GOLDEN:-}" ]]; then BITEXACT=false; cmp -s "$OUT/$OUT_FILE" "$GOLDEN" && BITEXACT=true; fi
echo "   SDF errors $SDF_ERRORS, testbench pass $PASSED, bit-exact against RTL $BITEXACT ($SIM_MIN min)"
[[ "$SDF_ERRORS" -eq 0 && "$PASSED" -eq 1 && "$BITEXACT" != false ]] ||
  { grep -E "^FAIL|^MISMATCH|SDF ERROR" sim.log | head -n 5; echo "$NAME: the simulation is not valid: not measured"; exit 1; }

echo "==> activities and OpenSTA power"
python3 "$TOOLS/toggles_to_activity.py" toggles.tsv --scope "$TB_TOP/$DUT" --period-s "${CLOCK_NS}e-9" \
  -o activity.tcl --summary activity_summary.json
export TOP PERIOD_NS="$CLOCK_NS" NETLIST="$OUT/design.nl.v" SPEF="$OUT/design.spef" CLK_PORT="$CLOCK_PORT"
export LIB_SC="$PDK_ROOT/$PDK/libs.ref/$LIB/lib/${LIB}__tt_025C_1v80.lib" MACRO_INST="${MACRO_INSTANCES:-}" LIB_SRAM=""
[[ -z "${MACRO_INSTANCES:-}" ]] || LIB_SRAM="$SRAM22/$MACRO_CELL/${MACRO_CELL}_tt_025C_1v80_pwr.lib"
export LIB_SRAM
sta_run() {   # <out dir> [env assignments]
  local out="$1"; shift
  mkdir -p "$out"
  ( [[ $# -eq 0 ]] || export "$@"; export OUT="$out" ACT_TCL="$OUT/activity.tcl"
    in_librelane sta -no_splash -exit "$TOOLS/power_sta.tcl" ) > "$out/sta.log" 2>&1 || { tail -n 20 "$out/sta.log"; exit 1; }
  local unmatched boxes
  unmatched=$(grep -c "spef.* not found" "$out/sta.log" || true)
  boxes=$(grep "Creating black box" "$out/sta.log" | grep -vE "tapvpwrvgnd|__fill_|__decap_|__diode_" || true)
  [[ "$unmatched" -eq 0 ]] || { echo "$unmatched SPEF entries without a match (see $out/sta.log)"; exit 1; }
  [[ -z "$boxes" ]] || { echo "cells without a liberty: $boxes"; exit 1; }
  python3 "$TOOLS/check_annotation.py" "$out" "$NETLIST" "$LIB_SC" ${LIB_SRAM:+"$LIB_SRAM"} > "$out/annotation.log" ||
    { cat "$out/annotation.log"; exit 1; }
}
sta_run "$OUT/sta"
REPORT="$OUT/sta"
if [[ -n "${MACRO_INSTANCES:-}" ]]; then
  python3 "$TOOLS/macro_state_correction.py" gen activity.tcl "$NETLIST" "$LIB_SRAM" --cells "$MACRO_CELL" \
    -o macro_cond.tcl --json macro_cond.json > /dev/null
  sta_run "$OUT/sta_macro" EXTRA_ACT_TCL="$OUT/macro_cond.tcl"
  python3 "$TOOLS/macro_state_correction.py" compare "$OUT/sta" "$OUT/sta_macro" "$NETLIST" --cells "$MACRO_CELL" \
    --json macro_state_correction.json > /dev/null
  REPORT="$OUT/sta_macro"
fi

# the clock duty from the toggle counts of the clock port: transitions / 2 cycles of CLOCK_NS within the window
DUTY=$(python3 - toggles.tsv "$TB_TOP/$DUT/$CLOCK_PORT" "$CLOCK_NS" <<'PY'
import sys
tsv, clk, period = sys.argv[1], sys.argv[2], float(sys.argv[3])
head, tc = {}, None
for line in open(tsv):
    f = line.rstrip("\n").split("\t")
    if line.startswith("#"): head[f[0][1:]] = float(f[1])
    elif f[0] == clk and len(f) == 3: tc = float(f[1])
window_ns = (head["time_max"] - head["time_min"]) * head["timescale_s"] * 1e9
print(tc / 2 * period / window_ns)
PY
)
echo "==> root-clock correction (clock duty $DUTY)"
python3 "$TOOLS/root_clock_correction.py" "$NETLIST" "$CLOCK_PORT" "$DUTY" "$REPORT" -o root_clock_correction.json

SIM_MODE="${SIM_MODE:-sdf}" python3 - "$OUT" "$DUTY" "$REPORT" "$UNITS" "$UNIT_NAME" "$SIM_MIN" "$BITEXACT" "$(versions_json)" <<'PY'
import json, os, sys
out, duty, report, units, unit, sim_min, bitexact, versions = sys.argv[1:]
corr = json.load(open(f"{out}/root_clock_correction.json"))
act = json.load(open(f"{out}/activity_summary.json"))
total, window_s = corr["corrected"], act["duration_s"]
m = {"p_total_uW": total["total"] * 1e6, "p_leak_uW": total["leakage"] * 1e6,
     "p_dyn_uW": (total["total"] - total["leakage"]) * 1e6,
     "p_sta_uW": corr["report"]["total"] * 1e6, "root_clock_removed_uW": corr["removed_W"] * 1e6,
     "clock_duty": float(duty), "window_s": window_s, "units": int(units), "unit": unit}
m[f"e_{unit}_nJ"] = m["p_total_uW"] * window_s / int(units) * 1e3
m[f"e_dyn_{unit}_nJ"] = m["p_dyn_uW"] * window_s / int(units) * 1e3
m["sta_groups_uW"] = {f[0].lower(): float(f[4]) * 1e6 for f in (l.split() for l in open(f"{report}/power_vcd.rpt"))
                      if len(f) == 6 and f[0] in ("Sequential", "Combinational", "Clock", "Macro")}
if os.path.exists(f"{out}/macro_state_correction.json"):
    m["macro_correction_uW"] = json.load(open(f"{out}/macro_state_correction.json"))["added_internal_W"] * 1e6
m.update({"pin_activities": act["pin_variables"], "sdf_errors": 0, "bit_exact": json.loads(bitexact),
          "sim_mode": os.environ.get("SIM_MODE", "sdf"),
          "gls_minutes": int(sim_min), "versions": json.loads(versions)})
json.dump(m, open(f"{out}/measure.json", "w"), indent=1)
print(f"P {m['p_total_uW']:.4f} µW (leakage {m['p_leak_uW']:.4f}, dynamic {m['p_dyn_uW']:.4f}; P_STA {m['p_sta_uW']:.4f}, "
      f"root clock removed {m['root_clock_removed_uW']:.4f}); E/{unit} {m[f'e_{unit}_nJ']:.4f} nJ")
PY
