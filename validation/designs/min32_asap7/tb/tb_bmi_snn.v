`timescale 1ns/1ps
// Testbench: replays a NeuroBench spike stream through bmi_snn_top and checks the two int24
// outputs bit-exactly against the integer reference model (sw/snn_int.py).
//
// Stream file (STREAM_HEX, 8-bit tokens): 0x00..0x5F input event (channel id), 0xFF end-of-bin tick.
// Expected file (EXPECT_HEX): two 32-bit words per bin (sign-extended y0, y1).
// Defines: N_BINS, MODE_DENSE (0/1), IDLE_GAP (cycles of forced idle after each bin),
//          DUMP_PATH/DUMP_LEVEL/DUMP_MODULE, SDF_ANNOTATE, GLS_PROGRESS, TIMEOUT_CYCLES, STAT_FILE.
module tb_bmi_snn;
  reg reset = 1;
`ifndef CLK_PERIOD_NS
  `define CLK_PERIOD_NS 25.0
`endif
  localparam real CLK_PERIOD_NS = `CLK_PERIOD_NS;
`ifdef REALTIME
  // Round 10: real-time presentation. The oscillator runs freely; the clock delivered to the core (clk = osc & clk_run) runs from
  // the start of a bin until the core is idle again and is stopped (low) for the rest of the 4 ms bin, as the front end's oscillator
  // enable does. clk_run changes only while osc is low, so the clock has no partial pulses.
  `ifndef BIN_NS
    `define BIN_NS 4000000
  `endif
  reg  osc = 0, clk_run = 1, rt_marker = 0;
  always #(CLK_PERIOD_NS / 2.0) osc = ~osc;
  wire clk = osc & clk_run;
  integer rt_bin = 0, rt_overrun = 0; reg [63:0] t_start = 0, t_bin = 0, t_end = 0, t_act_sum = 0, t_act_max = 0, t_act0 = 0;
`else
  reg clk = 0;
  always #(CLK_PERIOD_NS / 2.0) clk = ~clk;
`endif

`ifndef N_BINS
  `define N_BINS 100
`endif
`ifndef MODE_DENSE
  `define MODE_DENSE 0
`endif
`ifndef IDLE_GAP
  `define IDLE_GAP 64
`endif
`ifndef TIMEOUT_CYCLES
  `define TIMEOUT_CYCLES 200000000
`endif
`ifndef STREAM_HEX
  `define STREAM_HEX "stream.hex"
`endif
`ifndef EXPECT_HEX
  `define EXPECT_HEX "expect.hex"
`endif
`ifndef WEIGHTS_HEX
  `define WEIGHTS_HEX "weights.hex"
`endif
`ifndef MAX_TOKENS
  `define MAX_TOKENS 4000000
`endif
`ifndef THETA
  `define THETA 256
`endif
`ifndef K1
  `define K1 4
