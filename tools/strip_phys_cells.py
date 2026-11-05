#!/usr/bin/env python3
"""Drop the physical-only instances (fill, tap, endcap, decap, antenna diode) from a routed netlist, for the gate-level
simulation only.

They have no logic and no SDF delays, but Icarus' $sdf_annotate slows down with the instance count, and on a
low-utilisation layout they are most of it: 820 000 of them made the annotation of a 129 000-cell core run for over an
hour, against 25 min without them (sky130 notes 7.4). Simulate the stripped netlist and give OpenSTA the full one, so
that their leakage stays in the power. Instances whose cell matches --cells are removed whatever their connections.

Usage: strip_phys_cells.py <in.v> <out.v> [--cells REGEX]
  --cells  cell names to remove (default: sky130 fill, tapvpwrvgnd, decap and diode cells of every library, ASAP7
           FILLER, TAPCELL and DECAP cells)
"""
import argparse
import re

ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
ap.add_argument("netlist")
ap.add_argument("out")
ap.add_argument("--cells", default=r"sky130_(?:fd|ef)_sc_\w+__(?:fill|tapvpwrvgnd|decap|diode)\w*"
                                   r"|(?:FILLER|TAPCELL|DECAP)\w*_ASAP7\w*")
a = ap.parse_args()

text = open(a.netlist).read()
inst = re.compile(rf"^[ \t]*(?:{a.cells})[ \t]+(?:\\\S+|\w+)\s*\([^;]*\)\s*;[ \t]*\n?", re.M)
out, n = inst.subn("", text)
open(a.out, "w").write(out)
print(f"strip_phys_cells: removed {n} physical-only instances")
