# Upstream watch: installed versions against upstream

**Last review: 2026-10-24** (by the general agent, from the web check of both notes). **Next review: 2026-11-01** (automated, `maintenance/README.md`).

The open-source tools and PDKs change quickly. Several rules in the notes exist only because of bugs that upstream has
since fixed, and some recommended practices change with new releases. On the 1st of every month, an automated run of the
general agent of `/media/amir` reviews upstream and updates this file and the notes. The owner decides which upgrades to install.

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
   - rerun a reference design: the NEAT macro test design must reproduce its numbers, or the difference must be
     explained;
   - record the new pin in the notes' section 1 and in this file;
   - tell every project which version it uses, so that no project changes version silently.
5. Report to the owner: what changed upstream, what changed in the notes, and which upgrades are proposed.

## Installed versions (pins) and upstream

| component | installed (pin) | upstream now (2026-10-24) | effect on our rules |
|---|---|---|---|
| OpenLane 2 | 2.3.10, `a7b0e6d`, Nix flake in `/media/hardware_design_tools/openlane2` | OpenLane 2 is superseded by **LibreLane**, which its own README points to | LibreLane: `PL_TIME_DRIVEN` defaults to false, `PNR_CORNERS` exists (sky130 5.7). Needed for tapeout (sky130 12). |
| OpenSTA (inside OpenLane) | `b5f3a02` (2024-10-02), reports "2.6.0" | densities instead of per-cycle activities (2025-01-17); `report_activity_annotation` (2025-01-15); gated-clock activity fix (OpenROAD fork PR #425, 2026-10-19) | the clock-stop power loss is specific to our version (sky130 8.2); with newer versions, annotate with `-density`, because `-activity` is converted with the fastest clock |
| OpenROAD (inside OpenLane) | `edf00dff` | SPEF escaped-slash partial fix (PR #8772, 2025-11); escaped-name SPEF misses still open (#11839) | keep renaming with `legal_names.py` (sky130 5.4) |
| OpenROAD-flow-scripts | `b4dbcb4` (2024-10-02) **plus a local SRAM-Vt patch** | `ASAP7_USE_VT` replaces `ASAP7_USELVT`/`USESLVT`; hold metrics (2025-03); `REMOVE_ABC_BUFFERS` removed (2026-10-21); RVT `SIMPLE` FF liberty re-characterised (2026-02-23); `ROUTING_LAYER_ADJUSTMENT` 0.25; `CTS_BUF_LIST` | an update loses the local patch (ASAP7 1); several ASAP7 rules change (5, 6.4, 6.5, 7.2) |
| Yosys | 0.44+1 (OSS CAD Suite), 0.46 `e97731b` (Nix, used by OpenLane and ORFS) | `extract_fa` fix in 0.50 (PR #4691, 2025-02) | from 0.50 the adder map may be safe; verify with an equivalence check before enabling (ASAP7 5) |
| Icarus Verilog | 13.0 devel s20221226-533 (`676b36e45`, OSS CAD Suite 2024-08-07) | SDF `TIMESCALE` honoured in master (PR #1501, 2026-09-13); x/z on `COND` paths treated as true (#1541, 2026-10); still no `COND`, timing checks or bus-bit SDF | the sanitiser's ps → ns rescale becomes unnecessary with master (sky130 7.1) |
| sky130 PDK | open_pdks `c6d73a35` (volare) | not reviewed yet | check the `ms` leakage and the diode liberties (sky130 9.4; skywater-pdk #358) |
| SRAM22 macros | old views with `default_max_transition 0.04` (local fixed copies in NEAT `flow/macros/`) | fixed to 0.351 ns (sram22_sky130_macros PR #13, 2026-09-09); double-counting liberty unchanged; `prBoundary` declined (#504) | the slew-limit rule becomes unnecessary with new views; keep our LEF/GDS fixes (sky130 9.1) |
| ASAP7 library | `asap7sc7p5t_28` `472f7b3` (sparse clone) and the ORFS platform copy | issues #3 (FF RVT characterisation) and #5 (INVBUF names); asap7 #42 (10 ps precision) open | ASAP7 3.3, 8.1 |
| OSS CAD Suite | 2024-08-07 | not reviewed yet | carries our Icarus and the 0.44 Yosys |

## Upgrade candidates (owner decides)

| candidate | gain | cost and risk |
|---|---|---|
| LibreLane (next to OpenLane 2.3.10) | needed for a tapeout; newer OpenROAD and OpenSTA; `PNR_CORNERS` | configuration changes; every project's numbers move; must be validated on the NEAT reference design |
| Newer OpenSTA for power analysis only | densities, `report_activity_annotation`, gated-clock fix | power numbers move compared with published ones; run it next to the old one first |
| ORFS update | upstream ASAP7 fixes (FF liberty, hold metrics) | loses the local SRAM-Vt patch, which must be re-applied on top of `ASAP7_USE_VT`; many ASAP7 rules change |
| Icarus master | SDF time scale handled natively | development build; the bit-exact and annotation checks must be repeated |
| SRAM22 views from upstream | correct slew limit | our LEF and GDS fixes must be re-applied |
