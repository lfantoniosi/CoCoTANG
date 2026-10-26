`timescale 1ns/1ps
// At 8580 clocks per line the DDS advances 1820 octants: four modulo eight.
// Skip only even numbers of lines, preserving the real DDS/field phase.
module tb_cvbs_field_cadence;
 reg clk135=0,clk270=0,reset_n=0,checking=0;
 always #4 clk135=~clk135;
 always #2 clk270=~clk270;
 wire ay,ac,by,bc;
 wire [9:0] ax,bx;
 wire [7:0] ar,br,ap,bp;
 wire av,bv,apv,bpv;
 coco_cvbs_ntsc #(.CANONICAL_640_INPUT(1),.CVBS_INCREMENTAL_DOTS(1),
  .LUMA_DAC_EVEN_LEVELS(1),.LUMA_SCANLINE_PHASE_ALTERNATION(1),
  .CVBS_SVIDEO_SCANLINE_PHASE_ALTERNATION(1)) continuous(
  .clk135(clk135),.clk270(clk270),.reset_n(reset_n),.video_50hz(1'b0),
  .high_resolution(1'b1),.compatibility_mode(1'b0),.active_height(8'd225),
  .framebuffer_data(6'h24),.border_rgb(6'h09),.row_border_valid(1'b0),
  .vertical_border_valid(1'b0),.luma_out(ay),.chroma_out(ac),
  .source_x(ax),.source_y(ar),.source_valid(av),.prefetch_y(ap),.prefetch_valid(apv));
 coco_cvbs_ntsc #(.CANONICAL_640_INPUT(1),.CVBS_INCREMENTAL_DOTS(1),
  .CVBS_FIELD_PHASE_ALIGN(1),.LUMA_DAC_EVEN_LEVELS(1),
  .LUMA_SCANLINE_PHASE_ALTERNATION(1),.CVBS_SVIDEO_SCANLINE_PHASE_ALTERNATION(1)) aligned(
  .clk135(clk135),.clk270(clk270),.reset_n(reset_n),.video_50hz(1'b0),
  .high_resolution(1'b1),.compatibility_mode(1'b0),.active_height(8'd225),
  .framebuffer_data(6'h24),.border_rgb(6'h09),.row_border_valid(1'b0),
  .vertical_border_valid(1'b0),.luma_out(by),.chroma_out(bc),
  .source_x(bx),.source_y(br),.source_valid(bv),.prefetch_y(bp),.prefetch_valid(bpv));
 always @(negedge clk270)if(checking)begin
  #0.1;
  if({ay,ac}!=={by,bc})$fatal(1,"Field wrap changed continuous S-Video");
 end
 always @(negedge clk135)if(checking)begin
  #0.1;
  if({ax,ar,av,ap,apv}!=={bx,br,bv,bp,bpv})$fatal(1,"Field wrap changed raster requests");
 end
 integer field;
 reg expected_flip;
 initial begin
  repeat(4)@(negedge clk135);
  // Reset starts at line17. Advancing to261 skips244 complete lines, an
  // even number, so retaining the DDS state is exact modulo its period.
  continuous.v_line=261;aligned.v_line=261;reset_n=1;checking=1;
  for(field=0;field<4;field=field+1)begin
   wait(aligned.v_line==0&&aligned.h_sample==0&&aligned.sample_phase==0);
   @(posedge clk135);#0.1;
   expected_flip=(field==0||field==3);
   if(aligned.cvbs_phase_flip!==expected_flip)$fatal(1,"Wrong real field-phase sequence field=%0d flip=%0d",field,aligned.cvbs_phase_flip);
   if((aligned.carrier_octant^{aligned.cvbs_phase_flip,2'b00})!==3'd0)
    $fatal(1,"Composite field origin is not stationary");
   if(continuous.carrier_octant!==aligned.carrier_octant ||
      continuous.carrier_fraction!==aligned.carrier_fraction)
    $fatal(1,"Phase alignment reset the underlying DDS");
   @(negedge clk135);
   // Next fields are naturally 263,262,263 lines. Skip260 whole lines
   // while retaining parity, sample phase, fractional residue and octant.
   continuous.v_line=260;aligned.v_line=260;
  end
  $display("CVBS field cadence PASS: real alternating field wraps, stationary composite origin, continuous S-Video and unchanged DDS/raster");
  $finish;
 end
 initial begin #1000000;$fatal(1,"timeout");end
endmodule
