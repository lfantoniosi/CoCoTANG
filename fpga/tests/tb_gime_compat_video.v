`timescale 1ns/1ps
module tb_gime_compat_video;
 reg clk=0,reset_n=0,css=0;
 wire hs_n,fs_n,hborder_irq_n,hblank,vblank;
 wire sample,sample_css;
 wire [7:0] sample_y;
 wire [4:0] sample_byte;
 integer errors=0,line_ticks=0,frame_ticks=0,samples=0,lines=0;
 reg saw_hs_release=0,saw_fs_release=0;

 always #5 clk=!clk;
 gime_native_video dut(
  .clk(clk),.reset_n(reset_n),.video_50hz(1'b0),.bit_plane(1'b0),
  .hdmi_frame_start(1'b0),.hdmi_active_50hz(1'b0),
  .active_height(8'd192),.compatibility_mode(1'b1),
  .compatibility_css(css),.pixel_rgb(6'd0),
  .hs_n(hs_n),.fs_n(fs_n),.hborder_irq_n(hborder_irq_n),
  .hblank(hblank),.vblank(vblank),
  .compatibility_sample(sample),.compatibility_sample_css(sample_css),
  .compatibility_sample_y(sample_y),.compatibility_sample_byte(sample_byte),
  .red(),.green(),.blue());

 // Change the live CSS pin after the sample was registered. The recorded
 // value must remain the one observed at the raster edge.
 always @(negedge clk) if(reset_n&&sample&&sample_y==0)begin
  if(sample_css!==css)begin
   $display("VDG CSS was sampled one clock late");errors=errors+1;
  end
  css<=~css;
 end

 always @(posedge clk) if(reset_n)begin
  if(sample&&sample_y==0)begin
   if(sample_byte!==samples[4:0])begin
    $display("VDG byte sample %0d tagged %0d",samples,sample_byte);
    errors=errors+1;
   end
   if(samples==0&&
      (dut.compatibility_x!=10'd231||
       dut.compatibility_y!=dut.compatibility_top))begin
    $display("VDG first CSS sample missed calibrated x/y");errors=errors+1;
   end
   samples=samples+1;
  end
  if(dut.compatibility_raster_tick)begin
   line_ticks=line_ticks+1;frame_ticks=frame_ticks+1;
   if(hs_n&&dut.compatibility_x==10'd67)saw_hs_release=1;
   if(fs_n&&dut.compatibility_y==9'd3&&dut.compatibility_x==10'd1)
    saw_fs_release=1;
   if(dut.compatibility_x==10'd911)begin
    if(line_ticks!=912)begin
     $display("VDG line had %0d ticks",line_ticks);errors=errors+1;
    end
    line_ticks=0;lines=lines+1;
    if(dut.compatibility_y==9'd261)begin
     if(lines!=262||frame_ticks!=238944||samples!=32||
        !saw_hs_release||!saw_fs_release)begin
      $display("VDG field lines=%0d ticks=%0d samples=%0d HS=%b FS=%b",
               lines,frame_ticks,samples,saw_hs_release,saw_fs_release);
      errors=errors+1;
     end
     if(errors==0)$display("tb_gime_compat_video PASS");
     else $display("tb_gime_compat_video FAIL: %0d",errors);
     $finish;
    end
   end
  end
 end

 initial begin
  repeat(3)@(posedge clk);reset_n=1;
  repeat(2400000)@(posedge clk);
  $display("tb_gime_compat_video timeout");$finish;
 end
endmodule
