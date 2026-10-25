# Per-pin activity power of a hardened neat_decoder with OpenSTA (run by flow/power.sh inside the LibreLane environment).
# Environment: TOP NETLIST SPEF LIB_SC PERIOD_NS OUT ACT_TCL, for SRAM22 designs LIB_SRAM and MACRO_INST, optionally
# EXTRA_ACT_TCL (activities that override the measured ones: the macro state correction) and CLK_PORT (default clk).
# Writes OUT/power_vcd.rpt (the group table) and OUT/power_vcd_by_instance.rpt (one line per instance).
set OUT $::env(OUT)
read_liberty $::env(LIB_SC)
if {[info exists ::env(MACRO_INST)] && $::env(MACRO_INST) ne ""} { read_liberty $::env(LIB_SRAM) }
read_verilog $::env(NETLIST)
link_design $::env(TOP)
read_spef $::env(SPEF)

set period $::env(PERIOD_NS)
set clkport [expr {[info exists ::env(CLK_PORT)] ? $::env(CLK_PORT) : "clk"}]
create_clock -name clk -period $period -waveform [list 0.0 [expr {$period / 2.0}]] [get_ports $clkport]
set_propagated_clock [all_clocks]

file mkdir $OUT
# input ports without an annotation get activity 0 instead of OpenSTA's default (0.1 transitions per cycle); every port and
# pin the simulation saw is annotated by the activity file
set_power_activity -input -activity 0.0 -duty 0.0
puts "sourcing activities $::env(ACT_TCL)"
source $::env(ACT_TCL)
if {[info exists ::env(EXTRA_ACT_TCL)]} { source $::env(EXTRA_ACT_TCL); puts "EXTRA_ACT_TCL: $::env(EXTRA_ACT_TCL)" }
report_power -digits 6 > $OUT/power_vcd.rpt
report_power -instances [get_cells *] -digits 4 > $OUT/power_vcd_by_instance.rpt
puts "WROTE $OUT/power_vcd.rpt"
