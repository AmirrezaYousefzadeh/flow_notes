# Reference tools

Maintained copies of the tools the flow notes refer to. Copy what you need into your project and record the
`flow_notes` commit you copied from. Do not edit them here: report bugs or improvements through `../inbox/`.

| tool | what it does | notes section |
|---|---|---|
| `legal_names.py` | renames every escaped identifier to a plain one, consistently in netlist, SDF and SPEF | sky130 5.4 |
| `signoff_sta.tcl` | OpenSTA sign-off with every net's parasitics and the run's SDC variables | sky130 6.2 |
| `hold_sta.tcl` | own hold check at several corners with SPEF (ORFS reports no hold slack in older versions) | ASAP7 7.2 |
| `check_metrics.py` | accepts or rejects an OpenLane run: routing DRC 0, setup and hold met, power grid clean, no unmatched SPEF entries, cell cap | sky130 5.2 |
| `macro_config.py` | macro instances and an absolute floorplan with SRAM22 macros in a column | sky130 5.5 |
| `sdf_sanitize_for_icarus.py` | makes an OpenSTA/OpenROAD SDF digestible for Icarus (triplets, COND, INTERCONNECT, bus bits, ps → ns) | sky130 7.1 |
| `write_sdf_sta.tcl` | writes an SDF with OpenSTA (ORFS writes none) | ASAP7 8.1 |
| `sky130_timing_icarus_fixes.v` | include guards and a no-op `lpflow_bleeder_1` for compiling the sky130 timing models | sky130 7.1 |
| `gen_phys_stubs.py` | empty modules for physical-only cells missing from the model file | sky130 7.1 |
| `asap7_seq_icarus.v` | behavioural ASAP7 DFFHQNx1/2/3, ICGx1, DHLx1 (RVT and SRAM-Vt) for Icarus | ASAP7 8.1 |
| `liberty2verilog.py` | functional Verilog models from a liberty, for Verilator | sky130 7.4, ASAP7 8.2 |
| `icarus_sdf_fast.patch` | faster `$sdf_annotate` for Icarus on large netlists | sky130 7.4 |
| `vcd_toggles.c` | per-signal transition counts and high time from a VCD stream (OpenSTA's counting rules) | sky130 7.2 |
| `toggles_to_activity.py` | toggle counts → `set_power_activity` commands, net activities last | sky130 7.2 |
| `pin_net_consistency.py` | checks that pin and net activities of the same net agree | sky130 7.2 |
| `power_sta.tcl` | per-pin OpenSTA power with checks for unmatched SPEF entries and black boxes | sky130 8 |
| `root_clock_correction.py` | root-clock correction for sky130 designs whose clock is stopped most of the time (gates: `dlclkp`; walks through clock buffers and inverters, **not** through `dlygate` delay cells) | sky130 8.2 |
| `root_clock_correction_multipdk.py` | the same correction for any PDK (`--icg`, `--buf` cell-name lists; walks through `HBx`/`dly*` hold cells); different interface: two per-instance reports | sky130 8.2, ASAP7 9.6 |
| `macro_state_correction.py` | SRAM22 read energy conditioned on the macro clock running | sky130 9.1 |
| `rt_stats.py` | real-time statistics of a session (deadline overruns, clock duty) | |
| `reference_flow/` | a complete sky130 measurement flow (harden, gate-level simulation, power, one-session measurement) from a verified design, written for OpenLane 2; for LibreLane change `python3 -m openlane` to `python3 -m librelane`, the flake and `PDK_ROOT` (validated this way, `../validation/`). Variable and file names come from that design: adapt them | sky130 2 |
