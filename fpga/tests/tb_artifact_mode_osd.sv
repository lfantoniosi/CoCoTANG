`timescale 1ns/1ps
module tb_artifact_mode_osd;
 logic clk=0,reset=0;logic [1:0] mode=0;
 logic [9:0] x=0,y=0;logic [23:0] rgb_in=24'h123456;
 logic [23:0] rgb_out;integer errors=0;
 artifact_mode_osd #(.DISPLAY_CYCLES(8)) dut(
  .pixel_clk(clk),.reset(reset),.mode(mode),.x(x),.y(y),
  .rgb_in(rgb_in),.rgb_out(rgb_out));
 always #5 clk=!clk;
 initial begin
  reset=1;repeat(2)@(posedge clk);#1;reset=0;
  x=10'd269;y=10'd17;#1;
  if(rgb_out!==24'h102040)begin $display("OSD panel missing");errors++;end
  x=10'd393;y=10'd20;#1;
  if(rgb_out!==24'hffffff)begin $display("OSD OFF label missing");errors++;end
  repeat(10)@(posedge clk);#1;
  if(rgb_out!==rgb_in)begin $display("OSD did not expire");errors++;end
  mode=2'd2;repeat(4)@(posedge clk);#1;
  x=10'd269;y=10'd17;#1;
  if(rgb_out!==24'h102040||dut.mode_seen!==2'd2)begin
   $display("OSD did not retrigger for reverse mode");errors++;end
  if(errors==0)$display("tb_artifact_mode_osd PASS");
  else $display("tb_artifact_mode_osd FAIL: %0d",errors);
  $finish;
 end
endmodule
