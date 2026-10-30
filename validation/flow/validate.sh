#!/usr/bin/env bash
# Validate a tool and PDK set on the reference designs: one jobq job per design (its JOB_THREADS, JOB_MEM, JOB_TIME),
# then compare the results with a stored set (compare.py).
# Usage: validate.sh <label> [design ...]       (default: every design in ../designs)
#   Work directories: ../work_<label>/<design> (not in git). Tool versions: the defaults, or LIBRELANE, PDK_ROOT,
#   OSSCAD, ORFS from the environment (they are passed to the jobs).
# When the jobs are done: compare.py ../work_<label> ../results/<stored set>; store a new set with compare.py --store.
set -euo pipefail
[[ $# -ge 1 ]] || { sed -n '3p' "$0"; exit 2; }
FLOW="$(cd "$(dirname "$0")" && pwd)"
LABEL="$1"; shift
DESIGNS=("$@")
[[ ${#DESIGNS[@]} -gt 0 ]] || mapfile -t DESIGNS < <(ls "$FLOW/../designs")
WORK="$(cd "$FLOW/.." && pwd)/work_$LABEL"
mkdir -p "$WORK"
ENVS=""
for v in LIBRELANE PDK_ROOT PDK OSSCAD ORFS SRAM22; do [[ -z "${!v:-}" ]] || ENVS+="$v=${!v} "; done
for d in "${DESIGNS[@]}"; do
  D="$FLOW/../designs/$d"
  ( source "$D/design.sh"
    jobq add --name "val_${LABEL}_$d" --threads "$JOB_THREADS" --mem "$JOB_MEM" --time "$JOB_TIME" -- \
      "cd '$WORK' && ${ENVS}'$FLOW/run_design.sh' '$D' '$WORK/$d' > '$WORK/$d.log' 2>&1" )
done
echo "submitted ${#DESIGNS[@]} designs; logs in $WORK/<design>.log"
