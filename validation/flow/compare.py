#!/usr/bin/env python3
"""Compare the results of a validation run with a stored set, or store them as a new set.

Usage: compare.py <work dir> <stored set dir> [--store] [--tol 1e-6]
  <work dir>: ../work_<label> (one <design>/result.json per design); <stored set dir>: ../results/<set>.
  Without --store: prints, per design and quantity, the stored and the new value and their relative difference, and
  exits 1 if a check failed (not bit-exact, SDF errors, sign-off) or a quantity moved by more than --tol (relative).
  The same tools and PDK must reproduce the stored numbers (to the last digit on this machine); a new set is expected to
  move them, and the differences are what the validation report explains.
  With --store: copies every result.json to <stored set dir>/<design>.json.
"""
import argparse
import glob
import json
import os
import shutil
import sys

QUANTITIES = [("harden", "cells"), ("harden", "cell_area_um2"), ("harden", "accepted_utilisation_pct"),
              ("harden", "setup_ws_ns"), ("harden", "hold_ws_ns"), ("harden", "hold_buffers"),
              ("measure", "p_total_uW"), ("measure", "p_dyn_uW"), ("measure", "p_leak_uW"), ("measure", "p_sta_uW"),
              ("measure", "root_clock_removed_uW"), ("measure", "clock_duty")]


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("work")
    ap.add_argument("stored")
    ap.add_argument("--store", action="store_true")
    ap.add_argument("--tol", type=float, default=1e-6)
    a = ap.parse_args()
    results = {os.path.basename(os.path.dirname(p)): p for p in glob.glob(f"{a.work}/*/result.json")}
    if not results:
        sys.exit(f"no result.json under {a.work}")
    if a.store:
        os.makedirs(a.stored, exist_ok=True)
        for d, p in sorted(results.items()):
            shutil.copy(p, f"{a.stored}/{d}.json")
            print(f"stored {d}")
        return
    failed = False
    for d, p in sorted(results.items()):
        new = json.load(open(p))
        m = new["measure"]
        checks = [m.get("bit_exact") is not False, m.get("sdf_errors", 0) == 0, new["harden"].get("setup_ws_ns", 0) >= 0,
                  new["harden"].get("hold_ws_ns", 0) >= 0]
        print(f"== {d}: checks {'pass' if all(checks) else 'FAIL'} ({new['minutes']} min)")
        failed |= not all(checks)
        ref_path = f"{a.stored}/{d}.json"
        if not os.path.exists(ref_path):
            print("   no stored result")
            continue
        ref = json.load(open(ref_path))
        for part, q in QUANTITIES:
            r, n = ref.get(part, {}).get(q), new.get(part, {}).get(q)
            if r is None or n is None:
                continue
            rel = (n - r) / abs(r) if r else (0.0 if n == r else float("inf"))
            flag = "" if abs(rel) <= a.tol else "  <-- moved"
            failed |= bool(flag)
            print(f"   {part}.{q:24s} {r:14.6g} -> {n:14.6g}  {rel * 100:+8.3f} %{flag}")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
