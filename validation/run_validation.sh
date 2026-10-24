#!/usr/bin/env bash
# Validation of a tool/PDK set on the reference design: the SRAM22 macro test design of the verified sky130
# measurement flow (copy in neat_ref/, origin commit in neat_ref.COMMIT): hardening, then a 200-bin annotated
# gate-level simulation and per-pin OpenSTA power. Run through jobq.
# Usage: run_validation.sh old|new|ol2newpdk
set -euo pipefail
V=/media/amir/flow_notes/validation
T=/media/hardware_design_tools
case "${1:?old|new}" in
  old) ;;   # the installed defaults (section 1 of the notes)
  new) export OPENLANE_ROOT=$T/librelane-3.0.16 OL_MODULE=librelane \
              PDK_ROOT=/media/pdk/ciel/sky130/versions/8afc8346a57fe1ab7934ba5a6056ea8b43078e71 \
              OSSCAD=$T/oss-cad-suite-2026-10-24 ;;
  ol2newpdk) export PDK_ROOT=/media/pdk/ciel/sky130/versions/8afc8346a57fe1ab7934ba5a6056ea8b43078e71 ;;   # OpenLane 2 + new PDK
  *) exit 2 ;;
esac
export NEAT_THREADS=${JOBQ_THREADS:-4} NEAT_CPUS=0-$(( $(nproc) - 1 ))   # no pinning under jobq
W=$V/work_$1
mkdir -p "$W"
cd "$V/neat_ref"
flow/harden.sh flow/macros/test indy_20160630_01 "$W/macro_test"
flow/measure.sh flow/macros/test indy_20160630_01 "$W/macro_test/runs/accepted" "$W/macro_test_power" 200
cat "$W/macro_test/harden.json" "$W/macro_test_power/measure.json"
