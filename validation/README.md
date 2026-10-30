# Validation of tool and PDK versions

Every new set of default versions is validated here before it is announced (upgrade policy, `UPSTREAM.md`): the
reference designs are hardened and measured with the new set, and their numbers are compared with the stored set.
The same tools must reproduce a stored set to the last digit; a new set moves the numbers, and the report explains
every difference.

## The reference set (since 2026-10-30)

| design | kind | what it exercises | simulation |
|---|---|---|---|
| `designs/sram_probe` | sky130, one SRAM22 macro, 432 cells after synthesis | macro floorplan and power grid, SRAM22 state correction, root-clock correction | SDF, 200 bins |
| `designs/lmem2g` | sky130 latch-memory core, 50 688 latches in 97 rows, ~158 k cells, no latch waivers | routability and scaling, hold at latch inputs, per-row clock gates | zero delay, 20 bins |
| `designs/snn2_d` | sky130 adder-tree core, ~34 k cells, 155 clock gates | routing congestion (it failed at 40 % with LibreLane), adder trees, glitches | SDF, 25 samples |
| `designs/min32_asap7` | ASAP7 SRAM-Vt core, ~18 k cells | ORFS at TT, own hold check, 1 ps Icarus models, ICG delays, multi-PDK root-clock correction | SDF, 50 bins |

Each directory is a frozen copy (RTL, testbench, stimulus, expected outputs, constraints) with `ORIGIN` (project,
commit, source of every file and every change) and `design.sh` (the contract of `flow/README.md`). The flow in
`flow/` uses only the maintained tools and the notes' settings: LibreLane with the measurement settings of sky130 5.1,
the hardening ladder, a 9-corner own sign-off, bit-exact gate-level simulation, OpenSTA per-pin power with the
corrections; ORFS at TT for ASAP7.

**Run:** `flow/validate.sh <label>` (one `jobq` job per design, work in `work_<label>/`, not in git), then
`flow/compare.py work_<label> results/<stored set>`; store an accepted set with `--store` into `results/<set>/`.
Budget: the SRAM22 design minutes, the ASAP7 core under an hour, the adder-tree and latch cores several hours each.

The first stored set (the current defaults, LibreLane 3.0.16, open_pdks `8afc834`, ORFS `ef2cb37`, OSS CAD Suite
2026-10-24) is being produced; until then the results below are the reference.

## Previous procedure

Until 2026-10-29 only the SRAM22 design was validated, with a private copy of its project's flow (`neat_ref/`, not in
git; `run_validation.sh`) and ORFS's own `gcd` example (`run_orfs_check.sh`). Its summaries are in `results/old`,
`results/new`, `results/openlane2_newpdk` and `results/orfs_gcd_*`.

## 2026-10-24: LibreLane 3.0.16, open_pdks 8afc834, OSS CAD Suite 2026-10-24, ORFS ef2cb37

| quantity | old (OpenLane 2.3.10, open_pdks c6d73a35, Icarus 13) | new (LibreLane 3.0.16, open_pdks 8afc834, Icarus 14) |
|---|---|---|
| hardening | accepted at 30 %, DRC 0, power grid 0 | accepted at 30 %, DRC 0, power grid 0 |
| cells / cell area | 727 / 6 332 µm² | 828 / 8 356 µm² (OpenROAD's design repair, see below) |
| setup / hold slack (own sign-off, TT) | 118.04 / 0.95 ns | 117.31 / 1.13 ns |
| antenna-violating nets | 11 | 0 |
| unmatched SPEF entries, SDF errors | 0, 0 | 0, 0 |
| gate-level vs RTL | bit-exact, real time met | bit-exact, real time met |
| root clock tree | 4 buffers | 10 buffers |
| P_STA / removed by root-clock correction | 6.165 / 3.731 µW | 12.863 / 10.407 µW |
| dynamic power | 0.0900 µW | 0.1120 µW (+25 %) |
| leakage | 2.3435 µW | 2.3440 µW |
| **total power** | **2.4334 µW** | **2.4560 µW (+0.9 %)** |

- The old set reproduces itself to the last digit (2.433446750552603 µW in two runs).
- **Where the extra cells come from** (checked 2026-10-29 step by step on an equivalent LibreLane run of the same
  design, 836 cells): not synthesis (431 cells with Yosys 0.62, 434 with 0.46), but OpenROAD's design repair after
  global placement. The new OpenROAD buffers the ports with the delay cell `clkdlybuf4s25_1` (121 of 122 port
  buffers, 10 µm² each; the old one used mostly `buf_2`, 5 µm²) and resizes 1 instance instead of 509, so cells keep Yosys's drive strength 2
  instead of being sized down to 1 (167 instead of 397 drive-1 cells after the repair). LibreLane's antenna repair
  after detailed routing adds 102 diodes (OpenLane 2: 55); that run predates `DRT_ANTENNA_REPAIR_ITERS: 0`, and so
  does this validation, whose new column includes those diodes.
- **Where the extra dynamic power comes from** (+22 nW; per-instance power reports of the old and new runs, after the
  root-clock correction): the root clock tree with 10 instead of 4 buffers +9 nW, delay cells +7.5 nW, logic at drive
  strength 2 +7 nW, port buffers +1 nW (1.3 of 112 nW), other buffers −3 nW, diodes about 0.
- **OpenLane 2.3.10 with the new PDK fails:** hardening is identical to the old set, but its OpenSTA (`b5f3a02`)
  crashes with a segmentation fault in the SRAM22-conditioned power run, reproducibly (the liberty files are
  identical; the SPEF extracted with the new PDK's RC data differs). The same OpenSTA also crashed on the new
  LibreLane netlist. Hence `/media/pdk/sky130A` stays on the old PDK for OpenLane 2.
- ORFS `ef2cb37` with the LibreLane binaries: `gcd` routes DRC-clean in RVT and SRAM-Vt at TT, with the TT liberties
  (`*_SRAMVT_TT_*` for SRAM-Vt), and reports hold slack. Setup is negative at TT because `gcd`'s 310 ps clock is set
  for the FF corner.
