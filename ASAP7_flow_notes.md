# ASAP7 flow notes: synthesis, place and route with ORFS, gate-level simulation and power

**Version 5.0, last updated 2026-10-30.** The full history is in "Version history" at the end.

Read this before you synthesise, place and route or measure anything on ASAP7 (the predictive 7 nm library) on this
machine. It is written for engineers and AI agents. It collects what was learned measuring several neural-network
cores on ASAP7 (small decoders of 10–20 k cells and latch-memory cores of up to 1.3 M instances, September–October
2026), plus an audit and a check against upstream sources. It is the sibling of `skywater130_flow_notes.md` in this
folder. The general method is described there and is not repeated here: shared-machine rules, escaped-name renaming,
activity annotation, the root-clock correction, the reproducibility rules. Read that file too. Most of the problems
below fail **silently**: the flow runs to the end and prints a plausible number that is wrong. Section 11 is the
checklist every measurement must pass.

**Announcements.** Changes that every user must act on (new default tool or PDK versions, changed rules) are
broadcast in `/media/amir/flow_notes/ANNOUNCEMENTS.md`. Read it at the start of every measurement campaign. Keeping
your project in step with the notes and the announcements is your responsibility.

**How this file is kept current.** Only the maintainer (the general agent of `/media/amir`) edits the files in
`flow_notes`. Do not edit them. When you find a new pitfall, a mistake here, a better fix or a measured effect, leave
a note in `/media/amir/flow_notes/inbox/` (one file per finding; see the inbox README). The maintainer reads the
inbox, updates the notes (version bump, history row), announces what others must act on, and deletes the note.

**Is my copy current?** Record the version you read in your project's notes. At the start of the next session,
compare it with the line under the title. If the version has changed, read the history rows since your version.

**Upstream.** The tools and PDKs change quickly. The maintainer reviews upstream every month (`UPSTREAM.md`) and
updates these rules when upstream fixes a bug that one of them works around. Do not install or upgrade tools or PDKs,
and never modify a shared ORFS checkout.

**Start here.** Read sections 0, 1 and 3 first (queue, versions, corners and units), then the table below, then the
checklist in section 11.

**The silent errors, at a glance.** Each of these produced a plausible but wrong number here.

| error | effect seen | section |
|---|---|---|
| ORFS optimises at the FF corner unless `CORNER=TC` | runs documented as TT were optimised at FF | 3.3 |
| a period or delay in ns where ASAP7 uses ps | clock power 2.29 instead of 0.0315 mW | 3.4 |
| per-cell leakage averaged over the VDD and the VSS groups | leakage halved | 3.2 |
| clock gates instantiated through `OPENROAD_CLKGATE` without `-D OPENROAD_CLKGATE` | every gate becomes a wire | 4 |
| the adder map with an old Yosys | outputs off by ±2 | 5 |
| hold not checked (old checkout) or broken after detailed routing | 187 hold violations in an accepted run | 7.2 |
| Icarus reading ps as ns, rounding to 10 ps, a zero ICG rise delay | stalled runs; glitch factors off | 8.1 |
| escaped names from `keep_hierarchy` in the SPEF | 4.87 million parasitic entries dropped | 9.4 |
| leakage taken from an idle window instead of the measured one | 23–25 % too high | 9.5 |

Contents:
0. Ground rules on this machine
1. Tools and paths
2. Reference tools
3. Library flavours, corners and units
4. RTL rules for ASAP7
5. Synthesis
6. Place and route with ORFS
7. Timing sign-off
8. Gate-level simulation
9. Power with OpenSTA
10. Runtime and memory
11. Checklist for every measurement
12. Sanity numbers
13. Open questions

---

## 0. Ground rules on this machine

All of section 0 of the sky130 notes applies, in particular: every heavy job through the shared queue `jobq`
(`/media/amir/.jobq/AGENTS.md`), realistic `--mem`, never edit a running script. In addition, for ASAP7:

- **ORFS uses every core unless told otherwise.** `NUM_CORES` defaults to `nproc`, every CPU the job may use: one run
  without it routed at about 520 % CPU. Always pass `NUM_CORES=$JOBQ_THREADS`.
- **Declare realistic memory.** Detailed routing of a 1.3 M-instance latch core peaked at 32.5 GB (section 10); a
  400 k-instance core was OOM-killed at 19 GB.
- **One driver per ORFS design directory.** Two scripts running `make` on the same design, or a script edited while
  it ran, gave `mv: cannot stat *.tmp.log` and `ORD-0007 … odb does not exist`. Give every run its own `WORK_HOME`
  outside the ORFS checkout.
- **ORFS checkouts are shared.** Never `git checkout`, `git pull`, reset or edit them, and keep your designs in your
  project (via `WORK_HOME` and `DESIGN_CONFIG`), not under `flow/designs/`.

## 1. Tools and paths

These are the installed default versions (since 2026-10-24, validated with ORFS's `gcd` example in RVT and SRAM-Vt
at TT, `validation/`). `ANNOUNCEMENTS.md` says when they change.

