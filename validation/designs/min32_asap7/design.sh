# Validation design 4 (ASAP7, SRAM-Vt): BCI_paper's bmi_snn_min32, the hardwired variant of the parallel event-driven
# SNN decoder (96 inputs -> 32 LIF -> 2 outputs, 16-bit membranes, weights as a constant ROM inlined into the RTL), with
# its root and write clock gates instantiated as ICGx1_ASAP7_75t_SRAM; 24 683 instances in the project's run (taps included).
# Sourced by ../../flow/*.sh, with D (this directory) and, for the simulation, OUT (the output directory) set.
NAME=min32_asap7
KIND=asap7
TOP=bmi_snn_min32
CLOCK_PORT=clk
CLOCK_NS=200                               # the SDC is in ps (200000)
RTL=("$D/rtl/bmi_snn_min32.v")             # the asap7sram retarget (ICGx1_ASAP7_75t_SRAM); no includes, ROM inlined
INCDIRS=()
SYNTH_DEFINES=()                           # clock gates instantiated directly, not through OPENROAD_CLKGATE
SDC="$D/sdc/constraint.sdc"
UTILS="60 50 40"
MACRO_CELL=""
MACRO_INSTANCES=""
ORFS_VT=SRAM
# the project's synthesis settings (ASAP7 notes 5): no adder map (non-equivalent netlists), the inlined 24.8 kbit ROM
# above the default memory limit, area-oriented ABC
ORFS_EXTRA="export ADDER_MAP_FILE :=
export ABC_AREA = 1
export SYNTH_MEMORY_MAX_BITS = 65536"
# simulation: real-time presentation (-DREALTIME), one 4 ms bin after the other with the clock stopped between bins, as in
# the project's sim/measure_rt_pdk.sh; the testbench checks y0/y1 of every bin against expect_w50.hex and prints
# "PASS: 50 bins bit-exact"
TB="$D/tb/tb_bmi_snn.v"
TB_TOP=tb_bmi_snn
DUT=u_dut
UNITS=50
UNIT_NAME=bin
OUT_FILE=stats.txt                         # per bin: bin, cycles, active cycles, latency (informative)
GOLDEN=""
PASS_REGEX='^PASS'
SIM_MODE=sdf
RTL_SIM_CELLS=asap7                        # the RTL instantiates ICGx1_ASAP7_75t_SRAM (tools/asap7_seq_icarus.v)
tb_defines() {      # sets TB_DEFS: the testbench's own defines (the flow adds SDF_ANNOTATE, DUMP_* and CLK_PERIOD_NS)
  TB_DEFS=(-DGLS -DGLS_PROGRESS -DN_BINS=50 -DMODE_DENSE=0 -DIDLE_GAP=0 -DDUT=bmi_snn_min32 -DREALTIME
           -DTIMEOUT_CYCLES=2000000000 -DMAX_TOKENS=1400000
           -DSTREAM_HEX="\"$D/stim/stream_w50.hex\"" -DEXPECT_HEX="\"$D/stim/expect_w50.hex\""
           -DWEIGHTS_HEX="\"$D/stim/weights.hex\"" -DSTAT_FILE="\"$OUT/stats.txt\"")
}
# queue resources of one validation run (ORFS, gate-level simulation, power)
JOB_THREADS=4
JOB_MEM=8
JOB_TIME=3h
