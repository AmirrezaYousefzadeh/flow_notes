// Behavioural ASAP7 sequential cells for SDF-annotated gate-level simulation with Icarus (ASAP7 notes 8.1).
// The vendor models (asap7sc7p5t_SEQ_*_TT) build the flip-flops from UDPs with an uninitialised notifier and $setuphold
// timing checks; in annotated Icarus runs their state stayed X. These modules keep the pin names and the IOPATH paths of
// the vendor cells (SDF from OpenSTA write_sdf: CLK -> QN, CLK -> GCLK). Precision 1 ps: with the vendor 10 ps, the
// annotated delays (5-45 ps) are rounded to 10 ps steps; give the vendor models you compile with these the same 1 ps.
`timescale 1ns/1ps

module DFFHQNx1_ASAP7_75t_R (QN, D, CLK);
  output QN; input D, CLK; reg QN;
  always @(posedge CLK) QN <= ~D;
  specify
    (CLK => QN) = (0, 0);
  endspecify
endmodule

module DFFHQNx2_ASAP7_75t_R (QN, D, CLK);
  output QN; input D, CLK; reg QN;
  always @(posedge CLK) QN <= ~D;
  specify
    (CLK => QN) = (0, 0);
  endspecify
endmodule

module DFFHQNx3_ASAP7_75t_R (QN, D, CLK);
  output QN; input D, CLK; reg QN;
  always @(posedge CLK) QN <= ~D;
  specify
    (CLK => QN) = (0, 0);
  endspecify
endmodule

module ICGx1_ASAP7_75t_R (GCLK, ENA, SE, CLK);
  output GCLK; input ENA, SE, CLK; reg en_l;
  always @(CLK or ENA or SE) if (!CLK) en_l = ENA | SE;
  assign GCLK = CLK & en_l;
  specify
    (CLK => GCLK) = (0, 0);
    if (~ENA & ~SE) (CLK => GCLK) = (0, 0);
    if (ENA | (~ENA & SE)) (CLK => GCLK) = (0, 0);
  endspecify
endmodule

module DHLx1_ASAP7_75t_R (Q, D, CLK);
  output Q; input D, CLK; reg Q;
  always @(CLK or D) if (CLK) Q = D;
  specify
    (CLK => Q) = (0, 0);
    (D => Q) = (0, 0);
  endspecify
endmodule

module DFFHQNx1_ASAP7_75t_SRAM (QN, D, CLK);
  output QN; input D, CLK; reg QN;
  always @(posedge CLK) QN <= ~D;
  specify
    (CLK => QN) = (0, 0);
  endspecify
endmodule

module DFFHQNx2_ASAP7_75t_SRAM (QN, D, CLK);
  output QN; input D, CLK; reg QN;
  always @(posedge CLK) QN <= ~D;
  specify
    (CLK => QN) = (0, 0);
  endspecify
endmodule

module DFFHQNx3_ASAP7_75t_SRAM (QN, D, CLK);
  output QN; input D, CLK; reg QN;
  always @(posedge CLK) QN <= ~D;
  specify
    (CLK => QN) = (0, 0);
  endspecify
endmodule

module ICGx1_ASAP7_75t_SRAM (GCLK, ENA, SE, CLK);
  output GCLK; input ENA, SE, CLK; reg en_l;
  always @(CLK or ENA or SE) if (!CLK) en_l = ENA | SE;
  assign GCLK = CLK & en_l;
  specify
    (CLK => GCLK) = (0, 0);
    if (~ENA & ~SE) (CLK => GCLK) = (0, 0);
    if (ENA | (~ENA & SE)) (CLK => GCLK) = (0, 0);
  endspecify
endmodule

module DHLx1_ASAP7_75t_SRAM (Q, D, CLK);
  output Q; input D, CLK; reg Q;
  always @(CLK or D) if (CLK) Q = D;
  specify
    (CLK => Q) = (0, 0);
    (D => Q) = (0, 0);
  endspecify
endmodule

module ICGx2_ASAP7_75t_R (GCLK, ENA, SE, CLK);
  output GCLK; input ENA, SE, CLK; reg en_l;
  always @(CLK or ENA or SE) if (!CLK) en_l = ENA | SE;
  assign GCLK = CLK & en_l;
  specify
    (CLK => GCLK) = (0, 0);
    if (~ENA & ~SE) (CLK => GCLK) = (0, 0);
    if (ENA | (~ENA & SE)) (CLK => GCLK) = (0, 0);
  endspecify
endmodule

module ICGx2_ASAP7_75t_SRAM (GCLK, ENA, SE, CLK);
  output GCLK; input ENA, SE, CLK; reg en_l;
  always @(CLK or ENA or SE) if (!CLK) en_l = ENA | SE;
  assign GCLK = CLK & en_l;
  specify
    (CLK => GCLK) = (0, 0);
    if (~ENA & ~SE) (CLK => GCLK) = (0, 0);
    if (ENA | (~ENA & SE)) (CLK => GCLK) = (0, 0);
  endspecify
endmodule
