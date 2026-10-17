`timescale 1ns/1ps
// Replay both alternating analogue field phases against the HDMI producer.
// PMODE 4's full artifact pass must finish before each analogue row starts.
module tb_gime_pmode4_analog #(parameter RGB_COCO_TIMING=0);
 reg clk=0,hdmi_clk=0,cvbs_clk=0,reset_n=0;
 always #5 clk=~clk;
 always #20 hdmi_clk=~hdmi_clk;
 always #4 cvbs_clk=~cvbs_clk;
 reg [1:0] artifact=1;
 reg [95:0] palettes={16{6'd63}};
 wire [5:0] border_rgb=6'h3f;
 reg [9:0] hx=0,hy=0;
 always @(posedge hdmi_clk)if(!reset_n)begin hx<=0;hy<=0;end
 else if(hx==857)begin hx<=0;hy<=hy==524?0:hy+1'b1;end else hx<=hx+1'b1;
 wire frame_start=hx==0&&hy==0;
 wire [7:0] h_y=hy<52?0:(hy-52)>>1;
 wire [7:0] h_prefetch=hy<52?0:h_y+1'b1;
 wire hdmi_prefetch_valid=hy<52?hy>=50:hy<436&&h_y<191;
 wire hdmi_active=hy>=52&&hy<436;
 wire hdmi_valid=hdmi_active&&hx>=102&&hx<614;
 wire [9:0] hdmi_x=hdmi_valid?hx-102:0;
 wire [9:0] cvbs_x;
 wire [7:0] c_y,c_prefetch;
 wire cvbs_valid,c_prefetch_valid;
 wire [23:0] hdmi_pixel;
 wire [5:0] cvbs_pixel,hdmi_left,hdmi_right,cvbs_left,cvbs_right;
 wire hdmi_border_valid,cvbs_border_valid;
 wire memory_request;wire [22:0] memory_addr;
 reg memory_valid=0;reg [1:0] memory_state=0;
 gime_scanline_buffer dut(
  .clk(clk),.reset_n(reset_n),.bit_plane(1'b1),.hres(4'd0),.cres(2'd1),
  .active_height(8'd192),
  .lines_per_row_code(3'd0),.vertical_scroll(4'd0),
  .screen_base(19'd0),.video_bank(4'd0),.horizontal_offset(8'd0),
  .palettes(palettes),.border_rgb(border_rgb),
  .compatibility_mode(1'b1),.compatibility_an_g(1'b1),
  .compatibility_gm(3'd7),.compatibility_sam_mode(3'd6),
  .compatibility_css(1'b1),.compatibility_raster_write(1'b0),
  .compatibility_raster_y(8'd0),.compatibility_raster_byte(5'd0),
  .compatibility_raster_css(1'b0),.compatibility_border_write(1'b0),
  .compatibility_border_right(1'b0),.compatibility_border_y(9'd0),
  .compatibility_border_rgb(6'd0),.compatibility_bitmap_valid(1'b1),.compatibility_bitmap_data(9'h1ff),
  .compatibility_bitmap_read_addr(),.artifact_mode(artifact),.blink(1'b0),
  .cpu_write_strobe(1'b0),.cpu_write_addr(23'd0),
  .hdmi_read_clk(hdmi_clk),.hdmi_read_x(hdmi_x),.hdmi_display_y(h_y),
  .hdmi_frame_start(frame_start),.hdmi_active_50hz(1'b0),
  .hdmi_border_raster_y(9'd0),.hdmi_display_valid(hdmi_valid),
  .hdmi_picture_active(hdmi_active),.hdmi_prefetch_y(h_prefetch),
  .hdmi_prefetch_valid(hdmi_prefetch_valid),
  .hdmi_pixel_data(hdmi_pixel),.hdmi_left_border_data(hdmi_left),
  .hdmi_right_border_data(hdmi_right),.hdmi_border_valid(hdmi_border_valid),
  .cvbs_read_clk(cvbs_clk),.cvbs_read_x(cvbs_x),.cvbs_display_y(c_y),
  .cvbs_display_valid(cvbs_valid),.cvbs_prefetch_y(c_prefetch),
  .cvbs_prefetch_valid(c_prefetch_valid),.cvbs_border_raster_y(9'd0),
  .cvbs_pixel_data(cvbs_pixel),.cvbs_border_data(cvbs_left),
  .cvbs_right_border_data(cvbs_right),.cvbs_border_valid(cvbs_border_valid),
  .memory_request(memory_request),.memory_addr(memory_addr),
  .memory_data(32'hffffffff),.memory_valid(memory_valid)
 );

 coco_cvbs_ntsc #(.CANONICAL_640_INPUT(1),.RGB_SOG_OUTPUT(RGB_COCO_TIMING)) analog(
  .clk135(cvbs_clk),.clk270(cvbs_clk),.reset_n(reset_n),
  .video_50hz(1'b0),.high_resolution(1'b1),.compatibility_mode(1'b1),
  .framebuffer_data(cvbs_pixel),.border_rgb(6'h3f),
  .row_border_rgb(cvbs_left),.row_right_border_rgb(cvbs_right),
  .row_border_valid(cvbs_border_valid),.vertical_border_valid(1'b0),
  .vertical_left_border_rgb(6'h3f),.vertical_right_border_rgb(6'h3f),
  .active_height(8'd192),.source_x(cvbs_x),.source_y(c_y),
  .source_valid(cvbs_valid),.prefetch_y(c_prefetch),.prefetch_valid(c_prefetch_valid));
 always @(posedge clk)begin
  memory_valid<=0;
  if(memory_request&&memory_state==0)memory_state<=1;
  else if(memory_state==1)begin memory_valid<=1;memory_state<=2;end
  else if(memory_state==2&&!memory_request)memory_state<=0;
 end
 integer hits=0,misses=0,parity,selection;
 reg checking=0;
 integer analog_seen_y=-1;
 always @(negedge cvbs_clk)if(checking)begin
  if(cvbs_valid&&c_y<4&&cvbs_x>=300&&analog_seen_y!=c_y)begin
   analog_seen_y=c_y;
   if(!dut.c_read_valid)misses=misses+1;
   else begin
    hits=hits+1;
    if(cvbs_pixel!==(artifact==0?6'h3f:6'h3e)||
       analog.pixel_rgb!==cvbs_pixel)
     $fatal(1,"PMODE4 cached/encoded pixel is black or corrupted");
   end
  end
 end
 task run_phase(input integer phase,input integer selected_artifact);
  begin
   reset_n=0;checking=0;artifact=2'(selected_artifact);
   repeat(8)@(negedge clk);
   // Skip vertical blank without changing the relative half-line phase:
   // the 263-line field scans half a line earlier than HDMI's 262.5 lines.
   @(negedge hdmi_clk);hx=0;hy=48-phase;
   force analog.h_sample=0;force analog.v_line=41;
   force analog.sample_phase=0;
   @(negedge cvbs_clk);reset_n=1;
   release analog.h_sample;release analog.v_line;release analog.sample_phase;
   hits=0;misses=0;analog_seen_y=-1;checking=1;
   wait(analog.v_line==49&&analog.h_sample==0);
   @(negedge cvbs_clk);checking=0;
   $display("artifact=%0d field phase=%0d hit rows=%0d missed rows=%0d",
            selected_artifact,phase,hits,misses);
   if(hits!=4||misses!=0)$fatal(1,"PMODE4 analogue missed its row deadlines");
  end
 endtask
 initial begin
  for(selection=0;selection<3;selection=selection+1)
   for(parity=0;parity<2;parity=parity+1)run_phase(parity,selection);
  $display("tb_gime_pmode4_analog PASS");$finish;
 end
 initial begin #5000000;$fatal(1,"timeout");end
endmodule
