# SkyWater 130 nm flow notes: synthesis, hardening, gate-level simulation and power

**Version 5.4, last updated 2026-10-24.** The full history is in "Version history" below.

Read this before you synthesise, harden or measure anything on sky130 on this machine. It is written for engineers
and AI agents. Everything here was learned the hard way, in several research designs measured on this machine:
real-time neural decoders with latch, register-file and SRAM memories, a RISC-V SoC with SRAM macros, and adder-tree
SNN cores. Most of the problems below fail **silently**: the flow runs to the end and prints a plausible number that
is wrong. Section 10 is the checklist every measurement must pass. ASAP7 has its own notes: `ASAP7_flow_notes.md` in
this folder.

These notes are for **measuring** power, energy, area and timing. They do not describe a tapeout flow (section 12).

**Measurement or tapeout: which rules apply.** The rules here are of two kinds.
- **Correctness of the number** (always required): the layout must be legal and meet setup and hold at the sign-off
  corners with full parasitics, the simulation must match the RTL, and the power analysis must see every cell, net
  and activity. A layout with hold violations describes a chip that would not work, and the hold buffers a working
  chip needs are part of its power.
- **Robustness for silicon** (optional for a measurement-only project): margins and steps beyond what sign-off
  requires, such as hold or setup overfix margins, antenna repair, density fill, decaps and IR-drop margins. They
  cost area and power that a measurement should not include unless the design will be taped out. If you skip them,
  say so with the numbers; if you tape out, apply them (section 12).

**Announcements.** Changes that every user must act on (new default tool or PDK versions, changed rules) are
broadcast in `/media/amir/flow_notes/ANNOUNCEMENTS.md`. Read it at the start of every measurement campaign. Keeping
your project in step with the notes and the announcements is your responsibility.

**How this file is kept current.** Only the maintainer (the general agent of `/media/amir`) edits the files in
`flow_notes`. Do not edit them. When you find a new pitfall, a mistake here, a better fix or a measured effect, leave
a note in `/media/amir/flow_notes/inbox/` (one file per finding; see the inbox README). The maintainer reads the
inbox, updates the notes (version bump, history row), announces what others must act on, and deletes the note.

**Is my copy current?** Record the version you read in your project's notes. At the start of the next session,
compare it with the line under the title. If the version has changed, read the history rows since your version.

**Upstream.** The tools and PDKs change quickly. The maintainer reviews upstream every month (`UPSTREAM.md`) and
updates these rules when upstream fixes a bug that one of them works around. Do not install or upgrade tools or PDKs
yourself.

### Version history

| version | date | change |
|---|---|---|
| 1.0 | 2026-10-24 | first version, from the most thoroughly verified flow on this machine plus audits of the others |
| 1.1 | 2026-10-24 | 8.2: stopping clock propagation at the clock gates is wrong (combinational power disappears with toggle-count activities) |
| 2.0 | 2026-10-24 | section 0 rewritten: all heavy jobs go through the shared `jobq` queue. Corrected SRAM22 clock-pin conditions, clock duty and combinational-share ranges, hold-buffer counts, memory figures. New: low-voltage corners, measurement-only settings, decaps and endcaps, `sky130_fd_sc_ms` without leakage, clock-gate fan-out and SRAM clock slew, Icarus capacity and Verilator, pin/net activity order, register initialisation, five checklist lines |
| 2.1 | 2026-10-24 | rules checked against tool sources, documentation and issue trackers; sources added; version-specific behaviour of OpenSTA and Icarus; SRAM22 slew limit fixed upstream; 8.8 what a power number must state; precheck contents |
| 3.0 | 2026-10-24 | only the maintainer edits the notes; findings go to `inbox/` |
| 4.0 | 2026-10-24 | the notes are general: no references to individual projects. Reference tools now live in `flow_notes/tools/` (section 2); fixed SRAM22 views in `/media/pdk` (9.1); broadcast announcements in `ANNOUNCEMENTS.md` |
| 5.0 | 2026-10-24 | **new default versions** (section 1): LibreLane 3.0.16 with open_pdks `8afc834`, OSS CAD Suite 2026-10-24; OpenLane 2 kept for earlier numbers, never with the new PDK; validation results |
| 5.1 | 2026-10-24 | header: which rules are correctness (always) and which are silicon robustness (optional when not taping out); 5.1: default hold margins for measurement-only projects instead of a 0.5 ns overfix |
| 5.2 | 2026-10-25 | from the inbox: timing derating was off in every OpenLane 2 run on sky130 (6.1); OpenSTA 2.7 reads SPEF with escaped names (5.4, checked); `check_annotation.py` fails a run on lost activities (8.1, section 10); pin versions in scripts (1); reference flow now on the default versions (2) |
| 5.3 | 2026-10-25 | the queue's guide for agents is now `/media/amir/.jobq/AGENTS.md` (section 0) |
| 5.4 | 2026-10-28 | from the inbox: hardening policy and `tools/harden_ladder.sh` (5.3); routability can drop with LibreLane, `PL_TIMING_DRIVEN` (1, 5.7); unmapped-cell check with kept parametrised modules (1); `CTS_APPLY_NDR: none` and zero setup margins for latch memories (5.1); exception names in LibreLane and ORFS (6.1); sanitiser drops zero-filled conditional repeats (7.1); Verilator VCD scope and an annotated-pin check (7.4, 10) |

Contents:
0. Ground rules on this machine
1. Tools and paths
2. Reference tools
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
  `/media/amir/.jobq/AGENTS.md`). "Heavy" means longer than a few minutes, more than about 2 GB of RAM, more than 2
  threads, or the GPU. Never start such a job with `&` or `nohup`.
  - `jobq add --name N --threads T --mem <peak GB> [--gpu MB] [--stall-min N] -- 'command'`; then
    `jobq status | log N | wait N | cancel N`. Use `--high` only when the owner asks for it.
  - **Declare a realistic peak memory.** A job starts only when `--mem` + 3 GB is free; its RAM is capped at
    max(1.4 × mem, mem + 4) GB and it swaps above that. Only queue jobs may swap; anything outside the queue is
    OOM-killed instead.
  - **Pass the thread count on.** The job gets `JOBQ_THREADS`; give it to `ROUTING_CORES`, `-j`, `NUM_CORES`.
  - The queue runs jobs at `nice 19`, idle I/O priority and the lowest CPU weight, and its watchdog kills leftover
    processes and stalled jobs. Do not pin jobs to fixed CPUs (`taskset`): concurrent queue jobs would pile onto the
    same cores.
  - If the daemon is down, tell the owner; do not start jobs outside the queue. Never cancel other people's jobs.
