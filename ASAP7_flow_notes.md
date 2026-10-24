# ASAP7 flow notes: synthesis, place and route with ORFS, gate-level simulation and power

**Version 1.2, last updated 2026-10-24.** The full history is in "Version history" below.

Read this before you synthesise, place and route or measure anything on ASAP7 (the predictive 7 nm library) in any
project under `/media/amir`. It is written for engineers and AI agents. It collects what BCI_paper (rounds 2–10,
September–October 2026) and KWS_neuromorphic_tech_node (October 2026) learned, plus an audit of both made on
2026-10-24. It is the sibling of `/media/amir/flow_notes/skywater130_flow_notes.md`. The general method is described there and
is not repeated here: shared-machine rules, escaped-name renaming, activity annotation, the root-clock correction,
the reproducibility rules. Read that file too. Most of the problems below fail **silently**: the flow runs to the end
and prints a plausible number that is wrong. Section 11 is the checklist every measurement must pass.

**Keep this file current.** If you, engineer or AI agent, find a new pitfall, a mistake in this file, or a better
fix, update this file in the same session, before you finish:
- add the item to the section it belongs to, with its symptom, how to detect it, the fix and, if you measured it, the
  size of the effect;
- correct anything that turned out wrong, rather than adding a contradicting note;
- add the date and the project where it was found, for example "(found 2026-10-23, KWS)";
- add a line to the checklist of section 11 if the problem can be detected automatically;
- move an item out of section 13 (open issues) once it is resolved;
- raise the version in the line under the title and add a row to the version history below. Raise the minor number
  (1.0 → 1.1) for an added or corrected item, the major number (1.x → 2.0) when a recommended practice changes or a
  section is rewritten.

Tell the owner what you changed. If the lesson is not specific to ASAP7, put it in the sky130 notes instead (or as
well); this file covers what differs on ASAP7 and ORFS.

**Is my copy current?** Record the version you read in your project's notes. At the start of the next session,
compare it with the line under the title. If the version has changed, read the history rows since your version.

### Version history

| version | date | project | change |
|---|---|---|---|
| 1.0 | 2026-10-24 | all | first version: BCI_paper and KWS records, the chat histories, and an audit of both projects' ASAP7 flows |
| 1.1 | 2026-10-24 | all | section 0: the shared `jobq` queue in `/media/amir/.jobq` replaces KWS `tools/jobq.py`; open issues handed to each project as `ASAP7_FLOW_ISSUES.md` |
| 1.2 | 2026-10-24 | all | 9.2: the sky130 notes no longer recommend the clock-propagation stop; 8.1: net activities after pin activities (sky130 notes 7.2) |

Contents:
0. Ground rules on this machine
1. Tools and paths
2. Reference implementations to copy from
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
13. Open issues

---

## 0. Ground rules on this machine

All of section 0 of the sky130 notes applies: low priority, check memory first, start long jobs detached with
`setsid`, never edit a running script. **Submit every heavy job through the shared queue `jobq`** (`/media/amir/.jobq`,
guide in its `README.md`), which replaced the old KWS `tools/jobq.py` on 2026-10-24. In addition, for ASAP7:

- **ORFS uses every core unless told otherwise.** `NUM_CORES` defaults to `nproc` (24). BCI never set it, and its
  detailed routing ran at about 520 % CPU. Always pass `NUM_CORES=N` with N ≤ 10, and declare the same N in the queue.
- **Declare realistic memory.** Detailed routing of a 1.3 M-instance latch core peaked at 32.5 GB (section 10). The
  KWS run was declared at 12 GB. A 400 k-instance core was OOM-killed at 19 GB in BCI.
- **Swap.** The owner's ruling (KWS, 2026-10-22): do not shrink an experiment just because it does not fit in
  memory; swap is acceptable if the run is less than 5× slower, but other users' and system processes must never be
  pushed into swap. The slowdown has not been measured yet (section 13).
- **One driver per ORFS design directory.** Two scripts running `make` on the same design, or a script edited while
  it ran, gave `mv: cannot stat *.tmp.log` and `ORD-0007 … odb does not exist` (BCI, 2026-09-19). Give every run its
  own `WORK_HOME` (KWS does this).
- **The ORFS checkout is shared.** Do not `git checkout`, `git pull` or reset `/media/pdk/OpenROAD-flow-scripts`:
  it carries a local patch (section 1) that every SRAM-Vt run depends on.

## 1. Tools and paths

