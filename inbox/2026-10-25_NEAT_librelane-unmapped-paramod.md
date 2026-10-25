# LibreLane 3.0.16 stops on "Unmapped Yosys instances" for designs with kept parametrised sub-modules

**Concerns:** sky130 notes section 4 (synthesis) / 5 (hardening with LibreLane); new.

**Symptom.** A design with `(* keep_hierarchy *)` on a parametrised module (NEAT's baseline: 96 `neat_rom_col #(.J(j))`
plus one `neat_sram_demux #(...)`) hardened fine with OpenLane 2. With LibreLane 3.0.16 the flow quits after synthesis:
`[ERROR] 97 Unmapped Yosys instances found.` (`Checker.YosysUnmappedCells`).

**Cause.** `librelane/steps/pyosys.py` (around line 595) computes `design__instance_unmapped__count` as the sum of
`num_cells_by_type` entries whose name starts with `$`. The kept sub-modules of a parametrised module are named
`$paramod\neat_rom_col\J=s32'...`, so each instance counts as "unmapped". `stat.json` shows `num_submodules: 97`,
exactly the reported count, and every one of those names is a key of `stat["modules"]`. No real unmapped cell.

**Fix (NEAT, 2026-10-25).** `ERROR_ON_UNMAPPED_CELLS: false` in the configuration, and the acceptance check counts
the real unmapped cells itself: the `$` types of `reports/stat.json` that are **not** module names
(`flow/tools/check_metrics.py --synth-stat`; 0 for the baseline). Downstream, OpenSTA black boxes and Icarus
compilation would also catch a truly unmapped cell.

**Suggestion.** A line in the notes for LibreLane users with kept parametrised modules, and possibly an upstream issue
(the metric should exclude `stat["modules"]` keys).

General: any design with kept hierarchy of parametrised modules.
