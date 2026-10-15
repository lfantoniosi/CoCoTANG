`timescale 1ns/1ps
module tb_gime_nocan3;
 reg clk=0,reset_n=0,e=0,e_fall=0,cpu_rw_n=1;
 reg [15:0] cpu_addr=0;
 reg [7:0] cpu_data=0;
 wire [22:0] address,legacy_address;
 wire [3:0] video_bank,legacy_video_bank;
 wire is_rom;
 reg [7:0] ram_markers[0:1023];
 integer page;
 always #5 clk=~clk;
 gime_registers #(.DISTO_2MB(1),.NOCAN3_8MB(1)) dut(
  .clk(clk),.reset_n(reset_n),.e(e),.e_fall(e_fall),
  .cpu_addr(cpu_addr),.cpu_rw_n(cpu_rw_n),.cpu_data(cpu_data),
  .serint_n(1'b1),.keyint_n(1'b1),.cart_n(1'b1),.hs_n(1'b1),.fs_n(1'b1),
  .cpu_mem_addr(address),.cpu_mem_is_rom(is_rom),.video_bank(video_bank));
 gime_registers #(.DISTO_2MB(1),.NOCAN3_8MB(0)) legacy(
  .clk(clk),.reset_n(reset_n),.e(e),.e_fall(e_fall),
  .cpu_addr(cpu_addr),.cpu_rw_n(cpu_rw_n),.cpu_data(cpu_data),
  .serint_n(1'b1),.keyint_n(1'b1),.cart_n(1'b1),.hs_n(1'b1),.fs_n(1'b1),
  .cpu_mem_addr(legacy_address),.video_bank(legacy_video_bank));
 task write_reg(input [15:0] location,input [7:0] value);
  begin
   @(negedge clk);cpu_addr=location;cpu_data=value;cpu_rw_n=0;e_fall=1;
   @(negedge clk);e_fall=0;cpu_rw_n=1;
  end
 endtask
 task map_page(input [15:0] slot,input integer number);
  begin
   write_reg(16'hff9b,{2'b00,number[9:8],4'b0000});
   write_reg(slot,number[7:0]);
  end
 endtask
 task check_address(input [15:0] logical_address,input [22:0] expected);
  begin
   cpu_addr=logical_address;#1;
   if(address!==expected)$fatal(1,"address %h got %h expected %h",logical_address,address,expected);
  end
 endtask
 initial begin
  repeat(3)@(negedge clk);reset_n=1;
  check_address(16'h0123,23'h070123);
  write_reg(16'hff90,8'h40);
  write_reg(16'hffdf,0);
  // Every 8 KiB page, including the very last byte of physical RAM.
  for(page=0;page<1024;page=page+1)begin
   map_page(16'hffa0,page);
   check_address(16'h1fff,(page*8192)+8191);
   ram_markers[address[22:13]]=page[7:0]^{6'd0,page[9:8]};
   if(page<256 && address!==legacy_address)
    $fatal(1,"legacy DISTO mapping changed below 2 MiB");
  end
  for(page=0;page<1024;page=page+1)begin
   map_page(16'hffa0,page);
   check_address(16'h1fff,(page*8192)+8191);
   if(ram_markers[address[22:13]]!==(page[7:0]^{6'd0,page[9:8]}))
    $fatal(1,"page %0d aliases another page",page);
  end
  // Prefix changes must not retroactively remap a slot. Slots and tasks
  // independently retain the prefix sampled at their respective writes.
  map_page(16'hffa0,10'h105);
  map_page(16'hffa1,10'h205);
  map_page(16'hffa8,10'h305);
  write_reg(16'hff9b,8'h0f);
  check_address(16'h0123,23'h20a123);
  check_address(16'h2123,23'h40a123);
  if(video_bank!==15 || legacy_video_bank!==3)$fatal(1,"video bank decode");
  write_reg(16'hff91,1);
  check_address(16'h0123,23'h60a123);
  // Disabled-MMU and MC3 constant-page behavior remains the DISTO rule.
  write_reg(16'hff90,0);
  check_address(16'h0123,23'h670123);
  write_reg(16'hff90,8'h48);
  check_address(16'hfea5,23'h07fea5);
  // Internal ROM/vectors must remain independent of the RAM bank prefix.
  write_reg(16'hffde,0);
  check_address(16'hfffe,23'h007ffe);
  if(!is_rom)$fatal(1,"reset vector lost its ROM overlay");
  @(negedge clk);reset_n=0;
  @(negedge clk);reset_n=1;
  check_address(16'h0123,23'h070123);
  if(video_bank!==0)$fatal(1,"reset did not clear bank extension");
  $display("NoCan3: all 1024 CPU pages, independent task latches, video banks and ROM PASS");
  $finish;
 end
endmodule