| what | where / version | how to call |
|---|---|---|
| ORFS | `/media/pdk/OpenROAD-flow-scripts`, commit `b4dbcb4` (2024-10-02), chosen to match the OpenROAD of OpenLane 2.3.10; **locally modified** (below) | `make` in `flow/`, see below |
| OpenROAD, Yosys, KLayout, OpenSTA | not built inside ORFS; taken from the OpenLane 2 Nix shell: OpenROAD `edf00dff`, **Yosys 0.46** (`e97731b`), OpenSTA 2.6 | `nix --extra-experimental-features "nix-command flakes" develop --accept-flake-config /media/hardware_design_tools/openlane2 -c ...` |
| ASAP7 platform | `/media/pdk/OpenROAD-flow-scripts/flow/platforms/asap7`; `/media/pdk/asap7` is a symlink to it | `PLATFORM=asap7` |
| liberty (NLDM) | `platforms/asap7/lib/NLDM/`: `asap7sc7p5t_{AO,INVBUF,OA,SIMPLE}_<flavour>_<corner>_nldm_*.lib.gz` and `..._SEQ_..._nldm_220123.lib` (SEQ not gzipped) | OpenSTA reads `.gz` directly |
| upstream library | `/media/pdk/asap7sc7p5t_28` (sparse clone, `472f7b3`): `LIB/NLDM/*.7z`, `Verilog/` (all flavours) | |
| Verilog cell models | ORFS ships RVT TT only (`platforms/asap7/verilog/stdcell`); SRAM-Vt from `/media/pdk/asap7sc7p5t_28/Verilog` | see section 8 before simulating |
| Icarus model copies | `/media/pdk/icarus_sdf_models/asap7sc7p5t_*_{RVT,SRAM}_TT_*_sdf.v` (notifier initialised) | **not validated**: no project uses them |
| Icarus Verilog | OSS CAD Suite, see sky130 notes section 1 | |

**Invocation** (`KWS_neuromorphic_tech_node/synthesis/harden_asap7.sh`):

```
export QT_QPA_PLATFORM=offscreen
nix ... develop --accept-flake-config /media/hardware_design_tools/openlane2 -c bash -c \
  "cd /media/pdk/OpenROAD-flow-scripts/flow && make WORK_HOME=<own dir> DESIGN_CONFIG=<path>/config.mk \
   NUM_CORES=<=10 FILL_CELLS='FILLERxp5_ASAP7_75t_SRAM FILLER_ASAP7_75t_SRAM' \
   OPENROAD_EXE=\$(which openroad) YOSYS_EXE=\$(which yosys) KLAYOUT_CMD=\$(which klayout)"
```

- **`QT_QPA_PLATFORM=offscreen` is required.** Without it `6_report` aborts on a Qt plugin error (signal 6, rc=2) even
  when the route is clean, and an acceptance script rejects a good run (BCI round 6: g32p50 was first rejected at 60 %).
- **The local patch.** `git status` shows `flow/platforms/asap7/config.mk` modified: BCI added the `ASAP7_USESRAM`
  block (lines 207–255) and the untracked `yoSys/cells_{latch,clkgate,adders}_SRAM.v` (sed copies of the `_R` files)
  in September 2026. Upstream ORFS at this commit has no SRAM-Vt flavour. If the patch is lost, `ASAP7_USESRAM=1` is
  silently ignored and the run uses RVT: after synthesis, check that `objects/.../lib/` holds `*_SRAM_*` files.
  - The block assigns with `=`, because with `?=` the RVT defaults won and the flow failed with
    `TAP-0010 Master TAPCELL_ASAP7_75t_R not found` (BCI, 2026-09-19). Side effect: it also forces `FILL_CELLS`,
    which overrides a design config (section 6.3).
- **Stale paths.** BCI's designs under `flow/designs/asap7/bmi_snn_*`, BCI's `synthesis/orfs/asap7/config.mk`, the
  generated KWS configs and queue entries still point to `/home/yousefzadeha/workspace/...`, which no longer exists.
  Regenerate configs from the current project folder before rerunning anything.

## 2. Reference implementations to copy from

No single project has a fully verified ASAP7 flow yet. Copy the parts that were verified, and fix the open items of
section 13 as you go.

