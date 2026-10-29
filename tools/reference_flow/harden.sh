#!/usr/bin/env bash
# Harden a submission with LibreLane under the challenge's fixed flow (RULES.md, section 5).
#
# Usage: flow/harden.sh <submission dir> <session> <work dir> [utilisations, e.g. "30 25" (experiments only)]
#        SYNTH_ONLY=1 flow/harden.sh <submission dir> <session> <work dir>    synthesis only, a size estimate in minutes
# The flow runs once, from synthesis to sign-off STA, at the utilisation declared in submission.json (utilization_pct;
# placement density = utilisation + 10 %), and falls back to 20 % when none is declared or the declared one does not
# close. A run is accepted when flow/tools/check_metrics.py passes it: routing DRC clean, setup and hold met at the
# typical corner, no power-grid violation, at most CELL_CAP standard cells (default 300000, tap cells excluded). The
# timing is that of flow/tools/signoff_sta.tcl on the renamed netlist and SPEF (flow/tools/legal_names.py), so that the
# nets inside sub-modules keep their parasitics; LibreLane's own sign-off loses them.
# Designs with SRAM22 macros are synthesised first, for their standard-cell area, and get an absolute floorplan with
# the macros in a column on the left (flow/tools/macro_config.py); the macro's GDS is fetched when missing.
# A watchdog stops an attempt whose detailed routing cannot converge (more than 500 000 violations after 3 iterations,
# more than 20 000 after 6, more than 3 000 after 10), that completes no routing iteration for WATCHDOG_IDLE_H hours
# (default 12), or that runs longer than WATCHDOG_MAX_H hours (default 36).
# Result: <work dir>/runs/accepted -> the accepted run, and <work dir>/harden.json (summary, attempts, tool versions).
set -euo pipefail
[[ $# -ge 3 ]] || { sed -n '4,5p' "$0"; exit 2; }
F="$(cd "$(dirname "$0")" && pwd)"
source "$F/../env/env.sh" > /dev/null
SUB="$(cd "$1" && pwd)"
SESSION="$2"
WORK="$3"
UTILS="${4:-}"
IDLE_LIMIT_S=$(( ${WATCHDOG_IDLE_H:-12} * 3600 ))
MAX_LIMIT_S=$(( ${WATCHDOG_MAX_H:-36} * 3600 ))
mkdir -p "$WORK/logs"
WORK="$(cd "$WORK" && pwd)"
eval "$("$NEAT_PYTHON" "$F/../evaluate/subm.py" "$SUB/submission.json" "$SESSION")"   # RTL_FILES INCDIR CLK_NS UTIL ...
if [[ -z "$UTILS" ]]; then
  UTILS="$UTIL"; [[ "$UTIL" != "20" ]] && UTILS="$UTIL 20"     # the declared utilisation, then the 20 % fallback
fi
for U in $UTILS; do [[ "$U" =~ ^[0-9]+$ ]] || { echo "utilisations must be whole numbers: $UTILS"; exit 2; }; done

# ---- the configuration of this submission, from the template
DRT_THREADS=$(( NEAT_THREADS - 2 )); [[ $DRT_THREADS -lt 1 ]] && DRT_THREADS=1
"$NEAT_PYTHON" - "$F/config.template.yaml" "$WORK/config.template.yaml" "$RTL_FILES" "$INCDIR" "$CLK_NS" \
    "$F/neat_decoder.sdc" "$DRT_THREADS" <<'PY'
import sys
template, out, files, incdir, clk, sdc, drt_threads = sys.argv[1:]
text = open(template).read()
text = text.replace("@DRT_THREADS@", drt_threads).replace("@CLK@", clk).replace("@SDC@", f'"{sdc}"')
text = text.replace("@FILES@", "[" + ", ".join(f'"{f}"' for f in files.split()) + "]")
text = text.replace("@INCDIRS@", f'["{incdir}"]')
open(out, "w").write(text)
PY
if [[ -n "$MACRO_INSTANCES" && ! -f "$F/macros/$MACRO_CELL/$MACRO_CELL.gds" ]]; then
  "$F/macros/fetch.sh"                                    # LibreLane checks every file of the configuration at load time
fi

# ---- one LibreLane run, and how to stop it
ACTIVE=""                                                 # process group of the running LibreLane, if any
run_librelane() {   # <config> <run tag> <last step> <log>: in the background, as the leader of its own process group
  ( cd "$WORK" && exec setsid "${NEAT_LOWPRI[@]}" \
      nix --extra-experimental-features "nix-command flakes" develop --accept-flake-config "$LIBRELANE_ROOT" -c \
      python3 -m librelane --pdk-root "$PDK_ROOT" --pdk "$PDK" --manual-pdk --run-tag "$2" --overwrite --to "$3" "$1" \
    ) > "$4" 2>&1 &
  ACTIVE=$!                                               # setsid did not fork: this pid leads the group of every tool
}
stop_group() {     # <pgid>: TERM to the whole group, KILL after a minute
  kill -TERM -- "-$1" 2> /dev/null || return 0
  for _ in {1..12}; do kill -0 -- "-$1" 2> /dev/null || return 0; sleep 5; done
  kill -KILL -- "-$1" 2> /dev/null || true
}
trap '[[ -n "$ACTIVE" ]] && stop_group "$ACTIVE"' INT TERM EXIT
wait_librelane() {  # wait for the active run without a watchdog; returns its exit status
  local status=0; wait "$ACTIVE" || status=$?; ACTIVE=""; return $status
}

synthesise() {     # <config>: synthesis only; the metrics of state_out.json
  sed -e "s/@UTIL@/50/" -e "s/@DENS@/60/" "$WORK/config.template.yaml" > "$1"
  [[ -z "$MACRO_INSTANCES" ]] ||
    "$NEAT_PYTHON" "$F/tools/macro_config.py" "$1" "$F/macros" "$MACRO_CELL" $MACRO_INSTANCES --synthesis-only
  run_librelane "$1" synth Yosys.Synthesis "$WORK/logs/librelane_synth.log"
  wait_librelane || { tail -n 5 "$WORK/logs/librelane_synth.log"; exit 1; }
}

if [[ "${SYNTH_ONLY:-0}" == "1" ]]; then
  echo "==== $SESSION: synthesis only, clock $CLK_NS ns  ($(date +%H:%M))"
  synthesise "$WORK/config_synth.yaml"
  "$NEAT_PYTHON" - "$WORK/runs/synth" "$WORK/synth.json" "$SESSION" "$CLK_NS" <<'PY'
import glob, json, sys
run, out, session, clk = sys.argv[1:]
state = json.load(open(glob.glob(f"{run}/*-yosys-synthesis/state_out.json")[0]))["metrics"]
summary = {"session": session, "clock_period_ns": float(clk),
           "cells_after_synthesis": state.get("design__instance__count"),
           "cell_area_after_synthesis_um2": state.get("design__instance__area"),
           "note": "before placement and routing: the routed netlist has more cells (buffers, hold fixes)"}
json.dump(summary, open(out, "w"), indent=1)
print(f"   cells after synthesis {summary['cells_after_synthesis']}, "
      f"cell area {summary['cell_area_after_synthesis_um2']:.0f} µm²")
PY
  exit 0
fi

STD_AREA=""
if [[ -n "$MACRO_INSTANCES" ]]; then
  echo "==== $SESSION: macros $MACRO_INSTANCES; synthesis first, for the standard-cell area  ($(date +%H:%M))"
  synthesise "$WORK/config_synth.yaml"
  STD_AREA=$("$NEAT_PYTHON" - "$WORK/runs/synth" <<'PY'
import glob, json, sys
state = json.load(open(glob.glob(sys.argv[1] + "/*-yosys-synthesis/state_out.json")[0]))
print(state["metrics"]["design__instance__area"])
PY
)
  echo "   standard-cell area after synthesis: $STD_AREA µm²"
fi

watchdog() {       # <run dir>: stop the active run when its detailed routing cannot converge; prints the reason
  # (runs in a command substitution: it may signal the run's process group, but the caller waits for the run)
  local run="$1" seen=0 last_change start prev gap
  last_change=$(date +%s); start=$last_change; prev=$last_change
  while kill -0 "$ACTIVE" 2> /dev/null; do
    sleep 60
    local now log reason=""
    now=$(date +%s)
    # time spent frozen by jobq's memory guard (the watchdog is frozen too) is neither idle nor run time
    gap=$(( now - prev - 60 )); prev=$now
    (( gap > 180 )) && { last_change=$(( last_change + gap )); start=$(( start + gap )); }
    log=$(ls -t "$run"/*openroad-detailedrouting*/*.log 2> /dev/null | head -n 1 || true)
    if [[ -n "$log" ]]; then
      local v=() n
      mapfile -t v < <(grep "Number of violations" "$log" | awk '{print $NF}' | tr -d '.,')
      n=${#v[@]}
      [[ $n -ne $seen ]] && { seen=$n; last_change=$now; }
      (( n >= 3 && v[n-1] > 500000 )) && reason="${v[n-1]} routing violations after $n iterations"
      (( n >= 6 && v[n-1] > 20000 )) && reason="${v[n-1]} routing violations after $n iterations"
      (( n >= 10 && v[n-1] > 3000 )) && reason="${v[n-1]} routing violations after $n iterations"
      (( now - last_change > IDLE_LIMIT_S )) && reason="no completed routing iteration for $(( IDLE_LIMIT_S / 3600 )) h"
    else
      last_change=$now
    fi
    (( now - start > MAX_LIMIT_S )) && reason="longer than $(( MAX_LIMIT_S / 3600 )) h"
    if [[ -n "$reason" ]]; then stop_group "$ACTIVE"; echo "$reason"; return; fi
  done
}

signoff() {        # <run dir>: timing at the typical corner with the parasitics of every net -> <run dir>/signoff/
  local run="$1" out="$1/signoff" macro_libs=""
  mkdir -p "$out"
  "$NEAT_PYTHON" "$F/tools/legal_names.py" "$run/final/nl/$TOP.nl.v" \
    "$(ls "$run"/final/sdf/nom_tt_025C_1v80/*.sdf | head -n 1)" "$run/final/spef/nom/$TOP.nom.spef" "$out" \
    > "$out/legal_names.log" || return 1
  [[ -z "$MACRO_INSTANCES" ]] || macro_libs="$F/macros/$MACRO_CELL/${MACRO_CELL}_tt_025C_1v80.lib"
  (
    eval "$("$NEAT_PYTHON" - "$run/resolved.json" <<'PY'
import json, shlex, sys
config = json.load(open(sys.argv[1]))      # the variables flow/neat_decoder.sdc reads, as the run resolved them
for key in ("CLOCK_PERIOD", "CLOCK_PORT", "IO_DELAY_CONSTRAINT", "MAX_FANOUT_CONSTRAINT", "MAX_TRANSITION_CONSTRAINT",
            "MAX_CAPACITANCE_CONSTRAINT", "SYNTH_DRIVING_CELL", "SYNTH_CLK_DRIVING_CELL", "OUTPUT_CAP_LOAD",
            "CLOCK_UNCERTAINTY_CONSTRAINT", "CLOCK_TRANSITION_CONSTRAINT", "TIME_DERATING_CONSTRAINT"):
    value = config.get(key)
    if value is not None:
        value = " ".join(map(str, value)) if isinstance(value, list) else str(value)
        print(f"export {key}={shlex.quote(value)}")
PY
)"
    export LIB_SC="$PDK_ROOT/$PDK/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib" \
           LIB_MACROS="$macro_libs" NETLIST="$out/design.nl.v" SPEF="$out/design.spef" TOP="$TOP" \
           SDC="$F/neat_decoder.sdc" OUT="$out"
    "${NEAT_LOWPRI[@]}" \
      nix --extra-experimental-features "nix-command flakes" develop --accept-flake-config "$LIBRELANE_ROOT" -c \
      sta -no_splash -exit "$F/tools/signoff_sta.tcl"
  ) > "$out/sta.log" 2>&1 || return 1
  "$NEAT_PYTHON" - "$out/sta.log" "$out/signoff.json" <<'PY'
import json, re, sys
log, out = open(sys.argv[1], errors="replace").read(), sys.argv[2]
values = {key: float(value) * 1e9 for key, value in re.findall(r"^SIGNOFF (\w+) (\S+)$", log, flags=re.M)}
summary = {f"{key}_ns": values.get(key) for key in ("setup_ws", "hold_ws", "setup_tns", "hold_tns")}
summary["spef_unmatched"] = len(re.findall(r"spef.* not found", log))
summary["corner"] = "nom_tt_025C_1v80"
json.dump(summary, open(out, "w"), indent=1)
sys.exit(0 if None not in summary.values() else 1)
PY
}

# ---- the attempts: the declared utilisation, then the fallback
rm -f "$WORK/runs/accepted" "$WORK/harden.json"
ATTEMPTS="$WORK/attempts.jsonl"; : > "$ATTEMPTS"
record() {         # <utilisation> <status> <minutes> <reason>
  "$NEAT_PYTHON" - "$@" >> "$ATTEMPTS" <<'PY'
import json, sys
util, status, minutes, reason = sys.argv[1:]
print(json.dumps({"utilisation_pct": int(util), "status": status, "minutes": int(minutes), "reason": reason}))
PY
}
for U in $UTILS; do
  DENS=$(( U + 10 )); [[ $DENS -gt 95 ]] && DENS=95
  TAG="u$U"
  CFG="$WORK/config_$TAG.yaml"
  sed -e "s/@UTIL@/$U/" -e "s/@DENS@/$DENS/" "$WORK/config.template.yaml" > "$CFG"
  [[ -z "$MACRO_INSTANCES" ]] ||
    "$NEAT_PYTHON" "$F/tools/macro_config.py" "$CFG" "$F/macros" "$MACRO_CELL" $MACRO_INSTANCES \
      --std-area "$STD_AREA" --utilisation "$U"
  echo "==== $SESSION: clock $CLK_NS ns, utilisation $U % (density $DENS %), run $TAG  ($(date +%H:%M))"
  T0=$(date +%s)
  run_librelane "$CFG" "$TAG" OpenROAD.STAPostPNR "$WORK/logs/librelane_$TAG.log"
  STOPPED=$(watchdog "$WORK/runs/$TAG")
  wait "$ACTIVE" 2> /dev/null || true; ACTIVE=""
  MIN=$(( ($(date +%s) - T0) / 60 ))
  if [[ -n "$STOPPED" ]]; then
    echo "   stopped by the watchdog after $MIN min: $STOPPED"; record "$U" stopped "$MIN" "$STOPPED"; continue
  fi
  METRICS="$WORK/runs/$TAG/final/metrics.json"
  if [[ ! -f "$METRICS" ]]; then
    echo "   run $TAG produced no metrics after $MIN min (see logs/librelane_$TAG.log)"
    tail -n 5 "$WORK/logs/librelane_$TAG.log"
    record "$U" failed "$MIN" "LibreLane stopped before sign-off (see logs/librelane_$TAG.log)"; continue
  fi
  if ! signoff "$WORK/runs/$TAG"; then
    echo "   the sign-off timing of run $TAG failed (see runs/$TAG/signoff/sta.log)"
    record "$U" failed "$MIN" "sign-off timing failed (see runs/$TAG/signoff/sta.log)"; continue
  fi
  if "$NEAT_PYTHON" "$F/tools/check_metrics.py" "$METRICS" --cell-cap "${CELL_CAP:-300000}" \
       --signoff "$WORK/runs/$TAG/signoff/signoff.json" \
       --synth-stat "$(ls "$WORK/runs/$TAG"/*-yosys-synthesis/reports/stat.json | head -n 1)" \
       -o "$WORK/runs/$TAG/check.json" | sed 's/^/   /'; then
    ln -sfn "$TAG" "$WORK/runs/accepted"
    record "$U" accepted "$MIN" ""
    echo "   accepted after $MIN min: $WORK/runs/accepted -> $TAG"
    break
  fi
  REASONS=$("$NEAT_PYTHON" -c "import json, sys; print('; '.join(json.load(open(sys.argv[1]))['reasons']))" \
    "$WORK/runs/$TAG/check.json")
  record "$U" rejected "$MIN" "$REASONS"
  echo "   rejected after $MIN min"
done

# ---- the summary
"$NEAT_PYTHON" - "$WORK" "$SESSION" "$CLK_NS" "$LIBRELANE_ROOT" "$PDK_ROOT" "$PDK" <<'PY'
import json, os, subprocess, sys
work, session, clk, librelane_root, pdk_root, pdk = sys.argv[1:]
attempts = [json.loads(line) for line in open(f"{work}/attempts.jsonl")]
accepted = [a for a in attempts if a["status"] == "accepted"]
summary = {"session": session, "clock_period_ns": float(clk), "status": "accepted" if accepted else "failed",
           "attempts": attempts}
if accepted:
    summary.update(json.load(open(f"{work}/runs/accepted/check.json")))
    summary["utilisation_pct"] = accepted[0]["utilisation_pct"]
else:
    summary["reasons"] = ["neither the declared utilisation nor the 20 % fallback closed"]
def describe(cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=30).stdout.strip() or None
    except Exception:
        return None
summary["tools"] = {"librelane": describe(["git", "-C", librelane_root, "describe", "--tags", "--always"]),
                    "pdk": f"{pdk_root}/{pdk}", "pdk_version": describe(["cat", f"{pdk_root}/{pdk}/SOURCES"])}
json.dump(summary, open(f"{work}/harden.json", "w"), indent=1)
PY
trap - INT TERM EXIT
[[ -e "$WORK/runs/accepted" ]] || { echo "$SESSION: no utilisation closed ($UTILS)"; exit 1; }
