#!/usr/bin/env python3
"""Check that every cell pin the simulation saw received its measured activity in OpenSTA (flow/power.sh).

Usage: check_annotation.py <sta out dir> <netlist> <liberty> [<liberty> ...]
Reads annot_notfound_pins.txt and annot_notfound_top.txt (written by the activity file of toggles_to_activity.py).
Names that OpenSTA could not find are expected for supply pins and for the internal signals of the cell models
(and0_out_X, notifier, D_delayed, ...). A name <instance>/<pin> whose pin is a signal pin of the instance's liberty cell,
a name whose instance is not in the netlist, or any top-level name, means a measured activity was lost: the pin falls
back to propagated activity. Prints the counts and exits 1 if any activity was lost.
"""
import re
import sys
from pathlib import Path

from root_clock_correction import read_netlist


def signal_pins(liberties):
    """Liberty cell -> its signal pin and bus names (pg_pin supplies excluded)."""
    pins, cell = {}, None
    for path in liberties:
        for line in open(path, errors="ignore"):
            m = re.match(r"\s*cell\s*\(\s*\"?([\w$]+)\"?\s*\)", line)
            if m:
                cell = m.group(1)
                pins.setdefault(cell, set())
                continue
            m = re.match(r"\s*(pin|bus)\s*\(\s*\"?([\w$\[\]]+)\"?\s*\)", line)
            if m and cell:
                pins[cell].add(m.group(2))
    return pins


def tokens(path):
    """The names of a coverage file (a Tcl list: names with brackets are braced), read in chunks (millions of names)."""
    rest = ""
    with open(path, errors="ignore") as f:
        while chunk := f.read(1 << 24):
            parts = (rest + chunk).split()
            rest = "" if chunk[-1].isspace() else parts.pop()
            yield from (p.strip("{}") for p in parts)
    if rest:
        yield rest.strip("{}")


def main():
    if len(sys.argv) < 4:
        sys.exit(__doc__)
    out, netlist, liberties = Path(sys.argv[1]), sys.argv[2], sys.argv[3:]
    pins = signal_pins(liberties)
    cells = {name: cell for name, (cell, _) in read_netlist(netlist).items()}
    expected, lost = 0, []
    for name in tokens(out / "annot_notfound_pins.txt"):
        instance, _, pin = name.rpartition("/")
        if instance not in cells:
            lost.append(name)                                  # an instance name OpenSTA does not know: a naming mismatch
            continue
        cell_pins = pins.get(cells[instance], set())
        if pin in cell_pins or re.sub(r"\[\d+\]$", "", pin) in cell_pins:
            lost.append(name)
        else:
            expected += 1
    lost += list(tokens(out / "annot_notfound_top.txt"))
    print(f"check_annotation: {expected} names not found as expected (supplies, model internals), "
          f"{len(lost)} measured activities lost")
    for name in lost[:20]:
        print(f"   lost: {name}")
    sys.exit(1 if lost else 0)


if __name__ == "__main__":
    main()
