#!/usr/bin/env bash
# Enable the ASAP7 SRAM-Vt flavour in an ORFS checkout that has ASAP7_USE_VT (upstream >= 2025-03), without editing
# the platform config: use ASAP7_USE_VT=SRAM.
#  1. ASAP7_USE_VT=SRAM looks for asap7sc7p5t_*_SRAMVT_* liberties; the files are named *_SRAM_*: add aliases.
#  2. Add the Yosys map files cells_{latch,clkgate,adders}_SRAM.v (the _R files with the cell suffix changed).
#  3. The SRAM-Vt LEF declares DECAP cells CLASS CORE (RVT/LVT/SLVT: CORE SPACER), which makes ORFS count them as
#     logic (ASAP7 notes 6.3): make them CORE SPACER like the other flavours.
# Usage: apply_sram_vt_orfs.sh /media/pdk/OpenROAD-flow-scripts-<rev>
set -euo pipefail
P=${1:?orfs dir}/flow/platforms/asap7
cd "$P/lib/NLDM"
for f in asap7sc7p5t_*_SRAM_*; do ln -sfn "$f" "${f/_SRAM_/_SRAMVT_}"; done
cd "$P/yoSys"
for k in latch clkgate adders; do sed 's/_ASAP7_75t_R\b/_ASAP7_75t_SRAM/g' "cells_${k}_R.v" > "cells_${k}_SRAM.v"; done
L=$P/lef/asap7sc7p5t_28_SRAM_1x_220121a.lef
[[ -f $L.orig ]] || cp "$L" "$L.orig"
awk '/^MACRO DECAPx[0-9]+_ASAP7_75t_SRAM/{d=1} d && /^[ \t]*CLASS CORE ;/{sub(/CLASS CORE ;/,"CLASS CORE SPACER ;"); d=0} {print}' "$L.orig" > "$L"
echo "SRAMVT aliases: $(ls "$P/lib/NLDM" | grep -c SRAMVT); decap spacers: $(grep -c 'CLASS CORE SPACER' "$L")"
grep -c '_ASAP7_75t_SRAM' "$P"/yoSys/cells_*_SRAM.v
