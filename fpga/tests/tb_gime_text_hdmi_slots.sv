`timescale 1ns/1ps
// Stressed native text scanout with queued CPU writes and variable SDRAM
// latency. Both copies of every HDMI row must meet the earlier deadline;
// analog alone can pass even when the first HDMI copy is already black.
module tb_gime_text_hdmi_slots #(
 parameter CPU_CYCLE=120,COLUMNS=80,VIDEO_SLOT_CYCLES=31,RGB_COCO_TIMING=0,SCANNED_ROWS=192
);
 reg clk=0,hdmi_clk=0,cvbs_clk=0,reset_n=0;
 always #5 clk=~clk;
 always #20 hdmi_clk=~hdmi_clk;
 always #4 cvbs_clk=~cvbs_clk;
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
 wire hdmi_valid=hdmi_active&&hx>=38&&hx<678;
 wire [9:0] hdmi_x=hdmi_valid?hx-38:0;
 wire [9:0] cvbs_x;
 wire [7:0] c_y,c_prefetch;
 wire cvbs_valid,c_prefetch_valid;
 wire [23:0] hdmi_pixel;
 wire [5:0] cvbs_pixel,hdmi_left,hdmi_right,cvbs_left,cvbs_right;
 wire hdmi_border_valid,cvbs_border_valid;
 wire memory_request;wire [22:0] memory_addr;
 wire memory_valid;wire [31:0] memory_data;
 gime_scanline_buffer dut(
  .clk(clk),.reset_n(reset_n),.bit_plane(1'b0),.hres(COLUMNS==80?4'd7:4'd1),.cres(2'd1),
  .active_height(8'd192),
  .lines_per_row_code(3'd3),.vertical_scroll(4'd0),
  .screen_base(19'd0),.video_bank(4'd0),.horizontal_offset(8'd0),
  .palettes(palettes),.border_rgb(border_rgb),
  .compatibility_mode(1'b0),.compatibility_an_g(1'b1),
  .compatibility_gm(3'd7),.compatibility_sam_mode(3'd6),
  .compatibility_css(1'b1),.compatibility_raster_write(1'b0),
  .compatibility_raster_y(8'd0),.compatibility_raster_byte(5'd0),
  .compatibility_raster_css(1'b0),.compatibility_border_write(1'b0),
  .compatibility_border_right(1'b0),.compatibility_border_y(9'd0),
  .compatibility_border_rgb(6'd0),.compatibility_bitmap_valid(1'b0),.compatibility_bitmap_data(9'h1ff),
  .compatibility_bitmap_read_addr(),.artifact_mode(2'd0),.blink(1'b0),
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
  .memory_data(memory_data),.memory_valid(memory_valid)
 );

 coco_cvbs_ntsc #(.CANONICAL_640_INPUT(1),.RGB_SOG_OUTPUT(RGB_COCO_TIMING)) analog(
  .clk135(cvbs_clk),.clk270(cvbs_clk),.reset_n(reset_n),
  .video_50hz(1'b0),.high_resolution(1'b1),.compatibility_mode(1'b0),
  .framebuffer_data(cvbs_pixel),.border_rgb(6'h3f),
  .row_border_rgb(cvbs_left),.row_right_border_rgb(cvbs_right),
  .row_border_valid(cvbs_border_valid),.vertical_border_valid(1'b0),
  .vertical_left_border_rgb(6'h3f),.vertical_right_border_rgb(6'h3f),
  .active_height(8'd192),.source_x(cvbs_x),.source_y(c_y),
  .source_valid(cvbs_valid),.prefetch_y(c_prefetch),.prefetch_valid(c_prefetch_valid));
 // Exercise the same fractional master phase and E-fall slot opening as
 // the hardware, rather than an idealized fixed 60/120-clock CPU cycle.
 wire cpu_e,cpu_q,cpu_e_fall;
 reg [4:0] slot_count=0;
 gime_timing timing(.clk(clk),.reset_n(reset_n),.fast_mode(CPU_CYCLE==60),
  .e(cpu_e),.q(cpu_q),.e_fall(cpu_e_fall));
 always @(posedge clk)if(!reset_n)slot_count<=0;
 else if(cpu_e_fall)slot_count<=VIDEO_SLOT_CYCLES;
 else if(slot_count!=0)slot_count<=slot_count-1'b1;
 wire [4:0] phase=timing.phase;
 reg cpu_req=0;
 wire cpu_ack,rd,wr,refresh;
 reg busy=0,data_ready=0;
 integer latency=0;
 reg [15:0] random_state=16'h1639;
 always @(posedge clk)begin
  if(!reset_n)begin cpu_req<=0;busy<=0;latency<=0;data_ready<=0;end
  else begin
   random_state<={random_state[14:0],random_state[15]^random_state[13]^random_state[12]^random_state[10]};
   // Sustained queued RAM writes, as during a disk transfer into memory.
   if(cpu_ack)cpu_req<=0;
   else if(!cpu_req)cpu_req<=1;
   data_ready<=0;
   if(rd||wr||refresh)begin busy<=1;latency<=6+random_state[3:0];end
   else if(latency>1)latency<=latency-1;
   else if(latency==1)begin latency<=0;busy<=0;data_ready<=1;end
  end
 end
 cpu_sdram_arbiter arb(.clk(clk),.reset_n(reset_n),
  .e(cpu_e),.q(cpu_q),
  .cpu_req(cpu_req),.cpu_wr(1'b1),.cpu_addr(23'h10000),.cpu_wdata(8'h41),
  .cpu_ack(cpu_ack),.video_req(memory_request),.video_addr(memory_addr),
  .video_slot_open(slot_count!=0),.refresh_slot_open(slot_count!=0),
  .video_ack(memory_valid),.video_rdata(memory_data),
  .loader_req(1'b0),.loader_wr(1'b0),.loader_addr(23'd0),.loader_wdata(8'd0),
  .rd(rd),.wr(wr),.refresh(refresh),.dout(16'h3841),.dout32(32'h38413841),
  .data_ready(data_ready),.busy(busy),.enabled(1'b1));
 reg checking=0;
 integer hdmi_hits=0,hdmi_misses=0;
 always @(negedge hdmi_clk)if(checking && hdmi_valid && h_y<SCANNED_ROWS && hdmi_x==300)begin
  if(!dut.h_read_valid)begin
   hdmi_misses=hdmi_misses+1;
   $display("HDMI MISS hy=%0d source=%0d state=%0d fill=%0d tags=%0d/%0d valid=%b%b phase=%0d",
    hy,h_y,dut.state,dut.fill_y,dut.h_tag0,dut.h_tag1,dut.h_valid0,dut.h_valid1,phase);
  end else begin
   hdmi_hits=hdmi_hits+1;
   if(hdmi_pixel!==24'hffffff)$fatal(1,"HDMI returned a black/corrupt text pixel");
  end
 end
 integer hits=0,misses=0,parity,analog_seen_y=-1;

 always @(negedge cvbs_clk)if(checking)begin
  if(cvbs_valid&&c_y<SCANNED_ROWS&&cvbs_x>=300&&analog_seen_y!=c_y)begin
   analog_seen_y=c_y;
   if(!dut.c_read_valid)misses=misses+1;
   else begin
    hits=hits+1;
    if(cvbs_pixel!==6'h3f)$fatal(1,"Analog text pixel is black/corrupt");
   end
  end
 end
 task run_phase(input integer field_phase);
  begin
   reset_n=0;checking=0;
   repeat(8)@(negedge clk);
   // Skip vertical blank without changing the relative half-line phase:
   // the 263-line field scans half a line earlier than HDMI's 262.5 lines.
   @(negedge hdmi_clk);hx=0;hy=48-field_phase;
   force analog.h_sample=0;force analog.v_line=41;
   force analog.sample_phase=0;
   @(negedge cvbs_clk);reset_n=1;
   release analog.h_sample;release analog.v_line;release analog.sample_phase;
   hits=0;misses=0;analog_seen_y=-1;hdmi_hits=0;hdmi_misses=0;checking=1;
   wait(analog.v_line==45+SCANNED_ROWS&&analog.h_sample==0);
   @(negedge cvbs_clk);checking=0;
   $display("columns=%0d CPU cycle=%0d field=%0d analog hits=%0d misses=%0d",
            COLUMNS,CPU_CYCLE,field_phase,hits,misses);
   $display("HDMI hits=%0d misses=%0d",hdmi_hits,hdmi_misses);
   if(hdmi_hits!=2*SCANNED_ROWS||hdmi_misses!=0)$fatal(1,"Native text HDMI missed row deadlines");
   if(hits!=SCANNED_ROWS||misses!=0)$fatal(1,"Analog text missed its row deadlines");
  end
 endtask
 initial begin
  for(parity=0;parity<2;parity=parity+1)run_phase(parity);
  $display("tb_gime_text_hdmi_slots PASS");$finish;
 end
 initial begin #50000000;$fatal(1,"timeout");end
endmodule
