`timescale 1ns/1ps
module tb_cvbs_luma_notch;
 reg clk135=0,clk270=0,reset_n=0;
 reg [10:0] input_sum=0;
 reg [5:0] rgb_input=0;
 reg sample_tick=0;
 always #4 clk135=~clk135;
 always #2 clk270=~clk270;
 wire [5:0] cvbs_y[0:4],svideo_c[0:4];
 wire [6:0] svideo_y[0:4];
 wire y_pin[0:4],c_pin[0:4];
 genvar channel;
 generate for(channel=0;channel<5;channel=channel+1)begin: encoders
  // NTSC: bypass, Gaussian, trap. PAL: bypass, trap.
  coco_cvbs_ntsc #(.PAL_CHROMA_OUTPUT(channel>=3),
   .CVBS_SVIDEO_SCANLINE_PHASE_ALTERNATION(1),
   .CVBS_LUMA_FILTER(channel==1||channel==2||channel==4),
   .CVBS_LUMA_NOTCH(channel==2||channel==4)) dut(
   .clk135(clk135),.clk270(clk270),.reset_n(reset_n),
   .video_50hz(1'b0),.high_resolution(1'b1),.compatibility_mode(1'b0),
   .framebuffer_data(rgb_input),.border_rgb(rgb_input),.row_border_rgb(6'd0),
   .row_right_border_rgb(6'd0),.row_border_valid(1'b0),
   .vertical_left_border_rgb(6'd0),.vertical_right_border_rgb(6'd0),
   .vertical_border_valid(1'b0),.active_height(8'd192),
   .luma_out(y_pin[channel]),.chroma_out(c_pin[channel]));
  assign cvbs_y[channel]=dut.level_luma;
  assign svideo_y[channel]=dut.luma_level;
  assign svideo_c[channel]=dut.chroma_level;
 end endgenerate
 initial begin
  force encoders[0].dut.encoder_luma_sum=input_sum;
  force encoders[1].dut.encoder_luma_sum=input_sum;
  force encoders[2].dut.encoder_luma_sum=input_sum;
  force encoders[3].dut.encoder_luma_sum=input_sum;
  force encoders[4].dut.encoder_luma_sum=input_sum;
  force encoders[0].dut.encoder_sample_tick=sample_tick;
  force encoders[1].dut.encoder_sample_tick=sample_tick;
  force encoders[2].dut.encoder_sample_tick=sample_tick;
  force encoders[3].dut.encoder_sample_tick=sample_tick;
  force encoders[4].dut.encoder_sample_tick=sample_tick;
 end
 // Keep the actual ten-clock sample spacing so the history pipeline has
 // the same settling interval as the real encoder.
 task sample(input integer value);
  begin
   @(negedge clk135);input_sum=(value-10)*64;rgb_input=value;sample_tick=1;
   @(negedge clk135);sample_tick=0;
   repeat(8)@(negedge clk135);
   #1;
   if(svideo_y[2]!==svideo_y[0] || svideo_c[2]!==svideo_c[0] ||
      svideo_y[4]!==svideo_y[3] || svideo_c[4]!==svideo_c[3])
    $fatal(1,"CVBS trap changed S-Video levels");
  end
 endtask
 always @(negedge clk270)if(reset_n)begin
  if({y_pin[2],c_pin[2]}!=={y_pin[0],c_pin[0]} ||
     {y_pin[4],c_pin[4]}!=={y_pin[3],c_pin[3]})
   $fatal(1,"CVBS trap changed S-Video DAC waveform");
 end
 task impulse(input integer ntsc,input integer pal);
  begin
   if(cvbs_y[2]!==ntsc[5:0] || cvbs_y[4]!==pal[5:0])
    $fatal(1,"trap impulse mismatch: NTSC=%0d PAL=%0d expected %0d/%0d",
     cvbs_y[2],cvbs_y[4],ntsc,pal);
  end
 endtask
 task frequency(input real hz,input integer which,input integer stopband);
  integer index,value,delta,input_energy,output_energy,gaussian_energy;
  real phase;
  begin
   input_energy=0;output_energy=0;gaussian_energy=0;
   for(index=0;index<1072;index=index+1)begin
    phase=6.283185307179586*hz*index/13500000.0;
    value=$rtoi(21.5+11.0*$sin(phase));
    sample(value);
    if(index>=16)begin
     delta=value-21;input_energy=input_energy+delta*delta;
     delta=cvbs_y[which]-21;output_energy=output_energy+delta*delta;
     delta=cvbs_y[1]-21;gaussian_energy=gaussian_energy+delta*delta;
    end
   end
   $display("f=%0.3f MHz: input energy=%0d trap=%0d Gaussian=%0d",
     hz/1000000.0,input_energy,output_energy,gaussian_energy);
   if(stopband)begin
    if(output_energy*100>input_energy)$fatal(1,"carrier rejection below 20 dB");
    if(which==2 && output_energy*10>gaussian_energy)
     $fatal(1,"NTSC trap did not improve carrier rejection by 10 dB");
   end else if(output_energy*100<input_energy*80 ||
               output_energy*100>input_energy*105)
    $fatal(1,"trap changed low-frequency brightness excessively");
  end
 endtask
 initial begin
  repeat(3)@(negedge clk135);reset_n=1;
  repeat(6)sample(10);impulse(10,10);
  sample(32);impulse(15,14);
  sample(10);impulse(16,17);
  sample(10);impulse(16,17);
  sample(10);impulse(15,14);
  sample(10);impulse(10,10);
  repeat(6)sample(32);impulse(32,32);
  frequency(500000.0,2,0);
  frequency(3579545.454545,2,1);
  frequency(4433618.75,4,1);
  force encoders[2].dut.level_sync=1;
  force encoders[2].dut.level_burst=0;
  force encoders[2].dut.level_picture=0;
  #1;if(encoders[2].dut.composite_level!==0)$fatal(1,"trap changed sync");
  force encoders[2].dut.level_sync=0;
  #1;if(encoders[2].dut.composite_level!==10)$fatal(1,"trap changed blanking");
  force encoders[2].dut.level_burst=1;
  force encoders[0].dut.level_burst=1;
  force encoders[0].dut.level_sync=0;
  force encoders[0].dut.level_picture=0;
  #1;if(encoders[2].dut.composite_level!==encoders[0].dut.composite_level)
   $fatal(1,"trap changed colour burst");
  $display("CVBS NTSC/PAL luma trap and unchanged S-Video PASS");$finish;
 end
endmodule
