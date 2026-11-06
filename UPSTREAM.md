# Upstream watch: installed versions against upstream

**Last review: 2026-11-01** (monthly, automated; report in `maintenance/reports/2026-11.md`). **Next review: 2026-12-01** (automated, `maintenance/README.md`).

The open-source tools and PDKs change quickly. Several rules in the notes exist only because of bugs that upstream has
since fixed, and some recommended practices change with new releases. On the 1st of every month, an automated run of the
general agent of `/media/amir` reviews upstream and updates this file and the notes. The owner decides which upgrades to install.

## Upgrade policy (owner's decision, 2026-10-28)

- **Upgrade the defaults at most once a quarter**, unless an upgrade fixes an error that silently falsifies numbers
  (such errors justify an upgrade at any time).
- **Prefer tagged releases over nightlies or development builds.** Where a tool has no releases (OpenROAD, ORFS, the
  OSS CAD Suite), take the version pinned by a LibreLane release, or a build that has been in use for a while and
  passed our validation, never simply the newest.
- **Validate on the reference set** (`validation/README.md`): one small SRAM22 design, a large latch-memory core, a
  dense arithmetic (adder-tree) core and an ASAP7 core. A single small design misses routability and scaling problems.
- Report bugs found in the tools upstream, with a minimal reproduction.

## Monthly review procedure

1. For each row below, check upstream releases, changelogs and the issues cited in the notes. Note new versions, and
   fixes or changes that touch a rule in either notes file.
2. Update the "upstream now" and "effect on our rules" columns and the review date. Correct the notes where a rule's
   explanation or a source changed. Follow their versioning rules, and commit and push.
3. **Do not upgrade an installed tool or PDK without the owner's approval.** An upgrade changes numbers, and a project
   in the middle of a paper must keep its pinned versions. Propose upgrades in the "upgrade candidates" table, with
   the expected effect.
4. When the owner approves an upgrade:
   - install it **next to** the old version, not over it;
   - rerun the reference designs (`validation/`): they must reproduce their numbers, or the difference must be
     explained;
   - record the new pin in the notes' section 1 and in this file;
   - announce the change in `ANNOUNCEMENTS.md`, with migration notes.
5. Report to the owner: what changed upstream, what changed in the notes, and which upgrades are proposed.

## Installed versions (pins) and upstream

