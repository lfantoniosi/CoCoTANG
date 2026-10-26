`timescale 1ns/1ps
// Real CPU memory service, arbitration slots, refresh and SDRAM controller.
// Only the physical RAM and external CPU are behavioral models.
module cvbs_contended_memory #(parameter FAST=1)(
 input clk,input reset_n,input video_req,input [22:0] video_addr,
 output video_ack,output [31:0] video_data);
 wire e,q,e_fall;
 gime_timing timing(.clk(clk),.reset_n(reset_n),.fast_mode(1'(FAST)),
  .e(e),.q(q),.e_fall(e_fall));
 reg q_prev=0;reg [5:0] bus_age=0;
 reg address_valid=0,bus_valid=0;
 reg [22:0] cpu_addr=23'h24000;
 always @(posedge clk)begin
  address_valid<=0;bus_valid<=0;
  q_prev<=q;
  if(!reset_n)begin bus_age<=0;cpu_addr<=23'h24000;end
  else if(q&&!q_prev)begin bus_age<=1;cpu_addr<=cpu_addr+1'b1;end
  else if(bus_age!=0)begin
   bus_age<=bus_age==20?0:bus_age+1'b1;
   address_valid<=bus_age==9;
   bus_valid<=bus_age==15;
  end
 end
 wire rd,wr,refresh,busy,ready,enabled;
 wire [22:0] address;
 wire [15:0] din,dout;
 wire [31:0] dout32;
 wire [1:0] wdm;
 coco3_memory service(.clk(clk),.reset_n(reset_n),.loader_start(1'b0),
  .cpu_access_enable(1'b1),.cpu_bus_valid(bus_valid),.cpu_address_valid(address_valid),
  .e(e),.q(q),.e_fall(e_fall),.cpu_mem_read(1'b1),.cpu_mem_write(1'b0),
  .cpu_mem_is_rom(1'b0),.cpu_logical_addr(cpu_addr[15:0]),
  .cpu_mem_addr(cpu_addr),.cpu_wdata(8'd0),
  .video_req(video_req),.video_addr(video_addr),.video_ack(video_ack),.video_rdata(video_data),
  .mspi_miso(1'b0),.sdram_enabled(enabled),.sd_rd(rd),.sd_wr(wr),.sd_refresh(refresh),
  .sd_addr(address),.sd_din(din),.sd_wdm(wdm),.sd_dout(dout),.sd_dout32(dout32),
  .sd_data_ready(ready),.sd_busy(busy));
 wire ram_clk=~clk;
 wire [31:0] dq;reg drive=0;reg [31:0] data=0;
 assign dq=drive?data:32'bz;
 wire [10:0] a;wire [1:0] ba;wire cs,we,ras,cas;
 reg [10:0] rows[0:3];
 sdram controller(.SDRAM_DQ(dq),.SDRAM_A(a),.SDRAM_BA(ba),
  .SDRAM_nCS(cs),.SDRAM_nWE(we),.SDRAM_nRAS(ras),.SDRAM_nCAS(cas),
  .clk(clk),.clk_sdram(ram_clk),.resetn(reset_n),.rd(rd),.wr(wr),.refresh(refresh),
  .addr(address),.din(din),.wdm(wdm),.dout(dout),.dout32(dout32),
  .data_ready(ready),.busy(busy),.enabled(enabled));
 function [7:0] pattern(input [22:0] a);
  pattern=a[7:0]^a[15:8]^8'hb6;
 endfunction
 task automatic response(input [22:0] address);
  begin
   repeat(3)@(posedge ram_clk);
   #2;data={pattern(address+23'd3),pattern(address+23'd2),pattern(address+23'd1),pattern(address)};drive=1;
   #9.259260;drive=0;
  end
 endtask
 always @(posedge ram_clk)if(reset_n&&!cs)begin
  if({ras,cas,we}==3'b011)rows[ba]<=a;
  else if({ras,cas,we}==3'b101)
   fork response({ba,rows[ba],a[7:0],2'b0});join_none
 end
 initial begin
  wait(reset_n);force controller.cfg_now=1;
  wait(!busy);release controller.cfg_now;
 end
endmodule
