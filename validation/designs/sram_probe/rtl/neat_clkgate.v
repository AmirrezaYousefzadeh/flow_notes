`timescale 1ns/1ps
// Integrated clock gate, the simulation model of the sky130 dlclkp cell: the enable is latched while the clock is low,
// so that the gated clock has no glitches. The examples instantiate the cell directly under synthesis (macro NEAT_ICG
// in neat_decoder.v, NEAT_SYNTH defined by the flow) and this module in RTL simulation; a design that instantiates this
// module itself gets the cell under synthesis.
module neat_clkgate (input wire clk, input wire en, output wire gclk);
`ifdef NEAT_SYNTH
  sky130_fd_sc_hd__dlclkp_4 u_icg (.CLK(clk), .GATE(en), .GCLK(gclk));
`else
  reg en_l;
  always @* if (!clk) en_l = en;
  assign gclk = clk & en_l;
`endif
endmodule
