#!/usr/bin/env bash
# Smoke test of the new ORFS checkout with LibreLane's binaries: ORFS's gcd example on ASAP7, RVT and SRAM-Vt, at TT.
# Usage: run_orfs_check.sh RVT|SRAM
set -euo pipefail
source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
VT=${1:?RVT|SRAM}
O=/media/pdk/OpenROAD-flow-scripts-ef2cb37
W=/media/amir/flow_notes/validation/work_orfs_$VT
mkdir -p "$W"
export QT_QPA_PLATFORM=offscreen
nix --extra-experimental-features "nix-command flakes" develop --accept-flake-config \
  /media/hardware_design_tools/librelane-3.0.16 -c bash -c "cd $O/flow && make WORK_HOME=$W \
  DESIGN_CONFIG=./designs/asap7/gcd/config.mk ASAP7_USE_VT=$VT CORNER=TC NUM_CORES=\${JOBQ_THREADS:-4} \
  OPENROAD_EXE=\$(which openroad) OPENSTA_EXE=\$(which sta) YOSYS_EXE=\$(which yosys) KLAYOUT_CMD=\$(which klayout)"
grep -h -o "asap7sc7p5t_[A-Z]*_[A-Z]*_[A-Z]*_nldm_[0-9]*" -r "$W/logs" | sort -u
grep -h -E '"(finish__timing__setup__ws|finish__timing__hold__ws|finish__design__instance__count__stdcell|finish__power__total|detailedroute__route__drc_errors)"' "$W"/logs/asap7/gcd/base/*.json "$W"/reports/asap7/gcd/base/*.json 2>/dev/null | sort -u
