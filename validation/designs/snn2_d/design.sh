# Validation design 3 (sky130, dense adder-tree core): synaptic_delay's snn2_d, a hardwired, fully parallel SNN for SHD
# (140 inputs -> 64 -> 64 -> 20 classes, synaptic delays 0..29 frames) whose ternary weights are wiring into trees of
# 12 986 directly instantiated full adders; 155 dlclkp clock gates (one per input counter, one per register bank).
# Sourced by ../../flow/*.sh, with D (this directory) and, for the simulation, OUT (the output directory) set.
NAME=snn2_d
KIND=sky130
TOP=snn2_d
CLOCK_PORT=clk
CLOCK_NS=10000                             # 100 kHz: the slowest clock that keeps the busiest 20 ms frame real time
RTL=("$D/rtl/snn2_d.v")
INCDIRS=()
SYNTH_DEFINES=()
SDC="$D/sdc/core.sdc"                      # the project's SDC (bank hold exceptions kept), derating / 100.0 (ORIGIN)
UTILS="30 20"
MACRO_CELL=""
MACRO_INSTANCES=""
# the project's design-specific settings: synthesis for area (timing is met by a wide margin at 10 us), and clock nets on
# met3-met5 with their RC estimated on those layers (the long wires from the clock gates came out slower than estimated)
CONFIG_EXTRA="SYNTH_STRATEGY: AREA 0
RT_CLOCK_MIN_LAYER: met3
CLOCK_WIRE_RC_LAYERS: [met3, met4, met5]"
# simulation: real-time presentation (-DREALTIME), frame k of a sample at k x 20 ms, the clock stopped once the core is
# idle; the testbench checks the 20 class scores and the class of every sample and prints "PASS: 25 samples bit-exact"
TB="$D/tb/tb_delay_snn.v"
TB_TOP=tb_delay_snn
DUT=u_dut
UNITS=25
UNIT_NAME=sample
OUT_FILE=stats.txt                         # per sample: sample, class, cycle (informative)
GOLDEN=""
PASS_REGEX='^PASS'
SIM_MODE=sdf
RTL_SIM_CELLS=sky130                       # the RTL instantiates sky130_fd_sc_hd__fa_1 and dlclkp_1/_4 directly
tb_defines() {      # sets TB_DEFS: the testbench's own defines (the flow adds SDF_ANNOTATE, DUMP_* and CLK_PERIOD_NS)
  # MAX_TOKENS: the stream has 207 299 tokens; the testbench default (20 M) costs 0.77 GB for an unused array
  TB_DEFS=(-DGLS -DGLS_PROGRESS -DN_SAMPLES=25 -DDUT=snn2_d -DSCORE_BITS=7 -DN_OUT=20 -DREALTIME -DFRAME_NS=20000000
           -DTIMEOUT_CYCLES=2000000000 -DMAX_TOKENS=250000
           -DSTREAM_HEX="\"$D/stim/stream.hex\"" -DEXPECT_HEX="\"$D/stim/expect.hex\"" -DSTAT_FILE="\"$OUT/stats.txt\"")
}
# queue resources of one validation run (hardening, gate-level simulation, power)
JOB_THREADS=4
JOB_MEM=8
JOB_TIME=14h
