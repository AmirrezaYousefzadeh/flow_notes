#!/usr/bin/env python3
"""Decide from the metrics of an OpenLane run whether the hardened design is accepted (flow/harden.sh; RULES.md,
sections 3 and 5): routing DRC clean, setup and hold met at the typical corner, no power-grid violation, and at most
CELL_CAP standard cells. Tap cells are not counted: their number grows with the core area, not with the design.

The timing comes from --signoff, the result of flow/tools/signoff_sta.tcl on the renamed netlist and SPEF, in which
every net has its parasitics; OpenLane's own sign-off loses those of the nets inside sub-modules, and its slacks are
kept for information only. Without --signoff the OpenLane slacks are used (for runs of other flows).

Usage: check_metrics.py <run dir>/final/metrics.json [--signoff signoff.json] [--corner nom_tt_025C_1v80]
                        [--cell-cap 300000] [-o summary.json]
Prints a one-line summary and PASS or FAIL; exit status 0 on PASS.
"""
import argparse
import json


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("metrics")
    ap.add_argument("--corner", default="nom_tt_025C_1v80")
    ap.add_argument("--cell-cap", type=int, default=300000)
    ap.add_argument("--signoff", default=None, help="signoff.json of flow/tools/signoff_sta.tcl")
    ap.add_argument("-o", "--out", default=None)
    a = ap.parse_args()

    m = json.load(open(a.metrics))
    taps = m.get("design__instance__count__class:tap_cell", 0)
    all_cells = m.get("design__instance__count__stdcell")
    summary = {
        "cells": None if all_cells is None else all_cells - taps,
        "tap_cells": taps,
        "cell_area_um2": m.get("design__instance__area__stdcell"),
        "die_area_um2": m.get("design__die__area"),
        "core_area_um2": m.get("design__core__area"),
        "utilization": m.get("design__instance__utilization"),
        "setup_ws_ns": m.get(f"timing__setup__ws__corner:{a.corner}"),
        "hold_ws_ns": m.get(f"timing__hold__ws__corner:{a.corner}"),
        "drc_errors": m.get("route__drc_errors"),
        "power_grid_violations": m.get("design__power_grid_violation__count", 0),
        "antenna_violating_nets": m.get("antenna__violating__nets"),   # reported only: no antenna repair in the flow
        "corner": a.corner,
        "cell_cap": a.cell_cap,
    }
    if a.signoff:
        signoff = json.load(open(a.signoff))
        summary["openlane_setup_ws_ns"], summary["openlane_hold_ws_ns"] = summary["setup_ws_ns"], summary["hold_ws_ns"]
        summary["setup_ws_ns"], summary["hold_ws_ns"] = signoff["setup_ws_ns"], signoff["hold_ws_ns"]
        summary["timing"] = "flow/tools/signoff_sta.tcl (renamed netlist and SPEF)"
        summary["spef_unmatched"] = signoff["spef_unmatched"]
    reasons = []
    if summary["drc_errors"] != 0:
        reasons.append(f"routing DRC errors: {summary['drc_errors']}")
    if summary["setup_ws_ns"] is None or summary["setup_ws_ns"] < 0:
        reasons.append(f"setup slack {summary['setup_ws_ns']} ns at {a.corner}")
    if summary["hold_ws_ns"] is None or summary["hold_ws_ns"] < 0:
        reasons.append(f"hold slack {summary['hold_ws_ns']} ns at {a.corner}")
    if summary.get("spef_unmatched"):
        reasons.append(f"{summary['spef_unmatched']} SPEF entries without a match in the sign-off timing")
    if summary["power_grid_violations"]:
        reasons.append(f"{summary['power_grid_violations']} power-grid violations (unconnected supply pins)")
    if summary["cells"] is None or summary["cells"] > a.cell_cap:
        reasons.append(f"{summary['cells']} standard cells, cap {a.cell_cap}")
    summary["pass"] = not reasons
    summary["reasons"] = reasons

    print(f"cells {summary['cells']} (+ {taps} taps)  cell area {summary['cell_area_um2']} µm²  "
          f"die {summary['die_area_um2']} µm²  "
          f"setup {summary['setup_ws_ns']} ns  hold {summary['hold_ws_ns']} ns  drc {summary['drc_errors']}  "
          f"pdn {summary['power_grid_violations']}")
    print("PASS" if summary["pass"] else "FAIL: " + "; ".join(reasons))
    if a.out:
        json.dump(summary, open(a.out, "w"), indent=1)
    raise SystemExit(0 if summary["pass"] else 1)


if __name__ == "__main__":
    main()
