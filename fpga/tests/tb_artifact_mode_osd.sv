`timescale 1ns/1ps
module tb_artifact_mode_osd;
 logic clk=0,reset=0,ssc_enabled=0;logic [1:0] mode=0;
 logic [9:0] x=0,y=0;logic [23:0] rgb_in=24'h123456;
 logic [23:0] rgb_out,analog_rgb,large_rgb;
 logic [9:0] large_x=0,large_y=0;
 integer i,m,px,py,dx,dy;
 logic [175:0] expected;
 artifact_mode_osd #(.DISPLAY_CYCLES(32)) dut(
  .pixel_clk(clk),.reset(reset),.mode(mode),.ssc_enabled(ssc_enabled),.x(x),.y(y),
  .rgb_in(rgb_in),.rgb_out(rgb_out));
 artifact_mode_osd #(.DISPLAY_CYCLES(32),.PANEL_X(228),
  .TIMER_DIVIDER(4),.REGISTER_PIXELS(1)) analog_osd(
  .pixel_clk(clk),.reset(reset),.mode(mode),.ssc_enabled(ssc_enabled),.x(x-10'd40),.y(y),
  .rgb_in(rgb_in),.rgb_out(analog_rgb));
 artifact_mode_osd #(.DISPLAY_CYCLES(1000000),.PANEL_X(136),
  .FONT_SCALE_LOG2(1),.REGISTER_PIXELS(1)) large_osd(
  .pixel_clk(clk),.reset(reset),.mode(mode),.ssc_enabled(ssc_enabled),
  .x(large_x),.y(large_y),.rgb_in(rgb_in),.rgb_out(large_rgb));
 always #5 clk=!clk;
 initial begin
  reset=1;repeat(2)@(negedge clk);reset=0;
  x=269;y=17;repeat(2)@(negedge clk);
  if(rgb_out!==24'h102040||analog_rgb!==rgb_out)$fatal(1,"OSD panels missing");
  for(m=0;m<6;m=m+1)begin
   case(m)
    0:begin mode=1;ssc_enabled=0;expected="ARTIFACT NORMAL       ";end
    1:begin mode=2;ssc_enabled=0;expected="ARTIFACT REVERSE      ";end
    2:begin mode=0;ssc_enabled=0;expected="NO ARTIFACT           ";end
    3:begin mode=1;ssc_enabled=1;expected="ARTIFACT NORMAL - SSC ";end
    4:begin mode=2;ssc_enabled=1;expected="ARTIFACT REVERSE - SSC";end
    5:begin mode=0;ssc_enabled=1;expected="NO ARTIFACT - SSC     ";end
   endcase
   repeat(5)@(negedge clk);
   for(i=0;i<22;i=i+1)
    if(dut.message_character(dut.mode_seen,5'(i))!==expected[175-i*8 -: 8])
     $fatal(1,"wrong label mode %0d character %0d",m,i);
  end
  mode=2;ssc_enabled=0;repeat(5)@(negedge clk);
  repeat(34)@(negedge clk);
  if(rgb_out!==rgb_in||analog_rgb!==rgb_in)$fatal(1,"OSD did not expire");
  // SSC alone must retrigger both outputs, and the final SSC must be visible.
  ssc_enabled=1;x=441;y=20;repeat(5)@(negedge clk);
  if(rgb_out!==24'hffffff||analog_rgb!==rgb_out)$fatal(1,"SSC suffix not rendered on both outputs");
  x=10;y=20;repeat(2)@(negedge clk);
  if(rgb_out!==rgb_in||analog_rgb!==rgb_in)$fatal(1,"OSD changed pixels outside panel");
  // Compare every doubled glyph cell against the font bitmap, including
  // spacing and the SSC suffix, for all six reset selections.
  for(m=0;m<6;m=m+1)begin
   mode=2'(m%3);ssc_enabled=m>=3;repeat(5)@(negedge clk);
   for(py=0;py<7;py=py+1)begin
    expected=large_osd.message_row({ssc_enabled,mode},3'(py));
    for(px=0;px<176;px=px+1)
    for(dy=0;dy<2;dy=dy+1)for(dx=0;dx<2;dx=dx+1)begin
     large_x=144+px*2+dx;large_y=24+py*2+dy;
     repeat(2)@(negedge clk);
     if(large_rgb!==(expected[175-px] ?
                    24'hffffff:24'h102040))
      $fatal(1,"2x font mismatch mode=%0d pixel=%0d,%0d subpixel=%0d,%0d",m,px,py,dx,dy);
    end
   end
  end
  $display("tb_artifact_mode_osd PASS");$finish;
 end
endmodule