`endif
`ifndef K2
  `define K2 4
`endif

  reg         mode_dense = `MODE_DENSE;
  reg         ev_valid = 0;
  reg  [6:0]  ev_ch = 0;
  wire        ev_ready;
  reg         tick = 0;
  wire        tick_ready;
  wire        out_valid;
  wire [23:0] y0, y1;
  wire        busy, core_clk_en;

  reg         wr_en = 0;
  reg  [10:0] wr_addr = 0;
  reg  [31:0] wr_data = 0;
  wire        wr_ready;
`ifndef DUT
  `define DUT bmi_snn_top
`endif
`ifdef GLS
  `DUT u_dut (
`else
  `DUT #(.THETA(`THETA), .K1(`K1), .K2(`K2)) u_dut (
`endif
    .clk(clk), .reset(reset), .mode_dense(mode_dense),
    .ev_valid(ev_valid), .ev_ch(ev_ch), .ev_ready(ev_ready),
    .tick(tick), .tick_ready(tick_ready),
    .out_valid(out_valid), .y0(y0), .y1(y1), .busy(busy), .core_clk_en(core_clk_en),
    .wr_en(wr_en), .wr_addr(wr_addr), .wr_data(wr_data)
`ifdef HAS_WR_READY
    , .wr_ready(wr_ready)
`endif
  );
  reg [31:0] weights [0:2047];

  reg [7:0]  stream [0:`MAX_TOKENS-1];
  reg [31:0] expect_y [0:2*`N_BINS-1];

  integer cyc = 0, active_cyc = 0, cyc_meas0 = 0, active_meas0 = 0;
  always @(posedge clk) begin
    cyc = cyc + 1;
    if (core_clk_en === 1'b1) active_cyc = active_cyc + 1;
`ifdef GLS_PROGRESS
    if ((cyc % 20000) == 0) $display("GLS_PROGRESS cycle=%0d max=%0d", cyc, `TIMEOUT_CYCLES);
`endif
    if (cyc > `TIMEOUT_CYCLES) begin $display("FAIL: timeout"); $fatal(1); end
  end

  // output capture
  integer bin = 0, errors = 0, nev = 0, ntok = 0;
  integer lat_sum = 0, lat_max = 0, tick_cyc = 0;
  integer bin_cyc_start = 0, active_at_bin_start = 0;
  integer f_stat;
  reg got_out = 0;
  always @(posedge clk) begin
    if (out_valid === 1'b1) begin
      if (y0 !== expect_y[2*bin][23:0] || y1 !== expect_y[2*bin+1][23:0]) begin
        errors = errors + 1;
        if (errors <= 10)
          $display("MISMATCH bin %0d: got %h %h expected %h %h", bin, y0, y1,
                   expect_y[2*bin][23:0], expect_y[2*bin+1][23:0]);
      end
      if (cyc - tick_cyc > lat_max) lat_max = cyc - tick_cyc;
      lat_sum = lat_sum + (cyc - tick_cyc);
`ifdef STAT_FILE
      $fwrite(f_stat, "%0d %0d %0d %0d\n", bin, cyc - bin_cyc_start, active_cyc - active_at_bin_start, cyc - tick_cyc);
`endif
      bin = bin + 1;
      got_out = 1;
    end
  end

  integer i, k;
  reg [7:0] tok;
  initial begin
`ifdef SDF_ANNOTATE
    $sdf_annotate(`SDF_ANNOTATE, u_dut);
    $display("SDF: annotated %s onto u_dut", `SDF_ANNOTATE);
`endif
`ifdef DUMP_PATH
  `ifndef DUMP_AFTER_LOAD
  `ifndef REALTIME
    $dumpfile(`DUMP_PATH);
    $dumpvars(`DUMP_LEVEL, `DUMP_MODULE);
    $display("WAVEFORM: dumping to %s", `DUMP_PATH);
  `endif
  `endif
`endif
`ifdef STAT_FILE
    f_stat = $fopen(`STAT_FILE, "w");
`endif
    for (i = 0; i < `MAX_TOKENS; i = i + 1) stream[i] = 8'hFE;   // sentinel = end of stream
    $readmemh(`STREAM_HEX, stream);
    $readmemh(`EXPECT_HEX, expect_y);
`ifdef LOAD_BACKDOOR
    $readmemh(`WEIGHTS_HEX, u_dut.u_wmem.mem);
`endif
    $readmemh(`WEIGHTS_HEX, weights);
    $display("TB: mode_dense=%0d n_bins=%0d idle_gap=%0d clk=%0g ns", mode_dense, `N_BINS, `IDLE_GAP, CLK_PERIOD_NS);

    reset = 1'b1;
    repeat (20) @(posedge clk);
    @(negedge clk); reset = 1'b0;
    repeat (4) @(posedge clk);
`ifdef LOAD_PORT
    // load W1 rows 0..96 (words 0..1551) and W2 (words 1600..1663) through the 32-bit write port
    for (i = 0; i < 1664; i = i + 1) begin
      if (i < 1552 || i >= 1600) begin
        @(negedge clk); wr_en = 1'b1; wr_addr = i[10:0]; wr_data = weights[i];
`ifdef HAS_WR_READY
        @(posedge clk); while (wr_ready !== 1'b1) @(posedge clk);
`else
        @(posedge clk); while (core_clk_en !== 1'b1) @(posedge clk);
`endif
      end
    end
    @(negedge clk); wr_en = 1'b0;
    repeat (4) @(posedge clk);
    $display("TB: weights loaded through the write port at cycle %0d", cyc);
`endif
`ifdef DUMP_PATH
  `ifdef DUMP_AFTER_LOAD
  `ifndef REALTIME
    $dumpfile(`DUMP_PATH);
    $dumpvars(`DUMP_LEVEL, `DUMP_MODULE);
    $display("WAVEFORM: dumping to %s from cycle %0d", `DUMP_PATH, cyc);
  `endif
  `endif
`endif
`ifdef REALTIME
    // stop the clock after reset and weight load; the measured window starts at the next full clock period, T_start, and
    // lasts N_BINS x BIN_NS; the marker toggles at both ends so that the waveform spans exactly the window
    @(negedge osc); clk_run = 0;
    t_start = (($time / 64'd200) + 64'd2) * 64'd200; if (CLK_PERIOD_NS != 200.0) t_start = (($time / 64'd1000) + 64'd1) * 64'd1000;
    #(t_start - $time);
    rt_marker = ~rt_marker;
  `ifdef DUMP_PATH
    $dumpfile(`DUMP_PATH);
    $dumpvars(`DUMP_LEVEL, `DUMP_MODULE);
    $dumpvars(0, rt_marker);
    $display("WAVEFORM: dumping to %s from t=%0t (window start)", `DUMP_PATH, $time);
  `endif
    $display("RT: window start t=%0d ns, %0d bins of %0d ns, end t=%0d ns", t_start, `N_BINS, `BIN_NS, t_start + `N_BINS * `BIN_NS);
`endif
    cyc_meas0 = cyc; active_meas0 = active_cyc;
    bin_cyc_start = cyc; active_at_bin_start = active_cyc;

    i = 0;
`ifdef REALTIME
    // bin k: at T_start + k x BIN_NS start the clock, present the events one at a time and the tick, wait for the output and for the
    // core to be idle (clock enable low, not busy), then stop the clock until the next bin
    while (stream[i] != 8'hFE && bin < `N_BINS) begin
      t_bin = t_start + rt_bin * `BIN_NS;
      if ($time > t_bin) begin rt_overrun = rt_overrun + 1; if (rt_overrun <= 5) $display("RT OVERRUN: bin %0d not idle at its slot start (t=%0t > %0d)", rt_bin, $time, t_bin); end
      else #(t_bin - $time);
      @(negedge osc); clk_run = 1; t_act0 = $time;
      tok = stream[i];
      while (tok != 8'hFF && tok != 8'hFE) begin
        i = i + 1; ntok = ntok + 1; nev = nev + 1;
        @(negedge clk); ev_valid = 1'b1; ev_ch = tok[6:0];
        @(posedge clk); while (ev_ready !== 1'b1) @(posedge clk);
        @(negedge clk); ev_valid = 1'b0;
        tok = stream[i];
      end
      if (tok == 8'hFF) begin
        i = i + 1; ntok = ntok + 1;
        @(negedge clk); tick = 1'b1;
        @(posedge clk); while (tick_ready !== 1'b1) @(posedge clk);
        tick_cyc = cyc;
        @(negedge clk); tick = 1'b0;
        got_out = 0;
        while (!got_out) @(posedge clk);
        bin_cyc_start = cyc; active_at_bin_start = active_cyc;
      end
      @(posedge clk); while (!(core_clk_en === 1'b0 && busy === 1'b0)) @(posedge clk);
      repeat (2) @(posedge clk);                 // the clock gate closes in the low phase after the enable fell
      @(negedge osc); clk_run = 0;               // osc is low: clk stays low until the next bin
      t_act_sum = t_act_sum + ($time - t_act0); if ($time - t_act0 > t_act_max) t_act_max = $time - t_act0;
      rt_bin = rt_bin + 1;
    end
    t_end = t_start + `N_BINS * `BIN_NS;
    if ($time < t_end) #(t_end - $time);
    rt_marker = ~rt_marker;
    #1;
    $display("RT: bins=%0d clk_cycles_in_window=%0d active_ns_mean=%0d active_ns_max=%0d overruns=%0d window_ns=%0d", rt_bin, cyc - cyc_meas0, (rt_bin > 0) ? t_act_sum / rt_bin : 0, t_act_max, rt_overrun, t_end - t_start);
`else
    while (stream[i] != 8'hFE && bin < `N_BINS) begin
      tok = stream[i]; i = i + 1; ntok = ntok + 1;
      if (tok == 8'hFF) begin
        // end of bin: tick handshake
        @(negedge clk); tick = 1'b1;
        @(posedge clk); while (tick_ready !== 1'b1) @(posedge clk);
        tick_cyc = cyc;
        @(negedge clk); tick = 1'b0;
        got_out = 0;
        while (!got_out) @(posedge clk);
        bin_cyc_start = cyc; active_at_bin_start = active_cyc;
        for (k = 0; k < `IDLE_GAP; k = k + 1) @(posedge clk);
      end else begin
        nev = nev + 1;
        @(negedge clk); ev_valid = 1'b1; ev_ch = tok[6:0];
        @(posedge clk); while (ev_ready !== 1'b1) @(posedge clk);
        @(negedge clk); ev_valid = 1'b0;
      end
    end
    repeat (8) @(posedge clk);
`endif
`ifdef STAT_FILE
    $fclose(f_stat);
`endif
    $display("SUMMARY: bins=%0d events=%0d errors=%0d cycles=%0d active_cycles=%0d avg_latency_cyc=%0d max_latency_cyc=%0d",
             bin, nev, errors, cyc, active_cyc, (bin > 0) ? lat_sum / bin : 0, lat_max);
    $display("MEASURED: cycles_from_dump_start=%0d active_cycles_from_dump_start=%0d", cyc - cyc_meas0, active_cyc - active_meas0);
    if (errors == 0 && bin == `N_BINS) $display("PASS: %0d bins bit-exact", bin);
    else $display("FAIL: errors=%0d bins=%0d", errors, bin);
    $finish;
  end
endmodule
