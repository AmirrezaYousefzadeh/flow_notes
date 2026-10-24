# SkyWater 130 nm flow notes: synthesis, hardening, gate-level simulation and power

**Version 3.0, last updated 2026-10-24.** The full history is in "Version history" below.

Read this before you synthesise, harden or measure anything on sky130 in any project under `/media/amir`. It is
written for engineers and AI agents. Everything here was learned the hard way, mostly in the NEAT BMI challenge
(`/media/amir/NEAT_Competition`), whose flow is the most thoroughly checked one on this machine, and in BCI_paper,
synaptic_delay, KWS_neuromorphic_tech_node and sky130-vex2-soc. Most of the problems below fail **silently**: the flow
runs to the end and prints a plausible number that is wrong. Section 10 is the checklist every measurement must pass.
ASAP7 has its own notes: `/media/amir/flow_notes/ASAP7_flow_notes.md`.

These notes are for **measuring** power, energy, area and timing. They do not describe a tapeout flow (section 12).

**How this file is kept current.** Only the maintainer (the general agent of `/media/amir`) edits this file.
Engineers and project agents **do not edit it**. When you find a new pitfall, a mistake in this file, a better fix,
or a measured effect, leave a note in the inbox and carry on:
- write `/media/amir/flow_notes/inbox/YYYY-MM-DD_<project>_<short-topic>.md`, one note per finding;
- say which file and section it concerns, the symptom, how you detected it, the fix, the measured size of the effect,
  and where the evidence is (paths, log lines);
- say whether it is general or specific to your project.

The owner asks the maintainer to process the inbox. The maintainer then updates this file (version bump, history
row) and deletes the processed note. The maintainer never writes into project folders: what a project must fix or
change (audit findings, tool migrations) is in `/media/amir/flow_notes/projects/<project>.md`. **Read your
project's file before every measurement**, and report fixes or disagreements through the inbox.

**Is my copy current?** Record the version you read in your project's notes. At the start of the next session,
compare it with the line under the title. If the version has changed, read the history rows since your version
before you start; if only those rows matter to you, there is no need to reread the whole file.

**Upstream.** The tools and PDKs change quickly. `UPSTREAM.md` in this folder lists the installed versions against
upstream and is reviewed monthly; when upstream fixes a bug that one of these rules works around, the rule is
updated. Do not upgrade an installed tool or PDK without the owner's approval.

### Version history

| version | date | project | change |
|---|---|---|---|
| 1.0 | 2026-10-24 | NEAT_Competition | first version: the verified NEAT flow, plus the audits of BCI_paper, KWS, synaptic_delay, Async_inference and sky130-vex2-soc |
| 1.1 | 2026-10-24 | BCI_paper (round 6), reported by the general agent | 8.2: the advice to stop clock propagation at the clock gates was wrong and is now a warning (combinational power disappears with toggle-count activities); two checklist lines; pointer to the ASAP7 notes in 9.3 |
| 2.0 | 2026-10-24 | all, audit by the general agent | **0 rewritten: all heavy jobs go through the shared `jobq` queue** (all cores at nice 19, no CPU pinning). Corrected: SRAM22 clock-pin conditions are `we`/`ce`, not `ce&rstb` (9.1); clock duty 0.19–1.06 % and combinational share 25–75 % (8.2); NEAT power 8.18 µW (5.4); hold buffers +53 and +930 (6.1, 9.2); Icarus compile about 10 GB (0); `env.sh` scope (1); physical-cell stubs only where the model file lacks the cell (7). New: low-voltage corners (5.7), physical-sign-off settings are measurement-only (5.1, 12), decap and endcap results, `sky130_fd_sc_ms` has no leakage (9.4), ICG fan-out and SRAM clock slew (3, 9.1), power-grid status of BCI and vex2 (9.1), Icarus capacity and Verilator (7.3, 7.4), pin/net activity order (8.1), register initialisation, FIFO deadlock, OpenSTA 2.6 commands, five checklist lines |
| 2.1 | 2026-10-24 | web check by the general agent | rules checked against tool sources, documentation and issue trackers; sources added. Corrected: 8.2 mechanism is specific to the OpenSTA of OpenLane 2.3.10 (newer OpenSTA stores densities); SRAM22 0.04 ns slew limit fixed upstream on 2026-09-09 (9.1); Icarus honours SDF `TIMESCALE` in master since 2026-09-13 (7.1); OpenLane defaults stated in 5.1; 9-corner sign-off is OpenLane's default (6.2). New: 8.8 what a power number must state; LibreLane `PNR_CORNERS` and `PL_TIME_DRIVEN` default (5.7); OpenSTA version notes (8.1); CTS skew across clock gates (3); precheck contents (12) |
| 3.0 | 2026-10-24 | owner's decision | **only the maintainer edits this file**; engineers and project agents report findings as notes in `flow_notes/inbox/` (header) |

Contents:
0. Ground rules on this machine
1. Tools and paths
2. Reference implementations to copy from
3. RTL rules for a design you want to measure
4. Synthesis
5. Hardening with OpenLane 2
6. Timing constraints and sign-off
7. Gate-level simulation
8. Power with OpenSTA
9. Special cases: the SRAM22 macro, latch memories, other libraries and PDKs
10. Checklist for every measurement
11. Reproducibility of the numbers (and of trained networks)
12. Not covered: tapeout

---

## 0. Ground rules on this machine

The workstation (24 cores, 62 GB RAM, one RTX 4060 Ti with 8 GB) is shared with other users and other projects.

- **Every heavy job goes through the shared queue `jobq`** (`/media/amir/.jobq/jobq.py`, guide in
  `/media/amir/.jobq/README.md`; since 2026-10-24 it replaces the KWS `tools/jobq.py`). "Heavy" means longer than a few
  minutes, more than about 2 GB of RAM, more than 2 threads, or the GPU. Never start such a job with `&` or `nohup`.
  - `jobq add --name N --threads T --mem <peak GB> [--gpu MB] [--stall-min N] -- 'command'`; then
    `jobq status | log N | wait N | cancel N`. Use `--high` only when the owner asks for it.
  - **Declare a realistic peak memory.** A job starts only when `--mem` + 3 GB is free; its RAM is capped at
    max(1.4 × mem, mem + 4) GB and it swaps above that. Only queue jobs may swap; anything outside the queue is
    OOM-killed instead.
  - **Pass the thread count on.** The job gets `JOBQ_THREADS`; give it to `ROUTING_CORES`, `-j`, `NUM_CORES`.
  - The queue runs jobs at `nice 19`, idle I/O priority and the lowest CPU weight, and its watchdog kills leftover
    processes and stalled jobs. Do not pin jobs to fixed CPUs (`taskset -c 0-9`, as `NEAT_Competition/env/env.sh`
    still does): concurrent queue jobs would pile onto the same cores.
  - If the daemon is down, tell the owner; do not start jobs outside the queue. Never cancel other people's jobs.
