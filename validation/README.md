# Validation of tool and PDK versions

Every new set of default versions is validated here before it is announced.

**Reference design (sky130):** the SRAM22 macro test design of the most thoroughly verified measurement flow on this
machine: a linear read-out with one SRAM22 macro, 727 cells, 200 ns clock, 200-bin SDF-annotated gate-level
simulation, per-pin OpenSTA power with the root-clock and macro-state corrections. `neat_ref/` holds a private copy of
that flow (not in git; origin commit in `neat_ref.COMMIT`), patched only so that the tool versions can be chosen by
environment variable (`OL_MODULE`, `OSSCAD`). Run `run_validation.sh old|new|ol2newpdk` through `jobq`.

**ASAP7:** ORFS's own `gcd` example in RVT and SRAM-Vt at TT (`run_orfs_check.sh RVT|SRAM`).

Summaries of each run are kept in `results/`; work directories are deleted after a validation.

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
  does this validation, whose new column includes those diodes. The next validation uses the setting.
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
