`timescale 1ns/1ps
module tb_gime_css_alignment;
 reg clk=0,reset_n=0,capture=1,prefetch=0;
 reg frame_start=0;
 reg [7:0] row=0;
 wire css;
 wire sample,sample_css;
 wire [7:0] sample_y;
 wire [4:0] sample_byte;
 wire request;
 wire renderer_request,renderer_valid,bitmap_valid;
 wire [22:0] renderer_addr;
 wire [12:0] bitmap_addr;
 wire [8:0] bitmap_data;
 reg [31:0] live_memory=32'hffffffff;
 reg memory_valid=0;
 reg [1:0] responder=0;
 reg [95:0] palettes=0;
 integer y,x,ticks,bank;
 reg [5:0] expected;
 reg [23:0] hdmi_expected;
 always #5 clk=~clk;

 // Replay the corrected Dragonfire title's first green/buff pair in the
 // CPU-visible raster: green starts on line 44, at ticks 262..741.
 // The requested correction maps that line to picture row 2, with buff
 // endpoints and green pixels 8..247. Stimulus is independent of DUT
 // capture-origin constants so the old one-byte/two-line slip fails.
 assign css=!(timing.compatibility_y>=44&&
              timing.compatibility_x>=262&&timing.compatibility_x<742);
 gime_native_video timing(
  .clk(clk),.reset_n(reset_n),.video_50hz(1'b0),.bit_plane(1'b1),
  .hres(4'd0),.vmode(8'h80),.active_height(8'd192),
  .hdmi_frame_start(1'b0),.hdmi_active_50hz(1'b0),
  .compatibility_mode(1'b1),.compatibility_css(css),
  .compatibility_border_rgb(css?6'h3f:6'h0c),.pixel_rgb(6'd0),
  .compatibility_sample(sample),.compatibility_sample_css(sample_css),
  .compatibility_sample_y(sample_y),.compatibility_sample_byte(sample_byte));
 gime_compat_capture snapshot(
  .clk(clk),.reset_n(reset_n),.enable(1'b1),.hdmi_frame_start(frame_start),
  .sample(sample&&capture),.sample_y(sample_y),.sample_byte(sample_byte),
  .sample_css(sample_css),.screen_base(19'd0),.video_bank(4'd0),
  .row_bytes(11'd32),.lines_per_row(8'd1),
  .cpu_write_strobe(1'b0),.cpu_write_addr(23'd0),
  .read_addr(bitmap_addr),.read_data(bitmap_data),.display_valid(bitmap_valid),
  .renderer_request(renderer_request),.renderer_addr(renderer_addr),
  .renderer_valid(renderer_valid),.memory_request(request),.memory_addr(),
  .memory_data(live_memory),.memory_valid(memory_valid));
 gime_scanline_buffer dut(
  .clk(clk),.reset_n(reset_n),.bit_plane(1'b1),.hres(4'd0),.cres(2'd0),
  .active_height(8'd192),.lines_per_row_code(3'd0),.vertical_scroll(4'd0),
  .screen_base(19'd0),.video_bank(4'd0),.horizontal_offset(8'd0),
  .palettes(palettes),.border_rgb(6'h3f),
  .compatibility_mode(1'b1),.compatibility_an_g(1'b1),
  .compatibility_gm(3'd7),.compatibility_sam_mode(3'd6),.compatibility_css(css),
  .compatibility_raster_write(sample&&capture),
  .compatibility_raster_y(sample_y),.compatibility_raster_byte(sample_byte),
  .compatibility_raster_css(sample_css),.compatibility_border_write(1'b0),
  .compatibility_border_right(1'b0),.compatibility_border_y(9'd0),
  .compatibility_border_rgb(6'd0),.artifact_mode(2'd0),.blink(1'b0),
  .compatibility_bitmap_valid(bitmap_valid),.compatibility_bitmap_data(bitmap_data),
  .compatibility_bitmap_read_addr(bitmap_addr),
  .cpu_write_strobe(1'b0),.cpu_write_addr(23'd0),
  .hdmi_read_clk(clk),.hdmi_read_x(10'd0),.hdmi_display_y(8'd0),
  .hdmi_frame_start(frame_start),.hdmi_active_50hz(1'b0),
  .hdmi_border_raster_y(9'd0),.hdmi_display_valid(1'b0),
  .hdmi_picture_active(1'b0),.hdmi_prefetch_y(row),.hdmi_prefetch_valid(prefetch),
  .cvbs_read_clk(clk),.cvbs_read_x(10'd0),.cvbs_display_y(8'd0),
  .cvbs_display_valid(1'b0),.cvbs_prefetch_y(8'd0),.cvbs_prefetch_valid(1'b0),
  .cvbs_border_raster_y(9'd0),.memory_request(renderer_request),
  .memory_addr(renderer_addr),.memory_data(live_memory),.memory_valid(renderer_valid));
 always @(posedge clk)begin
  memory_valid<=0;
  if(request&&responder==0)begin memory_valid<=1;responder<=1;end
  else if(responder==1&&!request)responder<=0;
 end

 initial begin
  palettes[9*6+:6]=6'd18;palettes[11*6+:6]=6'd63;
  repeat(3)@(negedge clk);reset_n=1;
  // Speed up only the raster clock. CSS capture still passes through the
  // real output registers and double-buffered RAM before rendering.
  force timing.compatibility_raster_tick=1'b1;
  repeat(3*262*912)@(negedge clk);
  capture=0;
  if(!dut.compatibility_css_display_valid)$fatal(1,"CSS field never completed");
  force timing.compatibility_raster_tick=1'b0;
  // Erase the live sprite RAM before HDMI scans it. Pixels and CSS must
  // still come from the same completed machine field, including at edges.
  live_memory=0;frame_start=1;repeat(8)@(negedge clk);
  frame_start=0;repeat(8)@(negedge clk);
  if(!bitmap_valid)$fatal(1,"graphics capture not ready");
  for(y=0;y<4;y=y+1)begin
   row=y;prefetch=1;ticks=0;
   while(!((dut.h_valid0&&dut.h_tag0==row)||
           (dut.h_valid1&&dut.h_tag1==row))&&ticks<20000)begin
    @(negedge clk);ticks=ticks+1;
   end
   if(ticks==20000)$fatal(1,"row %0d fill timed out",y);
   bank=!(dut.h_valid0&&dut.h_tag0==row);
   for(x=0;x<512;x=x+1)begin
    expected=(y>=2&&x>=16&&x<496)?6'h0c:6'h3f;
    hdmi_expected={{4{expected[5:4]}},{4{expected[3:2]}},{4{expected[1:0]}}};
    if((bank?dut.hdmi_line1[x]:dut.hdmi_line0[x])!==hdmi_expected)
     $fatal(1,"CSS alignment row=%0d pixel=%0d got=%h expected=%h",y,x,
       bank?dut.hdmi_line1[x]:dut.hdmi_line0[x],hdmi_expected);
   end
   if((bank?dut.h_left_border1:dut.h_left_border0)!==6'h3f||
      (bank?dut.h_right_border1:dut.h_right_border0)!==6'h3f)
    $fatal(1,"CSS leaked green into row %0d border",y);
   bank=(dut.c_valid0&&dut.c_tag0==row)?0:
        (dut.c_valid1&&dut.c_tag1==row)?1:2;
   for(x=0;x<640;x=x+1)begin
    expected=(y>=2&&x>=20&&x<620)?6'h0c:6'h3f;
    if((bank==0?dut.cvbs_line0[x]:bank==1?dut.cvbs_line1[x]:dut.cvbs_line2[x])!==expected)
     $fatal(1,"analog CSS alignment row=%0d pixel=%0d",y,x);
   end
   prefetch=0;repeat(5)@(negedge clk);
  end
  $display("tb_gime_css_alignment PASS");$finish;
 end
 initial begin #20000000;$fatal(1,"CSS alignment timeout");end
endmodule
