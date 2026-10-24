// Behavioural ASAP7 sequential cells for SDF-annotated gate-level simulation with Icarus (round 5, E5).
// The vendor models (asap7sc7p5t_SEQ_*_TT) build the flip-flops from UDPs with a notifier and clock the UDP from the delayed_* nets
// of $setuphold timing checks; Icarus implements neither, so the state never leaves X once the specify blocks are enabled.
// These modules keep the pin names and the IOPATH paths of the vendor cells (SDF from OpenSTA write_sdf: CLK -> QN, CLK -> GCLK).
`timescale 1ns/10ps

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
