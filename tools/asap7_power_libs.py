#!/usr/bin/env python3
"""Write power-only copies of ASAP7 liberties whose leakage OpenSTA evaluates correctly (ASAP7 notes 9.5).

Why: the ASAP7 liberties write each leakage state of a cell together with its outputs, for example INVx1 "(A * !Y)"
and "(!A * Y)", and they have no cell_leakage_power. OpenSTA evaluates a condition as the product of the duties of its
pins, as if they were independent, and charges a cell's cell_leakage_power (absent here) for the probability no
condition matches. The outputs are functions of the inputs, so most of that probability belongs to impossible states
and is lost: at duty 0.5 an INVx1 gets 5.15 pW for states of 9.91 and 10.70 pW, an FAx1 13.3 pW for states of 47.6 to
67.0 pW. Constant pins give the exact value; a design's leakage reads lower the more it toggles.

The copies change only leakage, nothing that timing reads:
  1. combinational cells: the output pins are dropped from the leakage conditions. Each cell must then list every
     combination of its inputs exactly once (checked), so the probabilities sum to 1 and the leakage is the
     duty-weighted mean of the states (exact for independent inputs).
  2. every cell without cell_leakage_power gets one: the value of its unconditional leakage_power group (the
     library's mean). OpenSTA charges it for whatever probability the conditions still miss: the latches (DHL, DLL),
     clock gates (ICG) and DFFASRHQN list their output or state pin and skip impossible combinations.
Internal-power and timing groups are copied unchanged. Use the copies for OpenSTA power only; timing, SDF and the
flow keep the original liberties.

Usage: asap7_power_libs.py <out dir> <liberty[.gz]>...      (writes <out dir>/<same file name>; never overwrites)
Origin: the combinational rewrite follows a project's patch_leakage_when.py (flow_notes inbox, 2026-11-16).
"""
import collections
import gzip
import os
import re
import sys


def read(path):
    return (gzip.open(path, "rt") if path.endswith(".gz") else open(path)).read()


def write(path, text):
    (gzip.open(path, "wt") if path.endswith(".gz") else open(path, "w")).write(text)


def convert(text, name):
    lines = text.split("\n")
    outs, ins, seq = collections.defaultdict(set), collections.defaultdict(set), set()
    cell = pin = None
    for ln in lines:                                     # pass 1: pin directions, sequential cells
        m = re.match(r"\s*cell\s*\(\"?([^\")]+)\"?\)", ln)
        if m:
            cell, pin = m.group(1), None
            continue
        if re.match(r"\s*pg_pin\s*\(", ln):
            pin = None
            continue
        m = re.match(r"\s*pin\s*\(\"?([^\")]+)\"?\)", ln)
        if m:
            pin = m.group(1)
            continue
        if re.match(r"\s*(ff|latch|statetable|ff_bank|latch_bank)\s*\(", ln):
            seq.add(cell)
        m = re.match(r"\s*direction\s*:\s*\"?(\w+)\"?\s*;", ln)
        if m and pin and cell:
            if m.group(1) == "output":
                outs[cell].add(pin)
            elif m.group(1) == "input":
                ins[cell].add(pin)
    res, conds, rewritten = [], collections.defaultdict(set), 0
    cell, depth, in_leak = None, 0, None
    for ln in lines:                                     # pass 2: drop outputs from combinational conditions
        m = re.match(r"\s*cell\s*\(\"?([^\")]+)\"?\)", ln)
        if m:
            cell = m.group(1)
        if re.match(r"\s*leakage_power\s*\(\s*\)", ln):
            in_leak = depth
        m = re.match(r'(\s*when\s*:\s*")(.*)(";.*)', ln)
        if m and in_leak is not None and cell not in seq and ins[cell]:
            expr = m.group(2).strip()
            if not re.fullmatch(r"\(?[!\w\s*]+\)?", expr):
                sys.exit(f"{name}: {cell}: leakage condition is not a product of pins: {expr}")
            keep = [t.strip() for t in expr.strip("()").split("*") if t.strip().lstrip("!") not in outs[cell]]
            new = "(" + " * ".join(keep) + ")"
            conds[cell].add(new.replace(" ", ""))
            rewritten += new != expr
            ln = m.group(1) + new + m.group(3)
        depth += ln.count("{") - ln.count("}")
        if in_leak is not None and depth <= in_leak:
            in_leak = None
        res.append(ln)
    bad = [c for c, cs in conds.items()
           if len(cs) != 2 ** len(ins[c]) or any(len(k.strip("()").split("*")) != len(ins[c]) for k in cs)]
    if bad:
        sys.exit(f"{name}: combinational cells without one condition per input combination: {bad}")
    text = "\n".join(res)
    parts = re.split(r"(\n\s*cell\s*\([^)]*\)\s*\{)", text)  # pass 3: cell_leakage_power where missing
    out, filled, nofill = [parts[0]], 0, []
    for head, body in zip(parts[1::2], parts[2::2]):
        if not re.search(r"\bcell_leakage_power\b", body):
            value = None
            for blk in re.findall(r"leakage_power\s*\(\s*\)\s*\{(.*?)\}", body, re.S):
                v = re.search(r"value\s*:\s*([-\d.eE+]+)", blk)
                if "when" not in blk and v and float(v.group(1)) > 0:
                    value = v.group(1)
                    break
            if value is None:
                nofill.append(head.split("(")[1].split(")")[0])
            else:
                head += f"\n    cell_leakage_power : {value};"
                filled += 1
        out += [head, body]
    print(f"{name}: {rewritten} conditions of {len(conds)} combinational cells rewritten, {len(seq)} sequential cells "
          f"kept, cell_leakage_power added to {filled} cells"
          + (f"; no unconditional leakage to add for {nofill}" if nofill else ""))
    return "".join(out)


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    out_dir, files = sys.argv[1], sys.argv[2:]
    os.makedirs(out_dir, exist_ok=True)
    for f in files:
        dst = os.path.join(out_dir, os.path.basename(f))
        if os.path.exists(dst):
            sys.exit(f"{dst} exists; remove it first")
        write(dst, convert(read(f), os.path.basename(f)))


if __name__ == "__main__":
    main()
