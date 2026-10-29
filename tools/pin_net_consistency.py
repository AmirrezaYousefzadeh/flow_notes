#!/usr/bin/env python3
"""Diagnostic: cell output-pin variables of a toggle file whose transition count disagrees with the net they drive (the
net toggles, the pin variable does not, or the reverse). With annotated delays Icarus sometimes leaves a cell's output
port constant while its net toggles; toggles_to_activity.py writes the net activities last, so the net wins in OpenSTA
(sky130 notes 7.2). This shows how often it happens; it does not fail.
Usage: pin_net_consistency.py <netlist.v> <toggles.tsv> <scope, e.g. tb/u_dut>"""
import re, sys
if len(sys.argv) != 4: sys.exit(__doc__)
nl = open(sys.argv[1], errors="ignore").read(); tsv = sys.argv[2]; scope = sys.argv[3].rstrip("/") + "/"
OUTP = ("X", "Y", "Q", "Q_N", "GCLK", "Z", "ZN", "QN")
drv = {}   # inst/pin -> net
for m in re.finditer(r"^\s*([A-Za-z_][\w$]*)\s+(\\?\S+)\s*\((.*?)\);", nl, flags=re.S | re.M):
    if m.group(1) in ("module", "wire", "input", "output", "assign", "reg", "endmodule", "supply0", "supply1"): continue
    inst = m.group(2).lstrip("\\")
    for pin, net in re.findall(r"\.(\w+)\(\s*([^()]*?)\s*\)", m.group(3)):
        if pin in OUTP: drv[f"{inst}/{pin}"] = net.strip().lstrip("\\")
tog = {}
for line in open(tsv):
    if line.startswith("#"): continue
    f = line.rstrip("\n").split("\t")
    if not f[0].startswith(scope): continue
    name = f[0][len(scope):] + (f"[{f[3]}]" if len(f) > 3 else "")      # a bus bit carries its index in a 4th column
    tog[name] = (float(f[1]), int(f[2]))
n = bad0 = badn = 0; ex = []
for pin, net in drv.items():
    tp = tog.get(pin); tn = tog.get(net)
    if tp is None or tn is None: continue
    n += 1
    if tp[0] == 0 and tn[0] > 0: bad0 += 1; ex.append((pin, net, tp, tn))
    elif tn[0] == 0 and tp[0] > 0: badn += 1
print(f"{tsv}: {n} output pins with both pin and net variables; pin constant while net toggles: {bad0}; net constant while pin toggles: {badn}")
for e in ex[:5]: print("   ", e)
