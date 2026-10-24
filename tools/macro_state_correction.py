#!/usr/bin/env python3
"""State-dependent internal power of SRAM22 macros under a clock that is stopped most of the time (flow/power.sh).

Usage: macro_state_correction.py gen <activity.tcl> <netlist.v> <power liberty> [--cells sram22_2048x32m8w8]
                                     -o <macro_cond.tcl> [--json <file>]
       macro_state_correction.py compare <report dir> <conditioned report dir> <netlist.v> [--cells ...] [--json <file>]

The macro's liberty gives the clock-pin energy per state of its control pins (when "!we&ce" for a read, ...). OpenSTA
weights these tables with the time-averaged duty of the pins, but in the real-time window the clock runs a few per cent
of the time and the control pins are idle whenever it is stopped, so a read would be weighted with P(ce) of a few per
cent instead of P(ce | clock running), close to 1, and the macro's read energy would come out far too low.
gen writes set_power_activity commands for the pins named in the when-conditions, with the duty conditioned on the
macro clock running: duty_cond = (duty - v_idle (1 - d_clk)) / d_clk, where d_clk = (transitions of the clock pin per
period) / 2 is the fraction of cycles with a macro clock edge and v_idle the pin's value while the clock is stopped
(inferred from which of the two values is possible). compare reports the difference in internal power between the
standard run and the conditioned run, per macro, for information; the conditioned run is the one flow/power.sh reports.
"""
import argparse
import json
import re
import sys


def instances(netlist, cells):
    """Macro instances: name -> (cell, {pin: net})."""
    text = open(netlist, errors="ignore").read()
    found = {}
    for m in re.finditer(r"^\s*([A-Za-z_][\w$]*)\s+([A-Za-z_][\w$]*)\s*\((.*?)\);", text, flags=re.S | re.M):
        if m.group(1) in cells:
            found[m.group(2)] = (m.group(1), dict(re.findall(r"\.(\w+)\(\s*([^()]*?)\s*\)", m.group(3))))
    return found


def when_pins(liberty, cell):
    """The pins referenced by the when-conditions of the internal_power groups of a cell."""
    text = open(liberty, errors="ignore").read()
    start = max(text.find(f"cell ({cell})"), text.find(f'cell ("{cell}")'))
    if start < 0:
        sys.exit(f"cell {cell} not in {liberty}")
    end = text.find("\n  cell (", start + 10)
    body = text[start:end if end > 0 else len(text)]
    pins = set()
    for block in re.finditer(r"internal_power\s*\(\)\s*\{(.*?)\n\s*\}", body, flags=re.S):
        for condition in re.findall(r'when\s*:\s*"([^"]*)"', block.group(1)):
            pins.update(re.findall(r"[A-Za-z_]\w*(?:\[\d+\])?", condition))
    return sorted(pins)


def activities(activity_tcl):
    """Measured activity and duty per pin or net name, from the commands of flow/tools/toggles_to_activity.py."""
    found = {}
    for line in open(activity_tcl, errors="ignore"):
        m = re.match(r"__(?:top|pin)_act \{(.+?)\} (\S+) (\S+)", line)
        if m:
            found[m.group(1).replace("\\", "")] = (float(m.group(2)), float(m.group(3)))
    return found


def report(path):
    power = {}
    for line in open(path, errors="ignore"):
        f = line.split()
        if len(f) == 5:
            try:
                power[f[4]] = tuple(float(x) for x in f[:4])
            except ValueError:
                pass
    return power


def generate(a):
    activity_tcl, netlist, liberty = a.args
    macros = instances(netlist, a.cells.split(","))
    if not macros:
        sys.exit(f"no instance of {a.cells} in {netlist}")
    measured = activities(activity_tcl)
    commands = ["# macro state pins with the duty conditioned on the macro clock running (macro_state_correction.py)"]
    info = {}
    for name, (cell, pins) in macros.items():
        clk = measured.get(f"{name}/{a.clk_pin}") or measured.get(pins.get(a.clk_pin, ""))
        if not clk:
            sys.exit(f"no activity for the clock pin of {name}")
        d_clk = clk[0] / 2.0
        record = {"cell": cell, "clk_activity": clk[0], "d_clk": d_clk, "pins": {}}
        for pin in when_pins(liberty, cell):
            if pin not in pins:
                continue
            act = measured.get(f"{name}/{pin}") or measured.get(pins[pin])
            if not act:
                sys.exit(f"no activity for {name}/{pin}")
            duty = act[1]
            # the duties of activity.tcl carry six decimals: compare with a tolerance of one unit of the last one
            if d_clk <= 0:
                v_idle, cond = None, duty
            elif duty <= d_clk + 1e-6:
                v_idle, cond = 0, duty / d_clk
            elif duty >= 1 - d_clk - 1e-6:
                v_idle, cond = 1, (duty - (1 - d_clk)) / d_clk
            else:
                v_idle, cond = None, duty / d_clk
                print(f"WARNING: {name}/{pin}: duty {duty:.6f} is neither below d_clk {d_clk:.6f} nor above 1 - d_clk; "
                      "the pin changes while the clock is stopped")
            cond = min(max(cond, 0.0), 1.0)
            commands.append(f"set_power_activity -pins {{{name}/{pin}}} -activity {act[0]:.6g} -duty {cond:.6f}")
            record["pins"][pin] = {"activity": act[0], "duty_window": duty, "v_idle": v_idle, "duty_conditional": cond}
        info[name] = record
        print(f"{name} ({cell}): d_clk {d_clk:.6f}; " + "; ".join(
            f"{p}: duty {v['duty_window']:.6f} -> {v['duty_conditional']:.6f}" for p, v in record["pins"].items()))
    open(a.o, "w").write("\n".join(commands) + "\n")
    if a.json:
        json.dump(info, open(a.json, "w"), indent=1)


def compare(a):
    standard_dir, conditioned_dir, netlist = a.args
    macros = instances(netlist, a.cells.split(","))
    std = report(f"{standard_dir}/power_vcd_by_instance.rpt")
    cond = report(f"{conditioned_dir}/power_vcd_by_instance.rpt")
    result, added = {"instances": {}}, 0.0
    for name in macros:
        if name in std and name in cond:
            result["instances"][name] = {"internal_std_W": std[name][0], "internal_conditioned_W": cond[name][0]}
            added += cond[name][0] - std[name][0]
    result["added_internal_W"] = added
    if a.json:
        json.dump(result, open(a.json, "w"), indent=1)
    print(f"macro state correction: {added * 1e6:+.4f} µW of macro internal power")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("mode", choices=("gen", "compare"))
    ap.add_argument("args", nargs=3)
    ap.add_argument("--cells", default="sram22_2048x32m8w8")
    ap.add_argument("--clk-pin", default="clk")
    ap.add_argument("-o", default="macro_cond.tcl")
    ap.add_argument("--json", default=None)
    a = ap.parse_args()
    generate(a) if a.mode == "gen" else compare(a)


if __name__ == "__main__":
    main()
