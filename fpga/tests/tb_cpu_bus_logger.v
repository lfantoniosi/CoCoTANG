`timescale 1ns/1ps
module tb_cpu_bus_logger;
 reg clk=0,reset_n=0,capture_enable=1,bus_reset_n=1;
 reg e_fall=0,q=0,rw_n=1;reg [15:0] address=0;
 reg [7:0] cpu_data=0,expected_data=0;reg [2:0] s=0;
 reg data_oe=0,memory_wait=0;
 wire log_we,rebase_pulse;wire [3:0] log_addr;wire [39:0] log_data;
 wire [4:0] log_count;
 integer errors=0;

 always #5 clk=~clk;
 cpu_bus_logger #(.LOG_ADDR_WIDTH(4),.LOG_COUNT_WIDTH(5),.LOG_DEPTH(16),
  .LOG_START_ADDRESS(16'h0000),.LOG_WRITE_START_ADDRESS(16'h2000),
  .LOG_WRITE_END_ADDRESS(16'h20ff),.LOG_REBASE_EVERY_MATCH(1)) dut(
   .clk(clk),.reset_n(reset_n),.capture_enable(capture_enable),
   .bus_reset_n(bus_reset_n),.e_fall(e_fall),.q(q),.rw_n(rw_n),
   .address(address),.cpu_data(cpu_data),.expected_data(expected_data),.s(s),
   .data_oe(data_oe),.memory_wait(memory_wait),.log_we(log_we),
   .log_addr(log_addr),.log_data(log_data),.log_count(log_count),
   .rebase_pulse(rebase_pulse));

 task write_sample(input [15:0] a,input [7:0] d);
  begin
   rw_n=0;s=0;address=a;cpu_data=d;
   repeat(3)@(posedge clk);
   e_fall=1;@(posedge clk);#1;e_fall=0;
  end
 endtask

 initial begin
  repeat(3)@(posedge clk);reset_n=1;
  // A write match must arm/rebase capture without a preceding read trigger.
  write_sample(16'h2004,8'h11);
  if(!rebase_pulse||!log_we||log_addr!=0||log_count!=1)begin
   $display("first independent write did not rebase");errors=errors+1;end

  // Add an ordinary entry so the second match proves that the base resets.
  write_sample(16'h3000,8'h22);
  if(log_count!=2)begin
   $display("ordinary entry did not advance count");errors=errors+1;end

  write_sample(16'h20fe,8'h33);
  if(!rebase_pulse||!log_we||log_addr!=0||log_count!=1)begin
   $display("later matching write did not rebase");errors=errors+1;end

  if(errors==0)$display("tb_cpu_bus_logger PASS");
  else $display("tb_cpu_bus_logger FAIL: %0d",errors);
  $finish;
 end
endmodule