- **Memory figures for declaring `--mem`.**
  - Icarus compilation of a 100 000-cell SDF-annotated netlist: about 10 GB (NEAT). Running six at once triggered the
    out-of-memory killer, which killed a compilation and system processes of other users.
  - OpenROAD detailed routing: 10–15 GB for NEAT-size cores; above 20 GB for a 155 000-latch core (KWS), which then
    failed.
  - OpenROAD repair at a low-voltage corner: 40–45 GB (section 5.7).
- **Never edit a running bash script in place.** Bash reads scripts incrementally, so editing one mid-run corrupts
  the run. Write a new file and `mv` it over the old one.
- **OpenLane runs under `nix develop` with many child processes.** If you must stop one, signal its process group
  (`kill -TERM -- -PGID`), not single processes.
- **For AI agents.**
  - `pkill -f` or `pgrep -f` patterns that also match your own command line kill your own shell. Look up the process
    IDs first, then signal them by number.
  - A deletion through a shell variable (`rm -rf $DIR/...`) is blocked by the safety check; write `"${DIR:?}"`.
  - Never send a simulator's or tool's stderr to `/dev/null`: it hides compile errors (seen in Async_inference).
- **Ask before decisions.** The owner wants design choices, rule choices and anything destructive discussed first.

## 1. Tools and paths