| file | what it does | status |
|---|---|---|
| `BCI_paper/synthesis/run_orfs5.sh` | ORFS runs with a utilisation policy (60 → 20 %), config writing, acceptance (DRC 0, setup ≥ 0) | used for the paper; add `NUM_CORES`, a hold gate (7.2) |
| `KWS_neuromorphic_tech_node/synthesis/harden_asap7.sh` | ORFS for large latch cores, `WORK_HOME` per run, `FILL_CELLS` override, routing watchdog | watchdog `pkill` pattern matches nothing (6.6); accepts hold "NA" |
| `BCI_paper/power/run_write_sdf.sh`, `write_sdf_sta.tcl` | SDF from OpenSTA (ORFS writes none) | verified |
| `BCI_paper/sim/asap7_seq_icarus.v` | behavioural DFFHQNx1/2/3, ICGx1, DHLx1 (RVT and SRAM-Vt) for Icarus | verified bit-exact; lacks ICGx2, DLLx1 |
| `BCI_paper/sim/sdf_sanitize_for_icarus.py` | ps → ns rescale, empty triplets, COND unwrap | see 8.1 for its ICG bug |
| `BCI_paper/sim/gen_phys_stubs.py`, `KWS.../sim/stub_missing.py` | empty modules for tap, fill, decap | verified |
| `BCI_paper/sim/measure_pdk5.sh` | annotated Icarus run → toggles → OpenSTA power at TT | verified; `CLK_STOP_ICG=0` default since round 6 |
| `BCI_paper/power/hold_sta.tcl`, `sw/hold_orfs6.py` | own hold check at TT, SS, FF with SPEF | verified |
| `BCI_paper/power/root_clock_correction.py` | root-clock correction, walks through `HBx` hold buffers | verified; +5.6 % residual (section 13) |
| `KWS.../sim/liberty2verilog.py` | functional models of 202 SRAM-Vt cells from the liberty, for Verilator | truth-table-checked on 57 cells |
| `NEAT_Competition/flow/tools/legal_names.py` | renames escaped names consistently in netlist, SDF, SPEF | verified on sky130; needed for any kept hierarchy (9.4) |

## 3. Library flavours, corners and units

**3.1 Flavours.** Cell names end in `_ASAP7_75t_<f>`: `R` (RVT), `L` (LVT), `SL` (SLVT), `SRAM` (SRAM-Vt, the
lowest-leakage flavour, available here only through the local patch). Footprints are identical.
- **"asap7sram" in BCI is not an SRAM macro**; it is the SRAM-Vt standard-cell flavour. No project has used the
  platform's fakeram macros: every memory so far is flat latches or flip-flops.
- BCI round 3 made "SRAM-Vt" by swapping liberties on the routed RVT netlist (sed); rounds 5–10 hardened natively
  with `ASAP7_USESRAM=1`. Rows labelled SRAM-Vt mean different things in different rounds.
- The owner's choice (BCI round 5, KWS decision 13): SRAM-Vt is the primary ASAP7 result, hardened rather than
  substituted; RVT secondary. ASAP7 is always labelled "predictive".

**3.2 Per-cell leakage, DFFHQNx1 at TT, mean over states** (corrected 2026-10-24, audit):

| flavour | leakage | vs sky130 `dfxtp_1` (8.44 pW) |
|---|---|---|
| SRAM-Vt | 52.5 pW | 6.2× |
| RVT | 229.7 pW | 27× |
| LVT | 2.22 nW | 263× |
| SLVT | 22.5 nW | 2 670× |

ASAP7 lists every leakage state twice, with `related_pg_pin : VDD` (the value) and `VSS` (0). Averaging all groups
halves the result: `BCI_paper/sw/asap7_leakage.py` does that, and the BCI paper's ratios (3×, 14×, 132×, 1336×) are
too low by 2× (open, section 13). Average only the VDD groups. OpenSTA's design leakage is not affected.

**3.3 Corners.**

| corner | liberty | ORFS name | ORFS `*_TEMPERATURE` |
|---|---|---|---|
| TT | 0.70 V, 25 °C | `TC` | 0C (wrong) |
| FF | 0.77 V, 0 °C | `BC` | 25C (wrong) |
| SS | 0.63 V, 100 °C | `WC` | 100C |

- **ORFS optimises at FF by default.** `platforms/asap7/config.mk:311` has `export CORNER ?= BC`, and no script on
  this machine sets `CORNER`. Every BCI and KWS synthesis, repair, CTS and `6_report` ran on the FF libraries, while
  power was taken at TT. So BCI's "hold repair at the typical corner" (`run_log_round6.md`) and KWS's "TT 0.7 V 25 C"
  (`README.md`, `harden_asap7.sh`) are wrong (found 2026-10-24, audit). Pass `CORNER=TC` to optimise at TT, or sign
  off yourself at the corner you report (section 7), and write the corner into the result file.
