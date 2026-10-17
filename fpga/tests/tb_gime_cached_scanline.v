`timescale 1ns/1ps
// A committed line includes the native aperture, its margins, and both
// border endpoints. None of the three readers may reinterpret it with a
// later FF98/FF9A value.
module tb_gime_cached_scanline;
 reg clk=0,hdmi_clk=0,cvbs_clk=0,reset_n=0;
 always #5 clk=~clk;
 always #18.5 hdmi_clk=~hdmi_clk;
 always #3.7 cvbs_clk=~cvbs_clk;

 reg [3:0] hres=0;
 reg [5:0] border_rgb=6'h2a;
 reg [95:0] palettes=0;
 reg [9:0] hdmi_x=0,cvbs_x=0;
 reg hdmi_valid=0,hdmi_active=0,cvbs_valid=0;
 reg hdmi_prefetch_valid=1;
 reg memory_valid=0;
 reg [1:0] memory_state=0;
 wire memory_request;
 wire [22:0] memory_addr;
 wire [23:0] hdmi_pixel;
 wire [5:0] hdmi_left,hdmi_right,cvbs_pixel,cvbs_left,cvbs_right;
 wire hdmi_border_valid,cvbs_border_valid;
 integer i,timeout;

 gime_scanline_buffer dut(
  .clk(clk),.reset_n(reset_n),.bit_plane(1'b1),.hres(hres),.cres(2'd1),
  .active_height(8'd192),
  .lines_per_row_code(3'd0),.vertical_scroll(4'd0),
  .screen_base(19'd0),.video_bank(4'd0),.horizontal_offset(8'd0),
  .palettes(palettes),.border_rgb(border_rgb),
  .compatibility_mode(1'b0),.compatibility_an_g(1'b0),
  .compatibility_gm(3'd0),.compatibility_sam_mode(3'd0),
  .compatibility_css(1'b0),.compatibility_raster_write(1'b0),
  .compatibility_raster_y(8'd0),.compatibility_raster_byte(5'd0),
  .compatibility_raster_css(1'b0),.compatibility_border_write(1'b0),
  .compatibility_border_right(1'b0),.compatibility_border_y(9'd0),
  .compatibility_border_rgb(6'd0),.artifact_mode(2'd0),.blink(1'b0),
  .cpu_write_strobe(1'b0),.cpu_write_addr(23'd0),
  .hdmi_read_clk(hdmi_clk),.hdmi_read_x(hdmi_x),.hdmi_display_y(8'd0),
  .hdmi_frame_start(1'b0),.hdmi_active_50hz(1'b0),
  .hdmi_border_raster_y(9'd0),.hdmi_display_valid(hdmi_valid),
  .hdmi_picture_active(hdmi_active),.hdmi_prefetch_y(8'd0),
  .hdmi_prefetch_valid(hdmi_prefetch_valid),
  .hdmi_pixel_data(hdmi_pixel),.hdmi_left_border_data(hdmi_left),
  .hdmi_right_border_data(hdmi_right),.hdmi_border_valid(hdmi_border_valid),
  .cvbs_read_clk(cvbs_clk),.cvbs_read_x(cvbs_x),.cvbs_display_y(8'd0),
  .cvbs_display_valid(cvbs_valid),.cvbs_prefetch_y(8'd0),
  .cvbs_prefetch_valid(1'b0),.cvbs_border_raster_y(9'd0),
  .cvbs_pixel_data(cvbs_pixel),.cvbs_border_data(cvbs_left),
  .cvbs_right_border_data(cvbs_right),.cvbs_border_valid(cvbs_border_valid),
  .memory_request(memory_request),.memory_addr(memory_addr),
  .memory_data(32'h1b1b1b1b),.memory_valid(memory_valid)
 );

 always @(posedge clk) begin
  memory_valid<=0;
  if(memory_request&&memory_state==0)memory_state<=1;
  else if(memory_state==1)begin memory_valid<=1;memory_state<=2;end
  else if(memory_state==2&&!memory_request)memory_state<=0;
 end

 initial begin
  for(i=0;i<16;i=i+1)palettes[i*6+:6]=i;
  repeat(4)@(negedge clk);reset_n=1;
  timeout=0;
  while((!dut.h_valid0||!dut.c_valid0)&&timeout<200000)begin
   @(posedge clk);timeout=timeout+1;
  end
  if(timeout==200000)$fatal(1,"native scanline did not commit");
  #1;
  if(dut.hdmi_line0[0]!==24'haaaaaa||
     dut.hdmi_line0[63]!==24'haaaaaa||
     dut.hdmi_line0[64]===24'haaaaaa||
     dut.hdmi_line0[576]!==24'haaaaaa||
     dut.hdmi_line0[639]!==24'haaaaaa||
     dut.cvbs_line0[0]!==6'h2a||dut.cvbs_line0[63]!==6'h2a||
     dut.cvbs_line0[64]===6'h2a||dut.cvbs_line0[576]!==6'h2a||
     dut.cvbs_line0[639]!==6'h2a)
   $fatal(1,"committed 256-dot scanline omitted an aperture margin");
  if(dut.h_left_border0!==6'h2a||dut.h_right_border0!==6'h2a||
     dut.c_border0!==6'h2a||dut.c_right_border0!==6'h2a)
   $fatal(1,"border endpoints differ from their committed pixels");

  hdmi_prefetch_valid=0;
  border_rgb=6'h15;
  hdmi_active=1;
  repeat(4)@(posedge hdmi_clk);#1;
  if(!hdmi_border_valid||hdmi_left!==6'h2a||hdmi_right!==6'h2a)
   $fatal(1,"HDMI border used live FF9A instead of committed row");
  hdmi_valid=1;
  @(posedge hdmi_clk);#1;
  if(hdmi_pixel!==24'haaaaaa)
   $fatal(1,"HDMI first pixel differs from cached margin");
  hdmi_x=10'd64;
  repeat(3)@(posedge hdmi_clk);#1;
  if(hdmi_pixel===24'haaaaaa)
   $fatal(1,"HDMI aperture did not begin at sample 64");
  hdmi_x=10'd576;
  repeat(3)@(posedge hdmi_clk);#1;
  if(hdmi_pixel!==24'haaaaaa)
   $fatal(1,"HDMI right margin changed with live FF9A");

  repeat(4)@(posedge cvbs_clk);#1;
  if(!cvbs_border_valid||cvbs_left!==6'h2a||cvbs_right!==6'h2a)
   $fatal(1,"analog border used live FF9A instead of committed row");
  cvbs_valid=1;
  cvbs_x=0;
  @(posedge cvbs_clk);#1;
  if(cvbs_pixel!==6'h2a)
   $fatal(1,"analog first pixel differs from cached margin");
  cvbs_x=10'd64;
  repeat(4)@(posedge cvbs_clk);#1;
  if(cvbs_pixel===6'h2a)
   $fatal(1,"analog aperture did not begin at sample 64");
  cvbs_x=10'd576;
  repeat(4)@(posedge cvbs_clk);#1;
  if(cvbs_pixel!==6'h2a)
   $fatal(1,"analog right margin changed with live FF9A");

  // Read-ahead crosses ordinary page boundaries, but must hold the last
  // dot throughout its dwell instead of wrapping page 9 from offset 63 to 0.
  dut.cvbs_pages[9].line0[0]=6'h03;
  dut.cvbs_pages[9].line0[63]=6'h30;
  cvbs_x=10'd575;
  repeat(4)@(posedge cvbs_clk);#1;
  if(cvbs_pixel!==6'h03)$fatal(1,"analog read-ahead did not cross into final page");
  cvbs_x=10'd638;
  repeat(4)@(posedge cvbs_clk);#1;
  if(cvbs_pixel!==6'h30)$fatal(1,"analog read-ahead missed last dot");
  cvbs_x=10'd639;
  repeat(10)begin
   @(posedge cvbs_clk);#1;
   if(cvbs_pixel!==6'h30)$fatal(1,"last analog column wrapped to pixel 576: %h",cvbs_pixel);
  end
  cvbs_valid=0;cvbs_x=0;
  repeat(5)@(posedge cvbs_clk);#1;
  cvbs_valid=1;
  @(posedge cvbs_clk);#1;
  if(cvbs_pixel!==6'h2a)$fatal(1,"last analog dot leaked into the next left edge");

  // A new FF98 mode describes a future row, never the row in scanout.
  hres=7;
  repeat(12)@(posedge clk);
  hdmi_x=0;
  repeat(3)@(posedge hdmi_clk);#1;
  if(!hdmi_border_valid||hdmi_left!==6'h2a||hdmi_pixel!==24'haaaaaa)
   $fatal(1,"live FF98 reinterpreted an already committed HDMI row");
  $display("tb_gime_cached_scanline PASS");
  $finish;
 end
endmodule