| what | where / version | how to call |
|---|---|---|
| PDK | `/media/pdk/sky130A` (open_pdks `c6d73a35f524070e85faff4a6a9eef49553ebc2b`, volare); also sky130B, gf180mcuA–D, ihp-sg13g2, asap7, nangate45 | `PDK_ROOT=/media/pdk`, `PDK=sky130A` |
| OpenLane 2 | 2.3.10, checkout `/media/hardware_design_tools/openlane2` (commit `a7b0e6d`), Nix flake, with its OpenROAD, Yosys, OpenSTA 2.6.0 | `nix --extra-experimental-features "nix-command flakes" develop --accept-flake-config /media/hardware_design_tools/openlane2 -c python3 -m openlane --pdk-root /media/pdk --pdk sky130A --manual-pdk --run-tag TAG --overwrite [--to OpenROAD.STAPostPNR] config.yaml` |
| OpenSTA | inside the same Nix shell | `nix ... develop ... -c sta -no_splash -exit script.tcl` |
| Icarus Verilog, Yosys | OSS CAD Suite 2024-08-07 in `/media/hardware_design_tools/oss-cad-suite` (Icarus 13.0 devel s20221226-533, Yosys 0.44+1) | add its `bin/` to `PATH` |
| Nix | `/nix/var/nix/profiles/default` | `source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh` |
| Python with numpy 1.26.4, torch 2.2.2, h5py | `/media/amir/BCI_paper/.venv/bin/python` (NEAT's `.venv` is a symlink to it) | |
| OpenROAD-flow-scripts (ASAP7) | `/media/pdk/OpenROAD-flow-scripts` | see the ASAP7 notes |
| Icarus models with SDF paths for other PDKs | `/media/pdk/icarus_sdf_models/` | see section 9.3 before trusting them |
| shared job queue | `/media/amir/.jobq` | `jobq`, section 0 |

`/media/amir/NEAT_Competition/env/env.sh` sets up the PDK, OpenLane, Nix, OSS CAD Suite and Python paths. It does not
set ORFS or the Icarus model paths, and it still pins jobs to CPUs 0–9 with `NEAT_THREADS=10`; drop the pinning when
you run under `jobq`.

Folders that moved to `/media/amir` keep absolute symlinks into other projects (for example a `.venv` or a `macros`
folder), and many scripts and notes still name `/home/yousefzadeha/workspace/...`, which no longer exists. Check
links with `find -xtype l` and grep for the old path: a broken link to a liberty file makes a macro silently disappear
from the power analysis (BCI's `synthesis/bmi_snn_top/macros` link is broken today).

## 2. Reference implementations to copy from

**NEAT challenge flow: `/media/amir/NEAT_Competition/flow/`.** Verified end to end; the macro test design reproduces
the same power to the last digit. Start from it.

| file | what it does |
|---|---|
| `harden.sh` | one OpenLane run at a declared utilisation, fallback 20 %; routing watchdog; own sign-off timing; acceptance gate; `harden.json` |
| `config.template.yaml`, `neat_decoder.sdc`, `pdn_cfg_sram22.tcl` | the OpenLane configuration, the constraints (reset the only exception), the SRAM22 power grid |
| `tools/macro_config.py` | macro instances and an absolute floorplan with the macros in a column |
| `tools/legal_names.py` | plain names for every escaped identifier, consistently in netlist, SDF and SPEF (section 5.4) |
| `tools/signoff_sta.tcl` | sign-off timing with every net's parasitics |
| `tools/check_metrics.py` | accept or reject a run: routing DRC 0, setup and hold met, power grid clean, no unmatched SPEF entries in sign-off, cell cap |
| `gls.sh` | SDF-annotated Icarus simulation, waveform streamed into the toggle counter |
| `tools/sdf_sanitize_for_icarus.py`, `tools/sky130_timing_icarus_fixes.v`, `tools/gen_phys_stubs.py` | make the SDF, the PDK models and the physical cells digestible for Icarus |
| `tools/vcd_toggles.c`, `tools/toggles_to_activity.py` | per-pin transition counts and high times from a VCD stream → `set_power_activity` commands |
| `power.sh`, `tools/power_sta.tcl` | per-pin OpenSTA power, with checks for unmatched SPEF entries and black boxes |
| `tools/root_clock_correction.py` | correction for a clock that is stopped most of the time (section 8.2) |
| `tools/macro_state_correction.py` | SRAM22 read energy conditioned on its clock running (section 9.1) |
| `tools/rt_stats.py` | real-time statistics of a session (deadline overruns, clock duty) |
| `measure.sh` | one session: gate-level simulation, then power → `measure.json`; reuses a simulation only for identical inputs |
| `flow/README.md`, `flow/LESSONS.md` | how the pieces fit together; the pitfalls with their measured effects |

Known gaps of the NEAT flow itself: it warns about but does not fail on SDF errors, it does not count
`Unable to match ModPath`, it starts three Icarus compilations at once, and it runs at `nice 10` with CPU pinning.
These are listed in `flow_notes/projects/NEAT_Competition.md`.

When you copy a tool (`vcd_toggles.c`, `toggles_to_activity.py`, the sanitiser) into another project, record the
NEAT commit it came from; Async_inference's copies already differ from NEAT's.

**sky130-vex2-soc: `/media/amir/sky130-vex2-soc/sky130-vex2-soc`.** The VexRiscv + SRAM22 SoC, and the intended
future reference flow for all of the owner's sky130 projects. It is **not** a reference yet:
- its per-pin power script stops clock propagation at the clock gates (section 8.2), so its published power numbers
  lose most of the combinational power;
- its power grid has about 547 000 violations (section 9.1); use NEAT's `pdn_cfg_sram22.tcl`, not vex2's;
- its fixed SRAM22 GDS is git-ignored and exists only in the old untracked clone `skywater/` inside the repository,
  so the current checkout cannot load its own configuration (5.6).

Its `FLOW_ISSUES_FROM_NEAT.md` and `flow_notes/projects/sky130-vex2-soc.md` list what it still lacks. Until those are fixed, use the
NEAT scripts for measurement. Its SRAM22 LEF and liberty fixes (section 9.1) are correct.

## 3. RTL rules for a design you want to measure

- **Gate clocks with the library integrated clock gate, instantiated directly.** Use `sky130_fd_sc_hd__dlclkp_*`,
  behind a define for synthesis, with a behavioural model for RTL simulation.
  - A clock gated with ordinary logic glitches.
  - NEAT's and synaptic_delay's root-clock corrections only recognise `dlclkp` (BCI's also accepts the clock gates of
    other PDKs).
  - A gate inside a wrapper module gets an escaped name (`\u_x_icg.u_icg`) that Icarus cannot annotate unless you
    rename (section 5.4). vex2's `clk_gate` wrapper causes its 3 SDF errors.
- **Mind the clock-gate fan-out.** An ICG driving about 80 spread-out sinks got no leaf buffers from CTS: 1.4–2 ns slew
  and hold failures. Group about 300 or more sinks per gate (BCI). An ICG driving an SRAM22 clock pin directly gave
  1.5–2 ns slew against a 0.35 ns limit (vex2, section 9.1).
- **Expect skew across the gate boundary.** OpenROAD CTS builds a separate tree per gated net, which gives large
  skew between gated and ungated domains; `-balance_levels` equalises buffer counts, not delays (OpenROAD issue
  #4185). Check hold on paths that cross a gate. LibreLane can also infer ICGs in Yosys (`SYNTH_CLOCKGATE_*`), but
  direct instantiation keeps the names and the control.
- **Mind the names that hierarchy creates.** `(* keep_hierarchy *)` modules and generate blocks become escaped names
  with dots and slashes in the routed netlist. That is allowed, but then you must use the renaming of section 5.4.
- **No unintended latches.** Check that the latch and flip-flop counts after synthesis equal what the RTL declares.
- **Large constant tables.** 230 kbit of weights as one flat `case` synthesised into a web of shared logic that did
  not route at 20 % or 30 % utilisation (5.5 of 6.8 m of wire). One module per output column with
  `(* keep_hierarchy *)` routes; then the names of section 5.4 follow.
- **A register behind a constant ROM.** Yosys folds the register into the ROM's read port only if nothing sits
  between them. With a range check or a multiplexer in between, it pushes the address register through the ROM
  instead, which duplicates a register of the full row width: 1024 extra flip-flops, 37 % more clocked cells.
- **Real-time designs that stop their clock** need a clock-request output (`clk_req`) and a testbench that stops the
  clock while it is low. Power then depends mostly on what is clocked, and how often. A configuration-ready signal
  means the word was accepted, not written: wait, with a bound, for `clk_req` to fall.

## 4. Synthesis

- Run synthesis alone first (OpenLane `--to Yosys.Synthesis`, or `SYNTH_ONLY=1 flow/harden.sh`). It takes minutes,
  and gives a cell count and area for sizing the floorplan.
- Synthesis-only code goes behind a define in `VERILOG_DEFINES` (for example `NEAT_SYNTH`).
- After synthesis, compare the flip-flop and latch counts with the RTL.
- **Count the escaped names in the synthesis netlist** (identifiers starting with `\` that contain `.` or `/`). It is a
  cheap early warning for section 5.4: KWS synthesis netlists already had 875–3 851.
- Synthesis is deterministic. Comment-only RTL changes give a byte-identical netlist, which is a cheap way to prove
  that an edit does not invalidate earlier measurements.
- Yosys/ABC area from a synthesis-only probe is cell area only, untimed and without utilisation; do not compare it
  with OpenLane areas.

## 5. Hardening with OpenLane 2

**5.1 Settings** (`flow/config.template.yaml`). These are **measurement** settings: the flow stops after sign-off
timing (`--to OpenROAD.STAPostPNR`), so "DRC-clean" means the detailed router's DRC only, with no Magic or KLayout
DRC, no LVS and no antenna repair. A layout for tapeout needs the opposite of several of them (section 12).

| setting | value | why |
|---|---|---|
| `DECAP_CELL: []` | decap-free fill | Decap cells leak. With standard fill they made up 0.26 µW of a 1.87 µW measurement (NEAT); 53–81 % of the leakage in BCI round 6, and 2.1–3.8 µW of 2.9–4.9 µW in register-file and latch cores (BCI round 10: E_bin 27.3 → 12.1 nJ and 21.9 → 7.8 nJ). Report the logic's leakage, not the fill's (our measurements; no published source compares them). To fix an existing run, rerun from `OpenROAD.FillInsertion` with `DECAP_CELL: []` and reuse the toggles. |
| `ENDCAP_CELL` | `decap_3` (hd default; `ms` and `hs` use `decap_4`) | Endcaps remain decaps even with `DECAP_CELL: []`: 1 222–1 846 cells, about 4–6 nW. Negligible, but "decap-free" is not literal. |
| `RUN_HEURISTIC_DIODE_INSERTION: false`, `DIODE_ON_PORTS: in` | | Heuristic insertion is off by default in OpenLane 2; keep it off, it broke legalisation at high utilisation. `DIODE_ON_PORTS` defaults to `none`. |
| `RUN_ANTENNA_REPAIR: false` | | Antenna violations are reported, not gated. Measurement only. |
| hold slack margins | 0.5 ns at placement and global routing (defaults 0.1 and 0.05 ns) | A deliberate 5–10× overfix for robust gate-level timing; the hold delay cells cost 0.58–0.61 µW (about 8 %) in NEAT's designs. Choose and document it (KWS uses 0.3 ns, synaptic_delay 0.1 ns). |
| `*_HOLD_MAX_BUFFER_PCT` | 80 (default 50) | Hold buffers are numerous: 9 172 of 62 119 cells (15 %) in the NEAT baseline. OpenLane reports them as `design__instance__count__hold_buffer`. |
| `GRT_ALLOW_CONGESTION` | true (default false) | A congested design reaches detailed routing, where the watchdog (5.3) judges it. Measurement only; false for tapeout. |
| utilisation / density | density = utilisation + 10 %, at most 95 % | This equals OpenLane's default (utilisation + 5 × cell padding + 10, with padding 0 on sky130); with the cell padding of 2 used for SRAM22 floorplans (5.5) the default would be +20. A large ROM core closed at 20 % and not at 30 %. The same netlist at 30 % and 20 % differed by 7 % in power. Small BCI cores routed at 60 %; latch and register-file cores only at 20–30 % (seven 60 % attempts were hopeless after 7 h). |

**5.2 Accept a run only when all of these hold:**
- the detailed router's DRC count is 0;
- setup and hold are met at the sign-off corner, with every net's parasitics (section 6.2);
- the power grid has no violation (BCI's SRAM cores and vex2 fail this today, section 9.1);
- sign-off timing had no unmatched SPEF entries;
- the cell count is within any cap (tap cells excluded, since they grow with the core area).

`OpenLane` reports `design__instance__count__stdcell` including taps and excluding fill.

**5.3 Watchdog.** Detailed routing can run for a day without converging. Stop the run when the violation count stays
high: more than 500 000 after 3 iterations, 20 000 after 6, 3 000 after 10, or no finished iteration for 12 h; and
stop any run after 36 h in total (NEAT `harden.sh`).

**5.4 Escaped hierarchical names: the costliest silent error.** Kept hierarchy and generate blocks appear in the routed
netlist as `\u_rom.u_col_0/_307_`, `\g_ws[9].u_icg` or `\u_demux/_000_`.
- **Icarus SDF annotation** splits the instance name at the dot, logs `SDF ERROR: ... Cannot find X in scope`, and
  simulates the cell without its delays. The activity then misses glitches. Rewriting the SDF name as a Verilog
  escaped name does not help (tried in vex2).
- **OpenSTA SPEF reading.** `*DIVIDER /` makes every slash a hierarchy divider, so the net is not found and loses its
  parasitics. OpenROAD writes three spellings: `a\.b\/c`, `a\.b/c` and the bare `a/c`.
- **OpenLane's own sign-off** (`OpenROAD.STAPostPNR`) reads the same SPEF and loses the same parasitics.
- **Effect in NEAT:** 40 184 SDF errors and 803 757 unmatched SPEF entries; average power rose from 7.00 to 8.18 µW
  (+17 %) once both were fixed. A keep-hierarchy ASAP7 design in ORFS (KWS) lost 4.87 million SPEF entries.
- **Known upstream, not fixed in our version:** OpenROAD issues #3218 and #3211 (closed as stale; the maintainers
  blame the SPEF writer's escaping), #6339, PR #8772 (Nov 2025, partial fix) and the open #11839 (Oct 2026, 431 k
  "net not found" on OpenTitan). `read_spef` inside OpenROAD on the same database does not show it; the stand-alone
  `sta` does. `set_hierarchy_separator` is not a fix. LibreLane's `SYNTH_HIERARCHY_MODE: keep` has an open bug
  (librelane #1020).
- **Fix:** `legal_names.py` renames every escaped identifier to a plain one, the same way in netlist, SDF and SPEF.
  Simulate, time and analyse power on the renamed copies.
- A flat design whose only escaped names are nets without a slash (`\g_ffs.s_pad[0]`) reads correctly; BCI's and
  vex2's netlists are of this kind and show zero SPEF misses.

**5.5 SRAM22 designs.** See section 9.1: absolute floorplan, macro in a column with a 20 µm halo, power-grid hook,
timing liberty in the `MACROS` section, GDS present. `macro_config.py` sizes a roughly square die from the
synthesised standard-cell area, keeps 20 µm from core to die edge, and uses a PDN pitch of 80 and spacing of 15,
`RT_MAX_LAYER: met5` and cell padding 2; `ERROR_ON_PDN_VIOLATIONS: false` there is safe only because
`check_metrics.py` gates on the grid instead.

**5.6 OpenLane checks every file named in the configuration at load time**, including the macro GDS, even when the
flow stops before streamout.

**5.7 Low-voltage corners (for example 1.28 V).** `ss_n40C_1v28` is the only 1.28 V corner of `sky130_fd_sc_hd`, and
it is characterised at −40 °C.
- **Do not harden or repair at it.** OpenROAD repair at `ss_n40C_1v28` grew to 40–45 GB on 0.3–1 M-cell cores,
  because nearly every net violates that library's slew limits: 5 OOM kills in KWS. With it as `DEFAULT_CORNER`,
  timing-driven global placement died after 26 min ("OpenROAD.GlobalPlacement failed unexpectedly"); the workaround
  was `PL_TIME_DRIVEN: false` (BCI round 5; the run log misspells it `PL_TIMING_DRIVEN`). It defaults to true in
  OpenLane 2 and to false in LibreLane. The PDK's `MAX_TRANSITION_CONSTRAINT` is 0.75 ns, which most nets violate at
  1.28 V.
- **Harden at the standard corners, then evaluate the routed netlist and SPEF at the low-voltage liberty** with your
  own STA and power. That is a valid operating point. LibreLane's `PNR_CORNERS` does this inside the flow (optimise at
  the standard corners, report STA at more). Re-hardening with 1.28 V sign-off cost 7–41 % more energy and up
  to 2.5× more leakage in BCI, because of hold repair against `ff_n40C_1v95`.
- Slacks from a liberty swap ignore the IO delays unless you re-create the constraints from the run's SDC variables.
- Leakage at −40 °C is not comparable with 25 °C numbers (static energy fell about 32× in synaptic_delay), and some
  cells (for example `xnor2_4`) barely change. State the temperature with the number.
- SRAM22 has no 1.28 V liberty: at this corner the macro becomes a black box (section 9.1).

## 6. Timing constraints and sign-off

**6.1 Constraints.**
- One clock; `reset` held for many cycles is the only false path. Every other path is timed, latch paths included.
- A false path removes a path from every check, so keep exceptions to what is provably static.
- Exceptions must match objects. After flattening, flip-flops are named `_12345_` and only nets keep the RTL names,
  so `get_cells -quiet u_sleep/sleeping` (vex2) or `get_cells -quiet -hierarchical *sel_r*` (KWS) match nothing and
  the constraint silently does nothing. Count the objects an exception matches, and fail at zero.
- Any SDC change means hardening again. Removing the latch waiver in NEAT added 53 hold buffers to the SRAM baseline
  and 930 to the alternative baseline (whose cell count rose from 99 631 to 100 556).

**6.2 Sign-off.** Run OpenSTA yourself on the renamed netlist and SPEF (`signoff_sta.tcl`), with the run's own SDC
variables (from `runs/<tag>/resolved.json`), not hand-written constraints. Accept on that timing. In NEAT, OpenLane's
sign-off reported a hold slack of 0.35 ns where the complete parasitics give 0.52 ns; the error can go either way
(in NEAT's flat SRAM design both agree). For a flat netlist with zero SPEF misses, OpenLane's sign-off is acceptable.
- **Which corners.** OpenLane's default `STA_CORNERS` are {nom, min, max} parasitics × {tt_025C_1v80, ss_100C_1v60,
  ff_n40C_1v95} with `TIMING_VIOLATION_CORNERS: "*"`, so BCI's "all 9 corners pass" is the flow default; NEAT signs
  off at the typical corner only. State your policy with the result, and check every corner at which you report
  numbers. (Caravel's own timing sign-off, `make caravel-sta`, uses the same 3 × 3 grid; `cf precheck` checks no
  timing.)

**6.3 Reading latch paths.** OpenSTA checks flip-flop-to-latch paths against the latch's opening edge, without time
borrowing. Those paths showed the smallest setup slack of NEAT's designs, although the latch stays transparent for
half a period.

**6.4 Clock routing at low utilisation.** At low utilisation the router detours clock nets: a BCI core failed hold by
−0.70 ns at 20 %, another needed a 5 ns margin on its controller paths, and a latch write clock had 16 ns latency.
Check clock latency and skew after routing, not only slack.

## 7. Gate-level simulation

**7.1 Icarus with SDF.**
- **Sanitise the SDF** (`sdf_sanitize_for_icarus.py`). Icarus aborts on what it cannot parse. Keep the cell
  `IOPATH`s and:
  - fix the `a::b` triplets and fill empty `()` triplets with 0;
  - rescale a non-ns `(TIMESCALE ...)` to ns, because Icarus up to v13_0 (ours) ignores the header (iverilog #947;
    honoured in master since PR #1501, 2026-09-13), which matters for ASAP7;
  - drop `INTERCONNECT` (wire delays) and `TIMINGCHECK`;
  - turn `(COND ...) (IOPATH ...)` into plain `IOPATH`s (Icarus does not support `COND`, iverilog #949);
  - drop `IOPATH`s on bus bits (a macro's `dout[0]`; Icarus cannot parse them, iverilog #509);
  - drop cells left empty.

  The cell delays still include the load of the wires. Timing checks are not simulated (not implemented in Icarus,
  iverilog #945), so violations show up only in
  STA. Unwrapping `COND` leaves two `IOPATH`s for the same arc on xor2, xnor2, mux2 and mux4 cells (860 of 19 152 cells
  in a BCI core); only one of the two delays is applied, and the sanitiser does not record which.
- **Compile** with `-g2012 -gspecify -Ttyp`, in this order:
  1. `primitives.v`;
  2. `sky130_timing_icarus_fixes.v` (defines the include guards `_TIMING_V` and `_TIMING_PP_V` and a no-op model of
     `lpflow_bleeder_1`, whose PDK timing model references `VPWR` without declaring it; not needed for zero-delay
     runs);
  3. the macro model;
  4. `sky130_fd_sc_hd.v`;
  5. stubs for physical-only cells that the model file lacks (`gen_phys_stubs.py`); `sky130_fd_sc_hd.v` already
     defines `fill_1`, `tapvpwrvgnd_1`, `diode_2` and `decap_4`;
  6. the netlist;
  7. the testbench.

  BCI and vex2 also pass `-ginterconnect`; since the sanitiser drops all `INTERCONNECT` lines it makes no difference.
- **Macros** need a simulation model with the output delay built in for annotated runs (`*_tdout.v`), because their
  bus `IOPATH`s are dropped (vex2 still uses the zero-delay model).
- **Count annotation errors on every run** (`SDF ERROR`, `Unable to match ModPath`) and **fail the run** if there are
  any. NEAT, BCI and vex2 only print or grep part of them today.

**7.2 Activity extraction.**
- **Do not store the waveform.** Dump all levels of the design under test into a FIFO, read by `vcd_toggles`. It
  counts per-signal transitions and high time with the rules of OpenSTA's `read_power_activities -vcd`: the initial
  value does not count, and a change involving x or z counts half. Start the dump at the measurement window.
- **FIFO deadlock.** If the simulation dies before it opens the dump, `vcd_toggles` waits forever: release the FIFO on
  failure (NEAT `gls.sh`). Build `vcd_toggles` once, atomically, before starting parallel runs.
- **Write the net activities after the pin activities.** With annotated delays, Icarus sometimes leaves a cell's
  output-port variable constant while the net it drives toggles: 657 pins in one BCI core, 2 913 in another, costing
  0.53 nJ per bin (about 12 %) when the pin commands won. The net's measured activity must be the last command.
  BCI checks it with `sw/pin_net_consistency10.py`.

**7.3 Testbench and checks.**
- **Compare the gate-level outputs with the RTL outputs** bit for bit over the whole window.
- A missing or empty stimulus must fail: `$readmemh` of a missing file gives an empty stream that "passes".
- Bound every wait (configuration load, clock release, outputs). Count overruns of real-time deadlines.
- **Memories initialised in RTL lose their contents in the flattened netlist** (for example a register file loaded
  from a `.bin`): the flip-flops start at X and poison the datapath. Deposit the initial values (vex2
  `simulation/gen_gls_regfile_init.py`).

**7.4 Capacity, runtime and the alternatives.**
- 5 000 real-time bins of a 100 000-cell design took 4–9.5 h per session including power (NEAT).
- **The community treats Icarus SDF simulation as limited.** caravel-cocotb refuses Icarus for SDF-annotated
  gate-level runs and uses CVC or VCS; Open MPW sign-off used CVC (iverilog #746). Our Icarus flow is a measurement
  tool, validated by the bit-exact comparison and zero annotation errors, not a timing sign-off.
- `$sdf_annotate` is O(cells²) in this Icarus (our observation; no published source): hours at 530 000 cells, and annotation failed outright on 370–600 k
  instance netlists. synaptic_delay's `sim/sdf_fast.patch` (`tools/sdf_fast.vpi`) gives the same toggles much faster.
- **Workaround for very large netlists:** zero-delay simulation of the whole set, multiplied by a glitch factor
  (annotated over zero-delay energy) measured on an annotated subset or a smaller variant. Sampling error was 0.4 % in
  synaptic_delay. sky130 glitch factors: 1.18–1.22 at 5 MHz and 1.13–1.20 at 50 MHz for BCI cores; 1.13–1.93 for
  adder-tree cores (synaptic_delay). State which factor was applied.
- **Verilator** (KWS `sim/run_vsim.sh` with functional models from `liberty2verilog.py`) handles million-cell
  netlists in minutes, but zero-delay only, so glitch power is lost. Use it for functional checks and zero-delay
  activity, combined with a measured glitch factor.

## 8. Power with OpenSTA

**8.1 Activities.**
- Read the liberty files, the renamed netlist and the SPEF.
- Set `set_power_activity -input -activity 0 -duty 0`: OpenSTA's default for unannotated inputs is 0.1 transitions
  per cycle (BCI's rounds 5–7 lacked it; round 10 is clean).
- Then apply the measured per-pin activities, nets last (7.2). Count the pins that were not found, and look at the
  count: NEAT writes the lists but does not check them.
- **OpenSTA version.** OpenLane 2.3.10 builds OpenSTA commit `b5f3a02` (2024-10-02), which reports "2.6.0"; later
  commits carry the same label. In ours, `report_activity_annotation` does not exist (added 2025-01-15; vex2's
  coverage check silently does nothing), `set_clock_sense` is deprecated in favour of `set_sense -type clock`, and
  `read_power_activities` in favour of `read_vcd`.
- `set_power_activity -input` applies to every timing root, including tie-cell outputs (OpenSTA issue #539).
- Without annotation, OpenSTA propagates activity through logic (vectorless); that overestimates (OpenSTA issue
  #333) and models no glitches. Annotate every pin you can.

**8.2 The root clock network is charged at the full clock rate.** Between the clock port and the first clock gate,
OpenSTA takes the activity from the clock definition, whatever the annotation says.
- A design that stops its clock between computations (NEAT: running 0.19–1.06 % of the time) gets most of its
  reported power from there. OpenSTA reported 11.73 µW where the true value is 7.40 µW.
- OpenSTA has no option to set a lower activity on the root clock network (`activity cannot be set on clock ports`);
  the correction below is our own method, not a published one.
- **Correction** (`root_clock_correction.py`): P = P_STA − (1 − d) · P_root, where d is the measured clock duty.
  Buffers and inverters of the root lose internal and switching power; clock gates and other cells clocked directly
  by the root lose internal power only. The walk from the clock port must continue through hold and delay buffers
  (`dly*`). OpenSTA warns "activity cannot be set on clock ports"; that is expected.
- The correction is large: 4.3–7.4 µW in NEAT and 3–4 µW on BCI cores, more than half of OpenSTA's total. Report
  P_STA next to the corrected P.
- A design whose clock keeps running does not need it.
- **Never stop the clock propagation at the clock gates** (`set_clock_sense -stop_propagation` on clock-gate outputs,
  `CLK_STOP_ICG=1`) when the activities come from toggle counts. The annotated activities are per clock cycle, and
  OpenSTA converts them to rates with the clock that reaches each pin. Behind a stopped clock-gate output no clock
  reaches the downstream pins, and our OpenSTA (`b5f3a02`) then leaves the per-cycle activity unscaled, i.e. reads it
  as transitions per second: their internal and switching power become about 10⁻⁹ of the true value (confirmed in the
  source, `Power.cc` `findClkedActivity`). OpenSTA from 2025-01-17 stores densities and no longer has this trap, but
  the stop is still unnecessary. Flip-flops and the clock tree are
  not affected, which is why the total still looks plausible.
  - Evidence (BCI_paper round 6, found 2026-09-23): the same core and toggle file gave a combinational group of
    0.25 µW without the stop and 8·10⁻¹¹ W with it. Every non-sky130 power run of round 5 lost its combinational
    energy (E_bin rose 7–174 % once fixed). A test with VCD-based activity had shown no difference, which is why the
    stop was believed harmless.
  - The loss is not always near total. In vex2 (found 2026-10-24), the combinational group still showed 12.8 % of the
    total, but about 9 600 of 15 700 logic cells with measured activity reported 0 W; only the first logic level
    after a flip-flop kept its power. The running totals are probably 25–55 % low.
  - The stop is not needed. `sky130_fd_sc_hd__dlclkp` (like the GF180, IHP, NanGate45 and ASAP7 clock gates) carries
    `clock_gating_integrated_cell` in its liberty, so OpenSTA handles the gated subtrees itself; the NEAT flow uses
    no stop. Measured per-pin activities on the gated tree override OpenSTA's own estimate for it (whose formula
    overcounts in our version; OpenROAD's OpenSTA PR #425, 2026-10).
  - Check: the combinational group must be a plausible share of the dynamic power. NEAT's cores show 24–52 % before
    and 61–76 % after the root-clock correction; a share near 0 %, or many active logic cells at 0 W in the
    per-instance report, means the activities were lost.

**8.3 Black boxes.** Only physical cells may become black boxes. A macro without its liberty is a black box with zero
power, and scripts that read a liberty "if the file exists" hide that (vex2 and BCI still do). In the `ms` and `hs`
libraries even the antenna diode has no liberty (section 9.4).

**8.4 SPEF.** Zero `spef line N, net/instance ... not found` warnings (section 5.4).

**8.5 Report the energy, not only the power.** Window average power, energy per inference or bin, and a breakdown by
cell class (logic, clock tree, flip-flops, latches, hold cells, repair buffers, macros, leakage) find the cause of a
surprise quickly. Record the clock period actually used in the result file, not a default from a comment.

**8.6 Reuse a simulation only for identical inputs.** Stamp it with a hash of the netlist, SDF, SPEF, stimulus and
configuration image, leaving out the `*DATE` and `(DATE ...)` header lines, which change on every run.

**8.7 A global (median) activity is not a cross-check.** vex2's older flow applied one median activity to every data
net. Its total agreed with the per-pin flow "within 5 %" only because errors cancelled (combinational 0.58 against
1.62 mW, macro 1.52 against 0.22 mW). Compare per-group breakdowns, not totals.

**8.8 State what a power number assumes.** Besides the activity source:
- the SPEF corner (nom, min or max parasitics) used for power;
- the output load and driving cell of the ports (the PDK sets `OUTPUT_CAP_LOAD` 33.4 fF), or that they were zeroed;
- the single liberty corner of leakage (no process spread, no self-heating, no IR drop);
- the simulator and delay model behind any glitch power: glitch counts depend on how the simulator filters pulses
  (inertial or transport), and Icarus differs from commercial tools.

## 9. Special cases

### 9.1 The SRAM22 macro (`sram22_2048x32m8w8`)

- **Energy counted twice.** The as-generated liberty lists every internal energy once per supply pin and once per
  ground pin, and OpenSTA sums them (474 against 945 µW in BCI; confirmed in the OpenSTA source, which normalises per
  `related_pg_pin` and then adds them; still so in the upstream liberty, no upstream issue yet). Use the supply-only copy
  `sram22_2048x32m8w8_tt_025C_1v80_pwr.lib` for power, and the as-generated one for timing.
- **Read energy weighted with the wrong probability.** The clock-pin internal energy is split by
  `when : "we&ce"`, `"we&!ce"`, `"!we&ce"` (read) and `"!we&!ce"` (`ce&rstb` is the *leakage* condition), and OpenSTA
  weights each with the time-averaged duties of `we` and `ce`. With a gated or stopped macro clock, `ce` is high at
  almost every clock edge but low on average, so each access is counted with a weight close to the clock duty: read
  energy too low by about 1/duty.
  - Fix (`macro_state_correction.py`): duty_cond = (duty − v_idle (1 − d_clk)) / d_clk, where d_clk is the fraction
    of cycles with a macro clock edge and v_idle the pin's value while the clock is stopped. Compare the six-decimal
    duties of the activity file with a tolerance.
  - Effect: +0.27 to 0.58 µW of 7–9 µW in NEAT; +4.95 µW of 76.4 µW (+6.5 %) in BCI's dense SRAM core. In the
    VexRiscv SoC the macros' share was 1.7 % instead of about 12 %.
- **Layout views.** The GDS needs a `prBoundary` (235/4) on its top cell (LibreLane's Magic step needs it; sram22
  issue #504, declined upstream), and the LEF `OBS` must be on met1 only, so
  that the grid can reach the met2 supply pins. Fixed views are in `/media/amir/NEAT_Competition/flow/macros/` (and
  in vex2's old `skywater/` clone; its current checkout lacks the GDS).
- **Power grid.** `pdn_cfg_sram22.tcl` must end with `add_pdn_connect -grid macro -layers "met2 met4"`, together with
  `PDN_MACRO_CONNECTIONS: <inst> VPWR VGND vdd vss`. That gives zero power-grid violations (NEAT). Without it, the
  macro's supply pins stay unconnected: BCI's SRAM cores (`met3 met4` + `met2 met3`) have 268 602 violations and vex2
  about 547 000, hidden by `ERROR_ON_PDN_VIOLATIONS: false`. Power from OpenSTA is not affected, but the layouts fail
  5.2.
- Put the timing liberty in `MACROS` so that paths through the macro are timed.
- **Simulation:** use the functional model for zero-delay runs and the `_tdout` model, with its output delay, for
  annotated runs.
- **Slew limits.** The macro liberties before 2026-09-09 set a default maximum transition of 0.04 ns (sram22 issue
  #512; fixed upstream in sram22_sky130_macros PR #13, now 0.351 ns). Our copies are the old ones; pin the commit you
  use. The old value which the data outputs' own slew
  (0.5–0.9 ns) violates. Do not gate acceptance on max-slew at the data outputs. The **clock pin** limit (0.35 ns) is
  different: a slew of 1.2 ns (NEAT) or 1.7–2.0 ns (vex2, driven directly by a `dlclkp_2`) is a real
  violation. Buffer the macro clock.
- **Corners.** Liberties exist for tt 1.8 V 25 °C, ss 1.6 V 100 °C and ff 1.95 V −40 °C only; at any other corner
  (for example `ss_n40C_1v28`, `tt_100C`) the macro becomes a black box.
- **Leakage:** 2.34 µW per instance at tt, however few words are used. A read costs about 15 pJ, a write about 10 pJ,
  an idle clock edge about 1.15 pJ.

### 9.2 Latch memories

Several designs keep weights in latch rows: a staging register in front, one clock gate per row, and the gate opening
one cycle after the last word.
- **Do not waive latch paths in the SDC.** A blanket `set_false_path -from` latches plus a hold waiver at the latch
  data pins hides every latch timing problem, including those of a design that writes latches while it computes.
  NEAT now times all of them; both examples met timing, with 53 and 930 more hold buffers. BCI's latch and
  register-file cores, KWS and synaptic_delay still waive them (their files in `flow_notes/projects/` list where).
- **Hold buffers at latch inputs** cost area and power in large latch memories. Measure them.
- **Gate latch rows with `dlclkp` instantiated directly** (glitch-free enable, plain name, recognised by the root-clock
  correction).
- **Gate-level simulation does not check latch timing** (timing checks are dropped). STA and the bit-exact comparison
  with the RTL are the only safeguards. A waiver justified by a protocol argument cannot be checked by simulation.
- **Leakage.** Latches leak continuously: 83 000 of 150 000 cells in one all-latch core. Use decap-free fill if latch
  leakage is to be reported.
- **Clock stop.** Latches keep their contents while the clock is stopped, but the write pipeline must drain first: the
  testbench waits, with a bound, for `clk_req` to fall after the last configuration word.

### 9.3 Other PDKs

- **GF180 Icarus models.** The models in `/media/pdk/icarus_sdf_models/` declare edge-sensitive XOR/XNOR paths
  (`(posedge A1 => (ZN:A1))`) and conditional MUX paths, while the SDF has plain `IOPATH A1 ZN`. Every such cell keeps
  a placeholder delay of 1.0 ns: 2 144–5 530 `Unable to match ModPath` errors per run in BCI, about 6 % of the cells.
  Fix the models or the sanitiser before using GF180 annotated numbers. GF180 `primitives.v` has no timescale, so
  compile a timescale file first, and initialise `reg notifier`.
- **IHP.** `delayed_*` nets float without timing checks, and ABC's `Q|~Q` reset stays X. Decaps were 94 % of the
  leakage.
- **IHP and ASAP7 have state-dependent clock-pin internal power**, so duties must be conditioned on the clock enable
  as for SRAM22 (+27 % on IHP, BCI round 10).
- **ORFS (ASAP7, NanGate45)** writes the same slash names as OpenLane (section 5.4), and its adder techmap gives
  non-equivalent netlists. ASAP7 has its own notes: `/media/amir/flow_notes/ASAP7_flow_notes.md` (section 9.2 there covers the
  clock-propagation stop of section 8.2 here).
- **Check annotation and SPEF matching per PDK.** A flow that is clean on sky130 is not automatically clean elsewhere.

### 9.4 Other sky130 standard-cell libraries

- **`sky130_fd_sc_ms` has no leakage data.** All 376 cells have `cell_leakage_power : 0` and no `leakage_power`
  groups, so a design in `ms` reports leakage for its macros only, and OpenLane reports `power__leakage__total: 0`
  (vex2). Its decaps have no leakage either, so 5.1's decap advice changes nothing there. Leakage of an `ms` design
  needs another library or SPICE; say so with the number. (Our observation in the PDK files; no published source.) `hd`, `hdll` and `hs` have per-cell leakage; `ls` has
  state-dependent groups.
- **`ms` and `hs` have no `diode_2` liberty** (skywater-pdk issue #358, open), so antenna diodes become black boxes (14 506 in vex2) and their pin
  capacitance is missing from switching power.

## 10. Checklist for every measurement

| check | expect |
|---|---|
| the job ran through `jobq` with a realistic `--mem` | yes |
| escaped names (`\` with `.` or `/`) in the synthesis netlist | 0, or renaming (5.4) planned |
| `SDF ERROR` / `Unable to match ModPath` lines in the simulator log | 0, and the run fails otherwise |
| `spef line N, net/instance ... not found` in every OpenSTA log (sign-off and power) | 0 |
| `Creating black box` in the OpenSTA logs | physical cells only (tap, fill, decap, diode) |
| every macro liberty read, at the analysed corner | yes |
| standard-cell leakage in the liberty | non-zero (not `sky130_fd_sc_ms`) |
| every SDC exception matched at least one object | yes |
| latches and flip-flops after synthesis | the numbers the RTL declares |
| routing DRC errors, power-grid violations | 0, 0 |
| setup and hold at the sign-off corners, with every net's parasitics | met |
| gate-level outputs against RTL outputs | bit-exact over the whole window |
| testbench stimulus | non-empty, every bin or sample accounted for |
| annotated pins not found | 0, or listed and explained |
| pin and net activities of the same net | consistent (net written last) |
| clock duty d used for the root-clock correction | the measured one (clock cycles × period / window) |
| `set_clock_sense -stop_propagation` / `CLK_STOP_ICG` in the power script | absent |
| combinational group of the power report | a plausible share of the dynamic power, not near 0 %; no active logic cells at 0 W |
| a reference design hardened and measured twice | the same number to the last digit |

## 11. Reproducibility of the numbers (and of trained networks)

- **Pin versions:** OpenLane commit, PDK commit, OSS CAD Suite release, Python packages (numpy 1.26.4, torch 2.2.2).
  Write the tool versions into every result file (`harden.json`, `measure.json`; NEAT's `measure.json` records only
  the Icarus version so far).
- **Measure with a script that a second person can rerun**, and keep its outputs together with the commit of the
  scripts that produced them. Results that depend on an untracked clone (vex2's `skywater/`) are not reproducible.
- **Content-hash results for reuse** (section 8.6); never reuse across a change of netlist, SDF, SPEF or stimulus.
- **For hardware that runs a trained network:**
  - Make training deterministic: fixed seeds, deterministic library settings.
  - Compute statistics in float64; numpy float32 reductions depend on the memory alignment of the array.
  - Train at state widths where nothing saturates, check that the integer model reproduces the trained model
    exactly, and evaluate the circuit's own (saturating) widths with the integer model.
  - Report the spread over at least ten seeds: three seeds suggested a standard deviation of 0.017, ten gave 0.0095.
- **When a measurement surprises you, explain it before publishing it.** Every error in this file was found by asking
  why a number looked odd.

## 12. Not covered: tapeout

These notes describe a measurement flow. A tapeout (sparkrv_tapeout plans one on a ChipFoundry shuttle) needs, at
least, and none of it is set up or verified on this machine yet:
- LibreLane (the OpenLane successor named in OpenLane 2.3.10's own README) and the shuttle's `cf` tools
  (`pip install cf-precheck`; `cf init`, `cf setup`, `cf gpio-config`, which is required before precheck); none is
  installed under `/media/hardware_design_tools`;
- what `cf precheck` checks: XOR against the golden wrapper, top-cell name, metal density, KLayout FEOL/BEOL/off-grid/
  zero-area, spike, illegal cell names, OEB (with the CVC electrical checker), power grid and LVS; Magic DRC is
  optional, and **timing is not checked**;
- RTL and gate-level full-chip simulation of the wrapper, with the wrapper's pin order matching the template;
- physical sign-off: Magic and KLayout DRC, netgen LVS, antenna check and repair, density fill, decaps, IR drop;
- multi-corner sign-off (9 corners), which conflicts with SRAM22's three liberties (9.1) and needs a stated policy;
- harness integration (Caravel `user_project_wrapper` or OpenFrame): power pins, GPIO and OEB defaults, pad timing,
  gate-level simulation with pad models;
- macro-first hierarchical hardening (tiles, many-macro power grid, halos, hold and skew at SRAM pins);
- SRAM22 for tapeout: DRC waivers for the macro internals, a justification for the data-output slew waiver, the
  `prBoundary` and `OBS` fixes checked against the precheck;
- min/max SDF gate-level simulation at the sign-off corners;
- shuttle-specific PDK, LibreLane and precheck versions, separate from the measurement flow's pins.

When a project builds this, add a tapeout section here (or a separate notes file) with what was verified.
