#!/usr/bin/env python3
"""Parse the real-time summary of a testbench log (the line "RT: key=value ...") into JSON, with "pass" true when the
log has the PASS line (every bin met real time).

Usage: rt_stats.py <sim.log> [-o stats.json] [--extra key=value ...]
"""
import argparse
import json
import re


def number(value):
    return float(value) if any(c in value for c in ".eE") else int(value)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("log")
    ap.add_argument("-o", "--out", default=None)
    ap.add_argument("--extra", nargs="*", default=[], help="further key=value pairs to record (numbers)")
    a = ap.parse_args()

    text = open(a.log, errors="ignore").read()
    match = re.search(r"^RT: (.*)$", text, re.M)
    if not match:
        raise SystemExit("no RT summary line in " + a.log)
    stats = {key: number(value) for key, value in (item.split("=") for item in match.group(1).split())}
    stats["pass"] = bool(re.search(r"^PASS", text, re.M))
    stats.update({key: number(value) for key, value in (item.split("=", 1) for item in a.extra)})
    print(json.dumps(stats, indent=1))
    if a.out:
        json.dump(stats, open(a.out, "w"), indent=1)


if __name__ == "__main__":
    main()
