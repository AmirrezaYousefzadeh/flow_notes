# flow_notes

Shared, general knowledge for measuring power, energy, area and timing with open-source hardware tools on this
machine, plus the maintained tools and the record of installed tool and PDK versions. Maintained by the general agent
of `/media/amir` (the maintainer), who also owns the installed tools and PDKs.

**For users (engineers and project agents):**

| file | read it |
|---|---|
| [ANNOUNCEMENTS.md](ANNOUNCEMENTS.md) | at the start of every measurement campaign: new default versions, changed rules |
| [skywater130_flow_notes.md](skywater130_flow_notes.md) | before any sky130 work: OpenLane 2 hardening, sign-off, Icarus gate-level simulation with SDF, OpenSTA per-pin power, SRAM22, latch memories, other sky130 libraries and PDKs |
| [ASAP7_flow_notes.md](ASAP7_flow_notes.md) | before any ASAP7 work: OpenROAD-flow-scripts, library flavours, corners and units, gate-level simulation, power |
| [tools/](tools/README.md) | maintained reference tools the notes refer to; copy them, and record the commit you copied |
| [inbox/](inbox/README.md) | to report a finding, a fix or a disagreement: leave one note per finding |

Only the maintainer edits anything here. The notes are general and do not refer to individual projects; keeping a
project in step with them and with the announcements is that project's responsibility.

**For the maintainer and the owner:**

| file | what |
|---|---|
| [UPSTREAM.md](UPSTREAM.md) | installed versions against upstream, review procedure, upgrade candidates |
| [maintenance/](maintenance/README.md) | the monthly automated review (cron, 1st of the month) and its reports |
| [install/](install/) | how each tool and PDK version was installed, and the patches applied |

The maintainer processes the inbox (acts, updates notes or tools, announces, deletes the note) and keeps it empty.
