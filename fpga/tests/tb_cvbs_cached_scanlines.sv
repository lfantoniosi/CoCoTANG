`timescale 1ns/1ps
// Check PMODE 3 deadlines in both analog field alignments. Both doubled
// HDMI copies and the analog consumer must retain every rendered row.
module tb_cvbs_cached_scanlines #(parameter ROWS=192,GM=6,ARTIFACT=0);
 reg clk=0,hdmi_clk=0,cvbs_clk=0,reset_n=0;
 always #5 clk=~clk;
 always #20 hdmi_clk=~hdmi_clk;
 always #4 cvbs_clk=~cvbs_clk;
 reg [1:0] artifact=0;
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
 wire [9:0] raw_x,raw_read;
 wire [7:0] raw_y,raw_prefetch;
 wire raw_valid,raw_prefetch_valid;
 reg [9:0] cvbs_x=0,read_addr=0;
 reg [7:0] c_y=0,c_prefetch=0;
 reg cvbs_valid=0,c_prefetch_valid=0,last_request=0;
 always @(posedge cvbs_clk)begin
  if(!reset_n)begin
   cvbs_x<=0;read_addr<=0;c_y<=0;c_prefetch<=0;
   cvbs_valid<=0;c_prefetch_valid<=0;last_request<=0;
  end else begin
   cvbs_x<={raw_x[9:1],raw_x[0]&&!last_request};
   read_addr<=raw_valid?raw_read:10'd0;
   c_y<=raw_y;c_prefetch<=raw_prefetch;
   cvbs_valid<=raw_valid;c_prefetch_valid<=raw_prefetch_valid;
   last_request<=raw_x[9:1]==319;
  end
 end
 wire [23:0] hdmi_pixel;
 wire [5:0] cvbs_pixel,hdmi_left,hdmi_right,cvbs_left,cvbs_right;
 wire hdmi_border_valid,cvbs_border_valid;
 wire memory_request;wire [22:0] memory_addr;
 reg memory_valid=0;reg [1:0] memory_state=0;
 gime_scanline_buffer #(.CVBS_REGISTERED_READ_ADDRESS(1)) dut(
  .clk(clk),.reset_n(reset_n),.bit_plane(1'b1),.hres(4'd0),.cres(2'd1),
  .active_height(8'd192),
  .lines_per_row_code(3'd0),.vertical_scroll(4'd0),
  .screen_base(19'd0),.video_bank(4'd0),.horizontal_offset(8'd0),
  .palettes(palettes),.border_rgb(border_rgb),
  .compatibility_mode(1'b1),.compatibility_an_g(1'b1),
  .compatibility_gm(3'(GM)),.compatibility_sam_mode(3'd6),
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
  .cvbs_read_clk(cvbs_clk),.cvbs_read_x(cvbs_x),.cvbs_read_address(read_addr),.cvbs_display_y(c_y),
  .cvbs_display_valid(cvbs_valid),.cvbs_prefetch_y(c_prefetch),
  .cvbs_prefetch_valid(c_prefetch_valid),.cvbs_border_raster_y(9'd0),
  .cvbs_pixel_data(cvbs_pixel),.cvbs_border_data(cvbs_left),
  .cvbs_right_border_data(cvbs_right),.cvbs_border_valid(cvbs_border_valid),
  .memory_request(memory_request),.memory_addr(memory_addr),
  .memory_data(32'hffffffff),.memory_valid(memory_valid)
 );

 coco_cvbs_ntsc #(.CANONICAL_640_INPUT(1),.CVBS_FIELD_PHASE_ALIGN(1),
  .CVBS_INCREMENTAL_DOTS(1),.CVBS_FAST_PREFETCH(1)) analog(
  .clk135(cvbs_clk),.clk270(cvbs_clk),.reset_n(reset_n),
  .video_50hz(1'b0),.high_resolution(1'b1),.compatibility_mode(1'b1),
  .framebuffer_data(cvbs_pixel),.border_rgb(6'h3f),
  .row_border_rgb(cvbs_left),.row_right_border_rgb(cvbs_right),
  .row_border_valid(cvbs_border_valid),.vertical_border_valid(1'b0),
  .vertical_left_border_rgb(6'h3f),.vertical_right_border_rgb(6'h3f),
  .active_height(8'd192),.source_x(raw_x),.source_read_address(raw_read),.source_y(raw_y),
  .source_valid(raw_valid),.prefetch_y(raw_prefetch),.prefetch_valid(raw_prefetch_valid));
 always @(posedge clk)begin
  memory_valid<=0;
  if(memory_request&&memory_state==0)memory_state<=1;
  else if(memory_state==1)begin memory_valid<=1;memory_state<=2;end
  else if(memory_state==2&&!memory_request)memory_state<=0;
 end
 integer hits=0,misses=0,parity,selection;
 integer hdmi_hits=0,hdmi_misses=0,analog_seen_y=-1;
 reg checking=0;
 always @(negedge cvbs_clk)if(checking)begin
  if(cvbs_valid&&c_y<ROWS&&cvbs_x>=300&&analog_seen_y!=c_y)begin
   analog_seen_y=c_y;
   if(!dut.c_read_valid)misses=misses+1;
   else begin
    hits=hits+1;
    if(cvbs_pixel!==(artifact==0?6'h3f:6'h3e)||
       analog.pixel_rgb!==cvbs_pixel)
     $fatal(1,"CVBS cache cached/encoded pixel is black or corrupted");
   end
  end
 end
 always @(negedge hdmi_clk)if(checking&&hdmi_valid&&h_y<ROWS&&hdmi_x==300)begin
  if(!dut.h_read_valid)begin
   hdmi_misses=hdmi_misses+1;
   $display("CVBS cache HDMI missing doubled row hy=%0d source=%0d",hy,h_y);
  end else begin
   hdmi_hits=hdmi_hits+1;
   if(hdmi_pixel!==(ARTIFACT==0?24'hffffff:24'ha5c3ef))$fatal(1,"CVBS cache HDMI corrupt pixel");
  end
 end
 task run_phase(input integer phase,input integer selected_artifact);
  begin
   reset_n=0;checking=0;artifact=2'(ARTIFACT);
   repeat(8)@(negedge clk);
   // Skip vertical blank without changing the relative half-line phase:
   // the 263-line field scans half a line earlier than HDMI's 262.5 lines.
   @(negedge hdmi_clk);hx=0;hy=48-phase;
   force analog.h_sample=0;force analog.v_line=41;
   force analog.sample_phase=0;
   @(negedge cvbs_clk);reset_n=1;
   release analog.h_sample;release analog.v_line;release analog.sample_phase;
   hits=0;misses=0;hdmi_hits=0;hdmi_misses=0;analog_seen_y=-1;checking=1;
   wait(analog.v_line==45+ROWS&&analog.h_sample==0);
   @(negedge cvbs_clk);checking=0;
   $display("artifact=%0d field phase=%0d hit rows=%0d missed rows=%0d",
            ARTIFACT,phase,hits,misses);
   if(hdmi_hits!=2*ROWS||hdmi_misses!=0)$fatal(1,"CVBS cache HDMI missed scanlines: hits=%0d misses=%0d",hdmi_hits,hdmi_misses);
   if(hits!=ROWS||misses!=0)$fatal(1,"CVBS cache analogue missed its row deadlines");
  end
 endtask
 initial begin
  for(selection=0;selection<1;selection=selection+1)
   for(parity=0;parity<2;parity=parity+1)run_phase(parity,selection);
  $display("tb_cvbs_cached_scanlines PASS");$finish;
 end
 initial begin #100000000;$fatal(1,"timeout");end
endmodule
