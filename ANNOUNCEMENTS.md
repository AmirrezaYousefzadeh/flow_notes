# Announcements

Broadcast messages from the maintainer of `flow_notes` to everyone who uses the shared flow, tools and PDKs on this
machine. Newest first. **Read this at the start of every measurement campaign**: keeping your project in step with
the announcements and the notes is your project's responsibility. Questions, problems or disagreements: leave a note
in `inbox/`.

---

## 2026-11-03: the hold repair after global routing did not help on a latch core

sky130 notes 6.9 (5.1): on a latch core that failed hold at ff with the default margins, `RUN_POST_GRT_RESIZER_TIMING:
true` found no hold violation on the global routes at any of the 9 corners (margin 0.05 ns) and changed nothing;
sign-off still failed at ff (−0.079 ns). A 0.2 ns `PL_RESIZER_HOLD_SLACK_MARGIN` passed all 9 corners (+0.12 ns at
`max_ff`) for 1.9 times the hold delay cells and 0.7 % more cell area. If you rely on the post-GRT repair, check its
log: `RSZ-0033 No hold violations found` means it did nothing. Sign off hold at all 9 corners either way.

---

## 2026-11-03: CTS can leave a clock gate without its clock; check your netlists

sky130 notes 6.8 (9.2, 5.3, 5.1), ASAP7 notes 5.2 (6.4):
- **OpenROAD `dcf3613`'s CTS can leave a clock gate's `CLK` unconnected** (LibreLane 3.0.16 and 3.0.17, and ORFS run
  with the LibreLane binaries; OpenROAD issue #9816, fixed upstream after our version). It moves every clock gate to
  the centre of its sinks, and when that point is already taken, one gate loses its clock: its row or register bank
  is then never clocked. It hit 3 of 4 layouts of two latch cores with 113 and 165 row clock gates on one gated
  clock; no core with few gates per clock net showed it so far.
- **Check:** `tools/check_clock_gates.py <netlist>` on any netlist written after CTS (exit status 1 if a gate has no
  clock input). LibreLane's disconnected-pins checker stops the flow, but only after detailed routing; ORFS has no
  such check. If you have a sky130 or ASAP7 layout with clock gates hardened with these versions, run it on the final
  netlist.
- **Workaround:** `tools/firm_clock_gates.tcl` places each clock gate at the centre of its sinks, legalises and fixes
  the gates before CTS; with `harden_ladder.sh` set `PRE_CTS_TCL=<flow_notes>/tools/firm_clock_gates.tcl`. Do not
  just fix the gates where global placement left them: on a latch core that gave long, detoured clock wires and
  failed hold by up to 0.49 ns.
- **`harden_ladder.sh` updated:** it takes `PRE_CTS_TCL`, and it stops on disconnected pins after routing instead of
  trying a sparser utilisation (a tool bug says nothing about routability). Update your copies.
- **Hold with the default margins** (5.1): the latch core, with its clock gates at the centre, failed hold at ff by
  0.06 and 0.09 ns at two utilisations, also with nominal parasitics. One more reason to sign off hold at all 9
  corners.

---

## 2026-11-03: hold data corrected; check slews; no clock NDR with many gated clocks; LibreLane's own sign-off

sky130 notes 6.6:
- **Correction to the 2026-11-01 entry on hold margins** (5.1): the "three of three cores" were three layouts of two
  designs, hardened with port buffers and before the delay-cell rule. Two cores under the current settings met hold
  at all 9 corners with the default margins. Two of the three failing layouts also failed at tt with maximum
  parasitics, so nominal tt alone is not enough either: sign off hold at all 9 corners.
- **Check the post-route slew violations** (1.1, checklist 10). Delay cells as fanout buffers gave two decoder cores
  8–9 % more power, with 24 and 53 times the slew violations at nominal tt; LibreLane only warns. On another core the
  delay-cell rule put `buf_1` in their place and the slew violations stayed; whether the rule removes the increase on
  the decoders is being measured.
- **`CTS_APPLY_NDR: none` for designs with many gated clocks, latch memories with one gate per row included** (5.1,
  9.2). If your global-routing log shows `GRT-0273 Disabled NDR (to reduce congestion)`, the rule is costing you
  routability.
- **LibreLane's own `STAPostPNR` equals an own sign-off** on flat and kept-hierarchy designs (5.4, 6.2): its
  per-corner values in `final/metrics.json` can stand for the corners your own sign-off does not run, if the run
  reached `STAPostPNR` and every macro has a liberty per corner.

---

## 2026-11-01: monthly review; check your sign-off scripts and update three tools

sky130 notes 6.5 and ASAP7 notes 5.1 (history rows list everything). What you must check:
- **OpenSTA's Tcl slack commands return seconds** (`sta::worst_slack_cmd`, `sta::total_negative_slack_cmd`), whatever
  the liberty's unit (sky130 6.2, ASAP7 3.4). A script that read them as ps logged hold violations as "−0.0 ps".
  Check every script of yours that calls them.
- **An own sign-off on the design SDC must propagate the clocks** (ASAP7 7.1): with ideal clocks one core showed hold
  +58.2 ps where it was −80.4 ps.
- **Default hold margins fail hold at the fast corner** (sky130 5.1): three of three cores met hold at tt and failed
  at `ff_n40C_1v95`. With default margins, sign off hold at every corner; a tt-only sign-off accepts such layouts.
  `GRT_RESIZER_HOLD_SLACK_MARGIN` does nothing unless `RUN_POST_GRT_RESIZER_TIMING: true`.
- **Per-corner metrics are post-route only after `STAPostPNR`** (sky130 6.2): with `RUN_MCSTA: false` or an earlier
  `--to`, `final/metrics.json` keeps pre-placement slacks for most corners, unmarked.
- **Crashes before 2026-10-29 14:23 are suspect** (sky130 0): CPU 0 of this machine was faulty until it was fenced
  off. Rerun such a crash before you blame a tool. The timing-driven placement crashes in the notes were probably
  this core.
- **SDC exceptions:** use glob patterns, not `-regexp`, for hierarchical names, and check the match count in the
  floorplan log, not at sign-off (sky130 6.1). ASAP7: a `SYNTH_KEEP_MODULES` name that matches no module is only a
  warning; the module is flattened (ASAP7 5).
- **Reuse results on a stamp, not on an existing file** (sky130 8.6).
- **Remedy A** (drive-1 cells allowed in synthesis) measured on a real core: −8 % energy at tt, −19 % at 1.28 V, at
  the cost of one utilisation step (sky130 1.1). Not yet a rule; the owner decides.

**Update your copies** (tested):
- `harden_ladder.sh`: stops on a crash instead of stepping down to a sparser utilisation; refuses to overwrite
  existing `runs/u<U>` unless `OVERWRITE=1`; rejects a run that never reached `STAPostPNR`.
- `check_metrics.py`: rejects a run that never reached `STAPostPNR` unless `--signoff` gives the timing.
- `signoff_sta.tcl`: also prints the slacks in ns (`SIGNOFF_NS`); the `SIGNOFF` lines stay in seconds.

---

## 2026-10-30 (evening): exclude the delay cells from LibreLane's buffering

sky130 notes 6.2, owner's decision: add `EXTRA_EXCLUDED_CELLS: ["sky130_fd_sc_hd__clkdlybuf4s*"]` to every LibreLane
configuration (5.1). OpenROAD `dcf3613` otherwise uses the slow delay cell `clkdlybuf4s25_1` as an ordinary buffer
(1 384 of them in one core). Write the list in the configuration file, not with `--override-config`. A project in the
middle of a comparison keeps its settings for that comparison and says so.

---

## 2026-10-30 (later): no port buffers or port diodes in a measurement; why LibreLane cells stay large

sky130 notes 6.1:
- **Owner's decision: for a measurement, set `DESIGN_REPAIR_BUFFER_INPUT_PORTS: false`,
  `DESIGN_REPAIR_BUFFER_OUTPUT_PORTS: false` and `DIODE_ON_PORTS: none`** (5.1). They are silicon robustness; a
  tapeout turns them on (12). Without output buffers your own cells drive the SDC's output load: set
  `OUTPUT_CAP_LOAD` to fit the block's place in the SoC and state it. A project in the middle of a comparison keeps
  its settings for that comparison and says so.
- **LibreLane leaves cells at drive 2 and buffers with delay cells** (1.1): the PDK keeps synthesis off drive-1
  cells, and OpenROAD `dcf3613` no longer sizes them down after placement as OpenLane 2's did; it also picks the
  delay cell `clkdlybuf4s25_1` as a buffer. Open upstream (OpenROAD #10622, LibreLane #944). On a logic-dominated
  core this alone raised the energy 20 % at tt and 40 % at 1.28 V against OpenLane 2. Two remedies are being
  measured; until the notes recommend one, keep every compared design on the same settings and state them. Results
  of your own trials are welcome in the inbox (as a new note).

---

## 2026-10-30: full review of the notes and tools; update your copies

sky130 notes 6.0 and ASAP7 notes 5.0: both were checked line by line against the installed tool sources. Read their
new "silent errors" tables and the history rows. What you must check in your flow:
- **Sign-off corners** (sky130 6.2): LibreLane's own checkers fail hold at all 9 corners but setup only at the
  typical ones, and they never run when the flow stops at `STAPostPNR`. `check_metrics.py` and `signoff_sta.tcl`
  check one corner per call. `harden_ladder.sh` accepts on the worst slack over all corners. State your policy.
- **Macro timing per corner** (sky130 9.1): with one SRAM22 liberty under `"*"`, every corner timed the macro with
  its typical liberty. `macro_config.py` now writes one per corner; it also takes `--pdn-cfg` (the old default path
  did not exist for the shared macro views).
- **Power script** (sky130 8.1): one clock, propagated, with the simulated period, before the activities; OpenSTA 2.7
  converts all activities with the fastest clock (ASAP7 9.1: matters for a separate write clock).
- **Threads** (sky130 0): give LibreLane `-j` and `STA_THREADS`, or it runs up to 9 STA corners on every core.
  `harden_ladder.sh` does it now.
- **ASAP7:** `ROUTING_LAYER_ADJUSTMENT` is ignored in this ORFS (use `FASTROUTE_TCL`, 6.5); `OPENROAD_CLKGATE` needs
  `-D OPENROAD_CLKGATE` or every gate becomes a wire (4); the flavour check reads the logs, not `objects/` (1); model
  copies with 1 ps precision need `sed` (8.1).
- **Port buffers** (sky130 5.1): informational; very small IP blocks that will sit inside an SoC may turn them off.

**Update your copies** of these tools (all tested; details in `tools/README.md`):
- `check_annotation.py`: also fails when no pin activity was annotated (a wrong scope passed before), and reads
  gzipped liberties (ASAP7 losses passed before).
- `toggles_to_activity.py`: fails when no variable matches `--scope`.
- `vcd_toggles.c`: a 1-bit variable with a single index (`c [5]`) lost its index.
- `root_clock_correction.py`: any sky130 library (it knew only `hd` names) and walks through `dlygate`/`dlymetal`.
- `root_clock_correction_multipdk.py` with `power_sta.tcl ZERO_DATA=1`: run B can now be made with the shared tools.
- `hold_sta.tcl`: generic (reads the run's SDC, requires the SPEF, exits 1 on negative slack; the project-specific
  false path is gone). `signoff_sta.tcl` propagates the clocks when the SDC does not.
- `asap7_seq_icarus.v`: 1 ps precision. `check_metrics.py`: `--synth-stat` alone; no default cell cap.
- `reference_flow/measure.sh`: no longer measures a simulation with SDF errors.

---

## 2026-10-29 (evening): `macro_config.py` writes LibreLane names; why LibreLane numbers are larger

sky130 notes 5.7, from the inbox (checked by the maintainer):
- **`tools/macro_config.py` now writes LibreLane's `PDN_CFG`, `PDN_MULTILAYER` and `PDN_*` pitches and spacings.**
  The old `FP_PDN_*` names still work as deprecated aliases, with warnings. Update your copy.
- **The extra cells and area with LibreLane are not from Yosys** (as notes 1 said before), but from OpenROAD's design
  repair: the ports are buffered with the delay cell `clkdlybuf4s25_1`, twice the area of the `buf_2` used before,
  and gates are no longer sized down from drive strength 2 to 1; diodes from the post-routing antenna repair come on
  top (32 % more cell area on the reference design). Its +25 % dynamic power comes from the larger root clock tree,
  more delay cells and the larger logic cells in about equal parts; the port buffers are about 1 % of the dynamic
  power there. Nothing to change if you already compare only numbers from one version; know it when you explain a
  difference from older results.

---

## 2026-10-29 (later): update your copy of `check_annotation.py`

After a decap-free refill with reused toggles (sky130 notes 5.1), the fill instances have new names, and the old
`tools/check_annotation.py` counted their supply pins as lost activities, failing a correct run (30 904 on one core).
The fixed tool ignores supply pins of instances that are no longer in the netlist and still fails on any lost signal
pin (tested both ways). Update your copy. sky130 notes 5.6.

---

## 2026-10-29: antenna repair after routing; watchdogs and frozen jobs

sky130 notes 5.5, from findings reported through the inbox (checked by the maintainer):
- **Add `DRT_ANTENNA_REPAIR_ITERS: 0` to every LibreLane configuration with `RUN_ANTENNA_REPAIR: false`.**
  LibreLane runs a second antenna repair after detailed routing (default 3 iterations) that inserts diodes and
  routes again; on one core it added 1 232 diodes after routing had converged. `tools/reference_flow/` has it now.
- **Routing watchdogs must not count time a job spent frozen by the queue.** A healthy run was killed one minute
  after a 7-hour freeze. `tools/harden_ladder.sh` and `tools/reference_flow/harden.sh` are fixed (tested with a
  frozen process group); if you use your own watchdog, fix it the same way (notes 5.3), or update your copy.
- The queue now wants a `--time` with every job and may freeze jobs when memory runs low; its CPU set leaves out a
  faulty core, so never pin or widen CPUs yourself. Details in `/media/amir/.jobq/AGENTS.md` (notes 0).

---

## 2026-10-28: hardening policy, LibreLane settings, fixed SDF sanitiser

sky130 notes 5.4 and ASAP7 notes 4.2, from findings reported through the inbox (checked by the maintainer):
- **Never start a hardening by hand** (sky130 5.3): one ran 2.8 days without a watchdog. Use the new
  `tools/harden_ladder.sh` (any LibreLane configuration: utilisations dense to sparse, routing watchdog, process-group
  stop, acceptance from the run's metrics plus your own sign-off, every attempt logged) or your own equivalent.
- **Re-harden after moving to LibreLane:** the routable utilisation of a design can drop (an adder-tree core: 40 % →
  30 %). Timing-driven placement is `PL_TIMING_DRIVEN` (default false); turning it on crashed OpenROAD on one design.
- **LibreLane settings for some designs** (sky130 5.1): `CTS_APPLY_NDR: none` if global routing aborts with
  `GRT-0228/0229` (many gated clock nets); `PL_RESIZER_SETUP_SLACK_MARGIN: 0` and `GRT_RESIZER_SETUP_SLACK_MARGIN: 0`
  for latch memories timed without waivers; `ERROR_ON_UNMAPPED_CELLS: false` plus `check_metrics.py --synth-stat` for
  kept parametrised modules.
- **Update your copy of `tools/sdf_sanitize_for_icarus.py`:** it now rescales `(TIMESCALE 1ps)` itself and drops the
  zero-filled conditional repeats that set every clock-gate rise delay to 0 in Icarus. Output for SDFs without such
  repeats is unchanged.
- **Update your copy of `tools/legal_names.py`** if you use ORFS (a fourth SPEF spelling with a bare `$`), and of
  `asap7_seq_icarus.v` (now with ICGx2).
- **Verilator 5.053 writes its VCD without the `TOP` scope:** a fixed scope prefix silently annotates no activity.
  Fail a measurement when no pin activity was annotated (sky130 7.4, section 10).
- ORFS: use `DETAILED_ROUTE_END_ITERATION`, not `DETAILED_ROUTE_ARGS` (ASAP7 6.1).

---

## 2026-10-25: derating bug in OpenLane 2, new annotation check, version pinning

sky130 notes 5.2. From findings reported through the inbox, checked by the maintainer:
- **Every OpenLane 2 run on sky130 was timed without the intended ±5 % derating** (integer division in its
  `base.sdc`; notes 6.1). Slacks of OpenLane 2 runs were optimistic by up to 5 % of each path delay, for setup and
  hold. LibreLane is correct. If your project's SDC was copied from OpenLane 2's `base.sdc`, divide by `100.0`. Keep
  this in mind when you compare old OpenLane 2 timing with new results.
- **OpenSTA 2.7 (the default) reads SPEF files with escaped hierarchical names correctly** (notes 5.4). Renaming with
  `legal_names.py` is still needed for Icarus SDF annotation.
- **New tool `tools/check_annotation.py`**: fails the power analysis when a measured activity was lost, instead of
  asking you to look through millions of expected "not found" names (notes 8.1, section 10). Add it to your flow.
- **Pin your versions in your scripts** (notes 1): name the dated directories (`oss-cad-suite-2026-10-24`,
  `librelane-3.0.16`) if you must keep versions, and check `iverilog -V` and the PDK's `SOURCES` against your pins.
  The generic paths follow the defaults.
- `tools/reference_flow/` now runs on the default versions and fails on SDF errors and lost activities.

---

## 2026-10-24 (late): margins are optional when you only measure

sky130 notes 5.1 (header and section 5.1): rules are now marked as either correctness of the number (always required:
legal layout, setup and hold met at the sign-off corners with full parasitics, simulation matching the RTL, complete
power analysis) or robustness for silicon (optional for a measurement-only project: overfix margins, antenna repair,
density fill, decaps, IR-drop margins). For hold, a measurement-only project may use OpenLane's default margins
instead of the 0.5 ns overfix, as long as its own sign-off meets hold at every corner. State the choice with your
numbers.

---

## 2026-10-24 (evening): new default tools and PDK, validated

The update announced this morning is installed, validated (`validation/README.md`) and now the default.
The notes are now sky130 5.0 and ASAP7 4.0; read section 1 of each.

| what | new default | previous (kept, for reproducing earlier numbers only) |
|---|---|---|
| flow | LibreLane 3.0.16: `/media/hardware_design_tools/librelane`, `python3 -m librelane` | OpenLane 2.3.10: `/media/hardware_design_tools/openlane2`, `python3 -m openlane` |
| sky130 PDK | open_pdks `8afc834`: `PDK_ROOT=/media/pdk/sky130_8afc834` | open_pdks `c6d73a35`: `PDK_ROOT=/media/pdk` (`sky130A`) |
| OpenSTA | 2.7.0 (inside LibreLane) | `b5f3a02` (inside OpenLane 2) |
| Icarus, Yosys, Verilator | OSS CAD Suite 2026-10-24: `/media/hardware_design_tools/oss-cad-suite` now points here | `/media/hardware_design_tools/oss-cad-suite-2024-08-07` |
| ORFS (ASAP7) | `/media/pdk/OpenROAD-flow-scripts-ef2cb37` with the LibreLane binaries; SRAM-Vt via `ASAP7_USE_VT=SRAM` | `/media/pdk/OpenROAD-flow-scripts` with the OpenLane 2 binaries |
| SRAM22 views | `/media/pdk/sram22_sky130_fixed-de0a9a7/` | older fixed copies |

**Act on this:**
- **Already changed for everyone:** `/media/hardware_design_tools/oss-cad-suite` is now the 2026-10-24 suite (Icarus
  14 devel, Yosys 0.70). A script that relies on the old Icarus or Yosys must use the `-2024-08-07` path. Record the
  versions in your results.
- **Move new work to LibreLane with its PDK root.** Change `python3 -m openlane` to `python3 -m librelane`, the Nix
  flake to `/media/hardware_design_tools/librelane`, and `PDK_ROOT` to `/media/pdk/sky130_8afc834`. LibreLane 3 renamed
  or changed some configuration variables (for example `PL_TIME_DRIVEN` now defaults to false); check your config
  against its documentation and your run logs for warnings about unknown variables.
- **Never combine OpenLane 2 with the new PDK:** its OpenSTA crashes in the SRAM22 power analysis.
- **Expect numbers to move.** On the reference design: 14 % more cells, a larger root clock tree, dynamic power
  +25 %, total power +0.9 %. Do not compare numbers measured with different versions; re-measure the baseline.
- **ASAP7:** switch to the new ORFS path and the LibreLane Nix shell together (never mix them with the old ones), use
  `ASAP7_USE_VT=SRAM` instead of `ASAP7_USESRAM=1`, and pass `CORNER=TC` (ASAP7 notes 1, 3.3). The new ORFS reports
  hold slack.
- If anything breaks, leave a note in `inbox/`.

---

## 2026-10-24: tool and PDK update under way; how flow knowledge is shared

**Tool and PDK update (not yet the default).** New versions are being installed next to the current ones:
LibreLane 3.0.16 (successor of OpenLane 2; newer OpenROAD, OpenSTA and Yosys), sky130 open_pdks `8afc834`,
OSS CAD Suite 2026-10-24 (Icarus 14 devel, newer Yosys and Verilator), ORFS `ef2cb37` for ASAP7 (with the corrected
RVT FF liberty and SRAM-Vt via `ASAP7_USE_VT=SRAM`), and fixed SRAM22 views from upstream `de0a9a7`. They become the
defaults only after validation, with their own announcement and migration notes. Until then, keep using the versions
in section 1 of the notes. The fixed SRAM22 views (`/media/pdk/sram22_sky130_fixed-de0a9a7/`) can be used now; they
differ from older copies only in the corrected slew limit of the liberties.

**How flow knowledge is shared from now on.**
- The notes (`skywater130_flow_notes.md`, `ASAP7_flow_notes.md`) are general and maintained only by the maintainer.
  They are now sky130 4.0 and ASAP7 3.0: if your project recorded an older version, read their version histories.
- Report findings, fixes others should know about, and disagreements as a note in `inbox/` (one file per finding).
  The maintainer acts on it, updates the notes, announces here what everyone must act on, and deletes the note.
- Shared tools are maintained in `tools/`; copy them and record the `flow_notes` commit you copied.
- Do not install or upgrade tools or PDKs, and do not modify the shared ORFS checkouts.

**Rules that changed today and that every flow must check** (details in the notes):
- never stop clock propagation at clock gates in the power analysis (sky130 8.2, ASAP7 9.2);
- ORFS optimises ASAP7 at the FF corner unless `CORNER=TC` is set (ASAP7 3.3);
- ASAP7 per-cell leakage computed from the liberty must use the VDD groups only (ASAP7 3.2);
- ORFS in the default version reports no hold slack: check hold yourself (ASAP7 7.2);
- SRAM22: use the supply-only `_pwr.lib` for power, and the `add_pdn_connect met2 met4` grid hook (sky130 9.1);
- every heavy job through `jobq`; no CPU pinning (sky130 0).
