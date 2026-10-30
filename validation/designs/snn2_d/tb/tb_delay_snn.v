`timescale 1ns/1ps
// Testbench of the generated cores (sw/gen_rtl.py): replays SHD test samples, as fixed 20 ms frames of input events, and checks
// the class scores and the class of every sample bit-exactly against the integer reference model (sw/snn_int.py; vectors from
// sw/export_vectors.py). Used for RTL (sim/run_rtl.sh) and gate-level simulation (sim/run_gls_stream.sh, sim/measure_rt.sh).
// Events are presented back to back (one per clock cycle while ev_ready is high), each frame ends with a tick, the last frame of a
// sample with tick + tick_last. REALTIME: frame k is presented at k x FRAME_NS and the clock is stopped as soon as the core is idle
// again (as the real-time measurement of sky130-snn-bmi), so the recorded activity covers the whole window, idle time included.
//
// Stream file (STREAM_HEX, 8-bit tokens): 0x00..0x8B event (channel id), 0xFF end of frame, 0xFD end of the last frame of a
// sample, 0xFE end of stream.   Expected file (EXPECT_HEX): per sample N_OUT scores and the class (32-bit words).
// Defines: DUT (module name), N_SAMPLES, N_OUT, SCORE_BITS (width of the score port), CLK_PERIOD_NS, REALTIME (+ FRAME_NS),
//          DUMP_PATH / DUMP_LEVEL / DUMP_MODULE (waveform), SDF_ANNOTATE, GLS_PROGRESS, TIMEOUT_CYCLES, STAT_FILE, MAX_TOKENS.
module tb_delay_snn;
  reg reset = 1;
`ifndef CLK_PERIOD_NS
  `define CLK_PERIOD_NS 10000.0
`endif
  localparam real CLK_PERIOD_NS = `CLK_PERIOD_NS;
`ifdef REALTIME
  // The oscillator runs freely; the clock delivered to the core (clk = osc & clk_run) runs from the start of a frame until the
  // core is idle again and is stopped (low) for the rest of the frame. clk_run changes only while osc is low (no partial pulses).
  `ifndef FRAME_NS
    `define FRAME_NS 20000000
  `endif
  reg  osc = 0, clk_run = 1, rt_marker = 0;
  always #(CLK_PERIOD_NS / 2.0) osc = ~osc;
  wire clk = osc & clk_run;
  integer rt_frame = 0, rt_overrun = 0; reg [63:0] t_start = 0, t_fr = 0, t_end = 0, t_act_sum = 0, t_act_max = 0, t_act0 = 0;
`else
  reg clk = 0;
  always #(CLK_PERIOD_NS / 2.0) clk = ~clk;
`endif
`ifndef N_SAMPLES
  `define N_SAMPLES 10
`endif
`ifndef N_OUT
  `define N_OUT 20
`endif
`ifndef TIMEOUT_CYCLES
  `define TIMEOUT_CYCLES 2000000000
`endif
`ifndef STREAM_HEX
  `define STREAM_HEX "stream.hex"
`endif
`ifndef EXPECT_HEX
  `define EXPECT_HEX "expect.hex"
`endif
`ifndef MAX_TOKENS
  `define MAX_TOKENS 20000000
