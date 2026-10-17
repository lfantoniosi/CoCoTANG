`timescale 1ns/1ps
// RGB dot timing must preserve every canonical dot, both borders, and the
// producer's existing line/field identity while narrowing the active body.
module tb_rgb_coco_aperture;
 reg clk=0,reset_n=0,compatibility=0;
 always #4 clk=~clk;
 wire [9:0] source_x;
 wire [7:0] source_y,prefetch_y,old_y,old_prefetch_y;
 wire valid,prefetch_valid,old_valid,old_prefetch_valid;
 coco_cvbs_ntsc #(.CANONICAL_640_INPUT(1),.RGB_SOG_OUTPUT(1)) dut(
  .clk135(clk),.clk270(clk),.reset_n(reset_n),.video_50hz(1'b0),
  .high_resolution(1'b1),.compatibility_mode(compatibility),
  .active_height(8'd192),.framebuffer_data(6'h3f),.border_rgb(6'd0),
  .row_border_valid(1'b0),.vertical_border_valid(1'b0),
  .source_x(source_x),.source_y(source_y),.source_valid(valid),
  .prefetch_y(prefetch_y),.prefetch_valid(prefetch_valid));
 coco_cvbs_ntsc #(.CANONICAL_640_INPUT(1),.RGB_SOG_OUTPUT(1),
                  .RGB_COCO_APERTURE(0)) original(
  .clk135(clk),.clk270(clk),.reset_n(reset_n),.video_50hz(1'b0),
  .high_resolution(1'b1),.compatibility_mode(compatibility),
  .active_height(8'd192),.framebuffer_data(6'h3f),.border_rgb(6'd0),
  .row_border_valid(1'b0),.vertical_border_valid(1'b0),
  .source_y(old_y),.source_valid(old_valid),
  .prefetch_y(old_prefetch_y),.prefetch_valid(old_prefetch_valid));
 integer mode,ticks,previous_x,dot_ticks,dots,total_ticks,old_ticks;
 integer first_tick,last_tick,first_h_tick;
 integer standard,odd,scanline,position,line_count,sample_position;
 initial begin
  for(mode=0;mode<2;mode=mode+1)begin
   reset_n=0;compatibility=mode;
   repeat(4)@(negedge clk);
   force dut.h_sample=0;force dut.sample_phase=0;force dut.v_line=45;
   force original.h_sample=0;force original.sample_phase=0;force original.v_line=45;
   reset_n=1;
   @(negedge clk);
   release dut.h_sample;release dut.sample_phase;release dut.v_line;
   release original.h_sample;release original.sample_phase;release original.v_line;
   previous_x=-1;dot_ticks=0;dots=0;total_ticks=0;old_ticks=0;
   first_tick=-1;last_tick=-1;
   for(ticks=0;ticks<8580;ticks=ticks+1)begin
    @(negedge clk);
    if(dut.h_sample!==original.h_sample||dut.sample_phase!==original.sample_phase||
       dut.v_line!==original.v_line||dut.sync_tip!==original.sync_tip||
       source_y!==old_y||prefetch_y!==old_prefetch_y||prefetch_valid!==old_prefetch_valid)
     $fatal(1,"RGB aperture changed sync or renderer row scheduling");
    if(old_valid)old_ticks=old_ticks+1;
    if(valid)begin
     if(first_tick<0)begin
      first_tick=ticks;first_h_tick=dut.h_sample*10+dut.sample_phase;
     end
     last_tick=ticks;
     total_ticks=total_ticks+1;
     if(source_x!=previous_x)begin
      if(source_x!=previous_x+1)$fatal(1,"RGB skipped/repeated a source dot: %0d -> %0d",previous_x,source_x);
      if(previous_x>=0 && (dot_ticks<(mode?7:9)||dot_ticks>(mode?8:10)))
       $fatal(1,"RGB dot duration %0d",dot_ticks);
      dots=dots+1;previous_x=source_x;dot_ticks=0;
     end
     dot_ticks=dot_ticks+1;
    end
   end
   if(dots!=640||previous_x!=639||total_ticks!=(mode?4828:6035)||old_ticks!=(mode?5120:6400))
    $fatal(1,"RGB geometry mode=%0d dots=%0d duration=%0d old=%0d",mode,dots,total_ticks,old_ticks);
   if(first_h_tick!=(mode?2292:1689))$fatal(1,"RGB left edge %0d",first_h_tick);
   if(dot_ticks<(mode?7:9)||dot_ticks>(mode?8:10))$fatal(1,"last RGB dot duration");
   $display("RGB compatibility=%0d: all 640 dots, %0d clk135 ticks (old %0d), sync/prefetch unchanged PASS",mode,total_ticks,old_ticks);
  end
  // Compare the shifted RGB sync against the old waveform at line N+2,
  // including wrap across short/long fields at both video standards.
  for(standard=0;standard<2;standard=standard+1)begin
   force dut.video_50hz_active=standard;
   force dut.video_50hz_sync=standard;
   force original.video_50hz_active=standard;
   force original.video_50hz_sync=standard;
   for(odd=0;odd<2;odd=odd+1)begin
    force dut.field_odd=odd;force original.field_odd=odd;
    line_count=(standard?312:262)+odd;
    for(scanline=0;scanline<line_count;scanline=scanline+1)begin
     for(position=0;position<7;position=position+1)begin
      case(position)
       0:sample_position=0;1:sample_position=31;2:sample_position=32;
       3:sample_position=100;4:sample_position=427;5:sample_position=432;
       default:sample_position=800;
      endcase
      force dut.h_sample=sample_position;force original.h_sample=sample_position;
      force dut.sample_phase=0;force original.sample_phase=0;
      @(negedge clk);dut.v_line=scanline;original.v_line=(scanline+2)%line_count;
      repeat(2)@(negedge clk);
      if(dut.sync_tip!==original.sync_tip ||
         dut.rgb_equalizing!==(original.v_line<3 || (original.v_line>=6&&original.v_line<9)) ||
         dut.rgb_broad_sync!==(original.v_line>=3&&original.v_line<6))
       $fatal(1,"RGB vertical sync shift wrong: standard=%0d field=%0d line=%0d sample=%0d",standard,odd,scanline,sample_position);
      if((dut.rgb_equalizing||dut.rgb_broad_sync)&&dut.in_vdg_window)$fatal(1,"RGB picture leaked into vertical sync");
     end
    end
   end
  end
  $display("RGB sync advances two lines in short/long 50/60-Hz fields PASS");
  $display("tb_rgb_coco_aperture PASS");$finish;
 end
endmodule
