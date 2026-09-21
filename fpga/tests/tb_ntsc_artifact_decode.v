`timescale 1ns/1ps
module tb_ntsc_artifact_decode;
 reg [5:0] neighborhood=0;
 reg odd_pixel=0,reverse_phase=0,css=1;
 wire [5:0] rgb;
 integer errors=0;
 ntsc_artifact_decode dut(.neighborhood(neighborhood),.odd_pixel(odd_pixel),
  .reverse_phase(reverse_phase),.css(css),.rgb(rgb));
 initial begin
  #1;
  if(rgb!==6'h00)begin $display("black endpoint wrong: %h",rgb);errors=errors+1;end
  neighborhood=6'b000010;odd_pixel=1;reverse_phase=0;#1;
  if(rgb!==6'h24)begin $display("standard phase wrong: %h",rgb);errors=errors+1;end
  reverse_phase=1;#1;
  if(rgb!==6'h05)begin $display("reverse phase wrong: %h",rgb);errors=errors+1;end
  neighborhood=6'h3f;odd_pixel=1;#1;
  if(rgb!==6'h3e)begin $display("buff endpoint wrong: %h",rgb);errors=errors+1;end
  if(errors==0)$display("tb_ntsc_artifact_decode PASS");
  else $display("tb_ntsc_artifact_decode FAIL: %0d",errors);
  $finish;
 end
endmodule