`endif
`ifndef DUT
  `define DUT snn2_d
`endif

  reg         ev_valid = 0;
  reg  [7:0]  ev_ch = 0;
  wire        ev_ready;
  reg         tick = 0, tick_last = 0;
  wire        tick_ready;
  wire        out_valid;
  wire [4:0]  out_class;
  wire        score_valid;
  wire [31:0] score_w;
  wire        busy, core_clk_en;
  `DUT u_dut (
    .clk(clk), .reset(reset),
    .ev_valid(ev_valid), .ev_ch(ev_ch), .ev_ready(ev_ready),
    .tick(tick), .tick_last(tick_last), .tick_ready(tick_ready),
    .out_valid(out_valid), .out_class(out_class), .score_valid(score_valid), .score(score_w),
    .busy(busy), .core_clk_en(core_clk_en)
  );
  // the score port is narrower than 32 bits: sign-extend from its width (SCORE_BITS)
`ifndef SCORE_BITS
  `define SCORE_BITS 12
`endif
  wire signed [31:0] score_s = {{(32-`SCORE_BITS){score_w[`SCORE_BITS-1]}}, score_w[`SCORE_BITS-1:0]};

  reg [7:0]  stream [0:`MAX_TOKENS-1];
  reg [31:0] expect_w [0:(`N_OUT+1)*`N_SAMPLES-1];

  integer cyc = 0, active_cyc = 0, cyc_meas0 = 0, active_meas0 = 0;
  integer smp = 0, errors = 0, nsc = 0, nev = 0, nfr = 0;
`ifdef BANK_MONITOR
  integer bm_edges = 0, bm_clr = 0, bm_viol = 0;    // bank-protocol monitor (end of this file)
`endif   // sample, mismatches, scores seen, events, frames
  always @(posedge clk) begin
    cyc = cyc + 1;
    if (core_clk_en === 1'b1) active_cyc = active_cyc + 1;
`ifdef GLS_PROGRESS
    if ((cyc % 200000) == 0) begin $display("GLS_PROGRESS cycle=%0d sample=%0d", cyc, smp); $fflush; end
`endif
    if (cyc > `TIMEOUT_CYCLES) begin $display("FAIL: timeout"); $fatal(1); end
  end

  // ---- output capture: scores while score_valid, class at out_valid (sampled on the falling edge: stable)
  integer f_stat;
  reg got_out = 0;
  always @(negedge clk) begin
    if (score_valid === 1'b1) begin
      if (score_s !== $signed(expect_w[(`N_OUT+1)*smp + nsc])) begin
        errors = errors + 1;
        if (errors <= 10) $display("MISMATCH sample %0d score %0d: got %0d expected %0d", smp, nsc, score_s, $signed(expect_w[(`N_OUT+1)*smp + nsc]));
      end
      nsc = nsc + 1;
    end
    if (out_valid === 1'b1) begin
      if (nsc != `N_OUT || out_class !== expect_w[(`N_OUT+1)*smp + `N_OUT][4:0]) begin
        errors = errors + 1;
        if (errors <= 10) $display("MISMATCH sample %0d: class %0d expected %0d (scores seen %0d)", smp, out_class, expect_w[(`N_OUT+1)*smp + `N_OUT][4:0], nsc);
      end
`ifdef STAT_FILE
      $fwrite(f_stat, "%0d %0d %0d\n", smp, out_class, cyc);
`endif
      smp = smp + 1; nsc = 0; got_out = 1;
    end
  end

  integer i;
  reg [7:0] tok;
  // present one token stream entry: events back to back (one per cycle while ev_ready), then the tick. Inputs change on the
  // falling edge; the ready outputs are sampled a quarter period later (tick_ready depends combinationally on ev_valid, and
  // the gate-level netlist has real delays), i.e. still in the low phase, so the transfer happens at the next rising edge.
  localparam real QP = CLK_PERIOD_NS / 4.0;
  task present_frame;
    begin
      tok = stream[i];
      while (tok != 8'hFF && tok != 8'hFD && tok != 8'hFE) begin
        @(negedge clk); ev_valid = 1'b1; ev_ch = tok; #(QP);
        while (ev_ready !== 1'b1) begin @(negedge clk); #(QP); end
        @(posedge clk);
        i = i + 1; nev = nev + 1; tok = stream[i];
      end
      @(negedge clk); ev_valid = 1'b0;
      if (tok == 8'hFF || tok == 8'hFD) begin
        tick = 1'b1; tick_last = (tok == 8'hFD); got_out = 0; #(QP);
        while (tick_ready !== 1'b1) begin @(negedge clk); #(QP); end
        @(posedge clk);
        @(negedge clk); tick = 1'b0; tick_last = 1'b0;
        i = i + 1; nfr = nfr + 1;
        if (tok == 8'hFD) while (!got_out) @(posedge clk);
      end
    end
  endtask

  initial begin
`ifdef SDF_ANNOTATE
`ifdef SDF_FAST
    $sdf_annotate_fast(`SDF_ANNOTATE, u_dut);   // tools/sdf_fast.vpi (sim/build_sdf_fast.sh): the same annotation, hashed lookup
`else
    $sdf_annotate(`SDF_ANNOTATE, u_dut);
`endif
    $display("SDF: annotated %s onto u_dut", `SDF_ANNOTATE);
`endif
`ifdef DUMP_PATH
  `ifndef REALTIME
    $dumpfile(`DUMP_PATH);
    $dumpvars(`DUMP_LEVEL, `DUMP_MODULE);
  `endif
`endif
`ifdef STAT_FILE
    f_stat = $fopen(`STAT_FILE, "w");
`endif
    for (i = 0; i < `MAX_TOKENS; i = i + 1) stream[i] = 8'hFE;
    $readmemh(`STREAM_HEX, stream);
    $readmemh(`EXPECT_HEX, expect_w);
    $display("TB: n_samples=%0d clk=%0g ns", `N_SAMPLES, CLK_PERIOD_NS);
    reset = 1'b1;
    repeat (8) @(posedge clk);
    @(negedge clk); reset = 1'b0;
    repeat (4) @(posedge clk);
`ifdef REALTIME
    @(negedge osc); clk_run = 0;
    t_start = (($time / 64'd1000000) + 64'd1) * 64'd1000000;
    #(t_start - $time);
    rt_marker = ~rt_marker;
  `ifdef DUMP_PATH
    $dumpfile(`DUMP_PATH);
    $dumpvars(`DUMP_LEVEL, `DUMP_MODULE);
    $dumpvars(0, rt_marker);
    $display("WAVEFORM: dumping to %s from t=%0t (window start)", `DUMP_PATH, $time);
  `endif
`endif
    cyc_meas0 = cyc; active_meas0 = active_cyc;
    i = 0;
    while (stream[i] != 8'hFE && smp < `N_SAMPLES) begin
`ifdef REALTIME
      t_fr = t_start + rt_frame * `FRAME_NS;
      if ($time > t_fr) begin rt_overrun = rt_overrun + 1; if (rt_overrun <= 5) $display("RT OVERRUN: frame %0d not idle at its slot start", rt_frame); end
      else #(t_fr - $time);
      @(negedge osc); clk_run = 1; t_act0 = $time;
      present_frame;
      @(negedge clk); while (!(core_clk_en === 1'b0 && busy === 1'b0)) @(negedge clk);
      repeat (2) @(posedge clk);
      @(negedge osc); clk_run = 0;
      t_act_sum = t_act_sum + ($time - t_act0); if ($time - t_act0 > t_act_max) t_act_max = $time - t_act0;
      rt_frame = rt_frame + 1;
`else
      present_frame;
`endif
    end
`ifdef REALTIME
    t_end = t_start + rt_frame * `FRAME_NS;
    if ($time < t_end) #(t_end - $time);
    rt_marker = ~rt_marker;
    #1;
    $display("RT: frames=%0d clk_cycles_in_window=%0d active_ns_mean=%0d active_ns_max=%0d overruns=%0d window_ns=%0d", rt_frame, cyc - cyc_meas0, (rt_frame > 0) ? t_act_sum / rt_frame : 0, t_act_max, rt_overrun, t_end - t_start);
`else
    repeat (8) @(posedge clk);
`endif
`ifdef STAT_FILE
    $fclose(f_stat);
`endif
`ifdef BANK_MONITOR
    $display("BANKS: clock edges %0d, receiver cleared while its sender is clocked %0d, protocol violations %0d", bm_edges, bm_clr, bm_viol);
    errors = errors + bm_viol;
`endif
    $display("SUMMARY: samples=%0d frames=%0d events=%0d errors=%0d cycles=%0d active_cycles=%0d", smp, nfr, nev, errors, cyc - cyc_meas0, active_cyc - active_meas0);
    if (errors == 0 && smp == `N_SAMPLES) $display("PASS: %0d samples bit-exact", smp);
    else $display("FAIL: errors=%0d samples=%0d", errors, smp);
    $finish;
  end
`ifdef BANK_MONITOR
  // The hold waivers of synthesis/common/core.sdc (no hold check between the gated clocks of different register banks) rest on
  // the controller's protocol: a bank that launches a transfer is never clocked in the cycle in which the receiving bank
  // captures it, except in the clear state, in which the receiver loads zero whatever its input. Checked on every edge of the
  // core clock of the run (RTL simulation, sim/run_rtl.sh with EXTRA_DEFS=-DBANK_MONITOR): sender -> receiver pairs as in the
  // SDC: input counters -> layer-1 accumulators (a1), a1 -> s1, s1 -> s2, s2 -> read-out (o), s2 -> s1.
  task bm_check(input snd, input rcv, input rcv_cleared, input [8*16-1:0] what);
    if (snd & rcv) begin
      if (rcv_cleared) bm_clr = bm_clr + 1;
      else begin
        bm_viol = bm_viol + 1;
        if (bm_viol <= 10) $display("BANK PROTOCOL VIOLATION at %0t: %0s clocked in the same cycle", $time, what);
      end
    end
  endtask
  always @(posedge clk) begin
    #1;                                              // the gated clocks of this edge have risen
    if (!reset) begin
      bm_edges = bm_edges + 1;
      bm_check(u_dut.mon_cg, u_dut.g_a1, 1'b0, "counters->a1");
      bm_check(u_dut.g_a1, u_dut.g_s1, u_dut.clr_bank, "a1->s1");
      bm_check(u_dut.g_s1, u_dut.g_s2, u_dut.clr_bank, "s1->s2");
      bm_check(u_dut.g_s2, u_dut.g_o, u_dut.clr_bank, "s2->o");
      bm_check(u_dut.g_s2, u_dut.g_s1, u_dut.clr_bank, "s2->s1");
    end
  end
`endif
endmodule
