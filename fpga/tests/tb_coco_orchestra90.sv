`timescale 1ns/1ps
module tb_coco_orchestra90;
 reg clk=0,reset_n=0,e_fall=0,cpu_rw_n=1;
 reg [15:0] cpu_addr=0,mono_pcm=0;
 reg [7:0] cpu_data=0;
 wire [15:0] left_pcm,right_pcm,disabled_left,disabled_right;
 wire [15:0] mono_mix_pcm,disabled_mono;
 wire [7:0] analog_sample={~mono_mix_pcm[15],mono_mix_pcm[14:8]};
 wire audio_out;
 sigma_delta_dac analog_dac(.clk(clk),.reset_n(reset_n),
  .sample(analog_sample),.bit_out(audio_out));
 always #5 clk=~clk;
 coco_orchestra90 dut(.*);
 coco_orchestra90 #(.ENABLED(0)) disabled(
  .clk(clk),.reset_n(reset_n),.e_fall(e_fall),.cpu_rw_n(cpu_rw_n),
  .cpu_addr(cpu_addr),.cpu_data(cpu_data),.mono_pcm(mono_pcm),
  .left_pcm(disabled_left),.right_pcm(disabled_right),.mono_mix_pcm(disabled_mono));
 coco3_hdmi display(.pixel_clk(clk),.serial_clk(clk),.audio_clk(clk),
  .reset(!reset_n),.audio_pcm_left(left_pcm),.audio_pcm_right(right_pcm),
  .video_50hz(1'b0),.bit_plane(1'b1),.active_height(8'd192),
  .compatibility_mode(1'b0),.border_rgb(6'd0),.artifact_mode(2'd0),
  .artifact_video_active(1'b0),.artifact_css(1'b0),.overlay_enable(1'b0),
  .row_border_valid(1'b0),.vertical_border_valid(1'b0),.pixel_data(24'd0));
 // Exercise the real HDMI sample-packet formatter with the wrapper's
 // channel array. Timing/serializer stubs come from the border-handoff test.
 wire [23:0] packet_words[3:0][1:0];
 wire [1:0] flags[3:0];
 wire [23:0] header;
 wire [55:0] sub[3:0];
 genvar sample_index;
 generate for(sample_index=0;sample_index<4;sample_index=sample_index+1)begin
  assign packet_words[sample_index][0]={display.audio_samples[0],8'd0};
  assign packet_words[sample_index][1]={display.audio_samples[1],8'd0};
  assign flags[sample_index]=2'b00;
 end endgenerate
 audio_sample_packet packet(.frame_counter(8'd0),.valid_bit(flags),
  .user_data_bit(flags),.audio_sample_word(packet_words),
  .audio_sample_word_present(4'hf),.header(header),.sub(sub));
 task access_bus(input [15:0] address,input [7:0] value,input read_cycle,input complete);
  begin
   @(negedge clk);cpu_addr=address;cpu_data=value;cpu_rw_n=read_cycle;e_fall=complete;
   @(negedge clk);e_fall=0;cpu_rw_n=1;
  end
 endtask
 task check_analog_density(input integer expected_high_cycles);
  integer high_cycles,index;
  begin
   repeat(3)@(negedge clk);
   high_cycles=0;
   for(index=0;index<256;index=index+1)begin
    @(negedge clk);
    if(audio_out)high_cycles=high_cycles+1;
   end
   if(high_cycles!=expected_high_cycles)
    $fatal(1,"physical DAC pulse density=%0d expected=%0d",high_cycles,expected_high_cycles);
  end
 endtask
 task check(input integer expected_left,input integer expected_right);
  integer clipped_left,clipped_right,expected_mono,clipped_mono;
  begin
   clipped_left=expected_left>32767?32767:expected_left < -32768?-32768:expected_left;
   clipped_right=expected_right>32767?32767:expected_right < -32768?-32768:expected_right;
   expected_mono=(expected_left+expected_right)/2;
   clipped_mono=expected_mono>32767?32767:expected_mono < -32768?-32768:expected_mono;
   #1;
   if(left_pcm!==clipped_left[15:0] || right_pcm!==clipped_right[15:0])
    $fatal(1,"stereo mismatch: %h/%h expected %h/%h",left_pcm,right_pcm,clipped_left[15:0],clipped_right[15:0]);
   if(mono_mix_pcm!==clipped_mono[15:0] ||
      analog_sample!=={~clipped_mono[15],clipped_mono[14:8]})
    $fatal(1,"analog mono mismatch: %h expected %h",mono_mix_pcm,clipped_mono[15:0]);
   if(disabled_left!==mono_pcm || disabled_right!==mono_pcm || disabled_mono!==mono_pcm)
    $fatal(1,"disabled option changed mono audio");
   if(display.encoder.audio_sample_word[0]!==left_pcm ||
      display.encoder.audio_sample_word[1]!==right_pcm)
    $fatal(1,"HDMI wrapper swapped or duplicated stereo channels");
   if(sub[0][23:0]!=={left_pcm,8'd0} || sub[0][47:24]!=={right_pcm,8'd0})
    $fatal(1,"HDMI packet lost stereo sample ordering");
  end
 endtask
 integer value;
 initial begin
  repeat(2)@(negedge clk);reset_n=1;
  check(0,0);
  access_bus(16'hff7a,8'hff,0,1);check(16256,0);
  access_bus(16'hff7b,8'h00,0,1);check(16256,-16384);
  access_bus(16'hff7a,8'h00,1,1);check(16256,-16384);
  access_bus(16'hff7b,8'hff,1,1);check(16256,-16384);
  access_bus(16'hff7a,8'h00,0,0);check(16256,-16384);
  access_bus(16'hff7b,8'hff,0,0);check(16256,-16384);
  access_bus(16'hff79,8'h00,0,1);check(16256,-16384);
  access_bus(16'hff7c,8'hff,0,1);check(16256,-16384);
  // In-phase channels must add on the mono output, including clipping.
  access_bus(16'hff7b,8'hff,0,1);check(16256,16256);
  mono_pcm=16'h7530;check(46256,46256);
  access_bus(16'hff7a,8'h00,0,1);
  access_bus(16'hff7b,8'h00,0,1);
  mono_pcm=16'h8ad0;check(-46384,-46384);
  // Cover every DAC code and both clipping directions, including negative
  // mono samples, to catch signedness/extension mistakes in the mixer.
  for(value=0;value<256;value=value+1)begin
   mono_pcm=16'h7530;
   access_bus(16'hff7a,value[7:0],0,1);
   access_bus(16'hff7b,8'd255-value[7:0],0,1);
   check(30000+(value-128)*128,30000+(127-value)*128);
   mono_pcm=16'h8ad0;
   check(-30000+(value-128)*128,-30000+(127-value)*128);
  end
  mono_pcm=0;
  access_bus(16'hff7a,8'h00,0,1);
  access_bus(16'hff7b,8'h80,0,1);
  check_analog_density(96); // Left alone reaches the physical DAC.
  access_bus(16'hff7a,8'h80,0,1);
  access_bus(16'hff7b,8'h00,0,1);
  check_analog_density(96); // Right alone has the same mono gain.
  access_bus(16'hff7a,8'h00,0,1);
  check_analog_density(64); // Both channels add.
  access_bus(16'hff7a,8'h80,0,1);
  access_bus(16'hff7b,8'h80,0,1);
  check_analog_density(128); // Midpoint remains silence.
  @(negedge clk);reset_n=0;mono_pcm=16'h1234;
  check(4660,4660);
  $display("Orchestra-90 stereo DAC, analog mono mixing, disable and HDMI packets PASS");
  $finish;
 end
endmodule
