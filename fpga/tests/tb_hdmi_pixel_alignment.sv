`timescale 1ns/1ps
// Exercise the real wrapper, two-stage line RAM and HDMI RGB capture.
// Distinct pixels expose repeated first columns and missing final columns.
module tb_hdmi_pixel_alignment #(parameter ALIGN=1);
 reg clk=0,reset=1,compatibility=0,standard=0;
 integer artifact_case=0;
 always #5 clk=~clk;
 wire [9:0] source_x;
 wire [7:0] source_y;
 wire valid,active;
 wire [23:0] pixel;
 coco3_hdmi #(.ALIGN_SCANLINE_READ(ALIGN)) dut(
  .pixel_clk(clk),.serial_clk(clk),.audio_clk(clk),.reset(reset),
  .audio_pcm_left(16'd0),.audio_pcm_right(16'd0),
  .compatibility_mode(compatibility),.video_50hz(standard),
  .bit_plane(1'b1),.active_height(8'd192),.artifact_mode(2'd0),
  .artifact_video_active(artifact_case!=0),.artifact_css(artifact_case==2),.ssc_enabled(1'b0),
  .border_rgb(6'h0c),.row_left_border_rgb(6'h0c),
  .row_right_border_rgb(6'h0c),.row_border_valid(1'b1),
  .vertical_border_valid(1'b0),.pixel_data(pixel),
  .source_x(source_x),.source_y(source_y),.source_valid(valid),
  .source_picture_active(active));
 // Icarus cannot elaborate the audio packet arrays; video capture and
 // TMDS pixel timing are shared by the DVI and HDMI branches.
 defparam dut.encoder.DVI_OUTPUT=1;
 gime_scanline_buffer cache(.clk(clk),.reset_n(1'b0),
  .hdmi_read_clk(clk),.hdmi_read_x(source_x),.hdmi_display_y(source_y),
  .hdmi_display_valid(valid),.hdmi_picture_active(active),
  .hdmi_pixel_data(pixel));
 function automatic [23:0] expected(input integer x,input integer y);
  integer left,width,row;
  begin
   width=compatibility?512:640;left=(720-width)/2;
   row=(y-(standard?96:52))/2;
   expected=(x>=left && x<left+width)?
    ((row==9?24'h110000:24'h220000)+(x-left)):24'h00ff00;
   if(artifact_case!=0)
    expected=dut.artifact_rgb888(artifact_case==2,
     (x>=left && x<left+width)?4'((x-left)+(row==9?0:3)):4'hf);
  end
 endfunction
 integer i,hz,mode,tick,x,y,checked;
 initial begin
  force cache.h_valid0=1;force cache.h_valid1=1;
  force cache.h_tag0=9;force cache.h_tag1=10;
  for(artifact_case=0;artifact_case<3;artifact_case=artifact_case+1)
  for(hz=0;hz<2;hz=hz+1)for(mode=0;mode<2;mode=mode+1)begin
   for(i=0;i<640;i=i+1)begin
    cache.hdmi_line0[i]=artifact_case?{20'ha5c3e,4'(i)}:24'h110000+i;
    cache.hdmi_line1[i]=artifact_case?{20'ha5c3e,4'(i+3)}:24'h220000+i;
   end
   reset=1;standard=hz;compatibility=mode;
   repeat(4)@(negedge clk);reset=0;
   force dut.encoder.active_video_50hz=standard;
   repeat(8)@(negedge clk);
   force dut.encoder.cx=0;
   force dut.encoder.cy=standard?114:70;
   @(negedge clk);
   release dut.encoder.cx;release dut.encoder.cy;
   checked=0;
   for(tick=0;tick<(hz?864:858)*4;tick=tick+1)begin
    @(negedge clk);x=dut.x;y=dut.y;
    if(x<720)begin
     if(dut.stream_rgb!==expected(x,y))
      $fatal(1,"HDMI %0dHz compat=%0d x=%0d y=%0d RGB=%h expected=%h",
       hz?50:60,mode,x,y,dut.stream_rgb,expected(x,y));
     checked=checked+1;
    end
    if(x>0 && x<=720 && dut.encoder.video_data!==expected(x-1,y))
     $fatal(1,"HDMI encoder captured wrong column x=%0d y=%0d",x-1,y);
   end
   if(checked!=2880)$fatal(1,"Missing HDMI pixels: %0d",checked);
   $display("HDMI %0dHz compat=%0d artifact=%0d: all columns, both edges and doubled rows PASS",
    hz?50:60,mode,artifact_case);
   release dut.encoder.active_video_50hz;
  end
  $finish;
 end
endmodule
module serializer #(parameter integer NUM_CHANNELS=3,parameter real VIDEO_RATE=0)(
 input clk_pixel,clk_pixel_x5,reset,input [9:0] tmds_internal [NUM_CHANNELS-1:0],
 output [2:0] tmds,output tmds_clock);
 assign tmds=0;assign tmds_clock=0;
endmodule
module ELVDS_OBUF(input I,output O,OB);assign O=I;assign OB=~I;endmodule
