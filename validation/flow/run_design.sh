#!/usr/bin/env bash
# One validation design, end to end: harden (or, for ASAP7, the ORFS flow) and measure. Runs inside a jobq job
# (validate.sh submits it). Usage: run_design.sh <design dir> <work dir>
# Writes <work dir>/result.json: the hardening summary and the measurement, with the tool versions.
set -euo pipefail
[[ $# -eq 2 ]] || { sed -n '3p' "$0"; exit 2; }
FLOW="$(cd "$(dirname "$0")" && pwd)"
D="$(cd "$1" && pwd)"; source "$D/design.sh"
mkdir -p "$2"; WORK="$(cd "$2" && pwd)"
T0=$(date +%s)
case "$KIND" in
  sky130)
    if [[ -f "$WORK/harden/harden.json" ]]; then echo "$NAME: reusing the accepted hardening in $WORK/harden"
    else "$FLOW/sky130_harden.sh" "$D" "$WORK/harden"; fi
    "$FLOW/sky130_measure.sh" "$D" "$WORK/harden/runs/accepted" "$WORK/measure" ;;
  asap7)
    "$FLOW/asap7_run.sh" "$D" "$WORK" ;;
  *) echo "unknown KIND $KIND"; exit 2 ;;
esac
python3 - "$WORK" "$NAME" "$(( ($(date +%s) - T0) / 60 ))" <<'PY'
import json, sys
work, name, minutes = sys.argv[1], sys.argv[2], int(sys.argv[3])
result = {"design": name, "minutes": minutes,
          "harden": json.load(open(f"{work}/harden/harden.json")), "measure": json.load(open(f"{work}/measure/measure.json"))}
json.dump(result, open(f"{work}/result.json", "w"), indent=1)
print(f"{name}: done in {minutes} min: {work}/result.json")
PY
