`timescale 1ns/1ps
// Define PHASE7_LEGACY_REFERENCE and provide the pre-change encoder renamed
// coco_cvbs_ntsc_reference to compare against the previously approved source.
`ifdef PHASE7_LEGACY_REFERENCE
 `define PHASE7_BASE coco_cvbs_ntsc_reference
`else
 `define PHASE7_BASE coco_cvbs_ntsc
`endif
module cvbs_phase_pair #(parameter RGB=0,PAL=0,FILTERS=1)(output reg done=0);
 reg clk135=0,clk270=0,reset_n=0,compatibility=0;
 always #4 clk135=~clk135;
 always #2 clk270=~clk270;
 reg [5:0] color=0;
 wire ay,ac,av,ab,ar,by,bc,bv,bb,br;
 wire [9:0] ax,bx;
 wire [7:0] arow,brow,ap,bp;
 wire active_a,active_b,pv_a,pv_b;
 `PHASE7_BASE #(.CANONICAL_640_INPUT(1),.RGB_SOG_OUTPUT(RGB),
  .PAL_CHROMA_OUTPUT(PAL),.CVBS_CHROMA_FILTER(FILTERS),.CVBS_LUMA_FILTER(FILTERS),
  .CVBS_LUMA_NOTCH(FILTERS),.CVBS_SVIDEO_SCANLINE_PHASE_ALTERNATION(1)) baseline(
  .clk135(clk135),.clk270(clk270),.reset_n(reset_n),.video_50hz(1'b0),
  .high_resolution(1'b1),.compatibility_mode(compatibility),.active_height(8'd192),
  .framebuffer_data(color),.border_rgb(6'd0),.row_border_valid(1'b0),
  .vertical_border_valid(1'b0),.luma_out(ay),.chroma_out(ac),.cvbs_out(av),
  .component_pb_out(ab),.component_pr_out(ar),.source_x(ax),.source_y(arow),
  .source_valid(active_a),.prefetch_y(ap),.prefetch_valid(pv_a));
 coco_cvbs_ntsc #(.CVBS_FIELD_PHASE_ALIGN(1),.CANONICAL_640_INPUT(1),
  .RGB_SOG_OUTPUT(RGB),.PAL_CHROMA_OUTPUT(PAL),.CVBS_CHROMA_FILTER(FILTERS),
  .CVBS_LUMA_FILTER(FILTERS),.CVBS_LUMA_NOTCH(FILTERS),
  .CVBS_SVIDEO_SCANLINE_PHASE_ALTERNATION(1)) aligned(
  .clk135(clk135),.clk270(clk270),.reset_n(reset_n),.video_50hz(1'b0),
  .high_resolution(1'b1),.compatibility_mode(compatibility),.active_height(8'd192),
  .framebuffer_data(color),.border_rgb(6'd0),.row_border_valid(1'b0),
  .vertical_border_valid(1'b0),.luma_out(by),.chroma_out(bc),.cvbs_out(bv),
  .component_pb_out(bb),.component_pr_out(br),.source_x(bx),.source_y(brow),
  .source_valid(active_b),.prefetch_y(bp),.prefetch_valid(pv_b));
 integer mode,phase,tick,changed,chroma_sum;
 initial begin
  for(mode=0;mode<2;mode=mode+1)
   for(phase=0;phase<2;phase=phase+1)begin
    reset_n=0;compatibility=mode;color=0;
    repeat(4)@(negedge clk135);
    force baseline.h_sample=0;force baseline.sample_phase=0;force baseline.v_line=0;
    force aligned.h_sample=0;force aligned.sample_phase=0;force aligned.v_line=0;
    if(phase)begin
     force baseline.carrier_octant=3'd4;force aligned.carrier_octant=3'd4;
    end else begin
     force baseline.carrier_octant=3'd0;force aligned.carrier_octant=3'd0;
    end
    reset_n=1;repeat(3)@(negedge clk135);
    if(!RGB&&!PAL && aligned.cvbs_phase_flip!==phase[0])
     $fatal(1,"Field phase was not captured");
    release baseline.carrier_octant;release aligned.carrier_octant;
    release baseline.h_sample;release baseline.sample_phase;release baseline.v_line;
    release aligned.h_sample;release aligned.sample_phase;release aligned.v_line;
    force baseline.v_line=45;force aligned.v_line=45;
    changed=0;
    for(tick=0;tick<9000;tick=tick+1)begin
     @(negedge clk135);color=(tick/120)%64;
     if({ax,arow,active_a,ap,pv_a,baseline.sync_tip}!==
        {bx,brow,active_b,bp,pv_b,aligned.sync_tip})
      $fatal(1,"Phase option changed raster/read scheduling");
     if(tick>20)begin
      if(FILTERS==0 && aligned.cvbs_unfiltered_picture_chroma!==
          aligned.rgb_chroma(aligned.mod_x4,aligned.pal_picture_y4,
              aligned.pal_picture_sum3,aligned.pal_picture_difference3,
              aligned.cvbs_mod_carrier))
       $fatal(1,"Shared-matrix phase correction changed rounding");
      if({ay,ac}!=={by,bc})$fatal(1,"Phase option changed S-Video Y/C");
      if((RGB||PAL) && {ay,ac,av,ab,ar}!=={by,bc,bv,bb,br})
       $fatal(1,"Phase option changed RGB/PAL output");
      if(!RGB&&!PAL)begin
       if(phase==0 && aligned.mod_selected_chroma!==baseline.mod_selected_chroma)
        $fatal(1,"Zero phase unexpectedly changed chroma");
       // Arithmetic right shift rounds negative chroma down: opposite
       // carrier phases sum to zero or minus one quantization step.
       chroma_sum=$signed(aligned.mod_selected_chroma)+$signed(baseline.mod_selected_chroma);
       if(phase==1 && (chroma_sum>0 || chroma_sum< -1))
        $fatal(1,"Composite chroma did not reverse: sum=%0d",chroma_sum);
       if(av!==bv)changed=changed+1;
      end
     end
    end
    if(!RGB&&!PAL&&phase==1&&changed==0)$fatal(1,"CVBS correction had no effect");
    release baseline.v_line;release aligned.v_line;
   end
  $display("Field phase PASS RGB=%0d PAL=%0d FILTERS=%0d: waveform isolation, both phases and display modes",RGB,PAL,FILTERS);
  done=1;
 end
endmodule
module tb_cvbs_field_phase;
 wire cvbs_done,rgb_done,pal_done,raw_done;
 cvbs_phase_pair cvbs(cvbs_done);
 cvbs_phase_pair #(.FILTERS(0)) raw_cvbs(raw_done);
 cvbs_phase_pair #(.RGB(1)) rgb(rgb_done);
 cvbs_phase_pair #(.PAL(1)) pal(pal_done);
 initial begin wait(cvbs_done&&rgb_done&&pal_done&&raw_done);$display("tb_cvbs_field_phase PASS");$finish;end
 initial begin #1000000;$fatal(1,"timeout");end
endmodule
`undef PHASE7_BASE
