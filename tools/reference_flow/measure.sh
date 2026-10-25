#!/usr/bin/env bash
# The official power measurement of one session (RULES.md, section 3): the first 5000 test bins presented in real time to
# the hardened netlist with the session's configuration image, cell delays annotated (flow/gls.sh), and the per-pin
# OpenSTA power of that window (flow/power.sh).
#
# Usage: flow/measure.sh <submission dir> <session> <run dir> <out dir> [n_bins (default 5000)]
# Output: <out dir>/measure.json; the simulation in <out dir>/gls, the power analysis in <out dir>/power. A finished
# simulation is reused when its inputs are unchanged (netlist, SDF, SPEF, stream and image; recorded in gls/stamp).
set -euo pipefail
[[ $# -ge 4 ]] || { sed -n '6p' "$0"; exit 2; }
F="$(cd "$(dirname "$0")" && pwd)"
source "$F/../env/env.sh" > /dev/null
SUB="$(cd "$1" && pwd)"
SESSION="$2"
RUN="$(cd "$3" && pwd -P)"
OUT="$4"
NB="${5:-5000}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
eval "$("$NEAT_PYTHON" "$F/../evaluate/subm.py" "$SUB/submission.json" "$SESSION")"   # INCDIR CLK_NS TOP MACRO_*
STREAM="$NEAT_ROOT/data/streams/$SESSION/test_w$NB.hex"
[[ -f "$STREAM" ]] ||
  "$NEAT_PYTHON" "$NEAT_ROOT/data/make_stream.py" "$NEAT_ROOT/data/prepared/$SESSION.npz" -o "$STREAM" --n_bins "$NB"
T0=$(date +%s)

# the inputs of the simulation; the date lines of the SDF and SPEF headers are left out, so that an identical netlist
# hardened again reuses its gate-level simulation
STAMP=$(cat "$RUN/final/nl/$TOP.nl.v" "$RUN"/final/sdf/nom_tt_025C_1v80/*.sdf "$RUN/final/spef/nom/$TOP.nom.spef" "$STREAM" \
        "${LOAD_HEX_OVERRIDE:-$INCDIR/neat_weights.hex}" 2> /dev/null | grep -av -E '^\*DATE |^[[:space:]]*\(DATE ' |
        sha256sum | cut -c1-16)
if [[ -s "$OUT/gls/rt.json" && -s "$OUT/gls/toggles.tsv" && "$(cat "$OUT/gls/stamp" 2> /dev/null)" == "$STAMP" ]]; then
  echo "==> reusing the gate-level simulation in $OUT/gls"
else
  rm -rf "$OUT/gls"
  "$F/gls.sh" "$RUN" "$SUB" "$SESSION" "$STREAM" "$OUT/gls" "$NB" || true      # an overrun is recorded, not fatal
  [[ -s "$OUT/gls/rt.json" ]] || { echo "the gate-level simulation did not finish (see $OUT/gls/sim.log)"; exit 1; }
  echo "$STAMP" > "$OUT/gls/stamp"
fi
TOP="$TOP" MACRO_CELL="$MACRO_CELL" MACRO_INSTANCES="$MACRO_INSTANCES" "$F/power.sh" "$RUN" "$OUT/gls" "$CLK_NS" "$OUT/power"

MINUTES=$(( ($(date +%s) - T0) / 60 ))
"$NEAT_PYTHON" - "$OUT/gls/rt.json" "$OUT/power/power.json" "$OUT/measure.json" "$SESSION" "$CLK_NS" "$MINUTES" \
    "$(iverilog -V 2>&1 | head -n 1)" "$(git -C "$LIBRELANE_ROOT" describe --tags --always 2> /dev/null || echo unknown)" \
    "$(head -n 1 "$PDK_ROOT/$PDK/SOURCES" 2> /dev/null || echo unknown)" <<'PY'
import json, sys
rt, power = json.load(open(sys.argv[1])), json.load(open(sys.argv[2]))
out, session, clk, minutes = sys.argv[3], sys.argv[4], float(sys.argv[5]), int(sys.argv[6])
measure = {"session": session, "clock_period_ns": clk, "activity": "SDF-annotated gate level, typical corner",
           "runtime_min": minutes, "simulator": sys.argv[7], "librelane": sys.argv[8], "pdk": sys.argv[9]}
measure.update({k: rt[k] for k in ("bins", "events", "overruns", "clk_cycles_in_window", "latency_ns_mean",
                                   "latency_ns_max", "active_ns_mean", "active_ns_max", "sdf_errors") if k in rt})
measure["cycles_per_bin"] = rt["clk_cycles_in_window"] / rt["bins"]
measure.update(power)
measure["real_time_met"] = rt["overruns"] == 0 and rt["pass"]
json.dump(measure, open(out, "w"), indent=1)
print(json.dumps(measure, indent=1))
PY
