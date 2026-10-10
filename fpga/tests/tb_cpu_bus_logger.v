`timescale 1ns/1ps
module tb_cpu_bus_logger;
 reg clk=0,reset_n=0,capture_enable=1,capture_clear=0,bus_reset_n=1;
 reg nmi_event=0,e_fall=0,q=0,rw_n=1;
 reg [15:0] address=0;
 reg [7:0] cpu_data=0,expected_data=0;reg [2:0] s=1;
 reg data_oe=0,memory_wait=0;
 wire log_we,rebase_pulse,end_pulse;wire [3:0] log_addr,log_base;
 wire [47:0] log_data;wire [2:0] log_count;
 wire nmi_we,nmi_rebase,nmi_end;wire [3:0] nmi_addr,nmi_base;
 wire [47:0] nmi_data;wire [2:0] nmi_count;
 wire reads_we,reads_rebase,reads_end;wire [3:0] reads_addr,reads_base;
 wire [47:0] reads_data;wire [2:0] reads_count;
 integer errors=0;

 always #5 clk=~clk;
 cpu_bus_logger #(.LOG_ADDR_WIDTH(4),.LOG_COUNT_WIDTH(3),.LOG_DEPTH(4),
  .LOG_START_ADDRESS(16'h4000),.LOG_END_ADDRESS(16'h4002)) dut(
   .clk(clk),.reset_n(reset_n),.capture_enable(capture_enable),
   .capture_clear(capture_clear),.nmi_event(nmi_event),
   .bus_reset_n(bus_reset_n),.e_fall(e_fall),.q(q),.rw_n(rw_n),
   .address(address),.cpu_data(cpu_data),.expected_data(expected_data),.s(s),
   .data_oe(data_oe),.memory_wait(memory_wait),
   .mmu_task0_page(6'h12),.mmu_task1_page(6'h2a),
   .mmu_task(1'b1),.mmu_enabled(1'b1),.log_we(log_we),
   .log_addr(log_addr),.log_data(log_data),.log_count(log_count),
   .log_base(log_base),.rebase_pulse(rebase_pulse),.end_pulse(end_pulse));

 cpu_bus_logger #(.LOG_ADDR_WIDTH(4),.LOG_COUNT_WIDTH(3),.LOG_DEPTH(4),
  .LOG_START_ADDRESS(16'h4000)) nmi_dut(
   .clk(clk),.reset_n(reset_n),.capture_enable(capture_enable),
   .capture_clear(capture_clear),.nmi_event(nmi_event),
   .bus_reset_n(bus_reset_n),.e_fall(e_fall),.q(q),.rw_n(rw_n),
   .address(address),.cpu_data(cpu_data),.expected_data(expected_data),.s(s),
   .data_oe(data_oe),.memory_wait(memory_wait),
   .mmu_task0_page(6'h12),.mmu_task1_page(6'h2a),
   .mmu_task(1'b1),.mmu_enabled(1'b1),.log_we(nmi_we),
   .log_addr(nmi_addr),.log_data(nmi_data),.log_count(nmi_count),
   .log_base(nmi_base),.rebase_pulse(nmi_rebase),.end_pulse(nmi_end));

 cpu_bus_logger #(.LOG_ADDR_WIDTH(4),.LOG_COUNT_WIDTH(3),.LOG_DEPTH(4),
  .LOG_START_ADDRESS(16'h4000),.LOG_READS_ONLY(1)) reads_dut(
   .clk(clk),.reset_n(reset_n),.capture_enable(capture_enable),
   .capture_clear(capture_clear),.nmi_event(1'b0),.bus_reset_n(bus_reset_n),
   .e_fall(e_fall),.q(q),.rw_n(rw_n),.address(address),
   .cpu_data(cpu_data),.expected_data(expected_data),.s(s),
   .data_oe(data_oe),.memory_wait(memory_wait),
   .mmu_task0_page(6'h12),.mmu_task1_page(6'h2a),
   .mmu_task(1'b1),.mmu_enabled(1'b1),.log_we(reads_we),
   .log_addr(reads_addr),.log_data(reads_data),.log_count(reads_count),
   .log_base(reads_base),.rebase_pulse(reads_rebase),.end_pulse(reads_end));

 task read_sample(input [15:0] a,input [7:0] d);
  begin
   @(negedge clk);rw_n=1;s=1;address=a;cpu_data=d;
   repeat(3)@(negedge clk);
   e_fall=1;@(negedge clk);e_fall=0;
  end
 endtask

 task write_sample(input [15:0] a,input [7:0] d);
  begin
   @(negedge clk);rw_n=0;s=0;address=a;cpu_data=d;
   repeat(3)@(negedge clk);
   e_fall=1;@(negedge clk);e_fall=0;rw_n=1;s=1;
  end
 endtask

 initial begin
  repeat(3)@(posedge clk);reset_n=1;
  read_sample(16'h3000,8'h55);
  if(log_count!=0)begin
   $display("logger captured before the start address");errors=errors+1;end
  read_sample(16'h4000,8'h86);
  if(!rebase_pulse||log_count!=1||log_addr!=0||
     log_data[45:30]!=16'h4000)begin
   $display("start address did not rebase at entry zero");errors=errors+1;end
  read_sample(16'h4001,8'h01);
  read_sample(16'h4000,8'h86);
  if(!rebase_pulse||log_count!=1||log_addr!=0||
     log_data[45:30]!=16'h4000)begin
   $display("later start-address hit did not rebase the trace");errors=errors+1;end
  read_sample(16'h4001,8'h01);
  read_sample(16'h4002,8'h20);
  if(!end_pulse||log_count!=3||log_data[45:30]!=16'h4002)begin
   $display("end address was not captured inclusively");errors=errors+1;end
  read_sample(16'h4003,8'h12);
  if(log_count!=3||log_we)begin
   $display("capture continued beyond the end address");errors=errors+1;end
  read_sample(16'h4000,8'h86);
  if(!rebase_pulse||log_count!=1||log_addr!=0)begin
   $display("start-address hit after the end did not rebase");errors=errors+1;end

  // Fill the unrestricted logger, then hit the start again without clearing.
  read_sample(16'h4001,8'h01);
  read_sample(16'h4002,8'h20);
  read_sample(16'h4003,8'h12);
  read_sample(16'h4004,8'h12);
  if(nmi_count!=4||nmi_we)begin
   $display("non-ring logger did not stop writes at capacity");errors=errors+1;end
  read_sample(16'h4000,8'h86);
  if(!nmi_rebase||nmi_count!=1||nmi_addr!=0||nmi_base!=0)begin
   $display("full buffer blocked the next start-address hit");errors=errors+1;end
  read_sample(16'h4000,8'h86);
  if(!nmi_rebase||nmi_count!=1||nmi_addr!=0)begin
   $display("consecutive start-address hit did not rebase");errors=errors+1;end

  capture_clear=1;@(posedge clk);#1;capture_clear=0;
  read_sample(16'h4000,8'h86);
  nmi_event=1;@(posedge clk);#1;nmi_event=0;
  if(nmi_count!=2||!nmi_we||nmi_data[45:30]!=16'hfffc||
     nmi_data[29:22]!=8'h4e||nmi_data[21:14]!=8'h4d)begin
   $display("NMI marker missing from trace");errors=errors+1;end

  capture_clear=1;@(posedge clk);#1;capture_clear=0;
  write_sample(16'h4000,8'h86);
  if(reads_count!=0||reads_rebase||reads_we)begin
   $display("read-only trigger started on a write");errors=errors+1;end
  if(!nmi_rebase||nmi_count!=1)begin
   $display("unrestricted trigger failed to start on a write");errors=errors+1;end
  read_sample(16'h4000,8'h86);
  write_sample(16'h4001,8'h7e);
  if(reads_count!=2||reads_data[45:30]!=16'h4001||reads_data[46]!=0)begin
   $display("read-triggered trace failed to capture a write");errors=errors+1;end
  write_sample(16'h4000,8'h86);
  if(reads_count!=3||reads_rebase||reads_data[45:30]!=16'h4000)begin
   $display("start-address write rebased a read-only trigger");errors=errors+1;end
  read_sample(16'h4002,8'h20);
  if(reads_count!=4||reads_data[45:30]!=16'h4002)begin
   $display("read-triggered trace failed to capture a read");errors=errors+1;end
  read_sample(16'h4000,8'h86);
  if(reads_count!=1||!reads_rebase||reads_addr!=0)begin
   $display("start-address read failed to rebase after writes");errors=errors+1;end

  if(errors==0)$display("tb_cpu_bus_logger PASS");
  else $display("tb_cpu_bus_logger FAIL: %0d",errors);
  $finish;
 end
endmodule
