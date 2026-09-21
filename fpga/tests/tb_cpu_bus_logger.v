`timescale 1ns/1ps
module tb_cpu_bus_logger;
 reg clk=0,reset_n=0,capture_enable=1,capture_clear=0,bus_reset_n=1;
 reg e_fall=0,q=0,rw_n=1;reg [15:0] address=0;
 reg [7:0] cpu_data=0,expected_data=0;reg [2:0] s=0;
 reg data_oe=0,memory_wait=0;
 wire log_we,rebase_pulse,marker_pulse;wire [3:0] log_addr;wire [47:0] log_data;
 wire [4:0] log_count;wire [3:0] log_base;
 integer errors=0;

 always #5 clk=~clk;
 cpu_bus_logger #(.LOG_ADDR_WIDTH(4),.LOG_COUNT_WIDTH(5),.LOG_DEPTH(16),
  .LOG_START_ADDRESS(16'h0000),.LOG_WRITE_START_ADDRESS(16'h2000),
  .LOG_WRITE_END_ADDRESS(16'h20ff),.LOG_WRITE_DATA_MASK(8'hf0),
  .LOG_WRITE_DATA_VALUE(8'h30),
  .LOG_CAPTURE_START_ADDRESS(16'h2000),
  .LOG_CAPTURE_END_ADDRESS(16'h3fff),
  .LOG_CAPTURE_EXTRA_ADDRESS(16'h5000),
  .LOG_MARKER_ADDRESS(16'hff9b),.LOG_MARKER_DATA(8'hc7),
  .LOG_REBASE_EVERY_MATCH(1)) dut(
   .clk(clk),.reset_n(reset_n),.capture_enable(capture_enable),
   .capture_clear(capture_clear),
   .bus_reset_n(bus_reset_n),.e_fall(e_fall),.q(q),.rw_n(rw_n),
   .address(address),.cpu_data(cpu_data),.expected_data(expected_data),.s(s),
   .data_oe(data_oe),.memory_wait(memory_wait),.log_we(log_we),
   .mmu_task0_page(6'h12),.mmu_task1_page(6'h2a),
   .mmu_task(1'b1),.mmu_enabled(1'b1),
   .log_addr(log_addr),.log_data(log_data),.log_count(log_count),
   .log_base(log_base),
   .rebase_pulse(rebase_pulse),.marker_pulse(marker_pulse));

 task write_sample(input [15:0] a,input [7:0] d);
  begin
   rw_n=0;s=0;address=a;cpu_data=d;
   repeat(3)@(posedge clk);
   e_fall=1;@(posedge clk);#1;e_fall=0;
  end
 endtask

 initial begin
  repeat(3)@(posedge clk);reset_n=1;
  // The software landmark detector must remain live with capture stopped.
  capture_enable=0;
  write_sample(16'hff9b,8'hc7);
  if(!marker_pulse)begin $display("marker pulse missing");errors=errors+1;end
  if(log_count!=1 || !log_we || log_addr!=0 ||
     log_data[45:30]!=16'hff9b || log_data[29:22]!=8'hc7)begin
   $display("marker was not retained as entry zero");errors=errors+1;
  end
  @(posedge clk);#1;
  if(marker_pulse)begin $display("marker pulse did not clear");errors=errors+1;end
  capture_clear=1;@(posedge clk);#1;capture_clear=0;
  capture_enable=1;
  // A write match must arm/rebase capture without a preceding read trigger.
  write_sample(16'h2004,8'h31);
  if(!rebase_pulse||!log_we||log_addr!=0||log_count!=1)begin
   $display("first independent write did not rebase");errors=errors+1;end

  // Add an ordinary entry so the second match proves that the base resets.
  write_sample(16'h3000,8'h22);
  if(log_count!=2)begin
   $display("ordinary entry did not advance count");errors=errors+1;end

  // An address match with nonmatching data is an ordinary logged cycle.
  write_sample(16'h2008,8'h21);
  if(rebase_pulse||log_count!=3)begin
   $display("write-data mask did not reject nonmatching data");errors=errors+1;end

  write_sample(16'h20fe,8'h33);
  if(!rebase_pulse||!log_we||log_addr!=0||log_count!=1)begin
   $display("later matching write did not rebase");errors=errors+1;end

  // A stopped manual capture must preserve its contents.
  capture_enable=0;
  write_sample(16'h2004,8'h31);
  if(log_we||rebase_pulse||log_count!=1)begin
   $display("capture stop did not preserve capture");errors=errors+1;end

  // Filtering drops unrelated cycles but retains the explicit extra address.
  reset_n=0;capture_enable=1;repeat(3)@(posedge clk);reset_n=1;
  write_sample(16'h4000,8'h55);
  if(log_count!=0)begin
   $display("capture filter retained excluded address");errors=errors+1;end
  write_sample(16'h5000,8'h55);
  if(log_count!=1)begin
   $display("capture filter dropped extra address");errors=errors+1;end

  // Each entry carries both candidate MMU pages plus active-task state.
  if(log_data[13:0]!={1'b1,1'b1,6'h12,6'h2a})begin
   $display("MMU snapshot was not packed into the entry");errors=errors+1;end

  // A manual clear starts a new linear capture at entry zero.
  capture_clear=1;@(posedge clk);#1;capture_clear=0;
  if(log_count!=0||log_base!=0)begin
   $display("manual capture clear failed");errors=errors+1;end

  // A full manual capture stops rather than overwriting its oldest entry.
  reset_n=0;capture_enable=1;repeat(3)@(posedge clk);reset_n=1;
  repeat(18)begin
   write_sample(16'h3000+log_count+log_base,8'h55);
  end
  if(log_count!=16||log_base!=0||log_addr!=15)begin
   $display("full capture stop failed count=%0d base=%0d addr=%0d",
            log_count,log_base,log_addr);errors=errors+1;end

  if(errors==0)$display("tb_cpu_bus_logger PASS");
  else $display("tb_cpu_bus_logger FAIL: %0d",errors);
  $finish;
 end
endmodule
