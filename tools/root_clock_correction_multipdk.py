#!/usr/bin/env python3
"""Root-clock correction for any PDK (sky130 notes 8.2, ASAP7 notes 9.6), for a design whose root clock runs only a
fraction d of the time. OpenSTA gives every pin of the clock network between the clock port and the first clock gate the
activity of the clock definition (2 per period) and ignores the annotation there; downstream of a clock gate it uses the
annotated activity. This script walks the root network of one clock port in the routed netlist (through buffers,
inverters and hold or delay buffers, stopping at clock gates and at flip-flop clock pins) and removes the part of their
dynamic power that the stopped clock does not spend: P = P_A - (1 - d) * P_dyn,B, where A is the annotated power run and
B the same run with all data activities zero (tools/power_sta.tcl with ZERO_DATA=1). For buffers P_dyn,B = P_dyn,A; for
flip-flops clocked by the root, the annotated internal power is scaled by the duty directly.
Usage: root_clock_correction_multipdk.py <netlist.v> <clock_port> <duty> <by_instance_A.rpt> <by_instance_B.rpt>
       [--icg dlclkp,ICGx,...] [--buf clkbuf,...] [--prefix <instance prefix>] [-o out.json]
Prints the reported and corrected group totals (Sequential, Combinational, Clock by cell type; leakage unchanged) and,
if power_vcd.rpt sits next to report A, its total minus the removed power. Warns about root cells missing from B."""
import re, sys, json, argparse, collections
ap = argparse.ArgumentParser(); ap.add_argument("netlist"); ap.add_argument("clock_port"); ap.add_argument("duty", type=float); ap.add_argument("rptA"); ap.add_argument("rptB")
ap.add_argument("--icg", default="dlclkp,ICGx,icgt,lgcp,CLKGATE"); ap.add_argument("--buf", default="clkbuf,clkinv,buf,inv,BUF,INV,CKBUF,CKINV,HB1,HB2,HB3,HB4,dly,DLY"); ap.add_argument("-o", default=None)   # hold/delay buffers of the kits (ASAP7 HBx, sky130 dlygate) continue the walk
ap.add_argument("--prefix", default="", help="instance-name prefix of the netlist inside the reports (the block's instances inside a larger netlist)")
a = ap.parse_args()
nl = open(a.netlist, errors="ignore").read()
inst = {}
for m in re.finditer(r"^\s*([A-Za-z_][\w$]*)\s+(\\?\S+)\s*\((.*?)\);", nl, flags=re.S | re.M):
    if m.group(1) in ("module", "wire", "input", "output", "assign", "reg", "endmodule", "supply0", "supply1"): continue
    pins = dict(re.findall(r"\.(\w+)\(\s*([^()]*?)\s*\)", m.group(3)))
    inst[m.group(2).lstrip("\\")] = (m.group(1), pins)
sinks = collections.defaultdict(list)
OUTP = ("X", "Y", "Q", "Q_N", "GCLK", "Z", "ZN", "QN", "ECK")
for n, (t, p) in inst.items():
    for pin, net in p.items():
        if pin not in OUTP: sinks[net].append((n, pin))
icgs = [x for x in a.icg.split(",") if x]; bufs = [x for x in a.buf.split(",") if x]
root = {}                                    # instance -> kind (buf | icg | flop)
todo = [a.clock_port]; seen = set()
while todo:
    net = todo.pop()
    if net in seen: continue
    seen.add(net)
    for n, pin in sinks[net]:
        t = inst[n][0]
        if any(k in t for k in icgs): root[n] = "icg"                                  # clock-gate: its clock pin is root, its output is not
        elif any(k in t for k in bufs) and len([q for q in inst[n][1] if q not in OUTP and q not in ("VGND", "VPWR", "VNB", "VPB")]) == 1:
            root[n] = "buf"; out = next((inst[n][1][q] for q in OUTP if q in inst[n][1]), None)
            if out: todo.append(out)
        else: root[n] = "flop"                                                          # register (or other cell) clocked from the root network
def rpt(path):
    d = {}
    for line in open(path, errors="ignore"):
        f = line.split()
        if len(f) >= 5:
            n = f[4].lstrip("\\")
            if a.prefix:                                   # only the instances of the prefixed block, names as in its own netlist
                if not n.startswith(a.prefix): continue
                n = n[len(a.prefix):]
            try: d[n] = (float(f[0]), float(f[1]), float(f[2]), float(f[3]))
            except ValueError: pass
    return d
