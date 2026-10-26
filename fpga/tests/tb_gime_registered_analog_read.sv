`timescale 1ns/1ps
// Compare the original and preregistered scanline-RAM interfaces at every
// clk135 edge. Model the existing top-level staging, including the edge fix.
module tb_gime_registered_analog_read;
reg clk135=0,board_reset_n=0,compatibility=0;
always #4 clk135=~clk135;
wire [9:0] cvbs_source_x_raw;
wire [7:0] cvbs_source_y_raw,cvbs_prefetch_y_raw;
wire cvbs_source_valid_raw,cvbs_prefetch_valid_raw;
reg [9:0] cvbs_source_x=0,cvbs_read_address=0;
reg [7:0] cvbs_source_y=0,cvbs_prefetch_y=0;
reg cvbs_source_valid=0,cvbs_prefetch_valid=0,cvbs_last_request=0;
wire [9:0] cvbs_request_x={cvbs_source_x_raw[9:1],cvbs_source_x_raw[0]&&!cvbs_last_request};
always @(posedge clk135 or negedge board_reset_n)begin
 if(!board_reset_n)begin
  cvbs_source_x<=0;cvbs_read_address<=0;cvbs_source_valid<=0;cvbs_last_request<=0;
 end else begin
  cvbs_last_request<=cvbs_source_x_raw[9:1]==319;
  cvbs_source_x<=cvbs_request_x;
  cvbs_source_valid<=cvbs_source_valid_raw;
  cvbs_read_address<=cvbs_source_valid_raw?
   (cvbs_request_x==639?10'd639:cvbs_request_x+1'b1):10'd0;
 end
end
coco_cvbs_ntsc #(.CANONICAL_640_INPUT(1),.RGB_SOG_OUTPUT(1)) encoder(
 .clk135(clk135),.clk270(clk135),.reset_n(board_reset_n),.video_50hz(1'b0),
 .high_resolution(1'b1),.compatibility_mode(compatibility),.active_height(8'd192),
 .source_x(cvbs_source_x_raw),.source_valid(cvbs_source_valid_raw));
wire [5:0] old_pixel,new_pixel;
gime_scanline_buffer original(.clk(clk135),.reset_n(1'b0),
 .cvbs_read_clk(clk135),.cvbs_read_x(cvbs_source_x),.cvbs_display_y(8'd0),
 .cvbs_display_valid(cvbs_source_valid),.cvbs_pixel_data(old_pixel));
gime_scanline_buffer #(.CVBS_REGISTERED_READ_ADDRESS(1)) pipelined(
 .clk(clk135),.reset_n(1'b0),.cvbs_read_clk(clk135),.cvbs_read_x(cvbs_source_x),
 .cvbs_read_address(cvbs_read_address),.cvbs_display_y(8'd0),
 .cvbs_display_valid(cvbs_source_valid),.cvbs_pixel_data(new_pixel));
for(genvar page=0;page<10;page=page+1)begin:init_pages
 integer offset;
 initial for(offset=0;offset<64;offset=offset+1)begin
  original.cvbs_pages[page].line0[offset]=(offset^page)&63;
  pipelined.cvbs_pages[page].line0[offset]=(offset^page)&63;
 end
end
integer mode,tick;
initial begin
 force original.c_valid0=1;force original.c_tag0=0;
 force original.c_valid1=0;force original.c_valid2=0;
 force pipelined.c_valid0=1;force pipelined.c_tag0=0;
 force pipelined.c_valid1=0;force pipelined.c_valid2=0;
 for(mode=0;mode<2;mode=mode+1)begin
  board_reset_n=0;compatibility=mode;
  repeat(4)@(negedge clk135);
  force encoder.h_sample=0;force encoder.sample_phase=0;force encoder.v_line=45;
  board_reset_n=1;@(negedge clk135);
  release encoder.h_sample;release encoder.sample_phase;release encoder.v_line;
  for(tick=0;tick<17160;tick=tick+1)begin
   @(negedge clk135);
   if(old_pixel!==new_pixel)$fatal(1,"Analog read retiming changed pixels: mode=%0d tick=%0d x=%0d old=%h new=%h",mode,tick,cvbs_source_x,old_pixel,new_pixel);
  end
 end
 $display("Analog read retiming PASS: identical pixels and latency, both modes, page boundaries, final dot and blanking");
 $finish;
end
endmodule