| what | where / version | how to call |
|---|---|---|
| ORFS | `/media/pdk/OpenROAD-flow-scripts-ef2cb37`: upstream `ef2cb37` (2026-02-12) plus the re-characterised RVT FF liberty (cherry-pick of `3a376ac`, local branch `local-2026-10`) and SRAM-Vt support (`flow_notes/install/patches/apply_sram_vt_orfs.sh`) | `make` in `flow/`, see below |
| OpenROAD, Yosys, KLayout, OpenSTA | not built inside ORFS; taken from the LibreLane Nix shell: OpenROAD `dcf3613` (73 commits newer than ORFS's own pointer), OpenSTA 2.7.0, Yosys 0.62, KLayout 0.30.7 | `nix --extra-experimental-features "nix-command flakes" develop --accept-flake-config /media/hardware_design_tools/librelane -c ...` |
| ASAP7 platform | `<ORFS>/flow/platforms/asap7` | `PLATFORM=asap7`, `ASAP7_USE_VT=RVT\|LVT\|SLVT\|SRAM` |
| liberty (NLDM) | `platforms/asap7/lib/NLDM/`: `asap7sc7p5t_{AO,INVBUF,OA,SIMPLE}_<flavour>_<corner>_nldm_*.lib.gz` and `..._SEQ_..._nldm_220123.lib` (SEQ not gzipped); the `*_SRAMVT_*` names are aliases of the `*_SRAM_*` files | OpenSTA reads `.gz` directly |
| upstream library | `/media/pdk/asap7sc7p5t_28` (sparse clone, `472f7b3`): `LIB/NLDM/*.7z`, `Verilog/` (all flavours) | |
| Verilog cell models | ORFS ships RVT TT only (`platforms/asap7/verilog/stdcell`); SRAM-Vt from `/media/pdk/asap7sc7p5t_28/Verilog` | see section 8 before simulating |
| Icarus model copies | `/media/pdk/icarus_sdf_models/asap7sc7p5t_*_{RVT,SRAM}_TT_*_sdf.v` (notifier initialised) | **not validated** |
| Icarus Verilog | OSS CAD Suite, see sky130 notes section 1 | |

**Previous version, kept for reproducing earlier numbers:** ORFS `/media/pdk/OpenROAD-flow-scripts` (`b4dbcb4`,
2024-10-02, with the old `ASAP7_USESRAM` patch) run with the OpenLane 2 Nix shell (OpenROAD `edf00dff`, Yosys 0.46,
OpenSTA `b5f3a02`); `/media/pdk/asap7` and `/media/pdk/nangate45` still point into it. Never combine the new ORFS with
the OpenLane 2 binaries or the old ORFS with the LibreLane binaries.

**Invocation:**

```
export QT_QPA_PLATFORM=offscreen
nix ... develop --accept-flake-config /media/hardware_design_tools/librelane -c bash -c \
  "cd /media/pdk/OpenROAD-flow-scripts-ef2cb37/flow && make WORK_HOME=<own dir> DESIGN_CONFIG=<path>/config.mk \
   ASAP7_USE_VT=SRAM CORNER=TC NUM_CORES=\$JOBQ_THREADS \
   FILL_CELLS='FILLERxp5_ASAP7_75t_SRAM FILLER_ASAP7_75t_SRAM' \
   OPENROAD_EXE=\$(which openroad) OPENSTA_EXE=\$(which sta) YOSYS_EXE=\$(which yosys) KLAYOUT_CMD=\$(which klayout)"
```

(`FILL_CELLS` as shown for SRAM-Vt, to keep decaps out; for RVT use the `_R` fillers.)

- **`QT_QPA_PLATFORM=offscreen` is required.** The ORFS Makefile sets it only when `DISPLAY` is empty; under ssh or
  VS Code `DISPLAY` is set but unusable (ORFS issue #3034). Without it `6_report` aborts on a Qt plugin error
  (signal 6, rc=2) even when the route is clean, and an acceptance script rejects a good run.
- **SRAM-Vt** is selected with `ASAP7_USE_VT=SRAM`. Check that the `read_liberty` lines of
  `logs/asap7/<design>/<variant>/1_2_yosys.log` and `2_1_floorplan.log` name `*_SRAMVT_<TT|FF|SS>_*` at the corner you
  asked for (this ORFS copies no liberties into `objects/`), and that the netlist has no cell of another flavour
  (`grep -c '_ASAP7_75t_R '` is 0 for SRAM-Vt). SRAM-Vt has NLDM liberties only (no `LIB_MODEL=CCS`) and no
  `CLUSTER_FLOPS`.
- **Stale paths.** ORFS configs generated before October 2026 may point to `/home/yousefzadeha/workspace/...`, which
  no longer holds anything, and to the old checkout. Regenerate configs before rerunning anything.

## 2. Reference tools

Maintained copies are in `/media/amir/flow_notes/tools/` (see its README). For ASAP7 in particular:

| tool | what it does | status |
|---|---|---|
| `write_sdf_sta.tcl` | SDF from OpenSTA (ORFS writes none) | verified |
| `asap7_seq_icarus.v` | behavioural DFFHQNx1/2/3, ICGx1/2, DHLx1 (RVT and SRAM-Vt) for Icarus | verified bit-exact; lacks DLLx1 |
| `sdf_sanitize_for_icarus.py` | ps → ns rescale, empty triplets, COND unwrap | see 8.1 (ICG rise delay) |
| `gen_phys_stubs.py` | empty modules for tap, fill, decap | verified |
| `hold_sta.tcl` | own setup and hold check at one corner with SPEF; reads the run's `6_final.sdc` (or one clock with `PERIOD` in ps) | verified on sky130 |
| `root_clock_correction_multipdk.py` | root-clock correction, walks through hold buffers (`BUFx2` in ORFS) | verified; small residual (13) |
| `liberty2verilog.py` | functional models of the SRAM-Vt cells from the liberty, for Verilator | truth-table-checked on 57 cells |
| `legal_names.py` | renames escaped names consistently in netlist, SDF, SPEF | verified on sky130; needed for any kept hierarchy (9.4) |

A complete ORFS acceptance script needs: `NUM_CORES`, `CORNER`, routing DRC 0, setup at the reported corner, an own
hold check (7.2), and a routing watchdog that kills the process group and does not count time frozen by the queue
(6.6).

## 3. Library flavours, corners and units

**3.1 Flavours.** Cell names end in `_ASAP7_75t_<f>`: `R` (RVT), `L` (LVT), `SL` (SLVT), `SRAM` (SRAM-Vt, the
lowest-leakage flavour, selected with `ASAP7_USE_VT=SRAM`, section 1). Footprints are identical.
- **"SRAM" here is a standard-cell threshold flavour, not an SRAM macro.**
- Swapping liberties on a netlist routed with another flavour is not the same as hardening natively; label which one
  you did.
- The fakeram7 macros are common in academic ASAP7 work for area and placement, but their own `fakeram.cfg` says
  "VALUES NOT REALISTIC": never use them for energy or timing claims. No memory has been measured with them here.
- ASAP7 is a predictive library: always label its numbers as predictive.

**3.2 Per-cell leakage, DFFHQNx1 at TT, mean over states:**

| flavour | leakage | vs sky130 `dfxtp_1` (8.44 pW) |
|---|---|---|
| SRAM-Vt | 52.5 pW | 6.2× |
| RVT | 229.7 pW | 27× |
| LVT | 2.22 nW | 263× |
| SLVT | 22.5 nW | 2 670× |

ASAP7 lists every leakage state twice, with `related_pg_pin : VDD` (the value) and `VSS` (0). Averaging all groups
halves the result, an error that has already reached a paper draft here. Average only the VDD groups. The flavour
ratios (4.4×, 9.7×, 10.1× between neighbours) agree with the off-currents of the ASAP7 tutorial (0.1 / 1 / 10 /
100 nA/µm for SRAM / RVT / LVT / SLVT). OpenSTA's design leakage is not affected.

**3.3 Corners.**

| corner | liberty | ORFS name | ORFS `*_TEMPERATURE` |
|---|---|---|---|
| TT | 0.70 V, 25 °C | `TC` | 0C (wrong) |
| FF | 0.77 V, 0 °C | `BC` | 25C (wrong) |
| SS | 0.63 V, 100 °C | `WC` | 100C |

- **ORFS optimises at FF by default**, for historical reasons (a maintainer chose BC because of a problem reading the
  TT flip-flop library, ORFS issue #231); it is still the default upstream, so upstream ORFS QoR numbers are FF
  numbers too, while papers usually report TT 0.7 V 25 °C. `platforms/asap7/config.mk` has `export CORNER ?= BC`.
  Runs on this machine that did not set `CORNER` were synthesised, repaired and clock-tree-built at FF while power was
  taken at TT, and their documents wrongly said TT. Pass `CORNER=TC` to optimise at TT, or sign off yourself at the
  corner you report (section 7), and write the corner into the result file.
- **The RVT `SIMPLE` FF liberty is mis-characterised**: `asap7sc7p5t_SIMPLE_RVT_FF_nldm_211120.lib.gz` says 0.7 V,
  25 °C while the other FF files say 0.77 V, 0 °C (asap7sc7p5t_28 issue #3; re-characterised upstream in ORFS commit
  `3a376ac`, 2026-02-23, as a `_250407` file). RVT runs at the default BC corner used it; SRAM-Vt is fine. Another
  reason to optimise at `TC`.
- The platform temperatures for BC and TC are swapped relative to the liberties (still so upstream); this ORFS reads
  them nowhere. The "0.77 V supply" in ORFS IR reports is the FF voltage, not an IR-drop figure.
- **SS is leakage-dominated.** At 100 °C, the leakage of a 20 k-cell RVT core was 46.5 µW against 3.3 µW at TT, while
  its dynamic energy dropped 35 %: total energy per bin 0.175 nJ at SS against 0.058 nJ at TT. Report dynamic and
  leakage separately when you show SS. (These numbers use the post-reset idle leakage of 9.5 and probably predate
  the fix of 9.2: the trend holds, the values do not.)

**3.4 Units: the most common ASAP7 error.**

| where | unit |
|---|---|
| liberty | time **ps**, capacitance fF, leakage **pW**, current mA |
| SDC (ORFS and OpenSTA) | **ps**: 200000 for 5 MHz, 20000 for 50 MHz |
| ORFS metrics (`*.json`: slack, period) | ps; multiply by 1e-3 for ns |
| SPEF | `T_UNIT 1 NS`, `C_UNIT 1 PF` |
| OpenSTA `write_sdf` | `(TIMESCALE 1ps)` |
| vendor Verilog models | `` `timescale 1ns/10ps `` in every module (use 1 ps copies, 8.1) |
| `asap7_seq_icarus.v` | `` `timescale 1ns/1ps `` |

- `create_clock -period 20` in a power script means 20 ps, not 20 ns: it made a clock network's power 2.29 mW instead
  of 0.0315 mW and the total 2.47 mW instead of 0.148 mW. Compare with ORFS's own power report to catch it.
- A result collector once printed ASAP7 slacks in ps as if they were ns. Convert in one place, and name variables by
  their unit.

## 4. RTL rules for ASAP7

- **Clock gates: instantiate `ICGx1_ASAP7_75t_<f>` directly** (`.CLK .ENA .SE(1'b0) .GCLK`), behind a define, with a
  behavioural model for RTL simulation. The platform marks `ICG*`, `SDF*`, `*xp*` and `*x1p*` as don't-use, which
  stops synthesis from choosing them but not direct instantiation. The ASAP7 ICGs are true integrated clock gates
  (`clock_gating_integrated_cell : latch_posedge_precontrol`), which matters for power (9.2). ORFS's portable
  alternative is to instantiate `OPENROAD_CLKGATE` (`CK`, `E`, `GCK`) with `export VERILOG_DEFINES += -D
  OPENROAD_CLKGATE`; `CLKGATE_MAP_FILE` maps it to `ICGx1`. Without the define the map file turns every gate into a
  wire (`assign GCK = CK`), silently: count the ICGs in `1_2_yosys.v`.
- **Retarget every sky130 cell.** A latch core failed in ORFS within 1 s because sky130 `dlclkp_1` gates were left in
  the RTL. Grep the RTL for `sky130_` before an ASAP7 run.
- **Latches** are inferred (`always @*`) and mapped by `cells_latch_<f>.v` to `DHLx1` (active high) and `DLLx1`
  (active low). Check the latch count in the routed netlist against the RTL. Yosys `stat` counts only flip-flops as
  sequential area; latches are not counted.
- **Flip-flops have only a QN output** (`DFFHQNx*`), so they power up at 1 in Verilator. The testbench must ignore the
  outputs during reset.
- **A separate write clock for latch memories.** With one clock for the core and the latch-row write gates, CTS
  balanced the core clock against the deep write trees and the clock took 73 % of power. A separate, host-driven
  write-clock port fixed it.
- **`(* keep_hierarchy *)` produces escaped flat names** (`\u_neu/_10240_`) and breaks parasitic matching
  (section 9.4). Either keep the design flat or rename (sky130 notes section 5.4). ORFS's own flatten setting is not
  the cause; the attributes in the RTL are.

## 5. Synthesis

Settings that every ASAP7 config needs:

| setting | why |
|---|---|
| `ADDER_MAP_FILE :=` (empty) | **Adder mapping produces wrong netlists**: outputs off by ±2 against the RTL, already in `1_synth.v`, same on NanGate45. A SAT miter found a counterexample (an accumulator wrong 11 cycles after reset). With the map disabled, the netlists are bit-exact. The likely cause is Yosys `extract_fa`, which ORFS runs before this techmap: it miscompiled xor3/xnor3 polarity before Yosys 0.50 (YosysHQ PR #4691, 2025-02; issue #3660). The old stack's Yosys is 0.46; the default (0.62) has the fix, but keep the map off until an equivalence check of `1_2_yosys.v` against the RTL (Yosys/eqy) or the bit-exact simulation confirms it on your design. ORFS's `EQUIVALENCE_CHECK=1` (and `LEC_CHECK`) only checks the timing repair at CTS, not synthesis. |
| `SYNTH_MEMORY_MAX_BITS` | The default 4096 aborts on case-statement ROMs ("Synthesized memory size N exceeds SYNTH_MEMORY_MAX_BITS"; older ORFS: "... exceeds maximum allowed bits"). Values of 65536 and 1e6 were used. Never follow ORFS's suggestion `SYNTH_MOCK_LARGE_MEMORIES=1` for a measurement: it shrinks every large memory to one row. |
| `ABC_AREA=1` | Fewer cells and fanout violations. |
| `REMOVE_ABC_BUFFERS` | Old checkout: `=1` runs `remove_buffers` *instead of* the floorplan-stage `repair_timing` (setup and hold with ideal clocks), whose hold repair hit `RSZ-0060 Max buffer count reached` through nested clock gates at a 200 ns clock. In `ef2cb37` the floorplan repair is setup only and the variable is deprecated (use `SETUP_SLACK_MARGIN` or `SKIP_LAST_GASP=1`); set it only to stay comparable with old-checkout runs. Removed upstream (ORFS PR #4580, 2026-10-21). |

- **Count cells from the netlist plus all five liberty files** (AO, INVBUF, OA, SEQ, SIMPLE), not from flow metrics:
  `finish__design__instance__count__stdcell` includes the taps; fill (and the SRAM-Vt decaps, 6.3) is
  `class:fill_cell`.
- **Compare the synthesis netlist with the RTL bit for bit** before placing anything.

## 6. Place and route with ORFS

**6.1 Settings** (beyond section 5):

| setting | value | note |
|---|---|---|
| `CORE_UTILIZATION` | policy: 60 → 20 % in steps of 10 for small logic cores; 20 → 15 → 10 % for large latch cores | for one SRAM-Vt core, energy was flat within 1 % from 40 to 60 % and 9 % lower at 70 %; report the accepted utilisation with every number (sky130 notes 5.3) |
| `PLACE_DENSITY_LB_ADDON` | 0.10 | |
| `TNS_END_PERCENT` | 100 | the default |
| `DETAILED_ROUTE_END_ITERATION` | 40 to 64 | with a violation watchdog, as in sky130 notes 5.3. Leave `DETAILED_ROUTE_ARGS` unset: it replaces the default arguments, and with the LibreLane binaries `-bottom_routing_layer`/`-top_routing_layer` in it abort with `DRT-0509`/`DRT-0510` (deprecated; the platform sets the layers itself) |
| `NUM_CORES` | `$JOBQ_THREADS` | default: every CPU (section 0) |
| `CORNER` | set it explicitly | default BC = FF (3.3) |
| SDC | no `set_propagated_clock` | ORFS adds it after CTS |

**6.2 Make syntax.** `make` keeps the spaces before an inline `#` comment: `export PLATFORM = asap7   # note` sets
`"asap7   "` and fails with "Is a directory". Put comments on their own line.

**6.3 Decaps in the SRAM-Vt flavour.**
- The old checkout's SRAM-Vt patch forced `FILL_CELLS` to include `DECAPx1…x10`, after and over the design config;
  the default ORFS includes DECAPs in its default `FILL_CELLS` for every flavour. In one run, 796 602 decaps covered
  69 % of the core, and the report showed "98 % utilisation" at `CORE_UTILIZATION=20`. Fix: pass `FILL_CELLS` without
  decaps on the `make` command line.
- DECAPs are in the default `FILL_CELLS` for RVT too. The RVT, LVT and SLVT LEFs declare them `CLASS CORE SPACER`, but
  the SRAM-Vt LEF declares `DECAPx*_SRAM` as `CLASS CORE`, so ORFS counts decaps as standard cells: utilisation 0.94
  against 0.66 and area 3 441 against 2 469 µm² in one core. The installed checkout has this fixed (`SPACER`) by the
  local patch `apply_sram_vt_orfs.sh`, except `DECAPx2b`, which the default fill does not use; upstream and the old
  checkout have not. Report logic-only area.
- Decaps, fillers and taps have no ASAP7 liberty, so they cost area, routing and simulation time, not power (9.3).

**6.4 Clock-tree synthesis.** CTS used `BUFx24` for every clock buffer: 56 466 buffers and 59 764 clock nets in a
latch core with one tree per 512-latch row; the clock tree took 12.8 µW of 30.6 µW leakage. A smaller CTS buffer is a
candidate fix, not yet tested. **`CTS_BUF_CELL` does nothing** (removed as obsolete in ORFS PR #2029, 2024-05):
use `CTS_BUF_LIST` (this ORFS passes it as `-buf_list`), not `CTS_ARGS`, which replaces all CTS arguments.

**6.5 Failures seen and their fixes.**
- Global-routing congestion (`GRT-0116` or `GRT-0232`; old OpenROAD `GRT-0119`): a 20 k-cell core at 60 % (closed at
  50 %); large latch cores at 20, 15 and 10 % after up to 7.5 h, although a similar core routed at 20 % (old
  checkout, adjustment 0.5: derated resources 50–63 % per layer). In `ef2cb37` the ASAP7 platform's `fastroute.tcl`
  fixes the layer adjustment at 0.25 (M2–M7) and `ROUTING_LAYER_ADJUSTMENT` is ignored: to change it, point
  `FASTROUTE_TCL` at a project copy with another value (keep its `set_routing_layers` lines) and rerun from
  floorplan; `GRT-0704` suggests a value. Other levers: `MAX_ROUTING_LAYER` (default M7), `PLACE_DENSITY`.
- "stack smashing detected" (signal 6) in timing-driven global placement ("executing resizer for reweighting nets").
  The same crash in OpenLane was fixed by turning timing-driven placement off; the ORFS equivalent
  `GPL_TIMING_DRIVEN=0` (default 1) is untested (no upstream report found). The default OpenROAD also crashed in
  timing-driven placement on a sky130 design (sky130 notes 1.1).
- Detailed routing out of memory: a 400 k-instance latch core at 19 GB, another core at 29.6 GB in the first
  iteration. Declare memory per section 10.
- Rerunning `do-5_2_route` from a copied `5_1_grt.odb`: copy `5_1_grt.sdc` with it (the old checkout also needs
  `reports/.../congestion.rpt`).

**6.6 Watchdog.** A `pkill -f "DESIGN_NICKNAME=..."` matches nothing, because the nickname is in the config file, not
on the command line. Find the `openroad` process IDs and kill those, or kill the process group started with `setsid`
(under `jobq`, cancelling the job does this). The watchdog must not count time the job spent frozen by the queue
(sky130 notes 5.3): ASAP7 runs last hours.

**6.7 Acceptance.** Accept only when:
- `5_2_route.json` has DRC 0;
- setup is met at the reported corner (ORFS slack in ps);
- hold is met, checked yourself (7.2);
- logic cell counts match the RTL (section 4).

ORFS also leaves tens to hundreds of max-slew violations per run; record the count.

## 7. Timing sign-off

**7.1 Setup.** Sign off with OpenSTA yourself on the routed netlist and SPEF at the corner you report (sky130 notes
6.2), because ORFS signs off at FF by default (3.3). A reported setup slack of 0.00 on latch paths is time borrowing,
not a zero margin.

**7.2 Hold.** The old ORFS reports no hold slack (the metric was added upstream in March 2025): its
`6_report.json` has no `finish__timing__hold__ws`, so scripts read "NA" and accept. The default ORFS reports it. Hold
is repaired at CTS and after global routing, and never after detailed routing (still so upstream).
- A run accepted this way had `finish__timing__drv__hold_violation_count: 187`, worst −154 ps at FF. Global routing
  showed none; they appear only after RCX extraction.
- An own check (`tools/hold_sta.tcl`, TT/SS/FF with SPEF) found −12 ps and −14 ps at FF and −7 / −3 ps at TT in a
  20 k-cell core that the flow had accepted.
- Gate on `hold_violation_count == 0` or, better, on your own OpenSTA hold check at every corner you report.
- ORFS hold repair after global routing ran about 3 h on about 200 endpoints in a large latch core. The cause was skew
  between gated clock subtrees on a path that is not functional; a false path fixed it. Keep such exceptions minimal
  and count the objects they match (sky130 notes 6.1).

**7.3 Latch paths.** Do not waive them (sky130 notes 9.2). Time them.

## 8. Gate-level simulation

**8.1 Icarus with SDF** (verified bit-exact against the RTL over 200 and 5 000 bins, with zero `SDF ERROR` lines):
- **ORFS writes no SDF.** Write it with OpenSTA (`tools/write_sdf_sta.tcl`): netlist, SPEF, the liberties of the
  corner you report, propagated clock, `write_sdf -divider / -include_typ -digits 4`.
- **Vendor SEQ models stay X.** They use `altos_dff` UDPs with an uninitialised notifier; annotated runs completed 0
  bins in 7 h. (The `delayed_*` nets were first blamed, but this Icarus drives them since iverilog PR #966; the X more
  likely came from the notifier or the ps/ns time scale. Not retested yet.) Replace them with
  `tools/asap7_seq_icarus.v` (behavioural, IOPATH-only specify blocks) and keep the vendor AO, INVBUF, OA and SIMPLE
  models. Zero-delay runs work with the vendor models.
- **Sanitise the SDF** (`tools/sdf_sanitize_for_icarus.py`). Icarus up to v13_0 ignores `(TIMESCALE 1ps)` and reads
  113 ps as 113 ns (a core stalled for 7 h); the sanitiser rescales to ns and fills empty triplets with 0.
- **ICG rise delay became 0** with earlier sanitiser versions: the conditional CLK→GCLK arcs are fall-only, so their
  rise triplets are empty; zero-filled and unwrapped, they came last and overrode the unconditional value, so every
  clock gate ran with 0 ps rise delay (all 294 gates of one core). The sanitiser now drops those repeats (588 lines
  in that core). Effect on that core's glitch factor: 1.300 → 1.309.
- **Delays are rounded to 10 ps** (also raised upstream, asap7 issue #42). The models declare
  `` `timescale 1ns/10ps ``, so 22.7 ps becomes 20, 14 becomes 10, 4 becomes 0. ASAP7 gate delays are 5–45 ps, so this
  is coarse, and glitch factors measured this way carry the error. Fix: every module of the vendor models repeats
  the directive, so a timescale file compiled first does not override it, and Icarus has no option that does; compile
  copies made with `` sed 's#`timescale 1ns/10ps#`timescale 1ns/1ps#; s#`timescale 1ns / 10ps#`timescale 1ns/1ps#' ``.
  `tools/asap7_seq_icarus.v` has 1 ps since 2026-10-30.
- **INTERCONNECT is dropped, not matched** (about 47 000 lines for a 20 k-cell core). The wires are 0.07–0.19 ps, so
  the effect is negligible.
- Compile a `` `timescale 1ns/1ps `` file first (for files without a directive, such as the netlist). `6_final.v` of
  this ORFS contains no physical-only cells; netlists of the old checkout need empty stubs for tap, fill and decap.
- Write the net activities after the pin activities (sky130 notes 7.2): Icarus can leave a cell's output-port
  variable constant while its net toggles.
- `asap7_seq_icarus.v` covers DFFHQNx1/2/3, ICGx1/2 and DHLx1; add DLLx1 if the design uses it. (Synthesis never
  chooses an ICG, they are don't-use; ICGx2 appears where the RTL instantiates it.)

**8.2 Verilator, zero delay:** functional models generated from the liberty (`tools/liberty2verilog.py`), stubs for
physical cells. A 1.58 M-instance routed core built in 20 min (about 6–8 GB) and ran in 6 min. Liberty-generated
models hung in Icarus, so this route is for Verilator only.

**8.3 Glitch factor** (annotated over zero-delay energy): 1.17–1.28 on ASAP7 for small decoder cores, against
1.18–1.22 on sky130 for the same cores (these carry the 10 ps rounding). Earlier values of 1.07–1.11 were wrong (9.2).
A 72 000-instance time-multiplexed SNN core with a latch memory (SRAM-Vt, TT, 1 ps model precision, correct ICG
delays, zero SDF errors, bit-exact): 1.31 overall; by function clock tree 1.00, repair buffers 1.00, memory 1.09,
control 1.12, output 1.42, neurons 1.69, synapses 1.94. Glitches concentrate in arithmetic; a factor measured on one
design transfers to another only if the arithmetic share is similar.

## 9. Power with OpenSTA

**9.1 Setup.** Read all five liberty files of the flavour and corner, the netlist and the SPEF; give the clock period
in ps; set unannotated inputs to activity 0 (sky130 notes 8.1). OpenSTA 2.7 converts `set_power_activity -activity`
with the fastest defined clock (`-clock` is ignored): define only the clock the activities were normalised to, or
write `-density`. This matters for designs with a separate write clock (section 4).

**9.2 Do not stop clock propagation at the ICGs** (sky130 notes 8.2). With `set_clock_sense -stop_propagation` at the
clock-gate outputs and per-cycle activities from a toggle file, OpenSTA has no clock behind the gates to convert the
activities with, so the internal and switching power of everything downstream vanishes. The sequential and clock
groups are unaffected, so the totals still look plausible. Runs on GF180, IHP, NanGate45 and ASAP7 showed a
combinational group of 0.03–0.6 % of the total, against 52 % for the same core on sky130 without the stop. ASAP7
energy per bin was too low by 55–123 %, and ASAP7's advantage over sky130 fell from about 60× to about 35× once
fixed. The ASAP7 ICGs carry `clock_gating_integrated_cell`, so OpenSTA scales the gated subtrees itself; no stop is
needed. The loss is specific to the OpenSTA of OpenLane 2.3.10, but the rule stands.

**9.3 Physical cells are black boxes.** No ASAP7 liberty defines FILLER, DECAP or TAPCELL, so OpenSTA black-boxes them
with zero leakage ("module … not found"). `6_final.v` of this ORFS leaves them out, so expect no black box at all:
any black box is a real error. Netlists of the old checkout contain them: check that only physical cells are black
boxes. Decap-free fill makes no power difference on ASAP7.

**9.4 Parasitics and escaped names.** With `keep_hierarchy`, the netlist has `\u_neu/_10240_` and the SPEF the bare
`u_neu/_10240_` under `*DIVIDER /`. OpenSTA dropped 4.87 million SPEF entries (863 k of 2.04 M nets) in one design,
which invalidated its power breakdown. Fix: `tools/legal_names.py` (sky130 notes 5.4), then expect zero
`spef ... not found` warnings. Flat cores match fully. ORFS keeps Yosys' register names on the cells
(`\u_wmem/lat[39]$_DLATCH_P_`), and the old OpenROAD's SPEF writes them with escaped brackets but a bare `$`
(`u_wmem/lat\[39\]$_DLATCH_P_`), a fourth spelling (the default OpenROAD escapes the `$` too): `legal_names.py`
handles both since 2026-10-25 (earlier versions missed 187 893 entries of one core). OpenSTA 2.7 reads escaped names
itself (sky130 notes 5.4), so with the default tools the renaming matters for Icarus.

**9.5 Leakage depends on cell state.** ASAP7 per-state leakage differs by large factors, unlike sky130, GF180 or
NanGate45. In a 20 k-cell RVT core: idle after reset 3.30 µW, decode window 2.35 µW, real-time run 2.64 µW; in SRAM-Vt
idle 0.719 µW, real time 0.583 µW (−18 %). Take leakage from the same window as the activity, never from a post-reset
idle run.

**9.6 Root-clock correction** (sky130 notes 8.2) applies to ASAP7 designs that stop their clock, with two changes
(`tools/root_clock_correction_multipdk.py` has both):
- the walk from the clock port must continue through hold buffers (`BUFx2` in ORFS, `HBx` where a flow allows them);
- for root flip-flops, scale the annotated internal power by the clock duty directly; the zero-data run gave a
  state-dependent value 18 % too low (dynamic energy per bin 0.0913 → 0.0876 nJ in one core).
- the ICG clock pin's internal power is state-dependent too (conditioned on `ENA` and `GCLK`): condition the duties of
  root clock gates on the clock enable, as for SRAM22 (sky130 notes 9.1, 9.3).

**9.7 Reports.** Breakdown scripts written for sky130 match sky130 cell names only: they report no clock tree on ASAP7
and put ASAP7 CTS `BUFx` cells in "Combinational". Check the breakdown classes by cell name for ASAP7.

## 10. Runtime and memory

| run | threads | time | peak memory |
|---|---|---|---|
| 10–20 k-cell cores, full ORFS flow | ~5 | 6–30 min | 6.2 GB |
| 400 k-instance latch core, detailed routing | ~5 | killed after 77 min | > 19 GB |
| 1.3 M-instance latch core, full flow | 6 | 7.3 h | 32.5 GB |
| ↳ global routing (mostly hold repair) | | 4.7 h | 13.1 GB |
| ↳ detailed routing (131 883 → 0 violations in 5 iterations) | | 92 min | 32.5 GB |
| ↳ `6_report` (RCX) | | 18 min | 19.5 GB |
| ~1 M-instance cores: synthesis / global placement / global routing | 3 | 5 / 20 / 12 min | 3 / 7 / 15 GB |
| Icarus SDF, 5 000-bin window, 20 k-cell core | 1 | 60 min RVT, 55 min SRAM-Vt | < 1 GB |
| Verilator, 1.58 M-instance routed netlist | | build 20 min, run 6 min | 6–8 GB |

Detailed-routing memory scaled at about 124 kB per synthesised cell.

## 11. Checklist for every measurement

Everything in sky130 notes section 10, plus:

| check | expect |
|---|---|
| `NUM_CORES` passed to `make` | `$JOBQ_THREADS` |
| `read_liberty` lines of the synthesis and floorplan logs | the intended flavour (`*_SRAMVT_*` for SRAM-Vt) and corner (1) |
| `CORNER` used by ORFS, and the corner of sign-off and power | stated in the result file |
| `ADDER_MAP_FILE` | empty, unless an equivalence check proves the mapped netlist (Yosys 0.62 has the `extract_fa` fix) |
| every period, slack and delay | converted between ps and ns in one known place |
| synthesis and routed netlist against RTL | bit-exact |
| `DECAP` cells in the fill log | only if intended |
| hold, own OpenSTA check with SPEF | met at every reported corner |
| `spef ... not found` warnings | 0 |
| `-stop_propagation` in the power script | absent |
| clocks in the power script | only the one the activities were normalised to (9.1) |
| ICGs in `1_2_yosys.v` | the number the RTL instantiates (4) |
| Icarus model precision | 1 ps, not 10 ps |
| annotated ICG `CLK→GCLK` rise delay | non-zero |
| leakage window | the same window as the activity |
| per-cell leakage computed from the liberty | VDD groups only |

## 12. Sanity numbers

- **A 20 k-cell pruned decoder core at 5 MHz, TT** (RVT / SRAM-Vt): 19 954 / 19 604 logic cells (1 491 flip-flops,
  3 ICGs), 0.00245 / 0.00237 mm², leakage 2.64 / 0.583 µW, dynamic energy 0.0876 / 0.0820 nJ per bin (the same core
  on sky130: 2.81 nJ). Setup slack about 120 ns at 200 ns. Clock skew 64–158 ps. These include the 10 ps rounding of
  8.1 and were measured before the ICG rise-delay fix of 8.1 (2026-10-28).
- **f_max at SS** of that core: 667 MHz RVT, 480 MHz SRAM-Vt. An earlier 2.3 / 1.8 GHz came from runs with stopped
  clock propagation and is not trusted.
- **A large latch-memory core**: the weight memory was about 86 % of the area.

## 13. Open questions

General questions that no measurement here has answered yet. Report answers through the inbox.

| question | section |
|---|---|
| Do the vendor ASAP7 SEQ models work in current Icarus once the notifier is initialised and the SDF rescaled? | 8.1 |
| Does a smaller CTS buffer list reduce the clock-tree power of latch-row cores? | 6.4 |
| Which global-routing layer adjustment (through `FASTROUTE_TCL`) lets large latch cores route at 15–20 %? | 6.5 |
| Does `GPL_TIMING_DRIVEN=0` avoid the "stack smashing" crash? | 6.5 |
| How much slower is an ORFS run in swap than in RAM? | 10 |
| Where does the remaining ~5 % of dynamic energy after the root-clock correction come from (joint D/QN states of the clock-pin tables)? | 9.6 |
| Are fakeram7 macros, re-characterised with CACTI, usable for energy claims? | 3.1 |
| Why did a Verilator run on one synthesis netlist fail where Icarus and the routed netlist passed? | 8.2 |

### Version history

| version | date | change |
|---|---|---|
| 1.0 | 2026-10-24 | first version, from the ASAP7 measurements on this machine and an audit of them |
| 1.1 | 2026-10-24 | section 0: the shared `jobq` queue |
| 1.2 | 2026-10-24 | 9.2: no clock-propagation stop; 8.1: net activities after pin activities |
| 1.3 | 2026-10-24 | rules checked against upstream ORFS, issue trackers and papers; sources added. Corrected: adder-map error is a Yosys `extract_fa` bug; `REMOVE_ABC_BUFFERS`; `CTS_BUF_CELL` does nothing; hold repair stages; cause of the X in vendor SEQ models. New: mis-characterised RVT FF liberty, SRAM-Vt decap class, fakeram values, `QT_QPA_PLATFORM`, congestion levers |
| 2.0 | 2026-10-24 | only the maintainer edits the notes; findings go to `inbox/` |
| 3.0 | 2026-10-24 | the notes are general: no references to individual projects. Reference tools in `flow_notes/tools/`; open questions instead of per-project open issues (13); broadcast announcements in `ANNOUNCEMENTS.md` |
| 4.0 | 2026-10-24 | **new default versions** (section 1): ORFS `ef2cb37` with the LibreLane binaries, SRAM-Vt via `ASAP7_USE_VT=SRAM`, corrected RVT FF liberty, hold slack reported; the SRAM-Vt patch notes of 1, 6.3 updated |
| 4.1 | 2026-10-25 | the queue's guide for agents is now `/media/amir/.jobq/AGENTS.md` (section 0) |
| 4.2 | 2026-10-28 | from the inbox: `DETAILED_ROUTE_END_ITERATION` instead of `DETAILED_ROUTE_ARGS` (6.1); sanitiser fixed for the ICG rise delay and the time scale (8.1); ICGx2 model; glitch factor of a latch-memory core by function (8.3); fourth SPEF spelling for `legal_names.py` (9.4) |
| 5.0 | 2026-10-30 | full review against the ORFS `ef2cb37` sources: start-here and silent-error table; history moved to the end. Corrected for this ORFS: the flavour check reads the logs (1, 11); `ROUTING_LAYER_ADJUSTMENT` is ignored on ASAP7, use `FASTROUTE_TCL` (6.5); `CTS_BUF_LIST` exists (6.4); `REMOVE_ABC_BUFFERS` deprecated (5); `EQUIVALENCE_CHECK` does not cover synthesis (5); routing rerun and congestion messages (6.5); no physical cells in `6_final.v` (8.1, 9.3); the SPEF `$` spelling (9.4); hold buffers are `BUFx2` (9.6). New: `-D OPENROAD_CLKGATE` or the gates become wires (4); never `SYNTH_MOCK_LARGE_MEMORIES` (5); 1 ps model copies with `sed` (8.1); OpenSTA 2.7 converts activities with the fastest clock (9.1); watchdogs and frozen jobs (6.6); ICG clock-pin power is state-dependent (9.6); SS numbers flagged (3.3) |