| component | installed default (pin) | previous version kept | upstream now (2026-11-01) | effect on our rules |
|---|---|---|---|---|
| LibreLane | 3.0.16 (`01ddb25`), `/media/hardware_design_tools/librelane` | OpenLane 2.3.10 (`a7b0e6d`), `/media/hardware_design_tools/openlane2` | **3.0.17** (2026-10-26, unchanged since the last review): documentation and a backported Magic memory fix, same tool and PDK pins. **3.1** in development (pre-release 3.1.0.dev4, 2026-10-23; OpenROAD 26Q4 in open PR #1061). 3.1 changes that move numbers: port buffers use `SYNTH_BUFFER_CELL` (no more delay cells at the ports), `SYNTH_STRATEGY` default `DELAY 4` (was `AREA 0`), `SYNTH_MUL_BOOTH` and the new `SYNTH_ARITH_TREE` on by default, liberties no longer trimmed (`dont_use` passed to ABC); `OPENROAD_THREADS` replaces `DRT_THREADS`; Yosys 0.69, Verilator 5.046, Icarus 13.0, KLayout 0.30.12, Magic 8.3.677, ciel 3.2.0. Open: stale per-corner metrics when `STAPostPNR` does not run (issue #1040, PR #1042); delay-cell buffers in repair (#944). Not reported (2026-11-06): `steps/openroad.py` builds `_PNR_EXCLUDED_CELLS` from an unsorted set (3.0.16 and main), so the list's order follows Python's hash seed; with our OpenROAD that moves heap addresses and so breaks ties differently (the root cause is OpenROAD's, fixed upstream: next row); `sorted(...)` would make reruns repeatable. LibreLane's LLM policy requires a human-written report: whether to file it is the owner's call | sky130 6.2: per-corner metrics only after `STAPostPNR` (new; tools check it). sky130 11: `PYTHONHASHSEED=0` in `harden_ladder.sh` and the validation flow, until the list is sorted upstream or OpenROAD's determinism fixes arrive (3.1). At the 3.1 upgrade: pin the old synthesis defaults or re-measure baselines; rename `DRT_THREADS` (section 0, `harden_ladder.sh`) |
| OpenROAD / OpenSTA (inside LibreLane) | OpenROAD `dcf3613` (2026-02-17), OpenSTA 2.7.0 `857316f` | OpenROAD `edf00dff`, OpenSTA `b5f3a02` | no tagged releases; quarterly builds named `26Q4` etc. LibreLane 3.1 will move to OpenROAD 26Q4 with OpenSTA `e913e15` (2026-09-26). Since our version: global-router guard honours `-allow_congestion` (PR #11754, 2026-10-15); vectorless activity fix, which also fixes tie-cell outputs getting the input duty (OpenSTA PR #425, merged 2026-10-19, closes OpenSTA #539; **not in `e913e15`**). Fixed after our version: CTS leaving a clock gate's clock pin unconnected (#9816, PR #9864, 2026-03-27; seen here on two latch cores, workaround `tools/firm_clock_gates.tcl`); ties broken by heap address, among them detailed placement's mirroring (PR #10573, 2026-06-02; also #10085, #10398, #10655, #10656), which makes our reruns depend on the excluded-cell order and on the lengths of the input paths (found here 2026-11-06). Open: **clock-net detours with CTS NDRs, a 26Q4 regression ending in `GRT-0229`** (#11653; PRs #11963, #12039 in progress); delay cells as buffers (#10622); hierarchical SPEF names (#11839). Much resizer work in progress (`PARALLEL_EVAL`, `SETUP_REPAIR_PHASES`) | sky130 5.1 `CTS_APPLY_NDR: none` stays and matters more with 26Q4 (corrected: #11754 does not fix #11653); sky130 8.1 tie-cell outputs (#539, corrected); 1.1 drive-2 cells and delay cells unchanged; sky130 11: rerun in the same directory, and check reruns in directories of other path lengths at the 3.1 upgrade |
| Yosys | 0.62 (LibreLane, used by ORFS too); 0.70+219 devel (OSS CAD Suite) | 0.46 / 0.44 | release 0.70 (2026-10-13); 0.71 due in November | none |
| sky130 PDK | open_pdks `8afc834` (ciel), `PDK_ROOT=/media/pdk/sky130_8afc834` | `c6d73a35` (volare), `/media/pdk/sky130A` | LibreLane 3.0.17 keeps `8afc834`; `792ef67` in 3.1 (dev). open_pdks master: only gf180 DRC text since the last review. ciel 3.2.0 (2026-10-21) | **OpenLane 2's OpenSTA crashes on SPEF from the new PDK** (sky130 1) |
| OSS CAD Suite | 2026-10-24 nightly, `/media/hardware_design_tools/oss-cad-suite`: Icarus 14.0 devel, Verilator 5.053 devel, Yosys 0.70+219 | 2024-08-07 (`oss-cad-suite-2024-08-07`) | nightlies only (latest 2026-10-31). Tagged releases of its tools: Icarus v13_0 (2026-03-02), Verilator v5.052 (2026-09-05), Yosys v0.70; no new release since the last review | Verilator 5.053 VCD scope change (sky130 7.4) |
| OpenROAD-flow-scripts | `ef2cb37` (2026-02-12) + `3a376ac` + SRAM-Vt aliases, `/media/pdk/OpenROAD-flow-scripts-ef2cb37` | `b4dbcb4` + `ASAP7_USESRAM` patch, `/media/pdk/OpenROAD-flow-scripts` | no releases since v3.0 (2024); no ASAP7 platform change since 2026-10-24. Since the last review: synthesis stops on a `SYNTH_KEEP_MODULES` name that matches no module (`0bc1a7d`, 2026-10-27), `SETUP_REPAIR_PHASES`, `read_vcd`/`read_saif` through flow variables, `REMOVE_ABC_BUFFERS` removed (PR #4580). Earlier ASAP7 changes (tech LEF DRC fix, segment resistance, resistance-aware routing, `ROUTING_LAYER_ADJUSTMENT`, PDN halo fix) need a newer OpenROAD than LibreLane 3.0 ships | ASAP7 5: a keep-module name that matches nothing flattens silently in `ef2cb37` (new); ASAP7 1: `QT_QPA_PLATFORM` still required (fix #3944 covers an empty `DISPLAY` only) |
| SRAM22 macros | upstream `de0a9a7` with our fixes, `/media/pdk/sram22_sky130_fixed-de0a9a7` | fixed copies of `75cbe96` in project folders | unchanged (`de0a9a7`) | keep our LEF/GDS fixes (sky130 9.1) |
| ASAP7 library | `asap7sc7p5t_28` `472f7b3` and the ORFS platform copy | | unchanged; issues #3 (FF corner conditions), #5 (INVBUF names) and asap7 #42 (10 ps precision) open | ASAP7 8.1 |

## Upgrade candidates (owner decides)

| candidate | gain | cost and risk | recommendation (2026-11-01) |
|---|---|---|---|
| LibreLane 3.0.17 | latest patch release; Magic memory fix | none for measurement; tool pins unchanged | adopt at the next quarterly update (January 2027 at the earliest), or now if a tapeout needs Magic |
| LibreLane 3.1 (when released) with OpenROAD 26Q4, open_pdks `792ef67` | ports buffered with `SYNTH_BUFFER_CELL` instead of delay cells; newer OpenROAD for the ASAP7 ORFS fixes; OpenROAD's determinism fixes (ties no longer by heap address, sky130 11); `OPENROAD_THREADS` | **changes synthesis defaults** (`DELAY 4`, Booth, arithmetic trees, untrimmed liberties): every number moves; the 26Q4 clock-NDR detour regression (#11653) is open; OpenSTA `e913e15` still lacks PR #425 | wait for the release and for #11653 to be fixed; then validate on the reference set with the old synthesis defaults pinned and with the new ones, and decide which become the rule; also harden one design twice, in directories whose paths differ in length, to check the determinism fixes |
| Simulators from LibreLane's pinned environment instead of the OSS CAD nightly | released Verilator and Icarus, upgraded together with LibreLane (3.1: Verilator 5.046, Icarus 13.0) | Verilator scope, Icarus version and glitch numbers to revalidate on the reference set | at the next quarterly update, together with LibreLane |
| ORFS newer than `ef2cb37` | ASAP7 tech LEF DRC fix, better resistance model, keep-module check, headless `6_report` | needs a newer OpenROAD than LibreLane 3.0.x ships; ASAP7 rules change | with LibreLane 3.1's OpenROAD, after the reference set |
| OpenSTA with PR #425 | vectorless gated-clock activity no longer overcounted; tie-cell outputs keep their constant | not in any LibreLane yet (3.1 pins `e913e15`, before the merge) | wait for LibreLane; annotate tie-cell outputs meanwhile (sky130 8.1) |
| sky130 open_pdks `792ef67` | | only with LibreLane 3.1 | with LibreLane 3.1 |