- **Memory figures for declaring `--mem`.**
  - Icarus compilation of a 100 000-cell SDF-annotated netlist: about 10 GB. Six at once triggered the out-of-memory
    killer, which killed a compilation and system processes of other users.
  - OpenROAD detailed routing: 10–15 GB for 100 000-cell cores; above 20 GB for a 155 000-latch core, which then
    failed.
  - OpenROAD repair at a low-voltage corner: 40–45 GB (section 5.7).
- **Nix builds run outside the queue.** A `nix develop` that has to compile tools runs in the Nix daemon, not in your
  job; the daemon is capped at 2 builds × 4 cores. Tool installation is the maintainer's job.
- **Never edit a running bash script in place.** Bash reads scripts incrementally, so editing one mid-run corrupts
  the run. Write a new file and `mv` it over the old one.
- **OpenLane runs under `nix develop` with many child processes.** If you must stop one, signal its process group
  (`kill -TERM -- -PGID`), not single processes.
- **For AI agents.**
  - `pkill -f` or `pgrep -f` patterns that also match your own command line kill your own shell. Look up the process
    IDs first, then signal them by number.
  - A deletion through a shell variable (`rm -rf $DIR/...`) is blocked by the safety check; write `"${DIR:?}"`.
  - Never send a simulator's or tool's stderr to `/dev/null`: it hides compile errors.
- **Ask before decisions.** The owner wants design choices, rule choices and anything destructive discussed first.

## 1. Tools and paths

These are the installed default versions (since 2026-10-24, validated on the reference design in
`validation/`). `ANNOUNCEMENTS.md` says when they change.

| what | where / version | how to call |
|---|---|---|
| LibreLane (successor of OpenLane 2) | 3.0.16, `/media/hardware_design_tools/librelane` (→ `librelane-3.0.16`), Nix flake: OpenROAD `dcf3613`, OpenSTA 2.7.0 (`857316f`), Yosys 0.62, KLayout 0.30.7, Magic 8.3.623 | `nix --extra-experimental-features "nix-command flakes" develop --accept-flake-config /media/hardware_design_tools/librelane -c python3 -m librelane --pdk-root /media/pdk/sky130_8afc834 --pdk sky130A --manual-pdk --run-tag TAG --overwrite [--to OpenROAD.STAPostPNR] config.yaml` |
| PDK for LibreLane | open_pdks `8afc8346a57fe1ab7934ba5a6056ea8b43078e71` (the version LibreLane 3.0.16 is validated with), `PDK_ROOT=/media/pdk/sky130_8afc834` (sky130A, sky130B) | |
| OpenSTA | inside the LibreLane Nix shell | `nix ... develop ... /media/hardware_design_tools/librelane -c sta -no_splash -exit script.tcl` |
| Icarus Verilog, Yosys, Verilator | OSS CAD Suite 2026-10-24, `/media/hardware_design_tools/oss-cad-suite` (→ `oss-cad-suite-2026-10-24`): Icarus 14.0 devel s20260301-664, Yosys 0.70+219, Verilator 5.053 devel | add its `bin/` to `PATH` |
| Nix | `/nix/var/nix/profiles/default` | `source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh` |
| fixed SRAM22 views | `/media/pdk/sram22_sky130_fixed-de0a9a7/` (section 9.1) | |
| other PDKs | `/media/pdk`: gf180mcuA–D, ihp-sg13g2, asap7, nangate45 | |
| OpenROAD-flow-scripts (ASAP7) | see the ASAP7 notes | |
| Icarus models with SDF paths for other PDKs | `/media/pdk/icarus_sdf_models/` | see section 9.3 before trusting them |
| reference tools | `/media/amir/flow_notes/tools/` (section 2) | |
| shared job queue | `/media/amir/.jobq` (guide for agents: `AGENTS.md`) | `jobq`, section 0 |

**Previous versions, kept for reproducing earlier numbers** (do not start new work with them):

| what | where / version |
|---|---|
| OpenLane 2 | 2.3.10, `/media/hardware_design_tools/openlane2` (`a7b0e6d`): OpenROAD `edf00dff`, OpenSTA `b5f3a02` ("2.6.0"), Yosys 0.46; `python3 -m openlane` |
| PDK for OpenLane 2 | `/media/pdk/sky130A`, `sky130B` (open_pdks `c6d73a35`, volare) |
| OSS CAD Suite | 2024-08-07, `/media/hardware_design_tools/oss-cad-suite-2024-08-07` (Icarus 13.0 devel s20221226-533, Yosys 0.44+1) |

- **Pin your versions in your scripts.** The generic paths (`/media/hardware_design_tools/oss-cad-suite`,
  `/media/hardware_design_tools/librelane`, `/media/pdk/sky130_8afc834`) follow the defaults and change with an
  announcement. A project that must keep its versions (for example during a paper) names the dated or versioned
  directory (`oss-cad-suite-2026-10-24`, `librelane-3.0.16`), and its scripts check `iverilog -V` and the PDK's
  `$PDK_ROOT/sky130A/SOURCES` against the pinned build and warn or stop on a mismatch (which also catches a mix of
  OpenLane 2 with the new PDK).
- **Do not combine OpenLane 2 with the new PDK.** Hardening works, but OpenLane 2's OpenSTA (`b5f3a02`) crashes
  (segmentation fault) in the SRAM22-conditioned power analysis on SPEF extracted with the new PDK, every time. Use
  OpenLane 2 only with `/media/pdk/sky130A`, and LibreLane with `/media/pdk/sky130_8afc834`.
- **Moving from OpenLane 2 to LibreLane** changes the numbers. On the reference design (validation, 2026-10-24): 14 %
  more cells (Yosys 0.62), a larger root clock tree (10 instead of 4 buffers), dynamic power +25 %, total power +0.9 %
  (an SRAM-leakage-dominated design); SDF errors, SPEF misses and timing stay clean. Never mix versions within one set
  of compared numbers; re-measure the baseline with the new versions.
- **The routable utilisation can drop with LibreLane.** A flat 28 000-cell adder-tree core that routed at 40 % with
  OpenLane 2 (global-routing overflow 10 506, detailed routing converged in 14 iterations) had 3.3× the overflow with
  LibreLane and never converged at 40 % (violations rising to 200 000); it routed at 30 %. Harden every design again
  with the ladder of 5.3. Timing-driven placement is now `PL_TIMING_DRIVEN` (the old `PL_TIME_DRIVEN` is a deprecated
  alias) and defaults to false; turning it on made OpenROAD `dcf3613` crash (segmentation fault in
  `rsz::Rebuffer::fullyRebuffer`) in global placement on that design.
