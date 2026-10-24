#!/usr/bin/env python3
"""Reduce an OpenSTA SDF to what Icarus Verilog can annotate (flow/gls.sh).

Usage: sdf_sanitize_for_icarus.py <design.sdf> -o <design.icarus.sdf>
Icarus aborts the whole annotation on constructs it does not parse, so this keeps the cell delays (IOPATH) and drops the
rest:
  * VOLTAGE / TEMPERATURE / PROCESS triplets "a::b" become "a:a:b";
  * INTERCONNECT entries are dropped (wire delays are not modelled; the cell delays include the load of the wires);
  * TIMINGCHECK blocks are dropped (Icarus does not check them);
  * conditional delays (COND ...) (IOPATH ...) become plain IOPATHs, since Icarus does not parse the conditions;
  * IOPATHs on bus bits (dout[0] of a macro) are dropped, since Icarus does not parse them; the macro's own simulation
    model carries its output delay;
  * CELL entries left without any IOPATH are dropped;
  * empty delay triplets "()" become zeros.
Instance names must be plain identifiers (flow/tools/legal_names.py runs first) and the time scale 1 ns.
"""
import argparse
import re
import sys
from pathlib import Path


def skip_balanced(lines, start):
    """Index just past the parenthesised block that starts at lines[start]."""
    depth = 0
    for i in range(start, len(lines)):
        for ch in lines[i]:
            if ch == "(":
                depth += 1
            elif ch == ")":
                depth -= 1
                if depth == 0:
                    return i + 1
    return len(lines)


def sanitize(text):
    stats = dict.fromkeys(("dropped_interconnect", "dropped_timingcheck", "unwrapped_cond", "dropped_bus_iopath",
                           "dropped_empty_cells", "filled_empty_triplets"), 0)
    timescale = re.search(r"\(TIMESCALE\s+([^)]*)\)", text)
    if timescale and timescale.group(1).replace(" ", "") != "1ns":
        sys.exit(f"sdf_sanitize: time scale {timescale.group(1)}; the testbench expects 1ns")

    lines, out, i = text.splitlines(keepends=True), [], 0
    while i < len(lines):
        line = lines[i]
        stripped = line.lstrip()
        if stripped.startswith(("(VOLTAGE", "(TEMPERATURE", "(PROCESS")):
            line = re.sub(r"([-+0-9.eE]+)::([-+0-9.eE]+)", r"\1:\1:\2", line)
        if stripped.startswith("(INTERCONNECT"):
            stats["dropped_interconnect"] += 1
            i += 1
            continue
        if stripped.startswith("(TIMINGCHECK"):
            stats["dropped_timingcheck"] += 1
            i = skip_balanced(lines, i)
            continue
        if stripped.startswith("(COND"):
            # the next line is the IOPATH of the condition; it carries the closing parenthesis of the COND as well
            i += 1
            if i >= len(lines):
                break
            body = lines[i].rstrip()
            if body.endswith(")"):
                body = body[:-1].rstrip()
            i += 1
            if "[" in body:
                stats["dropped_bus_iopath"] += 1
                continue
            out.append(body + "\n")
            stats["unwrapped_cond"] += 1
            continue
        if stripped.startswith("(IOPATH") and "[" in stripped:
            stats["dropped_bus_iopath"] += 1
            i += 1
            continue
        out.append(line)
        i += 1

    # drop the CELL entries that kept no IOPATH; the file's closing parenthesis is taken off first and put back at the end
    body = "".join(out).rstrip()
    if body.endswith(")"):
        body = body[:-1].rstrip()
    first = body.find("(CELL")
    head, cells = (body, []) if first < 0 else (body[:first], re.split(r"(?=\(CELL\b)", body[first:]))
    kept = []
    for cell in cells:
        if "(IOPATH" in cell:
            kept.append(cell)
        elif cell.strip():
            stats["dropped_empty_cells"] += 1
    body = head + "".join(kept).rstrip() + "\n)\n"
    body, stats["filled_empty_triplets"] = re.subn(r"\(IOPATH ([^\n]*?) \(\) ",
                                                   lambda m: f"(IOPATH {m.group(1)} (0.000000:0.000000:0.000000) ", body)
    return body, stats


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("src", type=Path)
    ap.add_argument("-o", "--out", type=Path, required=True)
    a = ap.parse_args()
    body, stats = sanitize(a.src.read_text(errors="replace"))
    a.out.write_text(body)
    print(f"wrote {a.out}: " + ", ".join(f"{k} {v}" for k, v in stats.items()))


if __name__ == "__main__":
    main()
