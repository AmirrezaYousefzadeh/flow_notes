`timescale 1ns/1ps
// NEAT BMI decoder challenge: the testbench, for RTL and gate-level simulation.
//
// Real-time presentation of a token stream: bin k starts at T0 + k x BIN_NS. The events of the bin are offered one at a
// time through the valid/ready handshake (ascending channel id, one idle cycle after each accepted event), then the tick
// is pulsed for one cycle. The clock runs from the bin start until the design has produced out_valid and released
// clk_req (plus two cycles), then it is stopped low until the next bin; a design that keeps clk_req high keeps its clock.
// Per bin one line "<bin> <x> <y> <latency_ns>" goes to OUT_FILE. A bin whose output arrives after the start of the next
// bin is an overrun: the real-time requirement fails.
//
// Before the window: reset with the clock running, then, if LOAD_HEX is defined, the configuration image is written
// through the configuration port in ascending address order (at most LOAD_CYCLES cycles), and the design must release
// clk_req within RELEASE_CYCLES cycles after the last word. The load is outside the measurement window.
//
// Defines (all optional):
//   CLK_PERIOD_NS (200.0)  BIN_NS (4000000)  N_BINS (0 = the whole stream)  STREAM_HEX  OUT_FILE
//   LOAD_HEX (the configuration image, $readmemh format: "@address data" lines)
//   MAX_TOKENS (1500000)  RESET_CYCLES (20)  LOAD_CYCLES (1000000)  RELEASE_CYCLES (1024)
//   TIMEOUT_BINS (2: no output, or an event not accepted, within 2 bins = failure)
//   SDF_ANNOTATE (SDF file of a routed netlist)  PROGRESS (a line every 1000 bins)
//   DUMP_PATH / DUMP_LEVEL / DUMP_MODULE (waveform from the window start, e.g. into a FIFO for the toggle counter)
module tb_neat;
`ifndef CLK_PERIOD_NS
  `define CLK_PERIOD_NS 200.0
`endif
`ifndef BIN_NS
  `define BIN_NS 4000000
`endif
`ifndef N_BINS
  `define N_BINS 0
`endif
`ifndef MAX_TOKENS
  `define MAX_TOKENS 1500000
`endif
`ifndef RESET_CYCLES
  `define RESET_CYCLES 20
`endif
`ifndef LOAD_CYCLES
  `define LOAD_CYCLES 1000000
`endif
`ifndef RELEASE_CYCLES
  `define RELEASE_CYCLES 1024
`endif
`ifndef TIMEOUT_BINS
  `define TIMEOUT_BINS 2
`endif
`ifndef STREAM_HEX
  `define STREAM_HEX "stream.hex"
`endif
`ifndef OUT_FILE
  `define OUT_FILE "out.txt"
`endif
`ifndef DUMP_MODULE
  `define DUMP_MODULE tb_neat.u_dut
`endif
`ifndef DUMP_LEVEL
  `define DUMP_LEVEL 0
