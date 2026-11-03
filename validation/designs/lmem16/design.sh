# Validation design 2 (sky130, latch-memory core): BCI_paper's latch-memory decoder bmi_snn_lmem2g with 16 instead of
# 64 hidden neurons (96 inputs -> 16 LIF -> 2 outputs): 12 672 weight bits in level-sensitive latches written row by
# row through one dlclkp_1 per W1 row or W2 word (113), plus 4 dlclkp_4 (core, write, membrane and weight-row clocks);
# the weights are loaded through the 32-bit write port before the measurement window. It replaces the 64-neuron core,
# which did not route with LibreLane within 2.6 days (validation/README.md).
# Sourced by ../../flow/*.sh, with D (this directory) and, for the simulation, OUT (the output directory) set.
NAME=lmem16
KIND=sky130
TOP=bmi_snn_lmem16
CLOCK_PORT=clk
CLOCK_NS=200
RTL=("$D/rtl/bmi_snn_lmem16.v")            # generated flat variant; its own `defines select the latch memory
INCDIRS=()                                 # weights_rom.vh is only included by the HARDWIRED branch, not compiled here
SYNTH_DEFINES=()
SDC="$D/sdc/bmi_snn_lmem16.sdc"            # latch waivers removed, derating / 100.0 (ORIGIN)
UTILS="30 20"
MACRO_CELL=""
MACRO_INSTANCES=""
# latches borrow time and report a setup slack of exactly 0: no positive setup margin (sky130 notes 5.1); clock-tree
# buffers on long clock wires, which the project needed to close hold on the write-clock domain (16 ns latency without);
# the latch rows are intended (written as always @* if (gate) ...), so Verilator's LATCH is not a lint error (notes 9.2);
# no clock NDR for a design with one gated clock per latch row (notes 5.1: the 64-neuron core's global router dropped
# the NDR on 725 clock nets "to reduce congestion", GRT-0273, and the core never routed)
CONFIG_EXTRA="LINTER_ERROR_ON_LATCH: false
CTS_APPLY_NDR: none
PL_RESIZER_SETUP_SLACK_MARGIN: 0
GRT_RESIZER_SETUP_SLACK_MARGIN: 0
CTS_DISTANCE_BETWEEN_BUFFERS: 150
CTS_CLK_MAX_WIRE_LENGTH: 300"
# OpenROAD dcf3613's CTS left one row clock gate without its clock in 3 of 4 runs of the two latch cores (issue
# #9816): fix the gates in place before CTS (sky130 notes 9.2)
FIRM_CLOCK_GATES=1
# simulation: real-time presentation (-DREALTIME), one 4 ms bin after the other with the clock stopped between bins;
# the testbench checks y0/y1 of every bin against expect_w50.hex and prints "PASS: 50 bins bit-exact"
TB="$D/tb/tb_bmi_snn.v"
TB_TOP=tb_bmi_snn
DUT=u_dut
UNITS=50
UNIT_NAME=bin
OUT_FILE=stats.txt                         # per bin: bin, cycles, active cycles, latency (informative)
GOLDEN=""
PASS_REGEX='^PASS'
SIM_MODE=sdf
RTL_SIM_CELLS=sky130                       # the RTL instantiates sky130_fd_sc_hd__dlclkp_1/_4 directly
tb_defines() {      # sets TB_DEFS: the testbench's own defines (the flow adds SDF_ANNOTATE, DUMP_* and CLK_PERIOD_NS)
  TB_DEFS=(-DGLS -DGLS_PROGRESS -DN_BINS=50 -DMODE_DENSE=0 -DIDLE_GAP=64 -DDUT=bmi_snn_lmem16 -DLOAD_PORT
           -DHAS_WR_READY -DREALTIME -DTIMEOUT_CYCLES=2000000000 -DMAX_TOKENS=1400000
           -DSTREAM_HEX="\"$D/stim/stream_w50.hex\"" -DEXPECT_HEX="\"$D/stim/expect_w50.hex\""
           -DWEIGHTS_HEX="\"$D/stim/weights.hex\"" -DSTAT_FILE="\"$OUT/stats.txt\"")
}
# queue resources of one validation run (hardening, gate-level simulation, power)
JOB_THREADS=4
JOB_MEM=10
JOB_TIME=10h
