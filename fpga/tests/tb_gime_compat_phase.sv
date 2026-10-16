`timescale 1ns/1ps
module tb_gime_compat_phase;
 reg clk=0,board_reset_n=0,core_reset_n=0,fast_mode=1;
 wire e_fall,video_tick,video_sync,hs_n,sample;
 wire [7:0] sample_y;wire [4:0] sample_byte;
 integer clocks=0,last_sync=0,release_cycles,speed_cycles,edges=0;
 integer ticks=0;
 always #5 clk=~clk;
 always @(posedge clk)clocks=clocks+1;
 always @(posedge video_sync)last_sync=clocks;
 gime_timing cpu(.clk(clk),.reset_n(board_reset_n),.fast_mode(fast_mode),
  .e_fall(e_fall),.video_tick(video_tick),.video_e_fall(video_sync));
 gime_native_video #(.USE_CPU_VIDEO_CLOCK(1)) dut(
  .clk(clk),.reset_n(core_reset_n),.video_50hz(1'b0),.bit_plane(1'b1),
  .hres(4'd0),.vmode(8'h80),.active_height(8'd192),
  .hdmi_frame_start(1'b0),.hdmi_active_50hz(1'b0),
  .compatibility_mode(1'b1),.compatibility_css(1'b0),
  .compatibility_clock_tick(video_tick),.compatibility_clock_sync(video_sync),
  .compatibility_border_rgb(6'd0),.pixel_rgb(6'd0),.hs_n(hs_n),
  .compatibility_sample(sample),.compatibility_sample_y(sample_y),
  .compatibility_sample_byte(sample_byte));
 // Both possible fast E release phases, plus odd/even speed excursions,
 // must place HS after the same slow master phase. Fractional-N jitter
 // allows one 108 MHz clock, never half a CPU cycle (~60 clocks).
 always @(negedge hs_n)if(core_reset_n)begin
  #1;
  if(clocks-last_sync<9||clocks-last_sync>10)
   $fatal(1,"HS phase changed release=%0d fast=%b offset=%0d",
      release_cycles,fast_mode,clocks-last_sync);
  edges=edges+1;
 end
 always @(negedge clk)begin
  if(!core_reset_n)ticks=0;
  else if(dut.compatibility_raster_tick)begin
   ticks=ticks+1;
   if(dut.compatibility_x==911)begin
    if(ticks!=912)$fatal(1,"compatibility line changed: %0d ticks",ticks);
    ticks=0;
   end
  end
 end
 initial begin
  for(release_cycles=1;release_cycles<=4;release_cycles=release_cycles+1)begin
   @(negedge clk);board_reset_n=0;core_reset_n=0;fast_mode=1;
   repeat(3+release_cycles)@(negedge clk);board_reset_n=1;
   repeat(release_cycles)@(posedge e_fall);
   @(negedge clk);core_reset_n=1;
   repeat(2)@(posedge e_fall);
   @(negedge clk);fast_mode=0;
   for(speed_cycles=1;speed_cycles<=8;speed_cycles=speed_cycles+1)begin
    repeat(3)@(posedge e_fall);
    @(negedge clk);fast_mode=1;
    repeat(speed_cycles)@(posedge e_fall);
    @(negedge clk);fast_mode=0;
   end
   wait(sample&&sample_y==0&&sample_byte==0);#1;
   if(dut.compatibility_x!=247||dut.compatibility_y!=42)
    $fatal(1,"startup changed calibrated CSS origin");
  end
  if(edges<160)$fatal(1,"insufficient raster coverage: %0d lines",edges);
  $display("tb_gime_compat_phase PASS");$finish;
 end
 initial begin #20000000;$fatal(1,"compatibility phase test timeout");end
endmodule
