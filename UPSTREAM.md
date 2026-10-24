# Upstream watch: installed versions against upstream

**Last review: 2026-10-24** (web check of both notes; tool and PDK update installed and validated the same day). **Next review: 2026-11-01** (automated, `maintenance/README.md`).

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
   - rerun the reference designs (`validation/`): they must reproduce their numbers, or the difference must be
     explained;
   - record the new pin in the notes' section 1 and in this file;
   - announce the change in `ANNOUNCEMENTS.md`, with migration notes.
5. Report to the owner: what changed upstream, what changed in the notes, and which upgrades are proposed.

## Installed versions (pins) and upstream

| component | installed default (pin) | previous version kept | upstream now (2026-10-24) | effect on our rules |
|---|---|---|---|---|
| LibreLane | 3.0.16 (`01ddb25`), `/media/hardware_design_tools/librelane` | OpenLane 2.3.10 (`a7b0e6d`), `/media/hardware_design_tools/openlane2` | 3.0.16 latest release; 3.1.0.dev4 pre-release | `PL_TIME_DRIVEN` false by default, `PNR_CORNERS` (sky130 5.7) |
| OpenROAD / OpenSTA (inside LibreLane) | OpenROAD `dcf3613` (2026-02-17), OpenSTA 2.7.0 `857316f` | OpenROAD `edf00dff`, OpenSTA `b5f3a02` | OpenSTA gated-clock activity fix (OpenROAD fork PR #425, 2026-10-19), not in our version; SPEF escaped-name misses still open (#11839) | densities: no clock-stop trap (sky130 8.2); keep `legal_names.py` (5.4) |
| Yosys | 0.62 (LibreLane, used by ORFS too); 0.70+219 (OSS CAD Suite) | 0.46 / 0.44 | `extract_fa` fix since 0.50 | the ASAP7 adder map may be safe; verify before enabling (ASAP7 5) |
| sky130 PDK | open_pdks `8afc834` (ciel), `PDK_ROOT=/media/pdk/sky130_8afc834` | `c6d73a35` (volare), `/media/pdk/sky130A` | not reviewed beyond LibreLane's pin | **OpenLane 2's OpenSTA crashes on SPEF from the new PDK** (sky130 1) |
| OSS CAD Suite | 2026-10-24, `/media/hardware_design_tools/oss-cad-suite` | 2024-08-07 (`oss-cad-suite-2024-08-07`) | nightly | Icarus 14 devel honours SDF `TIMESCALE` (rescale harmless) |
| OpenROAD-flow-scripts | `ef2cb37` + `3a376ac` + SRAM-Vt aliases, `/media/pdk/OpenROAD-flow-scripts-ef2cb37` | `b4dbcb4` + `ASAP7_USESRAM` patch, `/media/pdk/OpenROAD-flow-scripts` | `REMOVE_ABC_BUFFERS` removed (2026-10-21), `ROUTING_LAYER_ADJUSTMENT` 0.25 | ASAP7 1, 5, 6 |
| SRAM22 macros | upstream `de0a9a7` with our fixes, `/media/pdk/sram22_sky130_fixed-de0a9a7` | fixed copies of `75cbe96` in project folders | double-counting liberty unchanged; `prBoundary` declined (#504) | keep our LEF/GDS fixes (sky130 9.1) |
| ASAP7 library | `asap7sc7p5t_28` `472f7b3` and the ORFS platform copy | | issues #5 (INVBUF names) and asap7 #42 (10 ps precision) open | ASAP7 8.1 |

## Upgrade candidates (owner decides)

| candidate | gain | cost and risk |
|---|---|---|
| ORFS newer than `ef2cb37` | upstream fixes since 2026-02 | needs matching (newer) OpenROAD than LibreLane 3.0.16 ships; rules in ASAP7 5–6 change |
| OpenSTA with PR #425 (gated-clock activity) | vectorless gated-clock activity no longer overcounted | only matters for unannotated gated trees; numbers move |
| LibreLane 3.1 | when released | revalidate on `validation/` |