- **Kept parametrised modules stop LibreLane after synthesis** with "N Unmapped Yosys instances found": its checker
  counts every `$`-named cell type, and kept sub-modules of a parametrised module are named `$paramod\...`, so each
  instance counts as unmapped. Set `ERROR_ON_UNMAPPED_CELLS: false` and count the real unmapped cells yourself:
  `tools/check_metrics.py --synth-stat <run>/…/reports/stat.json` counts the `$` cell types that are not module names.
- **OpenSTA 2.7** stores activities as densities: the clock-stop trap of section 8.2 does not occur, `-activity` per
  cycle is converted with the fastest clock (keep one clock, or use `-density`), and `report_activity_annotation`
  exists.

Folders that were moved keep absolute symlinks to old locations, and many scripts still name
`/home/yousefzadeha/workspace/...`, which no longer exists. Check links with `find -xtype l` and grep for the old
path: a broken link to a liberty file makes a macro silently disappear from the power analysis.

## 2. Reference tools

`/media/amir/flow_notes/tools/` holds maintained copies of the tools these notes refer to; `tools/README.md` lists
them. Copy them into your project and record the `flow_notes` commit you copied from (copies drift: two copies of
the toggle counter on this machine already differ). `tools/reference_flow/` is a complete flow taken from the most
thoroughly verified design on this machine (hardening, sign-off, gate-level simulation, power, one-session
measurement; it reproduces the same power to the last digit). Its variable and file names come from that design:
adapt them. It runs on the default versions (LibreLane 3.0.16), fails a run on any SDF annotation error or lost
activity (`check_annotation.py`, 8.1), records OpenSTA's group totals, and pins no CPUs under `jobq`. Running several
sessions in one queue job, declare the memory of all their Icarus compilations together.

## 3. RTL rules for a design you want to measure

- **Gate clocks with the library integrated clock gate, instantiated directly.** Use `sky130_fd_sc_hd__dlclkp_*`,
  behind a define for synthesis, with a behavioural model for RTL simulation.
  - A clock gated with ordinary logic glitches.
  - The root-clock correction recognises clock gates by cell name: `tools/root_clock_correction.py` knows `dlclkp`
    only; `tools/root_clock_correction_multipdk.py` also the other PDKs' clock gates.
  - A gate inside a wrapper module gets an escaped name (`\u_x_icg.u_icg`) that Icarus cannot annotate unless you
    rename (section 5.4); a wrapper of this kind caused the only SDF errors of an otherwise clean SoC.
- **Mind the clock-gate fan-out.** An ICG driving about 80 spread-out sinks got no leaf buffers from CTS: 1.4–2 ns slew
  and hold failures. Group about 300 or more sinks per gate. An ICG driving an SRAM22 clock pin directly gave 1.5–2 ns
  slew against a 0.35 ns limit (section 9.1).
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

- Run synthesis alone first (OpenLane `--to Yosys.Synthesis`). It takes minutes, and gives a cell count and area for
  sizing the floorplan.