`endif
  localparam real CP  = `CLK_PERIOD_NS;
  localparam real BIN = `BIN_NS;

  // ---- clock: a free-running oscillator gated by clk_run, which changes only while the oscillator is low
  reg  osc = 1'b0;
  always #(CP / 2.0) osc = ~osc;
  reg  clk_run = 1'b1;
  wire clk = osc & clk_run;
  reg  rt_marker = 1'b0;                // toggles at both ends of the measurement window (for the toggle counter)

  // ---- the design under test (RTL or routed netlist): the ports of INTERFACE.md
  reg         reset = 1'b1;
  reg         cfg_valid = 1'b0;
  reg  [15:0] cfg_addr = 16'd0;
  reg  [31:0] cfg_data = 32'd0;
  wire        cfg_ready;
  reg         ev_valid = 1'b0;
  reg  [6:0]  ev_ch = 7'd0;
  wire        ev_ready;
  reg         tick = 1'b0;
  wire        out_valid;
  wire [31:0] out_x, out_y;
  wire        clk_req;
  neat_decoder u_dut (
    .clk(clk), .reset(reset),
    .cfg_valid(cfg_valid), .cfg_ready(cfg_ready), .cfg_addr(cfg_addr), .cfg_data(cfg_data),
    .ev_valid(ev_valid), .ev_ready(ev_ready), .ev_ch(ev_ch), .tick(tick),
    .out_valid(out_valid), .out_x(out_x), .out_y(out_y), .clk_req(clk_req));

  // ---- state of the run
  reg  [7:0]  stream [0:`MAX_TOKENS-1];
  reg  [31:0] image [0:65535];
  integer     f_out, i, k, a, n_total, n_bins, bin, nev, overruns, n_words, wait_cycles;
  reg  [63:0] cyc, cyc_win0, cyc_load0;
  real        t_start, t_bin, t_next, t_tick, t_out, t_end, t_act0, t_act, t_act_max, lat_max, lat_sum;
  reg  [7:0]  tok;
  reg         got_out;
  reg  [31:0] x_cap, y_cap;

  always @(posedge clk) cyc = cyc + 1;
  // the output of a bin: sampled at the clock edge that ends the out_valid cycle
  always @(posedge clk) if (out_valid === 1'b1) begin got_out = 1'b1; t_out = $realtime; x_cap = out_x; y_cap = out_y; end

  initial begin
    cyc = 0; bin = 0; nev = 0; overruns = 0; lat_max = 0.0; lat_sum = 0.0; t_act = 0.0; t_act_max = 0.0;
    got_out = 1'b0;
    for (i = 0; i < `MAX_TOKENS; i = i + 1) stream[i] = 8'hFE;   // FE = end of stream, FF = tick, else an event
    $readmemh(`STREAM_HEX, stream);
    if (stream[`MAX_TOKENS-1] !== 8'hFE) begin
      $display("FAIL: the stream is longer than MAX_TOKENS (%0d); rerun with a larger -DMAX_TOKENS", `MAX_TOKENS);
      $finish;
    end
    n_total = 0;
    for (i = 0; i < `MAX_TOKENS; i = i + 1) if (stream[i] == 8'hFF) n_total = n_total + 1;
    if (n_total == 0) begin
      $display("FAIL: no bins in the stream %s (missing or empty file)", `STREAM_HEX);
      $finish;
    end
    n_bins = (`N_BINS == 0 || `N_BINS > n_total) ? n_total : `N_BINS;
    f_out = $fopen(`OUT_FILE, "w");
    $display("TB: clock %0.3f ns, bin %0.0f ns, %0d bins of %0d in the stream, stream %s", CP, BIN, n_bins, n_total,
             `STREAM_HEX);
`ifdef SDF_ANNOTATE
    $sdf_annotate(`SDF_ANNOTATE, u_dut);
    $display("TB: SDF %s annotated", `SDF_ANNOTATE);
`endif

    // ---- reset with the clock running
    reset = 1'b1;
    repeat (`RESET_CYCLES) @(posedge clk);
    @(negedge clk); reset = 1'b0;
    repeat (4) @(posedge clk);

`ifdef LOAD_HEX
    // ---- configuration: every word of the image through the port, ascending addresses, then wait for clk_req low
    for (a = 0; a < 65536; a = a + 1) image[a] = 32'bx;
    $readmemh(`LOAD_HEX, image);
    n_words = 0; cyc_load0 = cyc;
    for (a = 0; a < 65536; a = a + 1) begin
      if (image[a] !== 32'bx) begin
        @(negedge clk); cfg_valid = 1'b1; cfg_addr = a[15:0]; cfg_data = image[a];
        @(posedge clk);
        while (cfg_ready !== 1'b1) begin
          @(posedge clk);
          if (cyc - cyc_load0 > `LOAD_CYCLES) begin
            $display("FAIL: the configuration load takes more than %0d cycles", `LOAD_CYCLES); $finish;
          end
        end
        n_words = n_words + 1;
      end
    end
    @(negedge clk); cfg_valid = 1'b0;
    wait_cycles = 0;
    while (clk_req !== 1'b0) begin
      @(posedge clk); wait_cycles = wait_cycles + 1;
      if (wait_cycles > `RELEASE_CYCLES) begin
        $display("FAIL: clk_req still high %0d cycles after the configuration load", `RELEASE_CYCLES); $finish;
      end
    end
    repeat (4) @(posedge clk);
    $display("TB: %0d configuration words loaded from %s in %0d cycles", n_words, `LOAD_HEX, cyc - cyc_load0);
`endif

    // ---- the measurement window
    @(negedge osc); clk_run = 1'b0;
    t_start = $realtime + 2.0 * CP;
    #(t_start - $realtime);
    rt_marker = ~rt_marker; cyc_win0 = cyc;
`ifdef DUMP_PATH
    $dumpfile(`DUMP_PATH);
    $dumpvars(`DUMP_LEVEL, `DUMP_MODULE);
    $dumpvars(0, rt_marker);
    $display("TB: waveform %s from t=%0t (window start)", `DUMP_PATH, $realtime);
`endif
    $display("TB: window start t=%0.0f ns, %0d bins, end t=%0.0f ns", t_start, n_bins, t_start + n_bins * BIN);
    i = 0;
    for (k = 0; k < n_bins; k = k + 1) begin
      t_bin = t_start + k * BIN; t_next = t_bin + BIN;
      if ($realtime < t_bin) #(t_bin - $realtime);
      if (clk_run == 1'b0) begin @(negedge osc); clk_run = 1'b1; end
      t_act0 = $realtime;
      // the events of the bin
      tok = stream[i];
      while (tok != 8'hFF && tok != 8'hFE) begin
        i = i + 1; nev = nev + 1;
        @(negedge clk); ev_valid = 1'b1; ev_ch = tok[6:0];
        @(posedge clk);
        while (ev_ready !== 1'b1) begin
          @(posedge clk);
          if ($realtime > t_bin + `TIMEOUT_BINS * BIN) begin
            $display("FAIL: an event of bin %0d was not accepted within %0d bins", k, `TIMEOUT_BINS);
            $fclose(f_out); $finish;
          end
        end
        @(negedge clk); ev_valid = 1'b0;
        tok = stream[i];
      end
      if (tok == 8'hFE) begin $display("TB: stream ended before bin %0d", k); k = n_bins; end
      else begin
        i = i + 1;
        // the tick: a one-cycle pulse, accepted unconditionally
        @(negedge clk); tick = 1'b1;
        @(posedge clk); t_tick = $realtime;
        @(negedge clk); tick = 1'b0;
        got_out = 1'b0;
        while (!got_out) begin
          @(posedge clk);
          if ($realtime > t_tick + `TIMEOUT_BINS * BIN) begin
            $display("FAIL: no output within %0d bins after the tick of bin %0d", `TIMEOUT_BINS, k);
            $fclose(f_out); $finish;
          end
        end
        $fwrite(f_out, "%0d %0d %0d %0.0f\n", k, $signed(x_cap), $signed(y_cap), t_out - t_tick);
        if (t_out - t_tick > lat_max) lat_max = t_out - t_tick;
        lat_sum = lat_sum + (t_out - t_tick);
        if (t_out >= t_next) begin
          overruns = overruns + 1;
          if (overruns <= 5) $display("TB: OVERRUN bin %0d: output at %0.0f ns, next bin at %0.0f ns", k, t_out, t_next);
        end
        bin = bin + 1;
        // let the design release the clock; keep it running if it does not (until shortly before the next bin)
        while (clk_req !== 1'b0 && $realtime < t_next - 4.0 * CP) @(posedge clk);
        if (clk_req === 1'b0) begin
          repeat (2) @(posedge clk);
          @(negedge osc); clk_run = 1'b0;
        end
        t_act = t_act + ($realtime - t_act0);
        if ($realtime - t_act0 > t_act_max) t_act_max = $realtime - t_act0;
`ifdef PROGRESS
        if ((k + 1) % 1000 == 0)
          $display("TB: bin %0d of %0d (t=%0.1f ms, overruns %0d)", k + 1, n_bins, $realtime / 1.0e6, overruns);
`endif
      end
    end
    t_end = t_start + n_bins * BIN;
    if ($realtime < t_end) #(t_end - $realtime);
    rt_marker = ~rt_marker;
    #1;
    $fclose(f_out);
    $display({"RT: bins=%0d events=%0d overruns=%0d clk_cycles_in_window=%0d window_ns=%0.0f active_ns_mean=%0.0f ",
              "active_ns_max=%0.0f latency_ns_mean=%0.0f latency_ns_max=%0.0f"},
             bin, nev, overruns, cyc - cyc_win0, t_end - t_start, (bin > 0) ? t_act / bin : 0.0, t_act_max,
             (bin > 0) ? lat_sum / bin : 0.0, lat_max);
    if (bin == n_bins && overruns == 0) $display("PASS: %0d bins, real time met", bin);
    else $display("FAIL: bins=%0d of %0d, overruns=%0d", bin, n_bins, overruns);
    $finish;
  end
endmodule
