#!/usr/bin/env bash
# An ASAP7 validation design end to end (ASAP7 notes): ORFS with the LibreLane binaries at CORNER=TC over the design's
# utilisations (dense to sparse), accepted on routing DRC 0 and an own setup and hold check at TT, SS and FF with the
# extracted parasitics (tools/hold_sta.tcl, the run's SDC); then an SDF from OpenSTA, Icarus with 1 ps copies of the
# vendor models and tools/asap7_seq_icarus.v, toggles, OpenSTA power (run A, measured activities; run B, zero data)
# and the multi-PDK root-clock correction.
# Usage: asap7_run.sh <design dir> <work dir>
# Writes <work dir>/harden/harden.json and <work dir>/measure/measure.json; exit status 0 when every check passed.
set -euo pipefail
[[ $# -eq 2 ]] || { sed -n '7p' "$0"; exit 2; }
source "$(dirname "$0")/env.sh"
load_design "$1"
mkdir -p "$2"; WORK="$(cd "$2" && pwd)"
VT="${ORFS_VT:-SRAM}"
case "$VT" in SRAM) LIBVT=SRAMVT; TAG=SRAM ;; RVT) LIBVT=RVT; TAG=R ;; LVT) LIBVT=LVT; TAG=L ;; SLVT) LIBVT=SLVT; TAG=SL ;;
  *) echo "unknown ORFS_VT $VT"; exit 2 ;; esac
NLDM="$ORFS/flow/platforms/asap7/lib/NLDM"
libs() {   # <TT|FF|SS>: the five liberties of the flavour at that corner
  local c="$1" f out=""
  for f in AO INVBUF OA SEQ SIMPLE; do out+=" $(ls "$NLDM"/asap7sc7p5t_${f}_${LIBVT}_${c}_nldm_*.lib* | sort -r | head -n 1)"; done
  echo $out
}
export QT_QPA_PLATFORM=offscreen
H="$WORK/harden"; mkdir -p "$H"
ATTEMPTS="$H/attempts.tsv"
ACCEPTED=""
if [[ -f "$H/harden.json" ]]; then             # a rerun measures the accepted run again without routing it again
  ACCEPTED=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["accepted_utilisation_pct"])' "$H/harden.json")
  echo "$NAME: reusing the accepted ORFS run at $ACCEPTED %"
  UTILS=""
else
  : > "$ATTEMPTS"