- Synthesis-only code goes behind a define in `VERILOG_DEFINES`.
- After synthesis, compare the flip-flop and latch counts with the RTL.
- **Count the escaped names in the synthesis netlist** (identifiers starting with `\` that contain `.` or `/`). It is a
  cheap early warning for section 5.4; kept-hierarchy designs had 875–3 851 already after synthesis.
- Synthesis is deterministic. Comment-only RTL changes give a byte-identical netlist, which is a cheap way to prove
  that an edit does not invalidate earlier measurements.
- Yosys/ABC area from a synthesis-only probe is cell area only, untimed and without utilisation; do not compare it
  with OpenLane areas.

## 5. Hardening with OpenLane 2

**5.1 Settings** (`tools/reference_flow/config.template.yaml`). These are **measurement** settings: the flow stops
after sign-off timing (`--to OpenROAD.STAPostPNR`), so "DRC-clean" means the detailed router's DRC only, with no Magic
or KLayout DRC, no LVS and no antenna repair. A layout for tapeout needs the opposite of several of them (section 12).

| setting | value | why |
|---|---|---|
| `DECAP_CELL: []` | decap-free fill | Decap cells leak: 0.26 µW of a 1.87 µW measurement in one design, 53–81 % of the leakage in others, and 2.1–3.8 µW of 2.9–4.9 µW in register-file and latch cores (energy per bin 27.3 → 12.1 nJ and 21.9 → 7.8 nJ without them). Report the logic's leakage, not the fill's (our measurements; no published source compares them). To fix an existing run, rerun from `OpenROAD.FillInsertion` with `DECAP_CELL: []` and reuse the toggles. |
| `ENDCAP_CELL` | `decap_3` (hd default; `ms` and `hs` use `decap_4`) | Endcaps remain decaps even with `DECAP_CELL: []`: 1 200–1 850 cells, about 4–6 nW. Negligible, but "decap-free" is not literal. |
| `RUN_HEURISTIC_DIODE_INSERTION: false`, `DIODE_ON_PORTS: in` | | Heuristic insertion is off by default in OpenLane 2; keep it off, it broke legalisation at high utilisation. `DIODE_ON_PORTS` defaults to `none`. |
| `RUN_ANTENNA_REPAIR: false` | | Antenna violations are reported, not gated. Measurement only. |
| hold slack margins | the defaults (0.1 ns at placement, 0.05 ns at global routing) for a measurement-only project | Hold must be met at every sign-off corner with full parasitics (6.2); a margin above that is silicon insurance, not correctness. A 0.5 ns overfix cost about 0.6 µW (8 %) in a 7–9 µW design. With a small margin, the final hold check may fail and need a re-hardening; that is the trade-off. Choose and document the margin. |
| `*_HOLD_MAX_BUFFER_PCT` | 80 (default 50) | Hold buffers are numerous: 15 % of the cells in one design. OpenLane reports them as `design__instance__count__hold_buffer`. |
| `GRT_ALLOW_CONGESTION` | true (default false) | A congested design reaches detailed routing, where the watchdog (5.3) judges it. Measurement only; false for tapeout. |
| `CTS_APPLY_NDR` | `none` for designs with many gated clock nets (LibreLane default `half`) | With the default 2×-spacing rule on the upper clock nets, LibreLane 3.0.16's global router aborted with `GRT-0228/0229` ("edge usage exceeds the maximum allowed") on a core with 3 743 gated clock nets, at 50, 30 and 20 % utilisation; `GRT_ALLOW_CONGESTION` does not cover it (OpenROAD issue #11653; fixed by PR #11754, not in our version). OpenLane 2 applied no clock NDR, so `none` also keeps results comparable. |
| `PL_RESIZER_SETUP_SLACK_MARGIN`, `GRT_RESIZER_SETUP_SLACK_MARGIN` | 0 for latch memories timed without waivers (defaults 0.05 and 0.025 ns) | Latches borrow time and report a setup slack of exactly 0; with a positive margin every weight latch is a "violation" that no move can improve, and `repair_timing` looped 80 000 times in an hour without changing anything. Sign-off still requires slack ≥ 0. |
| utilisation / density | density = utilisation + 10 %, at most 95 % | This equals OpenLane's default (utilisation + 5 × cell padding + 10, with padding 0 on sky130); with the cell padding of 2 used for SRAM22 floorplans (5.5) the default would be +20. A large ROM core closed at 20 % and not at 30 %; the same netlist at 30 % and 20 % differed by 7 % in power. Small logic cores route at 60 %; latch and register-file cores only at 20–30 % (seven 60 % attempts were hopeless after 7 h). |

**5.2 Accept a run only when all of these hold:**
- the detailed router's DRC count is 0;
- setup and hold are met at the sign-off corners, with every net's parasitics (section 6.2);
- the power grid has no violation (section 9.1);
- sign-off timing had no unmatched SPEF entries;
- the cell count is within any cap (tap cells excluded, since they grow with the core area).

`tools/check_metrics.py` implements this. OpenLane reports `design__instance__count__stdcell` including taps and
excluding fill.

**5.3 Hardening policy and watchdog.** Detailed routing can run for days without converging: one hardening started by
hand ran 2.8 days before anyone noticed.
- **Never start a hardening by hand.** Run every hardening, one-off experiments included, through a script under
  `jobq` with the routing watchdog active.
- **Watchdog:** stop the run when the violation count stays high (more than 500 000 after 3 iterations, 20 000 after
  6, 3 000 after 10), when no iteration finishes for 12 h, or after 36 h in total. Stop it by its process group
  (start it with `setsid`, signal the group): `pkill -P` misses the grandchildren under `nix develop`.
- **Utilisation ladder:** try utilisations from dense to sparse and accept the first attempt that passes 5.2. State
  the steps, and report the accepted utilisation with every energy number, since utilisation changes wire length and
  power.
- **Log every attempt**, accepted or rejected, with its reason and run time.
- **In a comparison, harden every design under the same rule**; do not tune utilisation per design by hand.
- `tools/harden_ladder.sh <config> <work dir> "50 40 30 20"` does all of this for any LibreLane configuration (with an
  optional own sign-off, `SIGNOFF_CMD`); `tools/reference_flow/harden.sh` does the same for the reference design.

**5.4 Escaped hierarchical names: the costliest silent error.** Kept hierarchy and generate blocks appear in the routed
netlist as `\u_rom.u_col_0/_307_`, `\g_ws[9].u_icg` or `\u_demux/_000_`.
- **Icarus SDF annotation** splits the instance name at the dot, logs `SDF ERROR: ... Cannot find X in scope`, and
  simulates the cell without its delays. The activity then misses glitches. Rewriting the SDF name as a Verilog
  escaped name does not help.
- **OpenSTA SPEF reading (OpenLane 2 only).** In OpenLane 2's OpenSTA (`b5f3a02`), `*DIVIDER /` makes every slash a
  hierarchy divider, so the net is not found and loses its parasitics; OpenROAD writes three spellings: `a\.b\/c`,
  `a\.b/c` and the bare `a/c`. OpenLane 2's own sign-off (`OpenROAD.STAPostPNR`) loses the same parasitics.
  **The default OpenSTA 2.7 (LibreLane 3.0.16) reads these SPEFs correctly:** on the same 100 000-cell design it
  reported 0 missing nets where `b5f3a02` reported 803 760 (checked 2026-10-25). It still warns
  `net ... not found` for nets that really are missing, so the zero-warning check stays valid. LibreLane's own
  `STAPostPNR` on a kept-hierarchy design has not been compared with an own sign-off yet.
- **Effect:** 40 184 SDF errors and 803 757 unmatched SPEF entries in a 100 000-cell decoder; its average power rose
  from 7.00 to 8.18 µW (+17 %) once both were fixed. A kept-hierarchy ASAP7 design in ORFS lost 4.87 million SPEF
  entries.
- **Known upstream:** OpenROAD issues #3218 and #3211 (closed as stale; the maintainers
  blame the SPEF writer's escaping), #6339, PR #8772 (Nov 2025, partial fix) and the open #11839 (Oct 2026, 431 k
  "net not found" on OpenTitan). `read_spef` inside OpenROAD on the same database does not show it; the stand-alone
  `sta` does. `set_hierarchy_separator` is not a fix. LibreLane's `SYNTH_HIERARCHY_MODE: keep` has an open bug
  (librelane #1020).
- **Fix:** `tools/legal_names.py` renames every escaped identifier to a plain one, the same way in netlist, SDF and
  SPEF. Simulate, time and analyse power on the renamed copies. With the default tools, renaming is still needed for
  Icarus; one renamed copy then serves simulation, sign-off and power alike.
- A flat design whose only escaped names are nets without a slash (`\g_ffs.s_pad[0]`) reads correctly, with zero SPEF
  misses.

**5.5 SRAM22 designs.** See section 9.1: absolute floorplan, macro in a column with a 20 µm halo, power-grid hook,
timing liberty in the `MACROS` section, GDS present. `tools/macro_config.py` sizes a roughly square die from the
synthesised standard-cell area, keeps 20 µm from core to die edge, and uses a PDN pitch of 80 and spacing of 15,
`RT_MAX_LAYER: met5` and cell padding 2; `ERROR_ON_PDN_VIOLATIONS: false` there is safe only because
`check_metrics.py` gates on the grid instead.

**5.6 OpenLane checks every file named in the configuration at load time**, including the macro GDS, even when the
flow stops before streamout. A git-ignored GDS makes a fresh checkout unusable.

**5.7 Low-voltage corners (for example 1.28 V).** `ss_n40C_1v28` is the only 1.28 V corner of `sky130_fd_sc_hd`, and
it is characterised at −40 °C.
- **Do not harden or repair at it.** OpenROAD repair at `ss_n40C_1v28` grew to 40–45 GB on 0.3–1 M-cell cores,
  because nearly every net violates that library's slew limits (5 OOM kills). With it as `DEFAULT_CORNER`,
  timing-driven global placement died after 26 min ("OpenROAD.GlobalPlacement failed unexpectedly"); the workaround
  was timing-driven placement off (`PL_TIMING_DRIVEN: false`, in OpenLane 2 `PL_TIME_DRIVEN`). It defaults to true
  in OpenLane 2 and to false in LibreLane. The PDK's
  `MAX_TRANSITION_CONSTRAINT` is 0.75 ns, which most nets violate at 1.28 V.
- **Harden at the standard corners, then evaluate the routed netlist and SPEF at the low-voltage liberty** with your
  own STA and power. That is a valid operating point. LibreLane's `PNR_CORNERS` does this inside the flow (optimise at
  the standard corners, report STA at more). Re-hardening with 1.28 V sign-off cost 7–41 % more energy and up to 2.5×
  more leakage, because of hold repair against `ff_n40C_1v95`.
- Slacks from a liberty swap ignore the IO delays unless you re-create the constraints from the run's SDC variables.
- Leakage at −40 °C is not comparable with 25 °C numbers (static energy fell about 32× in one design), and some cells
  (for example `xnor2_4`) barely change. State the temperature with the number.
- SRAM22 has no 1.28 V liberty: at this corner the macro becomes a black box (section 9.1).

## 6. Timing constraints and sign-off

**6.1 Constraints.**
- One clock; `reset` held for many cycles is the only false path. Every other path is timed, latch paths included.
- A false path removes a path from every check, so keep exceptions to what is provably static.
- Exceptions must match objects. After flattening, flip-flops are named `_12345_` and only nets keep the RTL names,
  so `get_cells -quiet u_sleep/sleeping` or `get_cells -quiet -hierarchical *sel_r*` match nothing and the constraint
  silently does nothing. Count the objects an exception matches, and fail at zero. Which objects keep the RTL names
  depends on the flow: in LibreLane the nets keep them and the cells do not, in ORFS the cells keep Yosys' register
  names (`\\u_wmem/lat[39]$_DLATCH_P_`) and the nets do not; an exception that must work in both looks for nets first,
  then cells.
- **Timing derating was off in every OpenLane 2 run on sky130.** OpenLane 2.3.10's `base.sdc` computes
  `set_timing_derate -early [expr 1-[expr $::env(TIME_DERATING_CONSTRAINT) / 100]]`; the PDK sets the constraint to
  the integer 5, and Tcl's integer division gives 0, so both derate factors were exactly 1.0 instead of 0.95 / 1.05.
  Slacks were optimistic by up to 5 % of each path delay (late for setup, early for hold), and the resizer repaired
  correspondingly less. LibreLane divides by `100.0`. Any project SDC copied from OpenLane 2's `base.sdc` must be fixed
  the same way. The effect on power or slack has not been measured yet.
- Any SDC change means hardening again. Removing a latch waiver added 53 hold buffers to one design and 930 to
  another.

**6.2 Sign-off.** Run OpenSTA yourself on the renamed netlist and SPEF (`tools/signoff_sta.tcl`), with the run's own
SDC variables (from `runs/<tag>/resolved.json`), not hand-written constraints. Accept on that timing. With escaped
names, OpenLane's sign-off reported a hold slack of 0.35 ns where the complete parasitics give 0.52 ns; the error can
go either way. For a flat netlist with zero SPEF misses, OpenLane's sign-off is acceptable.
- **Which corners.** OpenLane's default `STA_CORNERS` are {nom, min, max} parasitics × {tt_025C_1v80, ss_100C_1v60,
  ff_n40C_1v95} with `TIMING_VIOLATION_CORNERS: "*"`, so "all 9 corners pass" is the flow default; signing off at the
  typical corner only is a weaker choice. State your policy with the result, and check every corner at which you
  report numbers. (Caravel's own timing sign-off, `make caravel-sta`, uses the same 3 × 3 grid; `cf precheck` checks
  no timing.)

**6.3 Reading latch paths.** OpenSTA checks flip-flop-to-latch paths against the latch's opening edge, without time
borrowing. Those paths can show the smallest setup slack of a design, although the latch stays transparent for half a
period.

**6.4 Clock routing at low utilisation.** At low utilisation the router detours clock nets: one core failed hold by
−0.70 ns at 20 %, another needed a 5 ns margin on its controller paths, and a latch write clock had 16 ns latency.
Check clock latency and skew after routing, not only slack.

## 7. Gate-level simulation

**7.1 Icarus with SDF.**
- **Sanitise the SDF** (`tools/sdf_sanitize_for_icarus.py`). Icarus aborts on what it cannot parse. Keep the cell
  `IOPATH`s and:
  - fix the `a::b` triplets and fill empty `()` triplets with 0;
  - rescale a non-ns `(TIMESCALE ...)` to ns, because Icarus up to v13_0 ignores the header (iverilog #947; honoured
    in master since PR #1501, 2026-09-13), which matters for ASAP7;
  - drop `INTERCONNECT` (wire delays) and `TIMINGCHECK`;
  - turn `(COND ...) (IOPATH ...)` into plain `IOPATH`s (Icarus does not support `COND`, iverilog #949);
  - drop `IOPATH`s on bus bits (a macro's `dout[0]`; Icarus cannot parse them, iverilog #509);
  - drop cells left empty.

  The cell delays still include the load of the wires. Timing checks are not simulated (not implemented in Icarus,
  iverilog #945), so violations show up only in STA. Unwrapping `COND` leaves several `IOPATH`s for the same arc on
  clock gates and xor2, xnor2, mux2 and mux4 cells, and Icarus applies the last one. The conditional ones often carry
  an empty, zero-filled rise triplet, which then overrode the real delay: every clock gate of an ASAP7 core ran with
  0 ps rise delay. The sanitiser now drops a repeated `IOPATH` of an arc already seen when one of its triplets is all
  zero (588 lines in that core). Where two non-zero conditional delays remain, the last one applies.
- **Compile** with `-g2012 -gspecify -Ttyp`, in this order:
  1. `primitives.v`;
  2. `tools/sky130_timing_icarus_fixes.v` (defines the include guards `_TIMING_V` and `_TIMING_PP_V` and a no-op
     model of `lpflow_bleeder_1`, whose PDK timing model references `VPWR` without declaring it; not needed for
     zero-delay runs);
  3. the macro model;
  4. `sky130_fd_sc_hd.v`;
  5. stubs for physical-only cells that the model file lacks (`tools/gen_phys_stubs.py`); `sky130_fd_sc_hd.v`
     already defines `fill_1`, `tapvpwrvgnd_1`, `diode_2` and `decap_4`;
  6. the netlist;
  7. the testbench.

  `-ginterconnect` makes no difference, since the sanitiser drops all `INTERCONNECT` lines.
- **Macros** need a simulation model with the output delay built in for annotated runs (`*_tdout.v`), because their
  bus `IOPATH`s are dropped.
- **Count annotation errors on every run** (`SDF ERROR`, `Unable to match ModPath`) and **fail the run** if there are
  any.

**7.2 Activity extraction.**
- **Do not store the waveform.** Dump all levels of the design under test into a FIFO, read by `tools/vcd_toggles.c`.
  It counts per-signal transitions and high time with the rules of OpenSTA's VCD reader: the initial value does not
  count, and a change involving x or z counts half. Start the dump at the measurement window.
- **FIFO deadlock.** If the simulation dies before it opens the dump, `vcd_toggles` waits forever: release the FIFO on
  failure (`tools/reference_flow/gls.sh`). Build `vcd_toggles` once, atomically, before starting parallel runs.
- **Write the net activities after the pin activities** (`tools/toggles_to_activity.py`). With annotated delays,
  Icarus sometimes leaves a cell's output-port variable constant while the net it drives toggles: 657 pins in one
  core, 2 913 in another, costing 0.53 nJ per bin (about 12 %) when the pin commands won. The net's measured activity
  must be the last command. `tools/pin_net_consistency.py` checks it.

**7.3 Testbench and checks.**
- **Compare the gate-level outputs with the RTL outputs** bit for bit over the whole window.
- A missing or empty stimulus must fail: `$readmemh` of a missing file gives an empty stream that "passes".
- Bound every wait (configuration load, clock release, outputs). Count overruns of real-time deadlines.
- **Memories initialised in RTL lose their contents in the flattened netlist** (for example a register file loaded
  from a `.bin`): the flip-flops start at X and poison the datapath. Deposit the initial values in the testbench.

**7.4 Capacity, runtime and the alternatives.**
- 5 000 real-time bins of a 100 000-cell design took 4–9.5 h per session including power.
- **The community treats Icarus SDF simulation as limited.** caravel-cocotb refuses Icarus for SDF-annotated
  gate-level runs and uses CVC or VCS; Open MPW sign-off used CVC (iverilog #746). Our Icarus flow is a measurement
  tool, validated by the bit-exact comparison and zero annotation errors, not a timing sign-off.
- `$sdf_annotate` is O(cells²) in this Icarus (our observation; no published source): hours at 530 000 cells, and
  annotation failed outright on 370–600 k-instance netlists. `tools/icarus_sdf_fast.patch` gives the same toggles
  much faster.
- **Workaround for very large netlists:** zero-delay simulation of the whole set, multiplied by a glitch factor
  (annotated over zero-delay energy) measured on an annotated subset or a smaller variant; the sampling error was
  0.4 %. sky130 glitch factors seen: 1.18–1.22 at 5 MHz and 1.13–1.20 at 50 MHz for decoder cores, 1.13–1.93 for
  adder-tree cores. State which factor was applied.
- **Verilator** with functional models generated from the liberty (`tools/liberty2verilog.py`) handles million-cell
  netlists in minutes, but zero-delay only, so glitch power is lost. Use it for functional checks and zero-delay
  activity, combined with a measured glitch factor.
- **Verilator's VCD scope changed:** 5.027 (OSS CAD Suite 2024-08-07) writes `TOP/tb/dut/...`, 5.053 (2026-10-24)
  `tb/dut/...`. A toggle conversion with a fixed `--scope TOP/...` then matched no pin, all activities were skipped,
  and OpenSTA reported only clock-tree power. Detect the prefix from the toggle file, and fail the measurement when no
  pin activity was annotated (section 10).

## 8. Power with OpenSTA

**8.1 Activities.**
- Read the liberty files, the renamed netlist and the SPEF.
- Set `set_power_activity -input -activity 0 -duty 0`: OpenSTA's default for unannotated inputs is 0.1 transitions
  per cycle.
- Then apply the measured per-pin activities, nets last (7.2), and **fail the run if any measured activity was
  lost** (`tools/check_annotation.py <sta out dir> <netlist> <liberty>...`). The raw "not found" list is useless by
  eye: it has millions of expected names (supply pins, internal signals of the cell and macro models such as
  `notifier`, `D_delayed`, `and0_out_X`). The tool counts as lost only names that are signal pins of the instance's
  cell (liberty `pin`/`bus`, not `pg_pin`), instances missing from the netlist, and top-level names. On real designs:
  4–6 million names not found, 0 lost, in 5 s.
- **OpenSTA version.** The default (LibreLane 3.0.16) has OpenSTA 2.7.0, with `report_activity_annotation`.
  OpenLane 2.3.10 builds OpenSTA commit `b5f3a02` (2024-10-02), which reports "2.6.0"; later commits carry the same
  label. In it, `report_activity_annotation` does not exist (added 2025-01-15; a script calling
  it silently checks nothing), `set_clock_sense` is deprecated in favour of `set_sense -type clock`, and
  `read_power_activities` in favour of `read_vcd`.
- `set_power_activity -input` applies to every timing root, including tie-cell outputs (OpenSTA issue #539).
- Without annotation, OpenSTA propagates activity through logic (vectorless); that overestimates (OpenSTA issue
  #333) and models no glitches. Annotate every pin you can.

**8.2 The root clock network is charged at the full clock rate.** Between the clock port and the first clock gate,
OpenSTA takes the activity from the clock definition, whatever the annotation says.
- A design that stops its clock between computations (running 0.2–1 % of the time) gets most of its reported power
  from there: OpenSTA reported 11.73 µW where the true value is 7.40 µW.
- OpenSTA has no option to set a lower activity on the root clock network (`activity cannot be set on clock ports`);
  the correction below is our own method, not a published one.
- **Correction** (`tools/root_clock_correction.py`, or `root_clock_correction_multipdk.py`): P = P_STA − (1 − d) ·
  P_root, where d is the measured clock duty. Buffers and inverters of the root lose internal and switching power;
  clock gates and other cells clocked directly by the root lose internal power only. The walk from the clock port must
  continue through hold and delay buffers (`dly*`): only the multi-PDK version does that. OpenSTA warns "activity cannot be set on clock ports"; that is expected.
- The correction is large: 3–7 µW in the designs measured here, more than half of OpenSTA's total. Report P_STA next
  to the corrected P.
- A design whose clock keeps running does not need it.
- **Never stop the clock propagation at the clock gates** (`set_clock_sense -stop_propagation` on clock-gate outputs)
  when the activities come from toggle counts. The annotated activities are per clock cycle, and OpenSTA converts them
  to rates with the clock that reaches each pin. Behind a stopped clock-gate output no clock reaches the downstream
  pins, and the OpenSTA of OpenLane 2.3.10 (`b5f3a02`) then leaves the per-cycle activity unscaled, i.e. reads it as
  transitions per second: their internal and switching power become about 10⁻⁹ of the true value (confirmed in the
  source, `Power.cc` `findClkedActivity`). OpenSTA from 2025-01-17 stores densities and no longer has this trap, but
  the stop is still unnecessary. Flip-flops and the clock tree are not affected, which is why the total still looks
  plausible.
  - Evidence: the same core and toggle file gave a combinational group of 0.25 µW without the stop and 8·10⁻¹¹ W
    with it; energies per bin rose 7–174 % once fixed. A test with VCD-based activity had shown no difference, which
    is why the stop was believed harmless.
  - The loss is not always near total. In a RISC-V SoC the combinational group still showed 12.8 % of the total, but
    about 9 600 of 15 700 logic cells with measured activity reported 0 W; only the first logic level after a
    flip-flop kept its power. Its totals were probably 25–55 % low.
  - The stop is not needed. `sky130_fd_sc_hd__dlclkp` (like the GF180, IHP, NanGate45 and ASAP7 clock gates) carries
    `clock_gating_integrated_cell` in its liberty, so OpenSTA handles the gated subtrees itself. Measured per-pin
    activities on the gated tree override OpenSTA's own estimate for it (whose formula overcounts in our version;
    OpenROAD's OpenSTA PR #425, 2026-10).
  - Check: the combinational group must be a plausible share of the dynamic power: 24–52 % before and 61–76 % after
    the root-clock correction in the decoders measured here. A share near 0 %, or many active logic cells at 0 W in
    the per-instance report, means the activities were lost.

**8.3 Black boxes.** Only physical cells may become black boxes. A macro without its liberty is a black box with zero
power, and scripts that read a liberty "if the file exists" hide that. In the `ms` and `hs` libraries even the antenna
diode has no liberty (section 9.4).

**8.4 SPEF.** Zero `spef line N, net/instance ... not found` warnings (section 5.4).

**8.5 Report the energy, not only the power.** Window average power, energy per inference or bin, and a breakdown by
cell class (logic, clock tree, flip-flops, latches, hold cells, repair buffers, macros, leakage) find the cause of a
surprise quickly. Record the clock period actually used in the result file, not a default from a comment.

**8.6 Reuse a simulation only for identical inputs.** Stamp it with a hash of the netlist, SDF, SPEF, stimulus and
configuration image, leaving out the `*DATE` and `(DATE ...)` header lines, which change on every run.

**8.7 A global (median) activity is not a cross-check.** A flow that applied one median activity to every data net
agreed with the per-pin flow "within 5 %" only because errors cancelled (combinational 0.58 against 1.62 mW, macro
1.52 against 0.22 mW). Compare per-group breakdowns, not totals.

**8.8 State what a power number assumes.** Besides the activity source:
- the SPEF corner (nom, min or max parasitics) used for power;
- the output load and driving cell of the ports (the PDK sets `OUTPUT_CAP_LOAD` 33.4 fF), or that they were zeroed;
- the single liberty corner of leakage (no process spread, no self-heating, no IR drop);
- the simulator and delay model behind any glitch power: glitch counts depend on how the simulator filters pulses
  (inertial or transport), and Icarus differs from commercial tools.

## 9. Special cases

### 9.1 The SRAM22 macro (`sram22_2048x32m8w8`)

**Use the fixed views in `/media/pdk/sram22_sky130_fixed-de0a9a7/`** (upstream `sram22_sky130_macros` `de0a9a7` with
the fixes below; built by `install/patches/fix_sram22.py` in this repository). Older copies in project folders carry
the old 0.04 ns slew limit.

- **Energy counted twice.** The as-generated liberty lists every internal energy once per supply pin and once per
  ground pin, and OpenSTA sums them (474 against 945 µW in one measurement; confirmed in the OpenSTA source, which
  normalises per `related_pg_pin` and then adds them; still so upstream, no upstream issue yet). Use the supply-only
  copies `*_pwr.lib` for power, and the as-generated ones for timing.
- **Read energy weighted with the wrong probability.** The clock-pin internal energy is split by
  `when : "we&ce"`, `"we&!ce"`, `"!we&ce"` (read) and `"!we&!ce"` (`ce&rstb` is the *leakage* condition), and OpenSTA
  weights each with the time-averaged duties of `we` and `ce`. With a gated or stopped macro clock, `ce` is high at
  almost every clock edge but low on average, so each access is counted with a weight close to the clock duty: read
  energy too low by about 1/duty.
  - Fix (`tools/macro_state_correction.py`): duty_cond = (duty − v_idle (1 − d_clk)) / d_clk, where d_clk is the
    fraction of cycles with a macro clock edge and v_idle the pin's value while the clock is stopped. Compare the
    six-decimal duties of the activity file with a tolerance.
  - Effect: +0.27 to 0.58 µW of 7–9 µW in one design, +6.5 % in a dense SRAM core; in a RISC-V SoC the macros' share
    was 1.7 % instead of about 12 %.
- **Layout views.** The GDS needs a `prBoundary` (235/4) on its top cell (LibreLane's Magic step needs it; sram22
  issue #504, declined upstream), and the LEF `OBS` must be on met1 only, so that the grid can reach the met2 supply
  pins. The fixed views have both.
- **Power grid.** `pdn_cfg_sram22.tcl` (`tools/reference_flow/`) must end with
  `add_pdn_connect -grid macro -layers "met2 met4"`, together with `PDN_MACRO_CONNECTIONS: <inst> VPWR VGND vdd vss`.
  That gives zero power-grid violations. Without it, the macro's supply pins stay unconnected: other grid variants on
  this machine (`met3 met4` + `met2 met3`) gave 268 000 and 547 000 violations, hidden by
  `ERROR_ON_PDN_VIOLATIONS: false`. Power from OpenSTA is not affected, but the layouts fail 5.2.
- Put the timing liberty in `MACROS` so that paths through the macro are timed.
- **Simulation:** use the functional model for zero-delay runs and the `_tdout` model, with its output delay, for
  annotated runs.
- **Slew limits.** Macro liberties before 2026-09-09 set a default maximum transition of 0.04 ns (sram22 issue #512;
  fixed upstream in sram22_sky130_macros PR #13, now 0.351 ns, and in the fixed views). With the old value, the data
  outputs' own slew (0.5–0.9 ns) violates it; do not gate on max-slew at the data outputs with old views. The
  **clock pin** limit (0.35 ns) is different: a slew of 1.2 ns, or 1.7–2.0 ns when a `dlclkp_2` drives the macro clock
  directly, is a real violation. Buffer the macro clock.
- **Corners.** Liberties exist for tt 1.8 V 25 °C, ss 1.6 V 100 °C and ff 1.95 V −40 °C only; at any other corner
  (for example `ss_n40C_1v28`, `tt_100C`) the macro becomes a black box.
- **Leakage:** 2.34 µW per instance at tt, however few words are used. A read costs about 15 pJ, a write about 10 pJ,
  an idle clock edge about 1.15 pJ.

### 9.2 Latch memories

Several designs keep weights in latch rows: a staging register in front, one clock gate per row, and the gate opening
one cycle after the last word.
- **Do not waive latch paths in the SDC.** A blanket `set_false_path -from` latches plus a hold waiver at the latch
  data pins hides every latch timing problem, including those of a design that writes latches while it computes.
  Timing all of them cost 53 and 930 extra hold buffers in two designs, and both met timing.
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
  a placeholder delay of 1.0 ns: 2 000–5 500 `Unable to match ModPath` errors per run, about 6 % of the cells. Fix the
  models or the sanitiser before using GF180 annotated numbers. GF180 `primitives.v` has no timescale, so compile a
  timescale file first, and initialise `reg notifier`.
- **IHP.** `delayed_*` nets float without timing checks, and ABC's `Q|~Q` reset stays X. Decaps were 94 % of the
  leakage.
- **IHP and ASAP7 have state-dependent clock-pin internal power**, so duties must be conditioned on the clock enable
  as for SRAM22 (+27 % on IHP).
- **ORFS (ASAP7, NanGate45)** writes the same slash names as OpenLane (section 5.4), and its adder techmap gives
  non-equivalent netlists with older Yosys. See `ASAP7_flow_notes.md`.
- **Check annotation and SPEF matching per PDK.** A flow that is clean on sky130 is not automatically clean elsewhere.

### 9.4 Other sky130 standard-cell libraries

- **`sky130_fd_sc_ms` has no leakage data.** All 376 cells have `cell_leakage_power : 0` and no `leakage_power`
  groups, so a design in `ms` reports leakage for its macros only, and OpenLane reports `power__leakage__total: 0`.
  Its decaps have no leakage either, so 5.1's decap advice changes nothing there. Leakage of an `ms` design needs
  another library or SPICE; say so with the number. (Our observation in the PDK files; no published source.) `hd`,
  `hdll` and `hs` have per-cell leakage; `ls` has state-dependent groups.
- **`ms` and `hs` have no `diode_2` liberty** (skywater-pdk issue #358, open), so antenna diodes become black boxes
  (14 500 in one SoC) and their pin capacitance is missing from switching power.

## 10. Checklist for every measurement

| check | expect |
|---|---|
| `ANNOUNCEMENTS.md` read; tool and PDK versions as in section 1 or as announced | yes |
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
| measured activities lost (`check_annotation.py`) | 0, and the run fails otherwise |
| pin activities annotated | more than 0 (a wrong scope prefix silently annotates none), and the run fails otherwise |
| pin and net activities of the same net | consistent (net written last) |
| clock duty d used for the root-clock correction | the measured one (clock cycles × period / window) |
| `set_clock_sense -stop_propagation` in the power script | absent |
| combinational group of the power report | a plausible share of the dynamic power, not near 0 %; no active logic cells at 0 W |
| a reference design hardened and measured twice | the same number to the last digit |

## 11. Reproducibility of the numbers (and of trained networks)

- **Pin versions:** OpenLane commit, PDK commit, OSS CAD Suite release, Python packages. Write the tool versions into
  every result file (hardening and measurement summaries alike).
- **Measure with a script that a second person can rerun**, and keep its outputs together with the commit of the
  scripts that produced them. Results that depend on an untracked clone are not reproducible.
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

These notes describe a measurement flow. A tapeout on a ChipFoundry shuttle needs, at least, the following, and none
of it is set up or verified on this machine yet:
- LibreLane (the OpenLane successor named in OpenLane 2.3.10's own README) and the shuttle's `cf` tools
  (`pip install cf-precheck`; `cf init`, `cf setup`, `cf gpio-config`, which is required before precheck);
- what `cf precheck` checks: XOR against the golden wrapper, top-cell name, metal density, KLayout FEOL/BEOL/off-grid/
  zero-area, spike, illegal cell names, OEB (with the CVC electrical checker), power grid and LVS; Magic DRC is
  optional, and **timing is not checked**;
- RTL and gate-level full-chip simulation of the wrapper, with the wrapper's pin order matching the template;
- physical sign-off: Magic and KLayout DRC, netgen LVS, antenna check and repair, density fill, decaps, IR drop;
- multi-corner sign-off (9 corners), which conflicts with SRAM22's three liberties (9.1) and needs a stated policy;
- harness integration (Caravel `user_project_wrapper` or OpenFrame): power pins, GPIO and OEB defaults, pad timing,
  gate-level simulation with pad models;
- macro-first hierarchical hardening (tiles, many-macro power grid, halos, hold and skew at SRAM pins);
- SRAM22 for tapeout: DRC waivers for the macro internals, a justification for any data-output slew waiver, the
  `prBoundary` and `OBS` fixes checked against the precheck;
- min/max SDF gate-level simulation at the sign-off corners;
- shuttle-specific PDK, LibreLane and precheck versions, separate from the measurement flow's pins.

When tapeout work verifies any of this, report it through the inbox; it will get its own section or notes file.