A = rpt(a.rptA); B = rpt(a.rptB)
SEQ = ("dfxtp", "dfrtp", "dfstp", "dfbbn", "dfbbp", "dfxbp", "dfrbp", "dfsbp", "sdf", "dlxtp", "dlxtn", "dlrtp", "dlrbp", "dlxbp", "edfxtp", "edfxbp", "DFF", "DHL", "DLL", "SDF", "dff", "latch", "lat")
CLKC = ("clkbuf", "clkinv", "clkdly", "dlclkp", "sdlclkp", "ICGx", "CKBUF", "CKINV", "icgt", "lgcp", "CLKGATE", "CLKBUF", "CLKINV")
def group(t):
    if any(k in t for k in CLKC): return "Clock"
    if any(k in t for k in SEQ): return "Sequential"
    return "Combinational"
tot = collections.defaultdict(lambda: [0.0, 0.0, 0.0, 0.0]); corr = collections.defaultdict(lambda: [0.0, 0.0, 0.0, 0.0]); nroot = collections.Counter(); removed = 0.0; removed_i = 0.0; removed_s = 0.0
missing_b = []
for n, (i, s, l, t_) in A.items():
    t = inst.get(n, ("?",))[0]; g = group(t)
    for k, v in enumerate((i, s, l, t_)): tot[g][k] += v
    ci, cs = i, s
    if n in root:
        nroot[root[n]] += 1; b = B.get(n)
        if b is None and root[n] != "flop":
            missing_b.append(n)
        if b or root[n] == "flop":
            di, ds = (b[0], b[1]) if b else (i, 0.0)                     # clock-driven dynamic power at the full clock rate
            if root[n] == "flop":
                # a register clocked from the root network (en_q, wr_en_q) toggles a few times per bin, so its internal power
                # in the annotated run is the full-rate clock-pin energy itself; the zero-data run does not give it reliably (the global
                # zero activity overrides the propagated clock activity at register clock pins in some libraries: 0 W for NanGate45,
                # a state-dependent value for ASAP7), so the annotated internal power is scaled by the duty directly
                di = i; ds = 0.0
            ci = i - (1 - a.duty) * min(di, i); cs = s - (1 - a.duty) * min(ds, s)
            removed += (1 - a.duty) * (min(di, i) + min(ds, s)); removed_i += (1 - a.duty) * min(di, i); removed_s += (1 - a.duty) * min(ds, s)
    for k, v in enumerate((ci, cs, l, ci + cs + l)): corr[g][k] += v
res = {"duty": a.duty, "root_cells": dict(nroot), "removed_W": removed, "removed_internal_W": removed_i, "removed_switching_W": removed_s,
       "reported": {g: dict(zip(("internal", "switching", "leakage", "total"), v)) for g, v in tot.items()},
       "corrected": {g: dict(zip(("internal", "switching", "leakage", "total"), v)) for g, v in corr.items()}}
for k in ("reported", "corrected"):
    res[k]["Total"] = {q: sum(res[k][g][q] for g in res[k] if g != "Total") for q in ("internal", "switching", "leakage", "total")}
# the OpenSTA group table (power_vcd.rpt next to the by-instance report) is the reference total; its per-instance sum
# exceeds it by up to 1 % on the largest netlists, so the corrected total handed on is report total - removed
import os
rp = os.path.join(os.path.dirname(a.rptA), "power_vcd.rpt")
if os.path.exists(rp):
    for line in open(rp):
        if line.startswith("Total"):
            f = line.split(); gi, gs, gl, gt = (float(x) for x in f[1:5])
            res["report"] = {"internal": gi, "switching": gs, "leakage": gl, "total": gt}
            res["corrected_report"] = {"internal": gi - removed_i, "switching": gs - removed_s, "leakage": gl, "total": gt - removed}
res["root_cells_missing_in_B"] = missing_b
print(f"root network of {a.clock_port}: {dict(nroot)}; duty {a.duty:.4f}; removed {removed*1e6:.4f} uW")
if missing_b: print(f"  WARNING: {len(missing_b)} root cells missing from report B, not corrected: {missing_b[:5]}")
for g in ("Sequential", "Combinational", "Clock", "Total"):
    r = res["reported"].get(g, {}).get("total", 0); c = res["corrected"].get(g, {}).get("total", 0)
    print(f"  {g:14s} reported {r*1e6:10.4f} uW  corrected {c*1e6:10.4f} uW")
if "corrected_report" in res: print(f"  report total {res['report']['total']*1e6:.4f} uW -> corrected {res['corrected_report']['total']*1e6:.4f} uW (leakage {res['report']['leakage']*1e6:.4f})")
if a.o: json.dump(res, open(a.o, "w"), indent=1)
