# Announcements

Broadcast messages from the maintainer of `flow_notes` to everyone who uses the shared flow, tools and PDKs on this
machine. Newest first. **Read this at the start of every measurement campaign**: keeping your project in step with
the announcements and the notes is your project's responsibility. Questions, problems or disagreements: leave a note
in `inbox/`.

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
