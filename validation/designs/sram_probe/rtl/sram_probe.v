`timescale 1ns/1ps
// Test design for the macro flow (not a decoder of any merit): a linear read-out whose 96 x 2 int16 weights live in
// one SRAM22 block, loaded through the configuration port (word address = channel). Per bin: o += W[c] for every event
// (reading the macro once per event), leak by 1/16 at the tick, output the two accumulators.
`ifdef NEAT_SYNTH
  `define NEAT_ICG(name, c, e, g) sky130_fd_sc_hd__dlclkp_4 name (.CLK(c), .GATE(e), .GCLK(g));
`else
  `define NEAT_ICG(name, c, e, g) neat_clkgate name (.clk(c), .en(e), .gclk(g));
`endif
module neat_decoder (
  input  wire        clk,
  input  wire        reset,
  input  wire        cfg_valid,
  output wire        cfg_ready,
  input  wire [15:0] cfg_addr,
  input  wire [31:0] cfg_data,
  input  wire        ev_valid,
  output wire        ev_ready,
  input  wire [6:0]  ev_ch,
  input  wire        tick,
  output reg         out_valid,
  output wire [31:0] out_x,
  output wire [31:0] out_y,
  output wire        clk_req
);
  localparam [1:0] S_IDLE = 2'd0, S_READ = 2'd1, S_ADD = 2'd2, S_OUT = 2'd3;
  reg [1:0] state;
  reg       en_q, tick_q;
  reg signed [15:0] o0, o1;
  wire tick_take = (state == S_IDLE) & tick_q;
  wire en_d = reset | ev_valid | tick | tick_q | (state != S_IDLE) | out_valid | cfg_valid;
  always @(posedge clk) begin
    en_q <= en_d;
    if (reset) tick_q <= 1'b0; else if (tick) tick_q <= 1'b1; else if (tick_take) tick_q <= 1'b0;
  end
  assign clk_req = en_d | en_q;
  wire core_clk;
  `NEAT_ICG(u_icg_core, clk, en_q, core_clk)
  assign cfg_ready = (state == S_IDLE) & en_q;
  assign ev_ready  = (state == S_IDLE) & en_q & ~tick_q & ~cfg_valid;
  assign out_x = {{16{o0[15]}}, o0};
  assign out_y = {{16{o1[15]}}, o1};
  // the macro: written by configuration words, read by events (data valid one cycle after ce)
  wire        mem_we = cfg_valid & cfg_ready;
  wire        mem_ce = mem_we | (ev_valid & ev_ready);
  wire [10:0] mem_addr = mem_we ? cfg_addr[10:0] : {4'd0, ev_ch};
  wire [31:0] mem_dout;
  // the macro runs on the core clock; a larger design gives it a clock gate of its own (submissions/baseline)
  sram22_2048x32m8w8 u_mem (.clk(core_clk), .rstb(~reset), .ce(mem_ce), .we(mem_we), .wmask(4'hF), .addr(mem_addr),
                            .din(cfg_data), .dout(mem_dout));
  always @(posedge core_clk) begin
    if (reset) begin state <= S_IDLE; o0 <= 16'sd0; o1 <= 16'sd0; out_valid <= 1'b0; end
    else begin
      out_valid <= 1'b0;
      case (state)
        S_IDLE: if (tick_q) begin o0 <= o0 - (o0 >>> 4); o1 <= o1 - (o1 >>> 4); state <= S_OUT; end
                else if (ev_valid && ev_ready) state <= S_READ;
        S_READ: state <= S_ADD;                                   // the word read at the event arrives on dout
        S_ADD:  begin o0 <= o0 + $signed(mem_dout[15:0]); o1 <= o1 + $signed(mem_dout[31:16]); state <= S_IDLE; end
        S_OUT:  begin out_valid <= 1'b1; state <= S_IDLE; end
      endcase
    end
  end
endmodule
