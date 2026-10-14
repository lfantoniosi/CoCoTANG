`timescale 1ns/1ps
// Preserve the legacy HBORD/PIA raster phase while making native VBORD
// safe for next-frame VOFF/HOFF writes at different CPU startup phases.
module tb_coco3_vborder_startup;
 reg clk=0,pixel_clk=0,board_reset=1,core_reset_n=0;
 always #5 clk=~clk;
 always #20 pixel_clk=~pixel_clk;
 wire frame_start,vb;
 wire [7:0] source_y,prefetch_y;
 wire active,prefetch_valid;
 wire [9:0] source_x;
 wire source_valid;
 reg swapped=0;
 integer mixed_rows=0;
 wire mem_req;
 wire [22:0] mem_addr;
 reg mem_valid=0;
 reg [1:0] mem_state=0;
 reg [4:0] prior_state=0;
 reg [15:0] cpu_addr=16'hffff;
 reg [7:0] cpu_data=0;
 reg cpu_rw_n=1;
 coco3 machine(.clk(clk),.reset_n(!board_reset),.cpu_reset_n(core_reset_n),
  .s2(1'b0),.artifact_mode(2'd0),.cpu_addr(cpu_addr),
  .cpu_rw_n(cpu_rw_n),.cpu_data(cpu_data),
  .serint_n(1'b1),.keyint_n(1'b1),.cart_n(1'b1),
  .video_memory_data(8'd0),.video_memory_data32(32'h01234567),
  .video_memory_valid(mem_valid),.video_memory_request(mem_req),
  .video_memory_addr(mem_addr),.hdmi_read_clk(pixel_clk),
  .hdmi_source_x(source_x),.hdmi_source_y(source_y),
  .hdmi_source_valid(source_valid),.hdmi_source_picture_active(active),
  .hdmi_prefetch_y(prefetch_y),.hdmi_prefetch_valid(prefetch_valid),
  .hdmi_frame_start(frame_start),.hdmi_active_50hz(1'b0),
  .hdmi_border_raster_y(9'd0),.cvbs_read_clk(pixel_clk),
  .cvbs_source_x(10'd0),.cvbs_source_y(8'd0),.cvbs_source_valid(1'b0),
  .cvbs_prefetch_y(8'd0),.cvbs_prefetch_valid(1'b0),
  .cvbs_border_raster_y(9'd0));
 assign vb=machine.vborder_irq_n;
 wire legacy_hs,legacy_fs,legacy_hbord;
 gime_native_video legacy_raster(.clk(clk),.reset_n(!board_reset&&core_reset_n),
  .video_50hz(machine.video_50hz),.bit_plane(machine.effective_bit_plane),
  .hres(machine.effective_hres),.vmode(machine.vmode),
  .hdmi_frame_start(frame_start),.hdmi_active_50hz(1'b0),
  .active_height(machine.active_height),.compatibility_mode(machine.compatibility_mode),
  .compatibility_css(1'b0),.compatibility_border_rgb(6'd0),.pixel_rgb(6'd0),
  .hs_n(legacy_hs),.fs_n(legacy_fs),.hborder_irq_n(legacy_hbord));
 always @(negedge clk)if(core_reset_n)begin
  if({machine.hs_n,machine.fs_n,machine.hborder_irq_n}!==
     {legacy_hs,legacy_fs,legacy_hbord})
   $fatal(1,"HBORD/PIA raster timing changed from legacy CPU-release phase");
 end
 task write_register;
  input [15:0] address;
  input [7:0] value;
  begin
   @(negedge clk);cpu_addr=address;cpu_data=value;cpu_rw_n=0;
   @(posedge machine.e_fall);
   repeat(2)@(negedge clk);
   cpu_rw_n=1;
  end
 endtask
 always @(posedge clk) begin
  if(!core_reset_n)begin mem_state<=0;mem_valid<=0;prior_state<=0;end
  else begin
   mem_valid<=0;
   if(mem_req && mem_state==0)mem_state<=1;
   else if(mem_state==1)begin mem_valid<=1;mem_state<=2;end
   else if(mem_state==2 && !mem_req)mem_state<=0;
   prior_state<=machine.scanlines.state;
  end
 end
 always @(negedge clk)begin
  if(core_reset_n && swapped &&
     machine.scanlines.state==machine.scanlines.DIVIDE_ROW && prior_state==0 &&
     machine.scanlines.fill_y>=176 && machine.scanlines.fill_hoff==7 &&
     machine.scanlines.frame_screen_base==19'h2000)begin
   mixed_rows=mixed_rows+1;
   if(mixed_rows<=2)
    $display("mixed scroll row=%0d: frame origin=%h fill offset=%h live origin=%h",
     machine.scanlines.fill_y,machine.scanlines.frame_screen_base,
     machine.scanlines.fill_hoff,machine.effective_screen_base);
  end
 end
 coco3_hdmi display(.pixel_clk(pixel_clk),.serial_clk(pixel_clk),
  .audio_clk(pixel_clk),.audio_pcm_left(16'd0),.audio_pcm_right(16'd0),.reset(board_reset),
  .video_50hz(1'b0),.bit_plane(1'b1),.active_height(8'd192),
  .compatibility_mode(1'b0),.border_rgb(6'd0),.artifact_mode(2'd0),
  .artifact_video_active(1'b0),.artifact_css(1'b0),.overlay_enable(1'b0),
  .row_border_valid(1'b0),.vertical_border_valid(1'b0),.pixel_data(24'd0),
  .source_frame_start(frame_start),.source_y(source_y),
  .source_x(source_x),.source_valid(source_valid),
  .source_picture_active(active),.prefetch_y(prefetch_y),
  .prefetch_valid(prefetch_valid));
 defparam display.encoder.DVI_OUTPUT=1;
 task run_phase;
 input integer release_line;
 begin
  @(negedge clk);
  core_reset_n=0;board_reset=1;cpu_rw_n=1;swapped=0;mixed_rows=0;
  repeat(8)@(negedge clk);
  board_reset=0;
  wait(display.y==release_line && display.x==0);
  @(negedge clk);core_reset_n=1;
  write_register(16'hff92,8'h08);
  write_register(16'hff98,8'h80);
  write_register(16'hff99,8'h1a); // 256 pixels, 16 colours, 192 lines
  write_register(16'hff9d,8'h04);
  write_register(16'hff9e,8'h00);
  write_register(16'hff9f,8'h80);
  @(negedge vb);#1;
  $display("core release HDMI line=%0d: VBORD HDMI line=%0d x=%0d logical row=%0d, rows remaining=%0d, next prefetch=%0d valid=%b",
    release_line,display.y,display.x,source_y,192-source_y,prefetch_y,prefetch_valid);
  if(!machine.picture_fetch_complete)
   $fatal(1,"VBORD fired before the final row was cached: row=%0d",source_y);
  repeat(2)@(negedge clk);
  if(!machine.registers.irq_pending[3])
   $fatal(1,"qualified VBORD did not latch the CPU interrupt");
  // Even an immediate handler must leave the old frame's rows intact.
  write_register(16'hff9d,8'h24);
  write_register(16'hff9e,8'h00);
  write_register(16'hff9f,8'h87);
  swapped=1;
  wait(!active);
  repeat(4)@(negedge clk);
  $display("rows filled using old origin/new offset=%0d",mixed_rows);
  if(mixed_rows!=0)$fatal(1,"VBORD exposed bottom rows to next-frame HOFF");
  // The next frame must still pick up the queued screen-buffer swap.
  @(posedge frame_start);
  repeat(16)@(negedge clk);
  if(machine.scanlines.frame_screen_base!=19'h12000)
   $fatal(1,"next frame did not capture new VOFF");
 end
 endtask
 initial begin
  run_phase(0);
  run_phase(497);
  $display("tb_coco3_vborder_startup PASS");$finish;
 end
 initial begin #100000000;$fatal(1,"timeout");end
endmodule
// Keep the real HDMI timing and source-row mapping; only the physical
// output serializer and differential pads are irrelevant to this test.
module serializer #(parameter integer NUM_CHANNELS=3,parameter real VIDEO_RATE=0)(
 input clk_pixel,clk_pixel_x5,reset,input [9:0] tmds_internal [NUM_CHANNELS-1:0],output [2:0] tmds,output tmds_clock);
 assign tmds=0;assign tmds_clock=0;
endmodule
module ELVDS_OBUF(input I,output O,OB);assign O=I;assign OB=~I;endmodule