- The platform temperatures for BC and TC are swapped relative to the liberties (they matter only for IR-drop
  reports). The "0.77 V supply" in ORFS IR reports is the FF voltage, not an IR-drop figure.
- **SS is leakage-dominated.** At 100 °C, RVT sp leakage is 46.5 µW against 3.3 µW at TT, while dynamic energy drops
  35 %. Total energy per bin 0.175 nJ at SS against 0.058 nJ at TT (BCI round 5). Report dynamic and leakage
  separately when you show SS.

**3.4 Units: the most common ASAP7 error.**

| where | unit |
|---|---|
| liberty | time **ps**, capacitance fF, leakage **pW**, current mA |
| SDC (ORFS and OpenSTA) | **ps**: 200000 for 5 MHz, 20000 for 50 MHz |
| ORFS metrics (`*.json`: slack, period) | ps; multiply by 1e-3 for ns |
| SPEF | `T_UNIT 1 NS`, `C_UNIT 1 PF` |
| OpenSTA `write_sdf` | `(TIMESCALE 1ps)` |
| vendor Verilog models, `asap7_seq_icarus.v` | `` `timescale 1ns/10ps `` |

- `create_clock -period 20` in a power script means 20 ps, not 20 ns. In BCI this made the clock-network power
  2.29 mW instead of 0.0315 mW and the total 2.47 mW instead of 0.148 mW. It was caught by comparing with ORFS's own
  power report (BCI, 2026-09-11). BCI's power scripts set `LIB_TIME_UNIT_S=1e-12`, and their variable `PERIOD_NS`
  holds the period in liberty units (ps) despite its name.
- A collector regression later printed ASAP7 slacks in ps as if they were ns (BCI, 2026-09-12). Convert in one place.

## 4. RTL rules for ASAP7

- **Clock gates: instantiate `ICGx1_ASAP7_75t_<f>` directly** (`.CLK .ENA .SE(1'b0) .GCLK`), behind a define, with a
  behavioural model for RTL simulation. The platform marks `ICG*`, `SDF*`, `*xp*` and `*x1p*` as don't-use
  (`config.mk:77-78`), which stops synthesis from choosing them but not direct instantiation. The ASAP7 ICGs are true
  integrated clock gates (`clock_gating_integrated_cell : latch_posedge_precontrol`), which matters for power (9.2).
- **Retarget every sky130 cell.** BCI's latch core failed in ORFS within 1 s because sky130 `dlclkp_1` gates were left
  in the RTL (BCI round 5). Grep the RTL for `sky130_` before an ASAP7 run.
- **Latches** are inferred (`always @*`) and mapped by `cells_latch_<f>.v` to `DHLx1` (active high) and `DLLx1`
  (active low). Check the latch count in the routed netlist against the RTL: in KWS, 155 648 `DHLx1` equalled
  `weight_bits_total`. Yosys `stat` counts only flip-flops as sequential area; latches are not counted.
- **Flip-flops have only a QN output** (`DFFHQNx*`), so they power up at 1 in Verilator. The testbench must ignore the
  outputs during reset (KWS, 2026-10-22).
- **A separate write clock for latch memories.** With one clock for the core and the latch-row write gates, CTS
  balanced the core clock against the deep write trees and the clock took 73 % of power. A separate, host-driven
  `wclk` port fixed it (KWS, 2026-10-22).
- **`(* keep_hierarchy *)` produces escaped flat names** (`\u_neu/_10240_`) and breaks parasitic matching
  (section 9.4). Either keep the design flat or rename (sky130 notes section 5.4). ORFS's own flatten setting is not the
  cause; the attributes in the RTL are.

## 5. Synthesis

Settings that every ASAP7 config needs (`run_orfs5.sh`, `harden_asap7.sh`):

| setting | why |
|---|---|
| `ADDER_MAP_FILE :=` (empty) | **The platform FA/HA techmap (`cells_adders_*.v`) produces wrong netlists**: outputs off by ±2 against the RTL, already in `1_synth.v`, same on NanGate45. A SAT miter found a counterexample (an accumulator wrong 11 cycles after reset). With the map disabled, the netlists are bit-exact (BCI, 2026-09-12). Not reported upstream. |
| `SYNTH_MEMORY_MAX_BITS` | The default 4096 aborts with "Synthesized memory size exceeds maximum allowed bits" on case-statement ROMs. BCI 65536, KWS 1e6. |
| `ABC_AREA=1` | Fewer cells and fanout violations; it closed IHP routing in BCI and is used for ASAP7 too. |
| `REMOVE_ABC_BUFFERS=1` | Skips the floorplan-stage wire-load repair, which hit `RSZ-0060 Max buffer count reached` through nested clock gates at a 200 ns clock (BCI, 2026-09-19). |

- **Count cells from the netlist plus all five liberty files** (AO, INVBUF, OA, SEQ, SIMPLE), not from flow metrics,
  which include taps, fill and, for SRAM-Vt, decaps (6.3).
- **Compare the synthesis netlist with the RTL bit for bit** before placing anything. A Verilator run on the KWS
  synthesis netlist failed with 16 errors where Icarus passed, which is unexplained (section 13).

## 6. Place and route with ORFS

**6.1 Settings** (beyond section 5):

| setting | value | note |
|---|---|---|
| `CORE_UTILIZATION` | policy: BCI 60 → 20 % in steps of 10; KWS latch cores 20 → 15 → 10 % | in BCI, SRAM-Vt sp energy was flat within 1 % from 40 to 60 % and 9 % lower at 70 %; the policy does not bias the result |
| `PLACE_DENSITY_LB_ADDON` | 0.10 | |
| `TNS_END_PERCENT` | 100 | |
| `DETAILED_ROUTE_ARGS` | `-droute_end_iter 40` (BCI) or 64 (KWS) | with a violation watchdog, as in sky130 notes 5.3 |
| `NUM_CORES` | ≤ 10 | default is 24 (section 0) |
| `CORNER` | set it explicitly | default BC = FF (3.3) |
| SDC | no `set_propagated_clock` | ORFS adds it after CTS |

**6.2 Make syntax.** `make` keeps the spaces before an inline `#` comment: `export PLATFORM = asap7   # note` sets
`"asap7   "` and fails with "Is a directory". Put comments on their own line (BCI configs still have
`REMOVE_ABC_BUFFERS = 1   # ...`).

**6.3 Decaps in the SRAM-Vt flavour.**
- The local `ASAP7_USESRAM` block forces `FILL_CELLS` to include `DECAPx1…x10`, after and over the design config. In
  the accepted KWS run, 796 602 decaps covered 69 % of the core, and the report showed "98 % utilisation" at
  `CORE_UTILIZATION=20` (KWS, 2026-10-22). Fix: pass `FILL_CELLS='FILLERxp5_ASAP7_75t_SRAM FILLER_ASAP7_75t_SRAM'`
  on the `make` command line. No run since this fix has reached the fill stage, so it is unverified.
- The SRAM-Vt LEF declares `DECAPx*_SRAM` as `CLASS CORE`, not `SPACER`, so ORFS counts decaps as standard cells:
  BCI sp_sram reported utilisation 0.94 against 0.66 and area 3 441 against 2 469 µm². Report logic-only area.
- Decaps, fillers and taps have no ASAP7 liberty, so they cost area, routing and simulation time, not power (9.3).

**6.4 Clock-tree synthesis.** Without `CTS_BUF_CELL`, CTS used `BUFx24` for every clock buffer: 56 466 buffers and
59 764 clock nets in the KWS core (one tree per 512-latch row); the clock tree took 12.8 µW of 30.6 µW leakage.
Setting a smaller CTS buffer is a candidate fix, not yet tested.

**6.5 Failures seen and their fixes.**
- `GRT-0119` global-routing congestion: BCI m12 at 60 % (closed at 50 %); KWS r2h96 cores at 20, 15 and 10 % after up
  to 7.5 h, although an older core of similar size routed at 20 %. Derated routing resources were 50–63 % per layer.
  Unresolved (section 13).
- "stack smashing detected" (signal 6) in timing-driven global placement ("executing resizer for reweighting nets"),
  in two KWS runs. The same crash in OpenLane was fixed by turning timing-driven placement off; the ORFS equivalent
  `GPL_TIMING_DRIVEN=0` is untested.
- Detailed routing out of memory: BCI's 400 k-instance latch core at 19 GB, a KWS core at 29.6 GB in the first
  iteration (possibly because of a 40 GB cgroup limit shared with another job). Declare memory per section 10.
- Rerunning `do-5_2_route` from a copied `5_1_grt.odb` fails because `detail_route.tcl` needs
  `reports/.../congestion.rpt`; copy the reports folder too.

**6.6 Watchdog.** `pkill -f "DESIGN_NICKNAME=..."` (`harden_asap7.sh`) matches nothing, because the nickname is in the
config file, not on the command line. Find the `openroad` process IDs and kill those, or kill the process group
started with `setsid`.

**6.7 Acceptance.** Accept only when:
- `5_2_route.json` has DRC 0;
- setup is met at the reported corner (ORFS slack in ps);
- hold is met, checked yourself (7.2), because ORFS reports "NA";
- logic cell counts match the RTL (section 4).

ORFS also leaves 40–390 max-slew violations per run (BCI). The scripts ignore them; record the count.

## 7. Timing sign-off

**7.1 Setup.** Sign off with OpenSTA yourself on the routed netlist and SPEF at the corner you report (sky130 notes
6.2), because ORFS signs off at FF by default (3.3). A reported setup slack of 0.00 on latch paths is time borrowing,
not a zero margin (KWS `6_finish.rpt`).

**7.2 Hold: ORFS does not report it for ASAP7.** `6_report.json` has no `finish__timing__hold__ws` in this ORFS, so
scripts read "NA" and accept.
- The accepted KWS run had `finish__timing__drv__hold_violation_count: 187`, worst −154 ps at FF. Global routing
  showed none; they appear only after RCX extraction, and ORFS repairs nothing after detailed routing.
- BCI's own check (`hold_sta.tcl`, TT/SS/FF with SPEF) found m12 at −12 ps (RVT) and −14 ps (SRAM-Vt) at FF, and
  also −7 / −3 ps at TT, which the BCI logs do not mention (`results/hold6.json`).
- Gate on `hold_violation_count == 0` or, better, on your own OpenSTA hold check at every corner you report.
- ORFS hold repair after global routing ran about 3 h on about 200 endpoints in KWS. The cause was skew between gated
  clock subtrees on a path that is not functional; a false path fixed it. Keep such exceptions minimal and count the
  objects they match (sky130 notes 6.1).

**7.3 Latch paths.** The KWS SDC still waives latch paths, against sky130 notes 9.2. Time them.

## 8. Gate-level simulation

**8.1 Icarus with SDF** (BCI round 5, bit-exact against the RTL over 200 and 5 000 bins; zero `SDF ERROR` lines):
- **ORFS writes no SDF.** Write it with OpenSTA (`run_write_sdf.sh`): netlist, SPEF, TT liberties, propagated clock,
  `write_sdf -divider / -include_typ -digits 4`.
- **Vendor SEQ models stay X.** They use `altos_dff` UDPs with an uninitialised notifier and are clocked from
  `delayed_*` nets that only `$setuphold` drives. Annotated runs completed 0 bins in 7 h. Replace them with
  `BCI_paper/sim/asap7_seq_icarus.v` (behavioural, IOPATH-only specify blocks) and keep the vendor AO, INVBUF, OA and
  SIMPLE models. Zero-delay runs work with the vendor models.
- **Rescale the SDF.** Icarus ignores `(TIMESCALE 1ps)` and reads 113 ps as 113 ns; the core stalled for 7 h.
  `sdf_sanitize_for_icarus.py` rescales to ns and fills empty triplets with 0.
- **ICG rise delay becomes 0** (found 2026-10-24, audit, confirmed with a small Icarus run). After the sanitiser
  unwraps the conditional ICG paths, the zero-filled rise triplets come last and override the unconditional value:
  `CLK→GCLK` rise is 0 instead of about 36 ps. Effect on glitch counts not measured.
- **Delays are rounded to 10 ps** (found 2026-10-24, audit, confirmed). The models declare
  `` `timescale 1ns/10ps ``, so 22.7 ps becomes 20, 14 becomes 10, 4 becomes 0. ASAP7 gate delays are 5–45 ps, so this
  is coarse, and BCI's glitch factors (1.17–1.28) carry the error. Fix: compile the models with a 1ps precision (for
  example a `` `timescale 1ns/1ps `` override) and remeasure.
