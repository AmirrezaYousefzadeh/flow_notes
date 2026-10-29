# Reference tools

Maintained copies of the tools the flow notes refer to. Copy what you need into your project and record the
`flow_notes` commit you copied from. Do not edit them here: report bugs or improvements through `../inbox/`.

| tool | what it does | notes section |
|---|---|---|
| `harden_ladder.sh` | hardens any LibreLane configuration under the hardening policy: utilisations dense to sparse, routing watchdog (not counting time frozen by the queue), process-group stop, acceptance from the run's metrics (worst slack over all STA corners, plus an optional own sign-off), every attempt logged in `ladder.json`; LibreLane's workers limited to the job's threads | sky130 5.3 |
| `legal_names.py` | renames every escaped identifier to a plain one, consistently in netlist, SDF and SPEF (all four SPEF spellings, including ORFS' bare and escaped `$`) | sky130 5.4, ASAP7 9.4 |
| `signoff_sta.tcl` | OpenSTA sign-off at one corner with every net's parasitics and the run's SDC (propagates the clocks when the SDC does not say) | sky130 6.2 |
| `hold_sta.tcl` | own setup and hold check at one corner; SPEF required; the run's SDC, or one clock with `PERIOD` in the liberties' time unit (ps on ASAP7); JSON in ns; exit 1 on negative slack | sky130 6.2, ASAP7 7.2 |
| `check_metrics.py` | accepts or rejects a run at one corner: routing DRC 0, setup and hold met, power grid clean, no unmatched SPEF entries, optional cell cap; `--synth-stat` counts truly unmapped cells (also alone, right after synthesis) | sky130 4, 5.2 |
| `macro_config.py` | SRAM22 macro instances in a column, one timing liberty per corner, the power-grid hook (`--pdn-cfg`) and an absolute floorplan | sky130 5.5, 9.1 |
| `sdf_sanitize_for_icarus.py` | makes an OpenSTA/OpenROAD SDF digestible for Icarus (triplets, COND, INTERCONNECT, bus bits, zero-filled conditional repeats, ps → ns) | sky130 7.1, ASAP7 8.1 |
| `write_sdf_sta.tcl` | writes an SDF with OpenSTA (ORFS writes none) | ASAP7 8.1 |
| `sky130_timing_icarus_fixes.v` | include guards and a no-op `lpflow_bleeder_1` for compiling the sky130 timing models | sky130 7.1 |
| `gen_phys_stubs.py` | empty modules for physical-only cells missing from the model file | sky130 7.1 |
| `asap7_seq_icarus.v` | behavioural ASAP7 DFFHQNx1/2/3, ICGx1/2, DHLx1 (RVT and SRAM-Vt) for Icarus, 1 ps precision | ASAP7 8.1 |
| `liberty2verilog.py` | functional Verilog models from a liberty, for Verilator | sky130 7.4, ASAP7 8.2 |
| `icarus_sdf_fast.patch` | a faster `$sdf_annotate_fast` task for Icarus on large netlists, built as a VPI module (load with `-m`, call it instead of `$sdf_annotate`); not installed: ask the maintainer through the inbox | sky130 7.4 |
| `vcd_toggles.c` | per-signal transition counts and high time from a VCD stream (OpenSTA's counting rules) | sky130 7.2 |
| `toggles_to_activity.py` | toggle counts → `set_power_activity` commands, net activities last; fails when no variable matches the scope | sky130 7.2 |
| `pin_net_consistency.py` | diagnostic: how many cell output pins disagree with the net they drive | sky130 7.2 |
| `check_annotation.py` | fails the power analysis when a measured activity was lost, or when no pin activity was annotated at all (separates the millions of expected "not found" names from real losses; reads gzipped liberties) | sky130 8.1 |
| `power_sta.tcl` | per-pin OpenSTA power: one propagated clock, unannotated inputs at 0, the activity file; several liberties; `ZERO_DATA=1` gives run B of the multi-PDK root-clock correction | sky130 8 |
| `root_clock_correction.py` | root-clock correction for sky130 designs whose clock is stopped most of the time (any sky130 library; gates `dlclkp`, `sdlclkp`; walks through clock, hold and delay buffers) | sky130 8.2 |
| `root_clock_correction_multipdk.py` | the same correction for any PDK (`--icg`, `--buf` cell-name lists); takes run A and run B (`power_sta.tcl` with `ZERO_DATA=1`); warns about root cells missing from B. On a sky130 design it agrees with the sky130 tool within 0.02 % | sky130 8.2, ASAP7 9.6 |
| `macro_state_correction.py` | SRAM22 read energy conditioned on the macro clock running | sky130 9.1 |
| `rt_stats.py` | real-time statistics of a session (deadline overruns, clock duty) | |
| `reference_flow/` | the complete sky130 measurement flow of one verified design (harden, gate-level simulation, power, one-session measurement) on the default versions; fails on SDF errors and lost activities. A reference implementation, **not runnable as copied**: it expects that design's environment script, SDC, testbench, macro views and submission parser | sky130 2 |
