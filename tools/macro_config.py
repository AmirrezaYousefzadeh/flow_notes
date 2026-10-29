#!/usr/bin/env python3
"""Add SRAM22 macro instances to a LibreLane configuration (sky130 notes 5.5, 9.1).

Usage: macro_config.py <config.yaml> <macros dir> <cell> <instance> [<instance> ...] [--synthesis-only]
                       [--std-area <µm²> --utilisation <percent>] [--pdn-cfg <tcl>] [--max-instances N]
<macros dir>/<cell>/ holds the views, e.g. /media/pdk/sram22_sky130_fixed-de0a9a7/sram22_2048x32m8w8/.
Appends the MACROS section (GDS, LEF, blackbox, and one timing liberty per corner present: tt, ss, ff), the
power-grid hooks (--pdn-cfg, default reference_flow/pdn_cfg_sram22.tcl next to this tool, connects the macros' supply
pins) and, unless --synthesis-only, an absolute floorplan:
the macros stand in a column on the left of the core, HALO µm apart and from the edge, and the core is about square,
its standard-cell region to the right of the column being the synthesis area divided by the declared utilisation.
"""
import argparse
import math
import re
from pathlib import Path

HALO = 20.0              # µm between the macros, the core edge and the standard cells
MARGIN = 20.0            # µm from the core to the die edge
CORNERS = ("tt_025C_1v80", "ss_100C_1v60", "ff_n40C_1v95")


def lef_size(lef):
    """Width and height of the macro, from the SIZE statement of its LEF."""
    m = re.search(r"\bSIZE\s+([\d.]+)\s+BY\s+([\d.]+)", Path(lef).read_text())
    if not m:
        raise SystemExit(f"no SIZE statement in {lef}")
    return float(m.group(1)), float(m.group(2))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("config")
    ap.add_argument("macros_dir")
    ap.add_argument("cell")
    ap.add_argument("instances", nargs="+")
    ap.add_argument("--synthesis-only", action="store_true")
    ap.add_argument("--std-area", type=float, default=None)
    ap.add_argument("--utilisation", type=float, default=None)
    ap.add_argument("--pdn-cfg", default=str(Path(__file__).resolve().parent / "reference_flow" / "pdn_cfg_sram22.tcl"))
    ap.add_argument("--max-instances", type=int, default=None)
    a = ap.parse_args()
    if a.max_instances is not None and len(a.instances) > a.max_instances:
        raise SystemExit(f"at most {a.max_instances} macro instances")
    if not Path(a.pdn_cfg).is_file():
        raise SystemExit(f"no power-grid script {a.pdn_cfg}")
    mdir = Path(a.macros_dir).resolve() / a.cell
    width, height = lef_size(mdir / f"{a.cell}.lef")

    lines = ["", "# ---- macros (macro_config.py)", "MACROS:", f"  {a.cell}:", "    instances:"]
    for i, inst in enumerate(a.instances):
        x, y = MARGIN + HALO, MARGIN + HALO + i * (height + HALO)
        lines += [f"      {inst}:", f"        location: [{x:.2f}, {y:.2f}]", "        orientation: N"]
    lines += [f"    gds: [\"{mdir}/{a.cell}.gds\"]", f"    lef: [\"{mdir}/{a.cell}.lef\"]",
              f"    vh: [\"{mdir}/{a.cell}.bb.v\"]",
              "    lib:"]
    libs = [(c, mdir / f"{a.cell}_{c}.lib") for c in CORNERS if (mdir / f"{a.cell}_{c}.lib").is_file()]
    if not libs:
        raise SystemExit(f"no timing liberty in {mdir}")
    lines += [f"      \"*_{c}\": [\"{lib}\"]" for c, lib in libs]   # one per corner: the macro is timed at each
    lines += ["VDD_NETS: [VPWR]", "GND_NETS: [VGND]", "PDN_MACRO_CONNECTIONS:"]
    lines += [f"  - {inst} VPWR VGND vdd vss" for inst in a.instances]
    lines += [f"PDN_CFG: \"{Path(a.pdn_cfg).resolve()}\"",
              "PDN_MULTILAYER: true", "PDN_VPITCH: 80", "PDN_HPITCH: 80",
              "PDN_VSPACING: 15", "PDN_HSPACING: 15",
              "ERROR_ON_PDN_VIOLATIONS: false     # gated by check_metrics.py instead (sky130 notes 5.5)",
              "RT_MAX_LAYER: met5", "GPL_CELL_PADDING: 2", "DPL_CELL_PADDING: 2"]
    die = ""
    if not a.synthesis_only:
        if a.std_area is None or a.utilisation is None:
            raise SystemExit("--std-area and --utilisation are needed for the floorplan")
        column_w = width + 2 * HALO
        column_h = len(a.instances) * (height + HALO) + HALO
        std_area = a.std_area / (a.utilisation / 100.0)
        core_h = max(column_h, math.sqrt(std_area + column_w * column_h))     # about square, at least the macro column
        core_w = column_w + std_area / core_h
        die_w = math.ceil((core_w + 2 * MARGIN) / 10.0) * 10
        die_h = math.ceil((core_h + 2 * MARGIN) / 10.0) * 10
        lines += ["FP_SIZING: absolute", f"DIE_AREA: [0, 0, {die_w}, {die_h}]",
                  f"CORE_AREA: [{MARGIN:.0f}, {MARGIN:.0f}, {die_w - MARGIN:.0f}, {die_h - MARGIN:.0f}]"]
        die = f", die {die_w} x {die_h} µm"
    text = Path(a.config).read_text()
    text = "\n".join(line for line in text.splitlines() if not line.startswith(("FP_SIZING:", "FP_CORE_UTIL:")))
    Path(a.config).write_text(text + "\n" + "\n".join(lines) + "\n")
    print(f"{a.config}: {len(a.instances)} x {a.cell} ({width} x {height} µm){die}")


if __name__ == "__main__":
    main()