- **INTERCONNECT is dropped, not matched**: 47 117 lines for BCI sp. The wires are 0.07–0.19 ps, so the effect is
  negligible, but BCI `run_log_round5.md` wrongly says they were matched.
- Compile `timescale_1ns_1ps.v` first and add empty stubs for tap, fill and decap cells.
- Write the net activities after the pin activities (sky130 notes 7.2): Icarus can leave a cell's output-port
  variable constant while its net toggles.
- `asap7_seq_icarus.v` covers DFFHQNx1/2/3, ICGx1 and DHLx1 only. KWS also needs ICGx2 and DLLx1: add them before
  using it there.

**8.2 Verilator, zero delay** (KWS): functional models generated from the liberty (`liberty2verilog.py`), stubs for
physical cells. The 1.58 M-instance routed core built in 20 min (about 6–8 GB) and ran in 6 min. In BCI, liberty-
generated models hung in Icarus, so this route is for Verilator only.

**8.3 Glitch factor** (annotated over zero-delay energy): 1.17–1.28 on ASAP7 after the BCI round-6 fix, against
1.18–1.22 on sky130. Round-5 values (1.07–1.11) were wrong (9.2).

## 9. Power with OpenSTA

**9.1 Setup.** Read all five liberty files of the flavour and corner, the netlist and the SPEF; give the clock period
in ps; set unannotated inputs to activity 0 (sky130 notes 8.1). `report_activity_annotation` does not exist in
OpenSTA 2.6, and `set_clock_sense` is deprecated there.

