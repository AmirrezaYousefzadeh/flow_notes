#!/usr/bin/env python3
"""Functional (zero-delay) Verilog models of standard cells from liberty files, for fast gate-level simulation
(Verilator: no UDPs, no specify blocks). Handles combinational functions, flip-flops (ff groups with clear/preset),
latches, integrated clock gates (latch the enable while the clock is low), multi-output cells (full adders) and
three-state outputs; physical cells (fill, tap, decap, diode) become empty modules with their ports.
Usage: liberty2verilog.py <lib[.gz]> [<lib> ...] <out.v> [cell ...]
"""
import gzip
import re
import sys
from pathlib import Path

PWR = {"VDD", "VSS", "VPWR", "VGND", "VNB", "VPB", "VNW", "VPW", "KAPWR", "LOWLVPWR", "VPWRIN"}


def groups(text, kind):
    """yield (name, body) of every top-level `kind (name) { ... }` group in text (brace matching)"""
    pat = re.compile(r"\b" + kind + r"\s*\(([^\)]*)\)\s*\{")
    pos = 0
    while True:
        m = pat.search(text, pos)
        if not m:
            return
        depth, i = 1, m.end()
        while depth and i < len(text):
            c = text[i]
            if c == "{":
                depth += 1
            elif c == "}":
                depth -= 1
            i += 1
        yield m.group(1).strip().strip('"'), text[m.end():i - 1]
        pos = i


def strip_groups(body):
    """body with nested groups removed (only the group's own attributes)"""
    out, depth = [], 0
    for c in body:
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
        elif depth == 0:
            out.append(c)
    return "".join(out)


def attr(body, key):
    m = re.search(r"\b" + key + r"\s*:\s*\"?([^\";\n]*)\"?\s*;", strip_groups(body))
    return m.group(1).strip() if m else None


def lib2v(expr):
    e = expr.strip().strip('"')
    e = re.sub(r"([A-Za-z_][A-Za-z0-9_]*)\s*'", r"~\1", e)
    e = e.replace("!", "~").replace("*", "&").replace("+", "|")
    e = re.sub(r"([A-Za-z0-9_\)])\s+([A-Za-z0-9_~\(])", r"\1 & \2", e)
    return e


def drop_group(body, kind):
    """remove every `kind (...) { ... }` group (e.g. test_cell, whose pins duplicate the cell's)"""
    pat = re.compile(r"\b" + kind + r"\s*\(([^\)]*)\)\s*\{")
    while True:
        m = pat.search(body)
        if not m:
            return body
        depth, i = 1, m.end()
        while depth and i < len(body):
            depth += {"{": 1, "}": -1}.get(body[i], 0)
            i += 1
        body = body[:m.start()] + body[i:]


def cell_model(name, body):
    body = drop_group(body, "test_cell")
    pins = []
    for pn, pb in groups(body, "pin"):
        pins.append((pn, attr(pb, "direction"), attr(pb, "function"), attr(pb, "three_state"),
                     "clock_gate_out_pin" in pb, "clock_gate_enable_pin" in pb or "clock_gate_test_pin" in pb, pb))
    ins = [p[0] for p in pins if p[1] == "input" and p[0] not in PWR]
    outs = [p for p in pins if p[1] in ("output", "inout") and p[0] not in PWR]
    L = [f"module {name} ({', '.join(ins + [p[0] for p in outs])});"]
    L += [f"  input {n};" for n in ins] + [f"  output {p[0]};" for p in outs]
    L.append("  supply1 VDD; supply0 VSS; supply1 VPWR; supply0 VGND;")
    ffs = list(groups(body, "ff"))
    las = list(groups(body, "latch"))
    icg = "clock_gating_integrated_cell" in body
    if ffs:
        (gname, gb) = ffs[0]
        iq, iqn = [x.strip().strip('"') for x in gname.split(",")]
        L.append(f"  reg {iq}; wire {iqn} = ~{iq};")
        clk = lib2v(attr(gb, "clocked_on")); nxt = lib2v(attr(gb, "next_state"))
        clr, pre = attr(gb, "clear"), attr(gb, "preset")
        edge = "negedge" if clk.startswith("~") else "posedge"
        sens = [f"{edge} {clk.lstrip('~').strip('()')}"]
        if clr:
            c = lib2v(clr); sens.append(f"{'negedge' if c.startswith('~') else 'posedge'} {c.lstrip('~').strip('()')}")
        if pre:
            c = lib2v(pre); sens.append(f"{'negedge' if c.startswith('~') else 'posedge'} {c.lstrip('~').strip('()')}")
        conds = []
        if clr:
            conds.append(f"if ({lib2v(clr)}) {iq} <= 1'b0;")
        if pre:
            conds.append(f"{'else ' if conds else ''}if ({lib2v(pre)}) {iq} <= 1'b1;")
        conds.append(f"{'else ' if conds else ''}{iq} <= {nxt};")
        L.append(f"  always @({' or '.join(sens)}) " + " ".join(conds))
    elif las and not icg:
        (gname, gb) = las[0]
        iq, iqn = [x.strip().strip('"') for x in gname.split(",")]
        L.append(f"  reg {iq}; wire {iqn} = ~{iq};")
        en = lib2v(attr(gb, "enable")); din = lib2v(attr(gb, "data_in"))
        clr, pre = attr(gb, "clear"), attr(gb, "preset")
        body_s = f"if ({en}) {iq} = {din};"
        if pre:
            body_s = f"if ({lib2v(pre)}) {iq} = 1'b1; else " + body_s
        if clr:
            body_s = f"if ({lib2v(clr)}) {iq} = 1'b0; else " + body_s
        L.append(f"  always @(*) {body_s}")
    if icg:
        clk = [p[0] for p in pins if p[1] == "input" and "clock" in p[6] and re.search(r"\bclock\s*:\s*true", p[6])]
        clk = clk[0] if clk else [n for n in ins if n in ("CK", "CLK")][0]
        en = [p[0] for p in pins if p[5] and p[1] == "input"]
        en_expr = " | ".join(en) if en else "1'b1"
        L.append(f"  reg IQ; always @(*) if (!{clk}) IQ = {en_expr};")
        for p in outs:
            L.append(f"  assign {p[0]} = {clk} & IQ;")
    else:
        for (n, d, fn, ts, cgo, cge, pb) in outs:
            if fn:
                e = lib2v(fn)
                L.append(f"  assign {n} = {lib2v(ts)} ? 1'bz : ({e});" if ts else f"  assign {n} = {e};")
    L.append("endmodule\n")
    return "\n".join(L)


def main():
    args = sys.argv[1:]
    out = Path([a for a in args if a.endswith(".v")][0])
    libs = [a for a in args if ".lib" in a]
    only = set(a for a in args if not a.endswith(".v") and ".lib" not in a)
    mods, seen, skipped = [], set(), []
    for l in libs:
        text = (gzip.open(l, "rt", errors="replace") if l.endswith(".gz") else open(l, errors="replace")).read()
        for name, body in groups(text, "cell"):
            if (only and name not in only) or name in seen:
                continue
            try:
                mods.append(cell_model(name, body)); seen.add(name)
            except Exception as e:
                skipped.append(f"{name}({e})")
    out.write_text("// functional models generated from liberty by sim/liberty2verilog.py\n`timescale 1ns/1ps\n" + "\n".join(mods))
    if skipped:
        print("skipped:", " ".join(skipped))
    print(f"{len(mods)} cell models written to {out}")


if __name__ == "__main__":
    main()
