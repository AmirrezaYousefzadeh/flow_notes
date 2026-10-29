# Upstream watch: installed versions against upstream

**Last review: 2026-10-28** (check for updates and more stable versions, on the owner's request). **Next review: 2026-11-01** (automated, `maintenance/README.md`).

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

| component | installed default (pin) | previous version kept | upstream now (2026-10-28) | effect on our rules |
|---|---|---|---|---|
| LibreLane | 3.0.16 (`01ddb25`), `/media/hardware_design_tools/librelane` | OpenLane 2.3.10 (`a7b0e6d`), `/media/hardware_design_tools/openlane2` | **3.0.17** (2026-10-26): no behavioural change, documentation plus a backported Magic memory fix; same OpenROAD, OpenSTA, Yosys and PDK pins. 3.1.0.dev4 is a pre-release (new sky130 pin `792ef67`) | none for measurement (Magic runs only in tapeout steps) |
| OpenROAD / OpenSTA (inside LibreLane) | OpenROAD `dcf3613` (2026-02-17), OpenSTA 2.7.0 `857316f` | OpenROAD `edf00dff`, OpenSTA `b5f3a02` | no tagged releases (last tag v2.0, 2021); LibreLane 3.0.17 and 3.1.0.dev4 keep `dcf3613`. Not in our version: global-router guard fix (PR #11754), gated-clock activity fix (OpenSTA PR #425) | keep `CTS_APPLY_NDR: none` where needed (sky130 5.1); `dcf3613` buffers ports with `clkdlybuf4s25_1` and hardly resizes in design repair, so cell area grows (sky130 1) |
| Yosys | 0.62 (LibreLane, used by ORFS too); 0.70+219 devel (OSS CAD Suite) | 0.46 / 0.44 | release 0.70 (2026-10-13) | |
| sky130 PDK | open_pdks `8afc834` (ciel), `PDK_ROOT=/media/pdk/sky130_8afc834` | `c6d73a35` (volare), `/media/pdk/sky130A` | LibreLane 3.0.17 keeps `8afc834`; `792ef67` only in the pre-release | **OpenLane 2's OpenSTA crashes on SPEF from the new PDK** (sky130 1) |
| OSS CAD Suite | 2026-10-24 nightly, `/media/hardware_design_tools/oss-cad-suite`: Icarus 14.0 devel, Verilator 5.053 devel, Yosys 0.70+219 | 2024-08-07 (`oss-cad-suite-2024-08-07`) | nightlies only. Tagged releases of its tools: Icarus v13_0 (2026-03-01), Verilator v5.052 (2026-09-05), Yosys v0.70. LibreLane's own environment ships Verilator 5.044 (release), Icarus 13.0, Yosys 0.62, pinned with each LibreLane release | Verilator 5.053 VCD scope change (sky130 7.4) |
| OpenROAD-flow-scripts | `ef2cb37` + `3a376ac` + SRAM-Vt aliases, `/media/pdk/OpenROAD-flow-scripts-ef2cb37` | `b4dbcb4` + `ASAP7_USESRAM` patch, `/media/pdk/OpenROAD-flow-scripts` | no releases since v3.0 (2024). ASAP7 changes since `ef2cb37`: fixed 1x tech LEF for M1–M3 DRC (2026-09-13), segment-based layer resistance (2026-05), resistance-aware global routing by default (2026-04), `ROUTING_LAYER_ADJUSTMENT` variable (2026-07), PDN halo fix (2026-10-23). They need a newer OpenROAD than LibreLane ships | ASAP7 1, 6 |
| SRAM22 macros | upstream `de0a9a7` with our fixes, `/media/pdk/sram22_sky130_fixed-de0a9a7` | fixed copies of `75cbe96` in project folders | unchanged (`de0a9a7`) | keep our LEF/GDS fixes (sky130 9.1) |
| ASAP7 library | `asap7sc7p5t_28` `472f7b3` and the ORFS platform copy | | issues #5 (INVBUF names) and asap7 #42 (10 ps precision) open | ASAP7 8.1 |

## Upgrade candidates (owner decides)

| candidate | gain | cost and risk | recommendation (2026-10-28) |
|---|---|---|---|
| LibreLane 3.0.17 | latest patch release; Magic memory fix | none for measurement; tool pins unchanged | adopt at the next quarterly update, or now if a tapeout needs Magic |
| Simulators from LibreLane's pinned environment instead of the OSS CAD nightly | released Verilator (5.044) and one pinned environment upgraded together with LibreLane | Verilator scope, Icarus version and glitch numbers to revalidate on the reference set | at the next quarterly update |
| ORFS newer than `ef2cb37` | ASAP7 tech LEF DRC fix, better resistance model | needs a newer OpenROAD than LibreLane 3.0.x ships; ASAP7 rules change | wait for a LibreLane release with a newer OpenROAD |
| OpenSTA with PR #425 (gated-clock activity) | vectorless gated-clock activity no longer overcounted | only matters for unannotated gated trees | wait for LibreLane |
| sky130 open_pdks `792ef67` | | only in LibreLane 3.1 pre-release | wait for LibreLane 3.1 |