**9.2 Do not stop clock propagation at the ICGs** (BCI round 6, 2026-09-23). With `set_clock_sense
-stop_propagation` at the clock-gate outputs (`CLK_STOP_ICG=1`) and per-cycle activities from a toggle file, OpenSTA
has no clock behind the gates to convert the activities with, so the internal and switching power of everything
downstream vanishes. The sequential and clock groups are unaffected, so the totals still look plausible. Every
non-sky130 run of BCI round 5 (GF180, IHP, NanGate45, ASAP7) showed a combinational group of 0.03–0.6 % of the total,
against 52 % for the same core on sky130 without the stop. ASAP7 energy per bin was too low by 55–123 % (min16
0.0318 → 0.0579 nJ), and ASAP7's advantage over sky130 fell from about 60× to about 35× once fixed. The ASAP7 ICGs carry
`clock_gating_integrated_cell`, so OpenSTA scales the gated subtrees itself; no stop is needed. A VCD-path test showed
no difference, which is why the error went unnoticed. BCI now defaults to 0; **KWS still sets `CLK_STOP_ICG=1`** in
`sim/measure.sh` (section 13). Sky130 notes 8.2 (since its version 1.1) gives the same rule for every PDK.

**9.3 Physical cells are black boxes.** No ASAP7 liberty defines FILLER, DECAP or TAPCELL, so OpenSTA black-boxes them
with zero leakage ("module … not found"). Count the black boxes and check that only physical cells are among them.
Decap-free fill makes no power difference on ASAP7.

