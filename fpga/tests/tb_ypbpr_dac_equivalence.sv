`timescale 1ns/1ps
// Exercise reset, sync restarts, all levels, and abrupt colour/neutral changes.
module ypbpr_dac_pair #(parameter STAGGER=1)(output reg done=0);
 reg clk135=0,clk270=0,reset_n=0,line_start=0;
 reg [6:0] pb_level=64,pr_level=64,y_level=68;
 wire ay,apb,apr,by,bpb,bpr;
 always #4 clk135=~clk135;
 always #2 clk270=~clk270;
 coco_cvbs_ntsc_reference #(.COMPONENT_DAC_PHASE_STAGGER(STAGGER),
  .LUMA_SCANLINE_PHASE_ALTERNATION(1)) original(
  .clk135(clk135),.clk270(clk270),.reset_n(reset_n),.video_50hz(1'b0),
  .luma_out(ay),.component_pb_out(apb),.component_pr_out(apr));
 coco_cvbs_ntsc #(.COMPONENT_DAC_PHASE_STAGGER(STAGGER),
  .LUMA_SCANLINE_PHASE_ALTERNATION(1)) candidate(
  .clk135(clk135),.clk270(clk270),.reset_n(reset_n),.video_50hz(1'b0),
  .luma_out(by),.component_pb_out(bpb),.component_pr_out(bpr));
 integer tick;
 initial begin
  force original.component_pb_level_135=pb_level;
  force candidate.component_pb_level_135=pb_level;
  force original.component_pr_level_135=pr_level;
  force candidate.component_pr_level_135=pr_level;
  force original.luma_level_135=y_level;
  force candidate.luma_level_135=y_level;
  force original.dac_line_start=line_start;
  force candidate.dac_line_start=line_start;
  for(tick=0;tick<40000;tick=tick+1)begin
   @(negedge clk270);#0.1;
   if({ay,apb,apr}!=={by,bpb,bpr})
    $fatal(1,"YPbPr DAC changed waveform stagger=%0d tick=%0d",STAGGER,tick);
   reset_n=(tick%1000)>2;
   line_start=(tick%173)==0;
   pb_level=(tick%3)==0?7'd64:7'((tick*37)%128);
   pr_level=(tick%5)==0?7'd64:7'((tick*53)%128);
   y_level=7'((tick*17)%128);
  end
  done=1;
 end
endmodule
module tb_ypbpr_dac_equivalence;
 wire a,b;
 ypbpr_dac_pair #(.STAGGER(0)) legacy(a);
 ypbpr_dac_pair #(.STAGGER(1)) staggered(b);
 initial begin wait(a&&b);$display("YPbPr DAC equivalence PASS: both phase settings, resets, sync restarts and 80000 level transitions");$finish;end
 initial begin #200000;$fatal(1,"timeout");end
endmodule
