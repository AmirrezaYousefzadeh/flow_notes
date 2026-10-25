#!/usr/bin/env bash
# Average power of a hardened run over a gate-level simulation window (flow/gls.sh), with OpenSTA: typical liberty,
# extracted parasitics, propagated clock, and the measured activity of every pin.
#
# Usage: flow/power.sh <run dir> <gls out dir> <clock_ns> <out dir>              Output: <out dir>/power.json
# Environment (set by flow/measure.sh from evaluate/subm.py): TOP, and MACRO_CELL / MACRO_INSTANCES for SRAM22 designs.
# The number:
#   P = P_STA - (1 - d) * P_root  [+ the macro state correction, part of P_STA of the conditioned run]
# P_STA is OpenSTA's total with the measured activities. OpenSTA charges the clock network between the clock port and the
# first clock gate at the full clock rate, but the testbench stops the clock between bins: P_root, the dynamic power of
# that root network (flow/tools/root_clock_correction.py), is scaled by the measured clock duty d. For SRAM22 macros,
# OpenSTA weights the read energy with the time-averaged state of the control pins, which are idle while the clock is
# stopped; those state duties are conditioned on the clock running (flow/tools/macro_state_correction.py) and the
# report of that run is the one corrected. Leakage is included (decap-free fill: logic and macros only).
set -euo pipefail
[[ $# -eq 4 ]] || { sed -n '5p' "$0"; exit 2; }
F="$(cd "$(dirname "$0")" && pwd)"
source "$F/../env/env.sh" > /dev/null
RUN="$(cd "$1" && pwd -P)"
GLS="$(cd "$2" && pwd)"
CLK_NS="$3"
OUT="$4"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
MACRO_CELL="${MACRO_CELL:-}"
MACRO_INSTANCES="${MACRO_INSTANCES:-}"
export TOP="${TOP:-neat_decoder}" PERIOD_NS="$CLK_NS"
export NETLIST="$GLS/design.nl.v" SPEF="$GLS/design.spef"                 # the renamed copies of flow/gls.sh
export LIB_SC="$PDK_ROOT/$PDK/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib"
export MACRO_INST="$MACRO_INSTANCES"
if [[ -n "$MACRO_INSTANCES" ]]; then
  export LIB_SRAM="$F/macros/$MACRO_CELL/${MACRO_CELL}_tt_025C_1v80_pwr.lib"   # the supply-only power liberty
  [[ -f "$LIB_SRAM" ]] || { echo "no power liberty $LIB_SRAM"; exit 1; }
fi
[[ -f "$NETLIST" && -f "$SPEF" ]] || { echo "no renamed netlist and SPEF in $GLS (run flow/gls.sh first)"; exit 1; }

sta_run() {   # <out dir> [env assignments]: OpenSTA inside the LibreLane environment, then the sanity checks of its log
  local out="$1"; shift
  mkdir -p "$out"
  env "$@" OUT="$out" ACT_TCL="$OUT/activity.tcl" "${NEAT_LOWPRI[@]}" \
    nix --extra-experimental-features "nix-command flakes" develop --accept-flake-config "$LIBRELANE_ROOT" -c \
    sta -no_splash -exit "$F/tools/power_sta.tcl" > "$out/sta.log" 2>&1 || { tail -n 20 "$out/sta.log"; exit 1; }
  local unmatched boxes
  unmatched=$(grep -c "spef.* not found" "$out/sta.log" || true)
  boxes=$(grep "Creating black box" "$out/sta.log" | grep -vE "tapvpwrvgnd|__fill_|__decap_" || true)
  [[ "$unmatched" -eq 0 ]] || { echo "$unmatched SPEF entries without a match in the netlist (see $out/sta.log)"; exit 1; }
  [[ -z "$boxes" ]] || { echo "cells without a liberty model: $boxes"; exit 1; }
  "$NEAT_PYTHON" "$F/tools/check_annotation.py" "$out" "$NETLIST" "$LIB_SC" ${LIB_SRAM:+"$LIB_SRAM"} > "$out/annotation.log" ||
    { cat "$out/annotation.log"; exit 1; }                # a measured activity that missed its pin
}

echo "==> activities from $GLS/toggles.tsv"
"$NEAT_PYTHON" "$F/tools/toggles_to_activity.py" "$GLS/toggles.tsv" --scope tb_neat/u_dut --period-s "$CLK_NS"e-9 \
  -o "$OUT/activity.tcl" --summary "$OUT/activity_summary.json"
echo "==> OpenSTA: measured activities"
sta_run "$OUT/sta"
REPORT="$OUT/sta"
if [[ -n "$MACRO_INSTANCES" ]]; then
  echo "==> macro state correction"
  "$NEAT_PYTHON" "$F/tools/macro_state_correction.py" gen "$OUT/activity.tcl" "$NETLIST" "$LIB_SRAM" --cells "$MACRO_CELL" \
    -o "$OUT/macro_cond.tcl" --json "$OUT/macro_cond.json"
  sta_run "$OUT/sta_macro" EXTRA_ACT_TCL="$OUT/macro_cond.tcl"
  "$NEAT_PYTHON" "$F/tools/macro_state_correction.py" compare "$OUT/sta" "$OUT/sta_macro" "$NETLIST" --cells "$MACRO_CELL" \
    --json "$OUT/macro_state_correction.json"
  REPORT="$OUT/sta_macro"
fi
DUTY=$("$NEAT_PYTHON" - "$GLS/rt.json" "$CLK_NS" <<'PY'
import json, sys
rt = json.load(open(sys.argv[1]))
print(rt["clk_cycles_in_window"] * float(sys.argv[2]) / rt["window_ns"])     # the fraction of the window the clock ran
PY
)
echo "==> root-clock correction (clock duty $DUTY)"
"$NEAT_PYTHON" "$F/tools/root_clock_correction.py" "$NETLIST" clk "$DUTY" "$REPORT" -o "$OUT/root_clock_correction.json"

"$NEAT_PYTHON" - "$OUT/root_clock_correction.json" "$GLS/rt.json" "$OUT/power.json" "$DUTY" \
    "$OUT/macro_state_correction.json" "$REPORT/power_vcd.rpt" <<'PY'
import json, os, sys
corr, rt = json.load(open(sys.argv[1])), json.load(open(sys.argv[2]))
out, duty, macro, groups = sys.argv[3], float(sys.argv[4]), sys.argv[5], sys.argv[6]
total, window_s = corr["corrected"], rt["window_ns"] * 1e-9
power = {
    "p_total_uW": total["total"] * 1e6,                 # average power over the real-time window
    "p_leak_uW": total["leakage"] * 1e6,
    "p_dyn_uW": (total["total"] - total["leakage"]) * 1e6,
    "p_internal_uW": total["internal"] * 1e6,
    "p_switching_uW": total["switching"] * 1e6,
    "p_sta_uW": corr["report"]["total"] * 1e6,          # OpenSTA's total before the root-clock correction
    "root_clock_removed_uW": corr["removed_W"] * 1e6,
    "clock_duty": duty, "window_s": window_s, "bins": rt["bins"], "events": rt["events"],
}
# information: OpenSTA's group totals before the root-clock correction (a combinational share near zero means lost activity)
power["sta_groups_uW"] = {f[0].lower(): float(f[4]) * 1e6 for f in (line.split() for line in open(groups))
                          if len(f) == 6 and f[0] in ("Sequential", "Combinational", "Clock", "Macro")}
if os.path.exists(macro):
    power["macro_correction_uW"] = json.load(open(macro))["added_internal_W"] * 1e6   # information: already in P_STA
power["e_bin_nJ"] = power["p_total_uW"] * window_s / rt["bins"] * 1e3
power["e_dyn_bin_nJ"] = power["p_dyn_uW"] * window_s / rt["bins"] * 1e3
json.dump(power, open(out, "w"), indent=1)
print(f"P_avg {power['p_total_uW']:.4f} µW (leakage {power['p_leak_uW']:.4f}, dynamic {power['p_dyn_uW']:.4f}"
      + (f", of which macro state correction {power['macro_correction_uW']:.4f}" if "macro_correction_uW" in power else "")
      + f"); E/bin {power['e_bin_nJ']:.3f} nJ over {rt['bins']} bins")
PY