**9.4 Parasitics and escaped names.** With `keep_hierarchy`, the netlist has `\u_neu/_10240_` and the SPEF the bare
`u_neu/_10240_` under `*DIVIDER /`. OpenSTA dropped 4.87 million SPEF entries (863 k of 2.04 M nets) in KWS, so the
KWS breakdown (101.9 µW) is invalid. Fix: `legal_names.py` (sky130 notes 5.4), then expect zero
`spef ... not found` warnings. BCI's ASAP7 cores are flat and match fully.

**9.5 Leakage depends on cell state.** ASAP7 per-state leakage differs by large factors, unlike sky130, GF180 or
NanGate45. RVT sp: idle after reset 3.30 µW, decode window 2.35 µW, real-time run 2.64 µW; SRAM-Vt idle 0.719 µW, real
time 0.583 µW (−18 %). Take leakage from the same window as the activity, never from a post-reset idle run (BCI round
10, 2026-10-08).

**9.6 Root-clock correction** (sky130 notes 8.2) applies to ASAP7 designs that stop their clock, with two changes:
- the walk from the clock port must continue through `HBx` hold buffers;
- for root flip-flops, scale the annotated internal power by the clock duty directly; the zero-data run gave a
  state-dependent value 18 % too low (RVT E_dyn 0.0913 → 0.0876 nJ, BCI round 10).

**9.7 Reports.** BCI's clock-tree report matches sky130 cell names only, so it reports no clock tree on ASAP7, and
`root_clock_correction.py` puts ASAP7 CTS `BUFx` cells in "Combinational". Check the breakdown classes by cell name for
ASAP7.

## 10. Runtime and memory

