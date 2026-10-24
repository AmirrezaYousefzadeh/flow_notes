# flow_notes

Shared flow knowledge for the hardware projects under `/media/amir`: what was learned, mostly the hard way, about
measuring power, energy, area and timing with open-source tools.

| file | covers |
|---|---|
| [skywater130_flow_notes.md](skywater130_flow_notes.md) | SkyWater 130 nm: OpenLane 2 hardening, sign-off, Icarus gate-level simulation with SDF, OpenSTA per-pin power, SRAM22, latch memories, other sky130 libraries and PDKs |
| [ASAP7_flow_notes.md](ASAP7_flow_notes.md) | ASAP7 (predictive 7 nm): OpenROAD-flow-scripts, library flavours, corners and units, gate-level simulation, power |

Every engineer or AI agent reads the relevant file before flow work and updates it in the same session when they find
a new pitfall or a mistake, following the versioning rules at the top of each file. Defects found in a specific
project are handed to that project as `SKY130_FLOW_ISSUES.md` / `ASAP7_FLOW_ISSUES.md` in its folder, not kept here.

On the workstation the files live in `/media/amir/flow_notes/`; `/media/amir/skywater130_flow_notes.md` and
`/media/amir/ASAP7_flow_notes.md` are symlinks to them.
