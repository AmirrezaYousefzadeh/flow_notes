# The fixed physical flow and the power measurement

Teams do not tune the flow: they choose their RTL, their clock period, their utilisation and their SRAM22 instances,
nothing else. Everything here is what the organisers run, so numbers obtained at home with the same tool versions
(`env/SETUP.md`) are the official ones. The scripts run on Linux (they use `taskset` and `setsid`).

| File | What it does |
|---|---|
| `LESSONS.md` | the pitfalls of the open sky130 tools met while building this flow, and the checks against them |
| `harden.sh` | `harden.sh <submission> <session> <work dir>`: one OpenLane 2 run, synthesis to sign-off STA, at the utilisation declared in `submission.json`, with 20 % as the fallback; a watchdog stops a run whose detailed routing cannot converge. `SYNTH_ONLY=1 harden.sh ...` synthesises only (minutes), for a size estimate. Environment: `CELL_CAP`, `WATCHDOG_IDLE_H`, `WATCHDOG_MAX_H` |
| `measure.sh` | the official measurement of one session: `gls.sh` on the first 5000 test bins, then `power.sh` → `measure.json` |
| `gls.sh` | gate-level simulation of the accepted netlist on a stream, typical-corner cell delays annotated, the waveform streamed into the toggle counter |
| `power.sh` | per-pin OpenSTA power from the toggle counts, with the root-clock correction and, for macros, the state correction → `power.json` |
| `config.template.yaml` | the OpenLane 2 configuration; `harden.sh` fills in the files, the clock, the constraints and the utilisation |
| `neat_decoder.sdc` | timing constraints: one clock, input and output delays, `reset` the only false path |
| `pdn_cfg_sram22.tcl` | the power grid of designs with SRAM22 macros (connects the macros' supply pins) |
| `macros/` | the SRAM22 2048 x 32 macro, the only macro teams may use, and a small test design (`macros/README.md`) |
| `tools/signoff_sta.tcl` | the sign-off timing at the typical corner, on the renamed netlist and SPEF (every net with its parasitics) |
| `tools/check_metrics.py` | accepts or rejects a hardened run (routing DRC, sign-off timing, power grid, cell cap) |
| `tools/macro_config.py` | adds the macro instances and an absolute floorplan to the configuration |
| `tools/legal_names.py` | gives hierarchical names (`\u_rom.u_col_0/_307_ `) plain spellings in the netlist, SDF and SPEF, for the simulation and the power analysis |
| `tools/sdf_sanitize_for_icarus.py`, `tools/sky130_timing_icarus_fixes.v`, `tools/gen_phys_stubs.py` | make the SDF, the sky130 timing models and the physical-only cells digestible for Icarus Verilog |
| `tools/vcd_toggles.c` | counts the transitions and high times of every signal of a VCD stream without storing it |
| `tools/toggles_to_activity.py` | turns the counts into OpenSTA activity commands |
| `tools/power_sta.tcl` | the OpenSTA script: liberty, netlist, SPEF, propagated clock, measured activities, reports |
| `tools/root_clock_correction.py` | scales the power of the root clock network by the measured clock duty |
| `tools/macro_state_correction.py` | conditions the macros' state-dependent read energy on the clock running |
| `tools/rt_stats.py` | the real-time summary of a simulation log as JSON |

## Hardening

One run at the declared utilisation (placement density = utilisation + 10 %), then at 20 % if it does not close. A
run is accepted when all of these hold:
- the detailed router leaves no DRC error;
- setup and hold are met at the typical corner (tt, 1.8 V, 25 °C);
- the power grid has no violation;
- the design has at most 300 000 standard cells, tap cells not counted (their number follows the core area, not the
  design).

The timing is that of `tools/signoff_sta.tcl`: OpenSTA on the renamed netlist and SPEF of `tools/legal_names.py`.
OpenLane's own sign-off reads the original SPEF, whose names of nets inside sub-modules it cannot match, so it times
those nets without their wires; its slacks are kept in `check.json` for information. The flow stops after sign-off
timing: no GDS streamout, no Magic or KLayout DRC, no LVS, no antenna repair (antenna violations are reported, not
checked). The watchdog stops
a run with more than 500 000 routing violations after 3 router iterations, 20 000 after 6, 3 000 after 10, no
finished iteration for 12 hours, or 36 hours in total. `harden.json` lists every attempt and the tool versions.

Constraints: one clock; `reset` is the only false path (it is held for many cycles); every other path is timed,
those launched from or ending at latches included (RULES.md, section 5). Gate clocks with the sky130 `dlclkp` cell:
the root-clock correction recognises it, and a clock gated with ordinary logic is not corrected.

## Power

The average power of a session is OpenSTA's total over the 20 s window of the first 5000 test bins, with the
measured activity of every pin, the extracted parasitics of the routed netlist and the typical-corner liberty,
leakage included (decap-free fill, so the leakage is that of the logic and the macros):

    P = P_STA - (1 - d) x P_root

OpenSTA charges the clock network between the clock port and the first clock gate at the full clock rate, but the
testbench stops the clock between bins: `P_root`, the dynamic power of that root network (buffers fully, clock gates and
directly clocked cells for their internal power), is scaled by the measured duty `d` of the clock
(`tools/root_clock_correction.py`). For SRAM22 macros, OpenSTA weights the read energy with the time-averaged state of
the control pins, which are idle while the clock is stopped; `tools/macro_state_correction.py` conditions those state
duties on the clock running, and `P_STA` is taken from that run. `measure.json` reports the result as `p_total_uW`,
the energy per bin as `e_bin_nJ`, and the gate-level output must equal the RTL output on every bin.

Not modelled: wire delays in the simulation (the cell delays include the load of the wires), the drive of the inputs
and the load of the outputs beyond the defaults of the constraints, and anything outside the typical corner.

The gate-level simulation and the power analysis run on renamed copies of the netlist, SDF and SPEF
(`tools/legal_names.py`): Icarus Verilog cannot annotate a cell whose instance name contains a dot, which is how
OpenROAD names the cells of sub-modules and generate blocks, and OpenSTA reads a slash in a SPEF name as a hierarchy
divider. `rt.json` of the simulation records the SDF annotation errors (0 expected); `power.sh` stops when a SPEF
entry finds no net or a cell has no liberty model.

## Pitfalls seen in the examples

**A register behind a constant table.** Yosys turns a `case` of constants into a ROM and folds the register behind it
into the ROM's read port. If anything else sits between the ROM and that register (a range check on an address wider
than the ROM, a multiplexer with another source), the fold fails and Yosys pushes the address register through the
ROM instead, which creates a second register of the full row width: 1024 surplus flip-flops in the alternative
baseline, 37 % more clocked cells. Compare the flip-flop count of the synthesis report with what the RTL declares.

**A large constant table as one flat `case`.** The 230 kbit of shared weights of the alternative baseline, generated
as one table, synthesised into one web of shared logic that placement could not keep local (5.5 of 6.8 m of wire);
the design did not route at 20 % or 30 % utilisation. One module per output byte with `(* keep_hierarchy *)` keeps
each column's logic next to its consumer (`neat_rom_col` in `submissions/baseline/pipeline/gen_weights.py`).

## Utilisation

The utilisation changes the wire length and the buffering, and with them the power by a few per cent in either
direction: the feedforward reference core (the same netlist, 200 bins) measured 2.38 µW hardened at 30 % and 2.22 µW
at 20 %, with longer routes in the denser core and more clock buffers in the larger one. It also decides whether a
design routes at all. Teams declare their utilisation and explore it at home; the flow is deterministic.

## CPU budget

Every script respects `NEAT_THREADS` of `env/env.sh` (default 10, or fewer on a smaller machine): the detailed router
gets `NEAT_THREADS - 2` threads, STA two, and every tool is pinned to the first `NEAT_THREADS` CPUs at low priority.
