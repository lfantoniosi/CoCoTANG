`timescale 1ns/1ps
module tb_artifact_mode_control;
 reg clk=0,enable=0,reset_n=1;wire [1:0] mode;wire ssc_enabled;
 wire [1:0] mode_without_ssc;wire no_ssc;integer errors=0,i;
 artifact_mode_control #(.DEBOUNCE_CYCLES(3),.INITIAL_MODE(2'd1)) dut(
  .clk(clk),.enable(enable),.reset_n(reset_n),.mode(mode),.ssc_enabled(ssc_enabled));
 artifact_mode_control #(.DEBOUNCE_CYCLES(3),.ENABLE_SSC(0)) without_ssc(
  .clk(clk),.enable(enable),.reset_n(reset_n),.mode(mode_without_ssc),.ssc_enabled(no_ssc));
 always #5 clk=!clk;
 task press;
  begin
   reset_n=0;repeat(8)@(posedge clk);#1;
   reset_n=1;repeat(8)@(posedge clk);#1;
  end
 endtask
 task check_mode(input [1:0] expected_mode,input expected_ssc);
  begin
   if(mode!==expected_mode || ssc_enabled!==expected_ssc ||
      mode_without_ssc!==expected_mode || no_ssc!==0) begin
    $display("expected mode=%0d SSC=%0d, got mode=%0d SSC=%0d",expected_mode,expected_ssc,mode,ssc_enabled);
    errors=errors+1;
   end
  end
 endtask
 initial begin
  reset_n=0;repeat(4)@(posedge clk);#1;
  enable=1;repeat(8)@(posedge clk);#1;
  check_mode(1,0);
  reset_n=1;repeat(8)@(posedge clk);#1;
  // A short reset glitch must not advance either selection.
  reset_n=0;@(posedge clk);#1;reset_n=1;repeat(8)@(posedge clk);#1;
  check_mode(1,0);
  for(i=0;i<2;i=i+1)begin
   press();check_mode(2,0);
   press();check_mode(0,0);
   press();check_mode(1,1);
   // Holding RESET must advance once, and disable/enable must preserve SSC.
   reset_n=0;repeat(30)@(posedge clk);#1;check_mode(2,1);
   enable=0;repeat(8)@(posedge clk);#1;check_mode(2,1);
   enable=1;repeat(8)@(posedge clk);#1;check_mode(2,1);
   reset_n=1;repeat(8)@(posedge clk);#1;
   press();check_mode(0,1);
   press();check_mode(1,0);
  end
  if(errors==0)$display("tb_artifact_mode_control PASS");
  else $fatal(1,"tb_artifact_mode_control FAIL: %0d",errors);
  $finish;
 end
endmodule
