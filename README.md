# flow_notes

Shared flow knowledge for the hardware projects under `/media/amir`: what was learned, mostly the hard way, about
measuring power, energy, area and timing with open-source tools.

| file | covers |
|---|---|
| [skywater130_flow_notes.md](skywater130_flow_notes.md) | SkyWater 130 nm: OpenLane 2 hardening, sign-off, Icarus gate-level simulation with SDF, OpenSTA per-pin power, SRAM22, latch memories, other sky130 libraries and PDKs |
| [projects/](projects/) | per project: open items and migration steps from the maintainer; read before every measurement |
| [inbox/](inbox/README.md) | findings from projects, waiting for the maintainer |
| [UPSTREAM.md](UPSTREAM.md) | installed versions against upstream, the monthly review procedure, upgrade candidates |
| [ASAP7_flow_notes.md](ASAP7_flow_notes.md) | ASAP7 (predictive 7 nm): OpenROAD-flow-scripts, library flavours, corners and units, gate-level simulation, power |

Every engineer or AI agent reads the relevant file before flow work. **Only the maintainer (the general agent of
`/media/amir`) edits the notes.** Anyone who finds a new pitfall, a mistake or a better fix leaves a note in
[`inbox/`](inbox/README.md); the owner asks the maintainer to process the inbox. Defects found in a specific
project, and migrations after a tool update, go to that project's file in [`projects/`](projects/), which its agent
reads before every measurement. Nothing is written into the project folders.

`UPSTREAM.md` tracks the installed tool and PDK versions against upstream. It is reviewed every month by an automated
run (`maintenance/`), and the notes
are updated when upstream fixes or changes something they rely on. Upgrades are installed only with the owner's
approval.

On the workstation the repository is `/media/amir/flow_notes/`; read the notes there.

**Who reads what.** Designer agents and engineers read the two notes files: their section 1 states the installed
versions they must use. `UPSTREAM.md` and `maintenance/` are for the maintainer (the general agent of `/media/amir`)
and the owner: the upstream comparison, the monthly review (`maintenance/README.md`) and its reports.
