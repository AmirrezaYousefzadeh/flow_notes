#!/usr/bin/env bash
# Own sign-off of a routed LibreLane run at all 9 corners (sky130 notes 6.2): {tt, ss, ff} liberties x {nom, min, max}
# parasitics, with the run's final netlist, SPEF and SDC (OpenSTA 2.7 reads the escaped SPEF names itself). Setup and
# hold must be met at every corner, and no SPEF entry may go unmatched.
# Usage: sky130_signoff.sh <run dir>          (DESIGN_DIR: the design; harden_ladder.sh calls it as SIGNOFF_CMD)
# Writes <run dir>/signoff/signoff.json; exit status 0 when every corner passes.
set -euo pipefail
[[ $# -eq 1 && -n "${DESIGN_DIR:-}" ]] || { sed -n '5p' "$0"; exit 2; }
source "$(dirname "$0")/env.sh"
load_design "$DESIGN_DIR"
RUN="$(cd "$1" && pwd)"
OUT="$RUN/signoff"; mkdir -p "$OUT"
export TOP NETLIST="$RUN/final/nl/$TOP.nl.v" SDC="$(ls "$RUN"/final/sdc/*.sdc | head -n 1)" OUT_DIR="$OUT"
export LIBDIR="$PDK_ROOT/$PDK/libs.ref/sky130_fd_sc_hd/lib" MACRO_LIBS=""
[[ -z "${MACRO_INSTANCES:-}" ]] || MACRO_LIBS="$SRAM22/$MACRO_CELL/$MACRO_CELL"
export SPEFDIR="$RUN/final/spef" HOLD_TCL="$TOOLS/hold_sta.tcl"
in_librelane bash -c '
  for corner in tt_025C_1v80 ss_100C_1v60 ff_n40C_1v95; do
    for rc in nom min max; do
      libs="$LIBDIR/sky130_fd_sc_hd__$corner.lib"
      [[ -z "$MACRO_LIBS" ]] || libs="$libs ${MACRO_LIBS}_$corner.lib"
      LIB_SC="$libs" SPEF="$SPEFDIR/$rc/$TOP.$rc.spef" OUT="$OUT_DIR/${rc}_$corner.json" \
        sta -no_splash -exit "$HOLD_TCL" > "$OUT_DIR/${rc}_$corner.log" 2>&1 || true
    done
  done'
python3 - "$OUT" <<'PY'
import glob, json, os, re, sys
out = sys.argv[1]
corners, problems = {}, []
for log in sorted(glob.glob(f"{out}/*.log")):
    name = os.path.basename(log)[:-4]
    text = open(log, errors="ignore").read()
    unmatched = len(re.findall(r"spef.*not found", text))
    try:
        r = json.load(open(f"{out}/{name}.json"))
    except (OSError, ValueError):
        problems.append(f"{name}: no result (see {log})"); continue
    r["spef_unmatched"] = unmatched
    corners[name] = r
    if r["setup_ws_ns"] < 0: problems.append(f"{name}: setup {r['setup_ws_ns']:.3f} ns")
    if r["hold_ws_ns"] < 0: problems.append(f"{name}: hold {r['hold_ws_ns']:.3f} ns")
    if unmatched: problems.append(f"{name}: {unmatched} unmatched SPEF entries")
if len(corners) != 9 and not problems:
    problems.append(f"{len(corners)} of 9 corners")
summary = {"corners": corners, "pass": not problems, "problems": problems,
           "setup_ws_ns": min((c["setup_ws_ns"] for c in corners.values()), default=None),
           "hold_ws_ns": min((c["hold_ws_ns"] for c in corners.values()), default=None)}
json.dump(summary, open(f"{out}/signoff.json", "w"), indent=1)
print(f"sign-off at {len(corners)} corners: worst setup {summary['setup_ws_ns']} ns, worst hold {summary['hold_ws_ns']} ns"
      + ("" if not problems else "; " + "; ".join(problems[:5])))
sys.exit(0 if summary["pass"] else 1)
PY
