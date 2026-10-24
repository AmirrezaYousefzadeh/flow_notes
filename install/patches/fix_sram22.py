#!/usr/bin/env python3
"""Build the fixed SRAM22 view set (sky130 notes 9.1) from an upstream sram22_sky130_macros checkout.

- liberties: upstream as is (timing), plus *_pwr.lib power copies without the vss internal/leakage groups
  (OpenSTA adds the tables of every related_pg_pin, which counts the energy twice);
- LEF (OBS on met1 only) and GDS (prBoundary 235/4): NEAT's verified fixes, used only if upstream's LEF/GDS/Verilog
  are unchanged from the version NEAT fixed (checked against the reference copy given);
- simulation models: NEAT's functional, black-box and _tdout models.
Usage: fix_sram22.py <upstream macro dir> <NEAT fixed macro dir> <reference old upstream macro dir> <out dir>
"""
import filecmp, re, shutil, sys
from pathlib import Path

up, neat, ref, out = map(Path, sys.argv[1:5])
name = up.name
for f in (f"{name}.gds.gz", f"{name}.lef", f"{name}.v"):
    if not filecmp.cmp(up / f, ref / f, shallow=False):
        sys.exit(f"{f} changed upstream: NEAT's LEF/GDS fixes must be redone by hand")
out.mkdir(parents=True, exist_ok=True)

def drop_vss_groups(text):
    res, i = [], 0
    pat = re.compile(r"^[ \t]*(internal_power|leakage_power)\s*\(\s*\)\s*\{", re.M)
    while (m := pat.search(text, i)):
        depth, j = 0, m.end() - 1
        while True:
            depth += {"{": 1, "}": -1}.get(text[j], 0); j += 1
            if depth == 0: break
        block = text[m.start():j]
        res.append(text[i:m.start()])
        if not re.search(r"related_pg_pin\s*:\s*vss\s*;", block):
            res.append(block)
        else:  # also drop the newline after the dropped block
            j += 1 if text[j:j+1] == "\n" else 0
        i = j
    res.append(text[i:])
    return "".join(res)

for lib in sorted(up.glob(f"{name}_*.lib")):
    shutil.copy2(lib, out / lib.name)
    pwr = drop_vss_groups(lib.read_text())
    hdr = ("/* Power-analysis copy of %s: internal_power and leakage_power groups related to vss removed, because\n"
           "   OpenSTA adds the tables of every related_pg_pin (energy counted twice). Timing tables untouched. */\n" % lib.name)
    (out / lib.name.replace(".lib", "_pwr.lib")).write_text(hdr + pwr)
for f in (f"{name}.lef", f"{name}.gds", f"{name}.v", f"{name}_tdout.v", f"{name}.bb.v"):
    shutil.copy2(neat / f, out / f)
shutil.copy2(up / f"{name}.spice", out / f"{name}.spice")
print("wrote", out)
