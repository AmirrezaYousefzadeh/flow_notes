# Correction and first result on "LibreLane keeps every logic cell at drive 2"

Project: synaptic_delay. Date: 2026-10-30. Follow-up to my request note of today (already taken from the inbox).

## Correction
Point 3 of that note said OpenLane 2's Yosys buffered in synthesis (`SYNTH_BUFFERING`). That is wrong: the OpenLane 2
run's `resolved.json` has `SYNTH_ABC_BUFFERING: false`, like LibreLane's, and `MAX_FANOUT_CONSTRAINT: 10` in both. The
difference in buffers is in OpenROAD's `repair_design` alone: OpenLane 2 fixed its slew violations mostly by resizing
(7 159 instances) and with fewer, larger buffers (buf_8/buf_12 and clkbuf_16: 919 buf + 1 677 clkbuf in the final
netlist), the new one resizes 138 and inserts 4 605 buffers (buf_4 1 528, clkdlybuf4s25_1 1 384 on internal nets,
2 314 clock buffers of which clkbuf_4 1 210). The CTS defaults also changed between the versions
(`CTS_SINK_CLUSTERING_SIZE`/`_MAX_DIAMETER` 25/50 → None, `CTS_APPLY_NDR: half`); the clock tree's dynamic power is +39 %.

## First result of the drive-1 experiment (synthesis and post-placement repair; routing still running)
`SYNTH_EXCLUDED_CELL_FILE` = the PDK's `no_synth.cells` minus its 91 drive-1 logic entries (all `_1` except clock,
delay, latch, scan, enable-flop and tri-state cells), `SYNTH_STRATEGY: AREA 0` unchanged:
- Yosys now maps to drive 1: dfxtp_1 3 634, nor2_1 2 558, inv_1 2 068, a21oi_1 1 407, nand2_1 841, and2_1 548,
  xnor2_1 456 (the mapping changes slightly: more xnor2 and inverters than with drive 2).
- `RepairDesignPostGPL` keeps them: dfxtp_1 3 466 / dfxtp_2 167 / dfxtp_4 1, nor2_1 2 553 / nor2_2 5; "Resized 423
  instances". So the resizer does size up where it must, and the sizing part of the difference is recoverable this way.
- It does not help the buffers: "Found 1657 slew violations, 352 fanout violations", "Inserted 4416 buffers in 1662
  nets" (buf_4 1 426, clkdlybuf4s25_1 1 457). Weaker drivers give a few more slew violations than with drive 2 (1 406).
A second experiment adds `SYNTH_ABC_BUFFERING: true` on top. Energy of both follows when they are measured.
