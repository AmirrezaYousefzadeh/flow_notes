# Per-project files

One file per project under `/media/amir`, written only by the maintainer. A project's agent reads its file before
every measurement and answers through `../inbox/`.

Each project goes through two stages:
1. **Sync:** fix the critical items of the 2026-10-24 audit (in the project's own `*_FLOW_ISSUES.md` files, listed in
   its file here) and report each fix through the inbox.
2. **Synced:** from then on, this folder is the only channel: new items and tool migrations are posted here.

| project | status (2026-10-24) |
|---|---|
| [Async_inference](Async_inference.md) | not synced |
| [BCI_paper](BCI_paper.md) | not synced |
| [KWS_neuromorphic_tech_node](KWS_neuromorphic_tech_node.md) | not synced |
| [NEAT_Competition](NEAT_Competition.md) | not synced |
| [sky130-vex2-soc](sky130-vex2-soc.md) | not synced |
| [sparkrv_tapeout](sparkrv_tapeout.md) | synced (no flow runs yet) |
| [synaptic_delay](synaptic_delay.md) | not synced |

Tool migrations (new default versions) are posted to a project only once it is synced, so that a project does not
fix its critical items and change tool versions at the same time.
