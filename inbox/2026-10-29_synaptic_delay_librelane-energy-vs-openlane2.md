# LibreLane 3 vs OpenLane 2 on a logic-dominated core: +20 % energy at tt, +40 % at ss_n40C_1v28

Project: synaptic_delay. Date: 2026-10-29. Complements notes 5.7 ("Moving from OpenLane 2 to LibreLane changes the
numbers"), which was measured on an SRAM-leakage-dominated design (total +0.9 %). On a core without macros the whole
difference shows in the total.

## Design and measurement
Flat 34 000-cell core (3 634 flip-flops, 155 clock gates, adder trees, 100 kHz clock stopped when idle), hardened twice
from the same RTL and SDC at 40 % utilisation: OpenLane 2 + `/media/pdk/sky130A`, and LibreLane 3.0.16 + `8afc834`
(defaults; `PL_TIMING_DRIVEN` off, antenna repair off, decap-free, `DRT_ANTENNA_REPAIR_ITERS: 0`). Same testbench, the
whole test set (2 264 samples, bit-exact in both), OpenSTA power with annotated toggles, the notes' root-clock
correction applied to both (it changes the old numbers by 0.4 %). Glitch factor from 100 SDF-annotated samples.

| energy per inference, decap-free | OpenLane 2 | LibreLane 3 | change |
|---|---|---|---|
| tt 1.8 V static / dynamic / total | 218 / 192 / 410 nJ | 234 / 257 / 491 nJ | +7 % / +34 % / **+20 %** |
| ss_n40C_1v28 static / dynamic / total | 6.9 / 84.3 / 91.2 nJ | 12.4 / 115.2 / 127.6 nJ | +79 % / +37 % / **+40 %** |
| glitch factor tt / 1.28 V | 1.30 / 1.32 | 1.41 / 1.42 | |

## Where it comes from (netlist and per-instance power)
- **No downsizing.** Every drive-1 logic cell of the OpenLane 2 netlist is drive 2 with LibreLane: dfxtp_1 2 481 → 0
  (dfxtp_2 555 → 3 617), nor2_1 1 985 → 0, and2_1 1 125 → 0, a21oi_1 960 → 0, nand2_1 683 → 0, or2_1 549 → 0, and3_1
  481 → 0, o21a_1 466 → 0. Only the full adders went the other way (fa_2 2 624 → 87, fa_1 +2 537).
- **Repair buffers on internal nets, not only ports:** buf_4 105 → 1 528, clkdlybuf4s25_1 0 → 1 384 (the design has
  under 200 ports), clkbuf_4 342 → 1 210; `design__instance__count__class:timing_repair_buffer` 1 460 → 4 636. Cells
  without fill and taps 31 399 → 34 477 (+10 %), cell area 0.464 → 0.496 mm².
- **Dynamic power (zero-delay, tt) by block:** clock tree +39 % (fewer but larger buffers), the input-event counters
  +42 %, the adder trees +9 %; total +24 % before the glitch factor, +34 % with it.
- **Leakage at ss_n40C_1v28 +80 %** (5.8 → 10.4 nW), almost all from the drive-2 cells that barely reduce their
  leakage in that library: xnor2_2 (8 → 255 instances) +2.7 nW and nand2_2 (53 → 880) +1.8 nW. At tt the leakage
  rises 7 %, in step with the cell area.

## Suggestions
- In 5.7, state that on logic-dominated cores the migration raises the total energy by tens of per cent, and most at
  the low-voltage corner, so published OpenLane 2 numbers cannot be reused next to LibreLane ones even approximately.
- The 1.28 V leakage quirk (notes: xnor2_4) extends to xnor2_2 and nand2_2; a drive-2-heavy netlist pays for it.
- If anyone knows a LibreLane/OpenROAD `dcf3613` setting that restores gate downsizing (or an ABC mapping to drive-1
  cells), it would be worth a line in 5.7. This project will try a synthesis-only exclusion of drive-2 logic cells and
  the resizer's power recovery, and report what happens.
