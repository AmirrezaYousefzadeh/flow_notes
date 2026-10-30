# Validation design 1 (sky130, one SRAM22 macro): a linear read-out whose weights live in one sram22_2048x32m8w8,
# behind a clock gate; 432 cells after synthesis. Sourced by ../../flow/*.sh, with D (this directory) and, for the
# simulation, OUT (the output directory) set.
NAME=sram_probe
KIND=sky130
TOP=neat_decoder
CLOCK_PORT=clk
CLOCK_NS=200
RTL=("$D/rtl/sram_probe.v" "$D/rtl/neat_clkgate.v")
INCDIRS=()
SYNTH_DEFINES=(NEAT_SYNTH)                 # the sky130 clock gate under synthesis, its model in RTL simulation
SDC="$D/sdc/core.sdc"
UTILS="30"                                 # one utilisation: the macro floorplan is absolute (sky130 notes 5.5)
MACRO_CELL=sram22_2048x32m8w8
MACRO_INSTANCES="u_mem"
CONFIG_EXTRA=""                            # further LibreLane settings (YAML lines)
# simulation: the testbench writes one line per bin (bin x y latency_ns) and prints PASS when real time was met;
# bit-exactness is the comparison of out.txt with the RTL simulation's (golden/out.txt)
TB="$D/tb/tb_neat.v"
TB_TOP=tb_neat
DUT=u_dut
UNITS=200
UNIT_NAME=bin
OUT_FILE=out.txt
GOLDEN="$D/golden/out.txt"
PASS_REGEX='^PASS'
tb_defines() {      # sets TB_DEFS: the testbench's own defines (the flow adds SDF_ANNOTATE, DUMP_* and CLK_PERIOD_NS)
  TB_DEFS=(-DN_BINS=200 -DSTREAM_HEX="\"$D/stim/test_w200.hex\"" -DLOAD_HEX="\"$D/rtl/neat_weights.hex\""
           -DOUT_FILE="\"$OUT/out.txt\"" -DPROGRESS)
}
# queue resources of one validation run (hardening, gate-level simulation, power)
JOB_THREADS=4
JOB_MEM=4
JOB_TIME=1h
