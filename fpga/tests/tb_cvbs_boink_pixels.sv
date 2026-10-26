`timescale 1ns/1ps
// Compare real cache consumers with textured native graphics and horizontal
// scroll writes; the earlier PMODE deadline test used uniform white data.
module cvbs_boink_consumer #(parameter COUNTERS=0,REAL_MEMORY=0,FAST=1)(input reset_n,input [7:0] hoff);
 reg clk=0,hdmi_clk=0,cvbs_clk=0;
 always #4.629630 clk=~clk;
 always #18.518519 hdmi_clk=~hdmi_clk;
 always #3.703704 cvbs_clk=~cvbs_clk;
 reg [1:0] artifact=0;
 reg [95:0] palettes;
 initial for(integer i=0;i<16;i=i+1)palettes[i*6+:6]=6'(i*3+1);
 wire [5:0] border_rgb=6'h3f;
 reg [9:0] hx=0,hy=0;
 always @(posedge hdmi_clk)if(!reset_n)begin hx<=0;hy<=0;end
 else if(hx==857)begin hx<=0;hy<=hy==524?0:hy+1'b1;end else hx<=hx+1'b1;
 wire frame_start=hx==0&&hy==0;
 wire [7:0] h_y=hy<18?0:(hy-18)>>1;
 wire [7:0] h_prefetch=hy<18?0:h_y+1'b1;
 wire hdmi_prefetch_valid=hy<18?hy>=16:hy<468&&h_y<224;
 wire hdmi_active=hy>=18&&hy<468;
 wire hdmi_valid=hdmi_active&&hx>=38&&hx<678;
 wire [9:0] hdmi_x=hdmi_valid?hx-38:0;
 wire [9:0] raw_x,raw_read;
 wire [7:0] raw_y,raw_prefetch;
 wire raw_valid,raw_prefetch_valid;
 reg [9:0] cvbs_x=0,read_addr=0;
 reg [7:0] c_y=0,c_prefetch=0;
 reg cvbs_valid=0,c_prefetch_valid=0,last_request=0;
 wire [9:0] request_x={raw_x[9:1],raw_x[0]&&!last_request};
 always @(posedge cvbs_clk)begin
  if(!reset_n)begin
   cvbs_x<=0;read_addr<=0;c_y<=0;c_prefetch<=0;
   cvbs_valid<=0;c_prefetch_valid<=0;last_request<=0;
  end else begin
   cvbs_x<={raw_x[9:1],raw_x[0]&&!last_request};
   read_addr<=raw_valid?(COUNTERS?raw_read:(request_x==639?10'd639:request_x+1'b1)):10'd0;
   c_y<=raw_y;c_prefetch<=raw_prefetch;
   cvbs_valid<=raw_valid;c_prefetch_valid<=raw_prefetch_valid;
   last_request<=raw_x[9:1]==319;
  end
 end
 wire [23:0] hdmi_pixel;
 wire [5:0] cvbs_pixel,hdmi_left,hdmi_right,cvbs_left,cvbs_right;
 wire hdmi_border_valid,cvbs_border_valid;
 wire memory_request;wire [22:0] memory_addr;
 wire memory_valid;wire [31:0] memory_word;
 function [7:0] pattern(input [22:0] a);
  pattern=a[7:0]^a[15:8]^8'hb6;
 endfunction
 gime_scanline_buffer #(.CVBS_REGISTERED_READ_ADDRESS(1)) dut(
  .clk(clk),.reset_n(reset_n),.bit_plane(1'b1),.hres(4'd7),.cres(2'd2),
  .active_height(8'd225),
  .lines_per_row_code(3'd0),.vertical_scroll(4'd0),
  .screen_base(19'd0),.video_bank(4'd0),.horizontal_offset(hoff),
  .palettes(palettes),.border_rgb(border_rgb),
  .compatibility_mode(1'b0),.compatibility_an_g(1'b1),
  .compatibility_gm(3'd7),.compatibility_sam_mode(3'd6),
  .compatibility_css(1'b1),.compatibility_raster_write(1'b0),
  .compatibility_raster_y(8'd0),.compatibility_raster_byte(5'd0),
  .compatibility_raster_css(1'b0),.compatibility_border_write(1'b0),
  .compatibility_border_right(1'b0),.compatibility_border_y(9'd0),
  .compatibility_border_rgb(6'd0),.compatibility_bitmap_valid(1'b0),.compatibility_bitmap_data(9'h1ff),
  .compatibility_bitmap_read_addr(),.artifact_mode(artifact),.blink(1'b0),
  .cpu_write_strobe(1'b0),.cpu_write_addr(23'd0),
  .hdmi_read_clk(hdmi_clk),.hdmi_read_x(hdmi_x),.hdmi_display_y(h_y),
  .hdmi_frame_start(frame_start),.hdmi_active_50hz(1'b0),
  .hdmi_border_raster_y(9'd0),.hdmi_display_valid(hdmi_valid),
  .hdmi_picture_active(hdmi_active),.hdmi_prefetch_y(h_prefetch),
  .hdmi_prefetch_valid(hdmi_prefetch_valid),
  .hdmi_pixel_data(hdmi_pixel),.hdmi_left_border_data(hdmi_left),
  .hdmi_right_border_data(hdmi_right),.hdmi_border_valid(hdmi_border_valid),
  .cvbs_read_clk(cvbs_clk),.cvbs_read_x(cvbs_x),.cvbs_read_address(read_addr),.cvbs_display_y(c_y),
  .cvbs_display_valid(cvbs_valid),.cvbs_prefetch_y(c_prefetch),
  .cvbs_prefetch_valid(c_prefetch_valid),.cvbs_border_raster_y(9'd0),
  .cvbs_pixel_data(cvbs_pixel),.cvbs_border_data(cvbs_left),
  .cvbs_right_border_data(cvbs_right),.cvbs_border_valid(cvbs_border_valid),
  .memory_request(memory_request),.memory_addr(memory_addr),
  .memory_data(memory_word),.memory_valid(memory_valid)
 );

 coco_cvbs_ntsc #(.CANONICAL_640_INPUT(1),.CVBS_FIELD_PHASE_ALIGN(0),
  .CVBS_INCREMENTAL_DOTS(COUNTERS),.CVBS_FAST_PREFETCH(COUNTERS)) analog(
  .clk135(cvbs_clk),.clk270(cvbs_clk),.reset_n(reset_n),
  .video_50hz(1'b0),.high_resolution(1'b1),.compatibility_mode(1'b0),
  .framebuffer_data(cvbs_pixel),.border_rgb(6'h3f),
  .row_border_rgb(cvbs_left),.row_right_border_rgb(cvbs_right),
  .row_border_valid(cvbs_border_valid),.vertical_border_valid(1'b0),
  .vertical_left_border_rgb(6'h3f),.vertical_right_border_rgb(6'h3f),
  .active_height(8'd225),.source_x(raw_x),.source_read_address(raw_read),.source_y(raw_y),
  .source_valid(raw_valid),.prefetch_y(raw_prefetch),.prefetch_valid(raw_prefetch_valid));
 generate if(REAL_MEMORY)begin:contended
  cvbs_contended_memory #(.FAST(FAST)) memory(.clk(clk),.reset_n(reset_n),
   .video_req(memory_request),.video_addr(memory_addr),
   .video_ack(memory_valid),.video_data(memory_word));
 end else begin:uncontended
 reg valid=0;reg [31:0] word_data=0;
 reg [1:0] memory_state=0;reg [3:0] memory_wait=0;
 assign memory_valid=valid;assign memory_word=word_data;
 always @(posedge clk)begin
  valid<=0;
  if(memory_request&&memory_state==0)memory_state<=1;
  else if(memory_state==1)begin
   if(memory_wait==9)begin
    word_data<={pattern(memory_addr+23'd3),pattern(memory_addr+23'd2),pattern(memory_addr+23'd1),pattern(memory_addr)};
    valid<=1;memory_state<=2;memory_wait<=0;
   end else memory_wait<=memory_wait+1'b1;
  end
  else if(memory_state==2&&!memory_request)memory_state<=0;
 end
 end endgenerate
endmodule
module tb_cvbs_boink_pixels #(parameter REAL_MEMORY=0,FAST=1,ROWS=12);
 reg reset_n=0;
 reg [7:0] hoff=0;
 cvbs_boink_consumer #(.COUNTERS(0),.REAL_MEMORY(REAL_MEMORY),.FAST(FAST)) original(reset_n,hoff);
 cvbs_boink_consumer #(.COUNTERS(1),.REAL_MEMORY(REAL_MEMORY),.FAST(FAST)) optimized(reset_n,hoff);
 integer pixels=0,hdmi_pixels=0,colors=0;
 reg [63:0] seen=0;
 always @(negedge optimized.cvbs_clk)if(reset_n)begin
  if(optimized.raw_valid&&optimized.analog.sample_phase==8&&optimized.c_y<ROWS)begin
   if(original.cvbs_pixel!==optimized.cvbs_pixel)
    $fatal(1,"Native cache pixels differ y=%0d x=%0d: %h/%h",optimized.c_y,optimized.raw_x,original.cvbs_pixel,optimized.cvbs_pixel);
   if(!optimized.dut.c_read_valid)$fatal(1,"Native analog row missed deadline");
   pixels=pixels+1;seen[optimized.cvbs_pixel]=1;
  end
 end
 always @(negedge optimized.hdmi_clk)if(reset_n)begin
  if(optimized.hdmi_valid&&optimized.h_y<ROWS)begin
   if(original.hdmi_pixel!==optimized.hdmi_pixel)$fatal(1,"Native HDMI pixels differ");
   if(!optimized.dut.h_read_valid)$fatal(1,"Native HDMI row missed deadline");
   hdmi_pixels=hdmi_pixels+1;
  end
  // Model FF9F writes in the horizontal border at regular raster intervals.
  if(optimized.hx==0&&optimized.hy>=18&&optimized.hy%8==0)hoff<=hoff+8'd7;
 end
 initial begin
  repeat(10)@(negedge optimized.clk);
  force original.analog.v_line=25;force optimized.analog.v_line=25;
  force original.analog.h_sample=0;force optimized.analog.h_sample=0;
  force original.analog.sample_phase=0;force optimized.analog.sample_phase=0;
  force original.hx=0;force optimized.hx=0;force original.hy=14;force optimized.hy=14;
  @(negedge optimized.cvbs_clk);reset_n=1;
  release original.analog.v_line;release optimized.analog.v_line;
  release original.analog.h_sample;release optimized.analog.h_sample;
  release original.analog.sample_phase;release optimized.analog.sample_phase;
  release original.hx;release optimized.hx;release original.hy;release optimized.hy;
  wait(optimized.analog.v_line==ROWS+28);
  for(integer i=0;i<64;i=i+1)if(seen[i])colors=colors+1;
  if(pixels<ROWS*640||hdmi_pixels<ROWS*1280||colors<8)$fatal(1,"Insufficient patterned graphics coverage");
  $display("Boink-style cache equivalence PASS: analog=%0d HDMI=%0d colors=%0d, native225, scroll writes, delayed word reads",pixels,hdmi_pixels,colors);
  $finish;
 end
 initial begin #20000000;$fatal(1,"timeout");end
endmodule
