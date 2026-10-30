# Validation flow

A generic, runnable measurement flow for the reference designs in `../designs/`, built from the maintained tools
(`../../tools/`) and the rules of the notes. Every design is rerun at every change of default tool or PDK versions
(`UPSTREAM.md`, upgrade policy) and its numbers are compared with the stored set in `../results/`.

| script | what it does |
|---|---|
| `validate.sh <label> [design ...]` | submits one `jobq` job per design (`run_design.sh`), work in `../work_<label>/` |
| `run_design.sh <design> <work>` | one design end to end; writes `<work>/result.json` |
| `sky130_harden.sh <design> <work>` | LibreLane with the measurement settings of sky130 notes 5.1, `tools/harden_ladder.sh`, accepted only on the 9-corner own sign-off |
| `sky130_signoff.sh <run>` | own sign-off at {tt, ss, ff} × {nom, min, max} with the run's netlist, SPEF and SDC (`tools/hold_sta.tcl`) |
| `sky130_measure.sh <design> <run> <out>` | Icarus gate-level simulation (SDF or zero delay), bit-exact check, toggles, OpenSTA per-pin power, SRAM22 state and root-clock corrections |
| `asap7_run.sh <design> <work>` | ORFS (`ef2cb37`, LibreLane binaries, `CORNER=TC`) over the design's utilisations, own hold check at TT/SS/FF, SDF from OpenSTA, Icarus with 1 ps models, power with run B and the multi-PDK root-clock correction |
| `rtl_sim.sh <design> <out> [--golden]` | RTL simulation with the design's testbench; `--golden` stores its output as the bit-exact reference |
| `compare.py <work> <results set> [--store]` | compares a run with a stored set, or stores it |

## A design directory

`designs/<name>/` holds a frozen copy of everything the design needs (RTL, testbench, stimulus, expected outputs,
constraints), `ORIGIN` (project, commit and source path of every file), and `design.sh`, sourced by the scripts with
`D` (the design directory) and, for simulations, `OUT` (the output directory) set. `design.sh` defines:

| variable | meaning |
|---|---|
| `NAME`, `KIND` | the design's name; `sky130` or `asap7` |
| `TOP`, `CLOCK_PORT`, `CLOCK_NS` | top module, clock port, clock period in ns |
| `RTL`, `INCDIRS`, `SYNTH_DEFINES` | arrays: RTL files, include directories, defines for synthesis (absolute paths, under `$D`) |
| `SDC` | constraints (sky130: LibreLane variables; asap7: ps) |
| `UTILS` | utilisations, dense to sparse ("50 40 30"); one value for a design with SRAM22 macros |
| `MACRO_CELL`, `MACRO_INSTANCES` | sky130 SRAM22 macro and its instance names (empty without macros) |
| `CONFIG_EXTRA` | sky130: further LibreLane settings, YAML lines |
| `ORFS_VT`, `ORFS_EXTRA` | asap7: the flavour (`SRAM`, `RVT`, ...) and further `config.mk` lines (`export X = Y`) |
| `TB`, `TB_TOP`, `DUT` | testbench file, its top module, the instance name of the design in it |
| `tb_defines()` | a function that sets the array `TB_DEFS`: the testbench's own defines (stimulus, counts, output file under `$OUT`); the flow adds `CLK_PERIOD_NS`, `SDF_ANNOTATE`, `DUMP_PATH`, `DUMP_LEVEL=0`, `DUMP_MODULE=$TB_TOP.$DUT` |
| `PASS_REGEX` | the testbench's pass line in the simulation log (it must also print nothing matching `^FAIL`/`^MISMATCH`) |
| `OUT_FILE`, `GOLDEN` | an output file the testbench writes and its golden copy from the RTL simulation (empty `GOLDEN` when the testbench checks its outputs itself) |
| `UNITS`, `UNIT_NAME` | how many bins, samples or inferences the window holds, for energy per unit |
| `SIM_MODE` | `sdf` (default) or `zero` (zero-delay functional models: for netlists whose SDF annotation takes hours) |
| `RTL_SIM_CELLS` | `none`, `sky130` or `asap7`: cell models the RTL simulation needs (RTL that instantiates clock gates) |
| `JOB_THREADS`, `JOB_MEM`, `JOB_TIME` | queue resources of one run (`jobq add --threads --mem --time`) |

The testbench must dump `$dumpvars(DUMP_LEVEL, DUMP_MODULE)` into `DUMP_PATH` only over the measurement window (the
flow reads it through a FIFO), so that the toggle file covers exactly the window; the clock duty comes from the toggles
of `$TB_TOP/$DUT/$CLOCK_PORT`.