| run | threads | time | peak memory |
|---|---|---|---|
| BCI cores, 10–20 k cells, full ORFS flow | ~5 (unset) | 6–23 min (m12 30 min) | 6.2 GB (sp) |
| BCI latch core, 400 k instances, detailed routing | ~5 | killed after 77 min | > 19 GB |
| KWS tm1 latch core, 1.3 M instances, full flow | 6 | 7.3 h | 32.5 GB |
| ↳ global routing (mostly hold repair) | | 4.7 h | 13.1 GB |
| ↳ detailed routing (131 883 → 0 violations in 5 iterations) | | 92 min | 32.5 GB |
| ↳ `6_report` (RCX) | | 18 min | 19.5 GB |
| KWS tm8 cores: synthesis / global placement / global routing | 3 | 5 / 20 / 12 min | 3 / 7 / 15 GB |
| Icarus SDF, 5 000-bin window, BCI sp | 1 | 60 min RVT, 55 min SRAM-Vt | < 1 GB |
| Verilator, 1.58 M-instance routed netlist | | build 20 min, run 6 min | 6–8 GB |

Detailed-routing memory scaled at about 124 kB per synthesised cell in KWS.

## 11. Checklist for every measurement

Everything in sky130 notes section 10, plus:

| check | expect |
|---|---|
| `NUM_CORES` passed to `make` | ≤ 10 |
| `objects/.../lib/` after synthesis | the intended flavour (`*_SRAM_*` for SRAM-Vt) and corner |
| `CORNER` used by ORFS, and the corner of sign-off and power | stated in the result file |
| `ADDER_MAP_FILE` | empty |
| every period, slack and delay | converted between ps and ns in one known place |
| synthesis and routed netlist against RTL | bit-exact |
| `DECAP` cells in the fill log | only if intended |
| hold, own OpenSTA check with SPEF | met at every reported corner |
| `spef ... not found` warnings | 0 |
| `CLK_STOP_ICG` / `-stop_propagation` in the power script | absent (0) |
| Icarus model precision | 1 ps, not 10 ps |
| leakage window | the same window as the activity |
| per-cell leakage computed from the liberty | VDD groups only |

## 12. Sanity numbers

- **BCI pruned core sp at 5 MHz, TT** (`deliverables_round10/tables/table3_round10.tex`): RVT / SRAM-Vt 19 954 /
  19 604 logic cells (1 491 flip-flops, 3 ICGs), 0.00245 / 0.00237 mm², P_leak 2.64 / 0.583 µW, E_dyn 0.0876 / 0.0820
  nJ per bin (sky130: 2.81 nJ). Setup slack about 120 ns at 200 ns. Clock skew 64–158 ps. These include the 10 ps
  rounding of 8.1.
- **f_max at SS**: 667 MHz RVT, 480 MHz SRAM-Vt (`results/PDKS5.md`). `run_log_round5.md` says 2.3 / 1.8 GHz; that value
  probably comes from the runs with stopped clock propagation and is not trusted.
- **KWS tm1_h128w4**: synthesis area 59 458 µm²; the weight memory is about 86 % of the r2h96 cores. Its power numbers
  are invalid (9.2, 9.4).

## 13. Open issues

Each project has the details and fixes in its own `ASAP7_FLOW_ISSUES.md` (`BCI_paper/`,
`KWS_neuromorphic_tech_node/`, and a pointer in `synaptic_delay/sky130-snn-bmi/`).

| issue | where | section |
|---|---|---|
| per-cell leakage halved; paper ratios too low by 2× | `BCI_paper/sw/asap7_leakage.py`, `paper/numbers_asap7.tex` | 3.2 |
| ORFS optimises at FF; project docs say TT | BCI, KWS | 3.3 |
| ICG rise delay zero after sanitising; 10 ps rounding | `sdf_sanitize_for_icarus.py`, model timescale | 8.1 |
| m12 hold violations at FF and TT | BCI | 7.2 |
| hold accepted as "NA"; 187 violations in the accepted KWS run | `harden_asap7.sh`, `run_orfs5.sh` | 7.2 |
| `CLK_STOP_ICG=1`, escaped-name SPEF loss, latch waivers | KWS | 9.2, 9.4, 7.3 |
| `FILL_CELLS` override unverified; CTS `BUFx24` | KWS | 6.3, 6.4 |
| `GRT-0119` congestion of KWS r2h96 cores | KWS | 6.5 |
| Verilator mismatch on the KWS synthesis netlist | KWS | 5 |
| swap slowdown (owner's 5× rule) never measured | KWS | 0 |
| no latch-memory core routed in BCI (400 k instances) | BCI | 6.5 |
| +5.6 % residual in ASAP7 dynamic energy after root-clock correction | BCI round 10 | 9.6 |
| fakeram macros never tried | all | 3.1 |
| shared ORFS checkout carries an unrecorded local patch | `/media/pdk/OpenROAD-flow-scripts` | 1 |
| stale `/home/yousefzadeha/workspace/...` paths in configs | BCI, KWS | 1 |
