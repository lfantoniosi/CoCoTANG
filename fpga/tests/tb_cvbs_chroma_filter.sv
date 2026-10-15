`timescale 1ns/1ps
module tb_cvbs_chroma_filter;
 reg clk135=0,clk270=0,reset_n=0,sample_tick=0;
 reg signed [7:0] axis=0;
 reg [10:0] input_sum=32;
 reg [2:0] phase=0;
 reg check_range=0;
 integer legacy_overshoots=0;
 always #4 clk135=~clk135;
 always #2 clk270=~clk270;
 wire [5:0] composite[0:3];
 wire signed [7:0] envelope[0:3];
 wire [6:0] y_level[0:3];
 wire [5:0] c_level[0:3];
 wire y_pin[0:3],c_pin[0:3];
 genvar channel;
 generate for(channel=0;channel<4;channel=channel+1)begin: encoders
  // Two NTSC and two PAL encoders, each comparing two- and four-tap chroma.
  coco_cvbs_ntsc #(.PAL_CHROMA_OUTPUT(channel>=2),
   .CVBS_SVIDEO_SCANLINE_PHASE_ALTERNATION(1),
   .CVBS_LUMA_FILTER(1),.CVBS_LUMA_NOTCH(1),
   .CVBS_CHROMA_FILTER(channel%2)) dut(
   .clk135(clk135),.clk270(clk270),.reset_n(reset_n),
   .video_50hz(1'b0),.high_resolution(1'b1),.compatibility_mode(1'b0),
   .framebuffer_data(6'd0),.border_rgb(6'd0),.row_border_rgb(6'd0),
   .row_right_border_rgb(6'd0),.row_border_valid(1'b0),
   .vertical_left_border_rgb(6'd0),.vertical_right_border_rgb(6'd0),
   .vertical_border_valid(1'b0),.active_height(8'd192),
   .luma_out(y_pin[channel]),.chroma_out(c_pin[channel]));
  assign composite[channel]=dut.composite_level;
  assign envelope[channel]=(channel%2) ? dut.cvbs_chroma_x_filtered : dut.chroma_x_filtered;
  assign y_level[channel]=dut.luma_level;
  assign c_level[channel]=dut.chroma_level;
  initial begin
   force dut.encoder_x_axis=axis;
   force dut.encoder_y_axis=axis;
   force dut.encoder_luma_sum=input_sum;
   force dut.encoder_sample_tick=sample_tick;
   force dut.mod_carrier=phase;
   force dut.mod_burst=0;
   force dut.level_sync=0;
   force dut.level_burst=0;
   force dut.level_picture=1;
  end
 end endgenerate
 always @(negedge clk270)if(reset_n)begin
  if({y_pin[1],c_pin[1]}!=={y_pin[0],c_pin[0]} ||
     {y_pin[3],c_pin[3]}!=={y_pin[2],c_pin[2]})
   $fatal(1,"CVBS chroma filter changed S-Video DAC waveform");
 end
 always @(posedge clk135)begin
  #1;
  if(reset_n && check_range)begin
   if(composite[1]>32 || composite[3]>32)
    $fatal(1,"filtered green/white edge exceeded DAC range: NTSC=%0d PAL=%0d",
      composite[1],composite[3]);
   if(composite[0]>32)legacy_overshoots=legacy_overshoots+1;
  end
 end
 task sample(input integer value,input integer luma_sum);
  begin
   @(negedge clk135);axis=value;input_sum=luma_sum;sample_tick=1;
   @(negedge clk135);sample_tick=0;
   repeat(8)@(negedge clk135);#1;
   if(y_level[1]!==y_level[0] || c_level[1]!==c_level[0] ||
      y_level[3]!==y_level[2] || c_level[3]!==c_level[2])
    $fatal(1,"CVBS chroma filter changed S-Video levels");
  end
 endtask
 task green_step(input integer expected);
  begin
   sample(-63,788);
   if(envelope[1]!==expected || envelope[3]!==expected)
    $fatal(1,"green step envelope=%0d/%0d expected %0d",envelope[1],envelope[3],expected);
  end
 endtask
 task frequency(input real hz,input integer stopband);
  integer index,value,input_energy,old_energy,new_energy,delta;
  begin
   input_energy=0;old_energy=0;new_energy=0;
   for(index=0;index<1096;index=index+1)begin
    value=$rtoi(-31.0+31.0*$sin(6.283185307179586*hz*index/13500000.0));
    sample(value,32-12*value);
    if(index>=16)begin
     delta=value+31;input_energy=input_energy+delta*delta;
     delta=envelope[0]+31;old_energy=old_energy+delta*delta;
     delta=envelope[1]+31;new_energy=new_energy+delta*delta;
    end
   end
   $display("chroma f=%0.3f MHz: input=%0d two-tap=%0d four-tap=%0d",
     hz/1000000.0,input_energy,old_energy,new_energy);
   if(stopband)begin
    if(new_energy*10>old_energy)$fatal(1,"high-frequency chroma reduction below 10 dB");
   end else if(new_energy*100<input_energy*80 || new_energy*100>input_energy*105)
    $fatal(1,"low-frequency chroma gain changed excessively");
  end
 endtask
 integer colour_phase;
 initial begin
  repeat(3)@(negedge clk135);reset_n=1;
  repeat(6)sample(0,32);
  green_step(-16);green_step(-31);green_step(-47);green_step(-63);
  repeat(6)sample(-63,788);
  for(colour_phase=0;colour_phase<8;colour_phase=colour_phase+1)begin
   phase=colour_phase;repeat(2)sample(-63,788);
   if(composite[1]!==composite[0] || composite[3]!==composite[2])
    $fatal(1,"steady green saturation/hue changed at carrier phase %0d",colour_phase);
   check_range=1;
   repeat(6)sample(0,1292); // White: real RGB222 matrix luma.
   repeat(6)sample(-63,788);
   check_range=0;
  end
  $display("green/white transient overshoots: legacy=%0d filtered=0",legacy_overshoots);
  if(legacy_overshoots==0)$fatal(1,"green-edge regression did not exercise DAC overflow");
  frequency(500000.0,0);
  frequency(3375000.0,1);
  force encoders[0].dut.mod_burst=1;
  force encoders[1].dut.mod_burst=1;
  force encoders[2].dut.mod_burst=1;
  force encoders[3].dut.mod_burst=1;
  repeat(3)@(negedge clk135);
  if(encoders[0].dut.level_chroma!==encoders[1].dut.level_chroma ||
     encoders[2].dut.level_chroma!==encoders[3].dut.level_chroma)
   $fatal(1,"CVBS chroma filter changed burst amplitude or phase");
  $display("CVBS green-edge chroma filtering, DAC range and unchanged S-Video PASS");
  $finish;
 end
endmodule