fi
for U in $UTILS; do
  NICK="${NAME}_u$U"
  CFG="$H/config_u$U.mk"
  {
    echo "export PLATFORM = asap7"
    echo "export DESIGN_NAME = $TOP"
    echo "export DESIGN_NICKNAME = $NICK"
    echo "export VERILOG_FILES = ${RTL[*]}"
    echo "export SDC_FILE = $SDC"
    echo "export CORE_UTILIZATION = $U"
    echo "export PLACE_DENSITY_LB_ADDON = 0.10"
    echo "export DETAILED_ROUTE_END_ITERATION = 40"
    [[ ${#INCDIRS[@]} -eq 0 ]] || echo "export VERILOG_INCLUDE_DIRS = ${INCDIRS[*]}"
    [[ ${#SYNTH_DEFINES[@]} -eq 0 ]] || echo "export VERILOG_DEFINES = $(printf -- '-D %s ' "${SYNTH_DEFINES[@]}")"
    printf '%s\n' "${ORFS_EXTRA:-}"
  } > "$CFG"
  echo "==== $NAME: ORFS at $U % ($VT, TC)  ($(date '+%F %H:%M'))"
  T0=$(date +%s); status=0
  in_librelane bash -c "cd '$ORFS/flow' && make WORK_HOME='$H/orfs' DESIGN_CONFIG='$CFG' ASAP7_USE_VT=$VT CORNER=TC \
    NUM_CORES=$THREADS FILL_CELLS='FILLERxp5_ASAP7_75t_$TAG FILLER_ASAP7_75t_$TAG' \
    OPENROAD_EXE=\$(which openroad) OPENSTA_EXE=\$(which sta) YOSYS_EXE=\$(which yosys) KLAYOUT_CMD=\$(which klayout)" \
    > "$H/orfs_u$U.log" 2>&1 || status=$?
  R="$H/orfs/results/asap7/$NICK/base"
  verdict="pass"
  if [[ $status -ne 0 || ! -s "$R/6_final.v" ]]; then
    verdict="ORFS stopped (rc $status, see orfs_u$U.log)"
  else
    DRC=$(python3 -c 'import glob,json,sys
v=[json.load(open(f)).get("detailedroute__route__drc_errors") for f in glob.glob(sys.argv[1]+"/*.json")]
v=[x for x in v if x is not None]; print(v[-1] if v else "none")' "$H/orfs/logs/asap7/$NICK/base")
    [[ "$DRC" == 0 ]] || verdict="routing DRC $DRC"
    if [[ "$verdict" == pass ]]; then
      for c in TT SS FF; do
        LIB_SC="$(libs $c)" NETLIST="$R/6_final.v" TOP="$TOP" SPEF="$R/6_final.spef" SDC="$R/6_final.sdc" \
          OUT="$H/signoff_u${U}_$c.json" in_librelane sta -no_splash -exit "$TOOLS/hold_sta.tcl" \
          > "$H/signoff_u${U}_$c.log" 2>&1 || verdict="own sign-off fails at $c (signoff_u${U}_$c.log)"
        n=$(grep -c "spef.*not found" "$H/signoff_u${U}_$c.log" || true)
        [[ "$n" -eq 0 ]] || verdict="$n unmatched SPEF entries at $c"
      done
    fi
  fi
  printf '%s\t%s\t%s\n' "$U" "$(( ($(date +%s) - T0) / 60 ))" "$verdict" >> "$ATTEMPTS"
  echo "   $verdict"
  [[ "$verdict" == pass ]] && { ACCEPTED=$U; break; }
done
[[ -n "$ACCEPTED" ]] || { echo "$NAME: no utilisation accepted"; exit 1; }
NICK="${NAME}_u$ACCEPTED"; R="$H/orfs/results/asap7/$NICK/base"
[[ -f "$H/harden.json" ]] || python3 - "$H" "$NICK" "$ACCEPTED" "$(versions_json)" <<'PY'
import glob, json, sys
h, nick, util, versions = sys.argv[1], sys.argv[2], int(sys.argv[3]), json.loads(sys.argv[4])
rep = {}
for f in sorted(glob.glob(f"{h}/orfs/logs/asap7/{nick}/base/*.json")) + sorted(glob.glob(f"{h}/orfs/reports/asap7/{nick}/base/*.json")):
    try: rep.update(json.load(open(f)))
    except ValueError: pass
so = {c: json.load(open(f"{h}/signoff_u{util}_{c}.json")) for c in ("TT", "SS", "FF")}
attempts = [dict(zip(("utilisation_pct", "minutes", "verdict"), l.rstrip("\n").split("\t"))) for l in open(f"{h}/attempts.tsv")]
summary = {"accepted_utilisation_pct": util, "attempts": attempts,
           "cells": rep.get("finish__design__instance__count__stdcell", 0) - rep.get("finish__design__instance__count__class:fill_cell", 0)
                    - rep.get("finish__design__instance__count__class:tap_cell", 0),
           "cell_area_um2": rep.get("finish__design__instance__area__stdcell"),
           "drc_errors": rep.get("detailedroute__route__drc_errors"),
           "max_slew_violations": rep.get("finish__timing__drv__max_slew"),
           "setup_ws_ns": min(s["setup_ws_ns"] for s in so.values()), "hold_ws_ns": min(s["hold_ws_ns"] for s in so.values()),
           "signoff": so, "versions": versions}
json.dump(summary, open(f"{h}/harden.json", "w"), indent=1)
print(json.dumps({k: v for k, v in summary.items() if k not in ("attempts", "signoff", "versions")}))
PY

# ---- measurement
M="$WORK/measure"; mkdir -p "$M"; OUT="$M"; cd "$M"
tb_defines
TT_LIBS="$(libs TT)"
echo "==> $NAME: SDF from OpenSTA, plain names, 1 ps models"
LIB_SC="$TT_LIBS" TOP="$TOP" NETLIST="$R/6_final.v" SPEF="$R/6_final.spef" PERIOD_NS="$(( CLOCK_NS * 1000 ))" \
  CLK_PORT="$CLOCK_PORT" SDF_OUT="$M/orig.sdf" in_librelane sta -no_splash -exit "$TOOLS/write_sdf_sta.tcl" > write_sdf.log 2>&1
python3 "$TOOLS/legal_names.py" "$R/6_final.v" orig.sdf "$R/6_final.spef" "$M" > legal_names.log
python3 "$TOOLS/sdf_sanitize_for_icarus.py" design.sdf -o design.icarus.sdf > sdf_sanitize.log
MODELS=()
for f in AO INVBUF OA SIMPLE; do
  src=$(ls /media/pdk/asap7sc7p5t_28/Verilog/asap7sc7p5t_${f}_${VT}_TT_*.v | head -n 1)
  sed 's#`timescale 1ns/10ps#`timescale 1ns/1ps#; s#`timescale 1ns / 10ps#`timescale 1ns/1ps#' "$src" > "model_$f.v"
  MODELS+=("$M/model_$f.v")
done
printf '`timescale 1ns/1ps\n' > timescale.v
python3 "$TOOLS/gen_phys_stubs.py" design.nl.v phys_stubs.v "${MODELS[@]}" "$TOOLS/asap7_seq_icarus.v" > /dev/null
cc -O2 -o vcd_toggles "$TOOLS/vcd_toggles.c"
INC=(); for i in "${INCDIRS[@]}"; do INC+=(-I "$i"); done
echo "==> gate-level simulation (sdf, $UNITS ${UNIT_NAME}s)"
iverilog -g2012 -gspecify -Ttyp -o gls.vvp -DCLK_PERIOD_NS="$CLOCK_NS" ${INC[@]+"${INC[@]}"} \
  -DSDF_ANNOTATE="\"$M/design.icarus.sdf\"" -DDUMP_PATH="\"$M/wave.vcd\"" -DDUMP_LEVEL=0 -DDUMP_MODULE="$TB_TOP.$DUT" \
  "${TB_DEFS[@]}" timescale.v "${MODELS[@]}" "$TOOLS/asap7_seq_icarus.v" phys_stubs.v design.nl.v "$TB" \
  2> iverilog.log || { tail -n 20 iverilog.log; exit 1; }
rm -f wave.vcd; mkfifo wave.vcd
./vcd_toggles -o toggles.tsv wave.vcd 2> toggles.log &
TPID=$!; T0=$(date +%s)
vvp -n gls.vvp > sim.log 2>&1 || true
kill -0 $TPID 2> /dev/null && { timeout 10 bash -c ': > wave.vcd' || kill $TPID 2> /dev/null; }
wait $TPID || true; rm -f wave.vcd
SIM_MIN=$(( ($(date +%s) - T0) / 60 ))
SDF_ERRORS=$(grep -c -E "SDF ERROR|Unable to match ModPath" sim.log || true)
PASSED=0; sim_ok sim.log && PASSED=1        # PASS, no FAIL/MISMATCH, no real-time overrun
BITEXACT=null
if [[ -n "${GOLDEN:-}" ]]; then BITEXACT=false; cmp -s "$M/$OUT_FILE" "$GOLDEN" && BITEXACT=true; fi
echo "   SDF errors $SDF_ERRORS, testbench pass $PASSED, bit-exact against RTL $BITEXACT ($SIM_MIN min)"
[[ "$SDF_ERRORS" -eq 0 && "$PASSED" -eq 1 && "$BITEXACT" != false ]] ||
  { grep -E "^FAIL|^MISMATCH|SDF ERROR" sim.log | head -n 5; echo "$NAME: the simulation is not valid: not measured"; exit 1; }

echo "==> activities and OpenSTA power (run A measured, run B zero data)"
python3 "$TOOLS/toggles_to_activity.py" toggles.tsv --scope "$TB_TOP/$DUT" --period-s "${CLOCK_NS}e-9" \
  -o activity.tcl --summary activity_summary.json
for run in A B; do
  mkdir -p "sta_$run"
  ( export TOP NETLIST="$M/design.nl.v" SPEF="$M/design.spef" LIB_SC="$TT_LIBS" PERIOD_NS="$(( CLOCK_NS * 1000 ))" \
      CLK_PORT="$CLOCK_PORT" OUT="$M/sta_$run" ACT_TCL="$M/activity.tcl"
    [[ $run == B ]] && export ZERO_DATA=1
    in_librelane sta -no_splash -exit "$TOOLS/power_sta.tcl" ) > "sta_$run/sta.log" 2>&1 || { tail -n 20 "sta_$run/sta.log"; exit 1; }
  n=$(grep -c "spef.* not found" "sta_$run/sta.log" || true)
  [[ "$n" -eq 0 ]] || { echo "$n SPEF entries without a match (sta_$run)"; exit 1; }
  boxes=$(grep "Creating black box" "sta_$run/sta.log" | grep -vE "TAPCELL|FILLER|DECAP" || true)
  [[ -z "$boxes" ]] || { echo "cells without a liberty: $boxes"; exit 1; }
done
python3 "$TOOLS/check_annotation.py" sta_A design.nl.v $TT_LIBS > sta_A/annotation.log || { cat sta_A/annotation.log; exit 1; }
DUTY=$(python3 - toggles.tsv "$TB_TOP/$DUT/$CLOCK_PORT" "$CLOCK_NS" <<'PY'
import sys
tsv, clk, period = sys.argv[1], sys.argv[2], float(sys.argv[3])
head, tc = {}, None
for line in open(tsv):
    f = line.rstrip("\n").split("\t")
    if line.startswith("#"): head[f[0][1:]] = float(f[1])
    elif f[0] == clk and len(f) == 3: tc = float(f[1])
print(tc / 2 * period / ((head["time_max"] - head["time_min"]) * head["timescale_s"] * 1e9))
PY
)
echo "==> root-clock correction (clock duty $DUTY)"
python3 "$TOOLS/root_clock_correction_multipdk.py" design.nl.v "$CLOCK_PORT" "$DUTY" sta_A/power_vcd_by_instance.rpt \
  sta_B/power_vcd_by_instance.rpt -o root_clock_correction.json | tail -n 2
python3 - "$M" "$DUTY" "$UNITS" "$UNIT_NAME" "$SIM_MIN" "$BITEXACT" "$(versions_json)" <<'PY'
import json, sys
m_dir, duty, units, unit, sim_min, bitexact, versions = sys.argv[1:]
corr = json.load(open(f"{m_dir}/root_clock_correction.json"))
act = json.load(open(f"{m_dir}/activity_summary.json"))
total, window_s = corr["corrected_report"], act["duration_s"]
m = {"p_total_uW": total["total"] * 1e6, "p_leak_uW": total["leakage"] * 1e6,
     "p_dyn_uW": (total["total"] - total["leakage"]) * 1e6, "p_sta_uW": corr["report"]["total"] * 1e6,
     "root_clock_removed_uW": corr["removed_W"] * 1e6, "clock_duty": float(duty), "window_s": window_s,
     "units": int(units), "unit": unit, "root_cells_missing_in_B": len(corr.get("root_cells_missing_in_B", []))}
m[f"e_{unit}_nJ"] = m["p_total_uW"] * window_s / int(units) * 1e3
m[f"e_dyn_{unit}_nJ"] = m["p_dyn_uW"] * window_s / int(units) * 1e3
m.update({"pin_activities": act["pin_variables"], "sdf_errors": 0, "bit_exact": json.loads(bitexact), "sim_mode": "sdf",
          "gls_minutes": int(sim_min), "versions": json.loads(versions)})
json.dump(m, open(f"{m_dir}/measure.json", "w"), indent=1)
print(f"P {m['p_total_uW']:.4f} µW (leakage {m['p_leak_uW']:.4f}, dynamic {m['p_dyn_uW']:.4f}; P_STA {m['p_sta_uW']:.4f}); "
      f"E/{unit} {m[f'e_{unit}_nJ']:.5f} nJ")
PY
