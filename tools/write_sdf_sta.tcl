# Write an SDF for gate-level simulation from the routed netlist, its parasitics and the liberty files (ASAP7 notes 8.1).
# Env: TOP LIB_SC NETLIST SPEF PERIOD_NS SDF_OUT, optional CLK_PORT (default clk). PERIOD_NS is in the liberties' time
# unit (ps on ASAP7); it only defines the clock whose propagation sets the clock-tree delays, so its value barely matters.
foreach l $::env(LIB_SC) { read_liberty $l }
read_verilog $::env(NETLIST)
link_design $::env(TOP)
read_spef $::env(SPEF)
set period $::env(PERIOD_NS); create_clock -name clk -period $period -waveform [list 0.0 [expr {$period / 2.0}]] [get_ports [expr {[info exists ::env(CLK_PORT)] ? $::env(CLK_PORT) : "clk"}]]
set_propagated_clock [all_clocks]
write_sdf -divider / -include_typ -digits 4 $::env(SDF_OUT)
puts "WROTE $::env(SDF_OUT)"
exit
