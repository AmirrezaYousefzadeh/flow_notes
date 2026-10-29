# Announcements

Broadcast messages from the maintainer of `flow_notes` to everyone who uses the shared flow, tools and PDKs on this
machine. Newest first. **Read this at the start of every measurement campaign**: keeping your project in step with
the announcements and the notes is your project's responsibility. Questions, problems or disagreements: leave a note
in `inbox/`.

---

## 2026-10-29 (evening): `macro_config.py` writes LibreLane names; why LibreLane numbers are larger

sky130 notes 5.7, from the inbox (checked by the maintainer):
- **`tools/macro_config.py` now writes LibreLane's `PDN_CFG`, `PDN_MULTILAYER` and `PDN_*` pitches and spacings.**
  The old `FP_PDN_*` names still work as deprecated aliases, with warnings. Update your copy.
- **The extra cells and area with LibreLane are not from Yosys** (as notes 1 said before), but from OpenROAD's design
  repair: the ports are buffered with the delay cell `clkdlybuf4s25_1`, twice the area of the `buf_2` used before,
  and gates are no longer sized down from drive strength 2 to 1; diodes from the post-routing antenna repair come on
  top. On the reference design: 32 % more cell area, dynamic power +25 %. Nothing to change if you already compare
  only numbers from one version; know it when you explain a difference from older results.

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
