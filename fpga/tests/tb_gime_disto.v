`timescale 1ns/1ps
module tb_gime_disto;
 reg clk=0,reset_n=0,e=0,e_fall=0,cpu_rw_n=1;
 reg [15:0] cpu_addr=0;reg [7:0] cpu_data=0;
 wire [22:0] disto_addr,stock_addr;
 wire [7:0] disto_rdata,stock_rdata;
 integer slot,bank;reg [7:0] expected_page;
 wire [3:0] disto_video_bank,stock_video_bank;
 integer errors=0;

 gime_registers #(.DISTO_2MB(1)) disto(
  .clk(clk),.reset_n(reset_n),.e(e),.e_fall(e_fall),
  .cpu_addr(cpu_addr),.cpu_rw_n(cpu_rw_n),.cpu_data(cpu_data),
  .serint_n(1'b1),.keyint_n(1'b1),.cart_n(1'b1),
  .hs_n(1'b1),.fs_n(1'b1),.core_rdata(disto_rdata),
  .cpu_mem_addr(disto_addr),.video_bank(disto_video_bank));
 gime_registers #(.DISTO_2MB(0)) stock(
  .clk(clk),.reset_n(reset_n),.e(e),.e_fall(e_fall),
  .cpu_addr(cpu_addr),.cpu_rw_n(cpu_rw_n),.cpu_data(cpu_data),
  .serint_n(1'b1),.keyint_n(1'b1),.cart_n(1'b1),
  .hs_n(1'b1),.fs_n(1'b1),.core_rdata(stock_rdata),.cpu_mem_addr(stock_addr),
  .video_bank(stock_video_bank));
 always #5 clk=!clk;

 task write_reg;
  input [15:0] address;input [7:0] value;
  begin
   cpu_addr=address;cpu_data=value;cpu_rw_n=0;e_fall=1;
   @(posedge clk);#1;e_fall=0;cpu_rw_n=1;
  end
 endtask

 initial begin
  repeat(3)@(posedge clk);reset_n=1;@(posedge clk);#1;
  // Bank zero must remain exactly the stock map before any DISTO writes.
  cpu_addr=16'h0123;#1;
  if(disto_addr!=stock_addr||disto_addr!=23'h070123)begin
   $display("power-up map DISTO=%h stock=%h",disto_addr,stock_addr);errors=errors+1;end

  write_reg(16'hff90,8'h40); // MMU enabled
  write_reg(16'hffdf,8'h00); // all RAM
  write_reg(16'hffa0,8'hc5);
  cpu_addr=16'h0123;#1;
  if(disto_addr!=23'h18a123)begin
   $display("DISTO DAT address got %h",disto_addr);errors=errors+1;end
  if(stock_addr!=23'h00a123)begin
   $display("stock DAT did not mask D7:D6: %h",stock_addr);errors=errors+1;end
  cpu_addr=16'hffa0;e=1;#1;
  if(disto_rdata!=8'hc5)begin
   $display("DISTO DAT readback incorrect: %h",disto_rdata);errors=errors+1;end
  e=0;

  // The external DAT bits remain active when the GIME uses its fixed map.
  write_reg(16'hff90,8'h00);cpu_addr=16'h0123;#1;
  if(disto_addr!=23'h1f0123||stock_addr!=23'h070123)begin
   $display("disabled-MMU map DISTO=%h stock=%h",disto_addr,stock_addr);
   errors=errors+1;end

  write_reg(16'hff9b,8'h03);
  if(disto_video_bank!=3||stock_video_bank!=0)begin
   $display("video banks DISTO=%b stock=%b",disto_video_bank,stock_video_bank);
   errors=errors+1;end

  // MC3's constant page is internal to the GIME and must stay in bank zero.
  write_reg(16'hff90,8'h48);cpu_addr=16'hfea5;#1;
  if(disto_addr!=23'h07fea5)begin
   $display("constant page escaped bank zero: %h",disto_addr);errors=errors+1;end

  // Exercise both task banks and every combination of external page bits.
  for(bank=0;bank<4;bank=bank+1)begin
   for(slot=0;slot<16;slot=slot+1)begin
    expected_page=(((bank+slot)%4)<<6)|(slot*3);
    write_reg(16'hffa0+slot,expected_page);
   end
   // Changing the active task must not change addressed-register readback.
   write_reg(16'hff91,bank[0]);
   for(slot=0;slot<16;slot=slot+1)begin
    expected_page=(((bank+slot)%4)<<6)|(slot*3);
    cpu_addr=16'hffa0+slot;e=1;#1;
    if(disto_rdata!==expected_page || stock_rdata!=={2'b00,expected_page[5:0]})
     $fatal(1,"MMU slot %0d bank %0d DISTO=%h stock=%h expected=%h",
            slot,bank,disto_rdata,stock_rdata,expected_page);
    e=0;
   end
  end

  if(errors==0)$display("tb_gime_disto PASS");
  else $display("tb_gime_disto FAIL errors=%0d",errors);
  $finish;
 end
endmodule
