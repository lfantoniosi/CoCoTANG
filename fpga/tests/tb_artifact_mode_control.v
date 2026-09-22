`timescale 1ns/1ps
module tb_artifact_mode_control;
 reg clk=0,enable=0,reset_n=1;wire [1:0] mode;integer errors=0;
 artifact_mode_control #(.DEBOUNCE_CYCLES(3),.INITIAL_MODE(2'd1)) dut(
  .clk(clk),.enable(enable),.reset_n(reset_n),.mode(mode));
 always #5 clk=!clk;
 task press;
  begin
   reset_n=0;repeat(8)@(posedge clk);#1;
   reset_n=1;repeat(8)@(posedge clk);#1;
  end
 endtask
 initial begin
  reset_n=0;repeat(4)@(posedge clk);#1;
  enable=1;repeat(8)@(posedge clk);#1;
  if(mode!==1)errors=errors+1;
  reset_n=1;repeat(8)@(posedge clk);#1;
  press();if(mode!==2)begin $display("first press: %0d",mode);errors=errors+1;end
  press();if(mode!==0)begin $display("second press: %0d",mode);errors=errors+1;end
  press();if(mode!==1)begin $display("third press: %0d",mode);errors=errors+1;end
  if(errors==0)$display("tb_artifact_mode_control PASS");
  else $display("tb_artifact_mode_control FAIL: %0d",errors);
  $finish;
 end
endmodule
