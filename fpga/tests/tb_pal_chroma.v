`timescale 1ns/1ps
module tb_pal_chroma;
 reg clk135=0,clk270=0,reset_n=0;
 wire [15:0] addr; wire [9:0] sx; wire [7:0] sy,py;
 wire sv, pv, y, c, cv, pb, pr;
 integer errors=0;
 coco_cvbs_ntsc #(.CANONICAL_640_INPUT(1),.PAL_MACHINE(1)) dut(
  .clk135(clk135),.clk270(clk270),.reset_n(reset_n),.video_50hz(1'b1),
  .high_resolution(1'b1),.compatibility_mode(1'b0),
  .framebuffer_data(6'd0),.border_rgb(6'd0),.row_border_rgb(6'd0),
  .row_border_valid(1'b0),.active_height(8'd192),.framebuffer_addr(addr),
  .source_x(sx),.source_y(sy),.source_valid(sv),.prefetch_y(py),
  .prefetch_valid(pv),.luma_out(y),.chroma_out(c),.cvbs_out(cv),
  .component_pb_out(pb),.component_pr_out(pr));
 always #4 clk135=~clk135;
 always #2 clk270=~clk270;
 initial begin
  #20; reset_n=1; #20;
  force dut.mod_burst=1'b1; force dut.mod_carrier=3'd0;
  force dut.mod_pal_odd=1'b0; #1;
  if(dut.mod_selected_chroma!==6)begin
   $display("PAL even burst=%0d",dut.mod_selected_chroma);errors=errors+1;end
  force dut.mod_pal_odd=1'b1; #1;
  if(dut.mod_selected_chroma!==-6)begin
   $display("PAL odd burst=%0d",dut.mod_selected_chroma);errors=errors+1;end
  force dut.level_carrier=3'd2;
  force dut.level_pal_odd=1'b0; #1;
  if(dut.pal_svideo_burst_phase!==3'd2)begin
   $display("PAL S-video even phase=%0d",dut.pal_svideo_burst_phase);errors=errors+1;end
  force dut.level_pal_odd=1'b1; #1;
  if(dut.pal_svideo_burst_phase!==3'd4)begin
   $display("PAL S-video odd phase=%0d",dut.pal_svideo_burst_phase);errors=errors+1;end
  force dut.v_line=9'd0; force dut.pal_line_parity=1'b0; #1;
  if(dut.pal_line_odd!==1'b0)begin
   $display("PAL initial line parity wrong");errors=errors+1;end
  force dut.pal_line_parity=1'b1; #1;
  if(dut.pal_line_odd!==1'b1)begin
   $display("PAL long-field parity did not carry");errors=errors+1;end
  // PAL burst must use the continuous chroma sigma-delta path.  The
  // NTSC-only XOR shaper is not coherent with the 4.43-MHz carrier.
  force dut.chroma_burst_270=1'b1;
  force dut.shaped_burst_bit=1'b0;
  force dut.chroma_sigma=6'b100000;
  @(posedge clk270); #1;
  if(c!==1'b1)begin
   $display("PAL S-video burst bypassed chroma DAC");errors=errors+1;end
  if(errors==0)$display("tb_pal_chroma PASS");
  else $display("tb_pal_chroma FAIL: %0d",errors);
  $finish;
 end
endmodule
