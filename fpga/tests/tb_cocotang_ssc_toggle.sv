// Verify the real top-level reset selector, SSC bus ownership and audio clamp.
`timescale 1ns/1ps
module tb_cocotang_ssc_toggle #(parameter ENABLE_ANALOG_BANNER=1);
 reg clk=0,reset_n=1;
 GSR GSR(.GSRI(1'b1));
 top_coco3 #(.ENABLE_ANALOG_BANNER(ENABLE_ANALOG_BANNER)) dut();
 defparam dut.artifact_control.DEBOUNCE_CYCLES=3;
 always #5 clk=~clk;
 task press;
  begin
   reset_n=0;repeat(10)@(posedge clk);#1;
   reset_n=1;repeat(10)@(posedge clk);#1;
  end
 endtask
 task check_off;
  begin
   if(dut.ssc_enabled!==0 || dut.ssc_reset_n!==0 ||
      dut.ssc_live_selected!==0 || dut.ssc_data_oe!==0 ||
      dut.ssc_read_hold!==0 || dut.ssc_audio_pcm!==0 || dut.sam_s!==6)
    $fatal(1,"Disabled SSC must be silent, held in reset, and leave cartridge bus available");
  end
 endtask
 initial begin
  force dut.clk108=clk;force dut.clk108p=clk;
  force dut.clk270=clk;force dut.clk135=clk;force dut.clk27=clk;
  force dut.board_reset_n=1;force dut.cpu_release=0;
  force dut.filtered_mux_reset_n=reset_n;
  force dut.address=16'hff7e;force dut.machine_sam_s=6;
  force dut.bus_address_valid=1;force dut.bus_snapshot_valid=1;
  force dut.cpu_bus_active=1;force dut.e_core=1;
  force dut.e_fall=0;force dut.rw_n=1;
  // Inject nonzero audio to prove the disabled SSC mixer is clamped too.
  force dut.ssc_psg_pcm=16'sd1000;force dut.ssc_speech_pcm=16'sd2000;
  repeat(10)@(posedge clk);#1;force dut.cpu_release=1;
  repeat(10)@(posedge clk);#1;check_off();
  press();check_off();press();check_off();press();
  if(dut.ssc_enabled!==1 || dut.ssc_reset_n!==1 ||
     dut.ssc_live_selected!==1 || dut.ssc_data_oe!==1 ||
     dut.ssc_audio_pcm!==3000 || dut.sam_s!==0)
   $fatal(1,"Selected SSC must own FF7E, answer status reads, and mix audio");
  // HDMI always shows the suffix; analog either shows it or bypasses it.
  force dut.visible_cvbs_pixel=6'h15;
  force dut.hdmi_output.x=433;force dut.hdmi_output.y=20;
  force dut.cvbs_source_x=466;force dut.cvbs_source_y=24;
  force dut.analog_encoder.in_picture=1;
  repeat(5)@(posedge clk);#1;
  if(dut.hdmi_output.artifact_osd.mode_seen!==3'b101 ||
     dut.analog_status_osd.mode_seen!==3'b101 ||
     dut.hdmi_output.rgb!==24'hffffff ||
     dut.analog_encoder.framebuffer_data!==(ENABLE_ANALOG_BANNER ? 6'h3f : 6'h15) ||
     dut.analog_encoder.mod_rgb!==(ENABLE_ANALOG_BANNER ? 6'h3f : 6'h15))
   $fatal(1,"SSC label/analog banner bypass incorrect");
  press();press();press();check_off();
  $display("tb_cocotang_ssc_toggle analog_banner=%0d PASS",ENABLE_ANALOG_BANNER);$finish;
 end
 initial begin #100000;$fatal(1,"timeout");end
endmodule
