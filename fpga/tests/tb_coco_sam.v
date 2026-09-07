`timescale 1ns/1ps
module tb_coco_sam;
    reg clk=0, reset_n=0, rw_n=1;
    reg [15:0] addr=0;
    wire [2:0] s, video_mode;
    wire e,q,e_rise,e_fall;
    wire [6:0] video_offset;
    wire page,all_ram;
    wire [1:0] rate,memory_size;
    coco_sam dut(.clk(clk),.reset_n(reset_n),.addr(addr),.rw_n(rw_n),.s(s),
      .e(e),.q(q),.e_rise(e_rise),.e_fall(e_fall),.video_mode(video_mode),
      .video_offset(video_offset),.page(page),.rate(rate),.memory_size(memory_size),
      .all_ram(all_ram));
    always #4.6295 clk=~clk;
    task sam_write(input [15:0] a);
      begin
        @(posedge e); addr=a; rw_n=0;
        @(negedge e); repeat(2) @(posedge clk);
        rw_n=1;
      end
    endtask
    initial begin
      repeat(4) @(posedge clk); reset_n=1;
      addr=16'h1234; #1; if(s!==0) $fatal(1,"RAM decode");
      addr=16'h8123; #1; if(s!==1) $fatal(1,"EXTROM decode");
      addr=16'ha123; #1; if(s!==2) $fatal(1,"ROM decode");
      addr=16'hff22; #1; if(s!==5) $fatal(1,"PIA1 decode");
      sam_write(16'hffc1); if(video_mode[0]!==1) $fatal(1,"V0 latch");
      sam_write(16'hffdf); addr=16'h8123; #1;
      if(!all_ram || s!==0) $fatal(1,"all-RAM mapping");
      $display("tb_coco_sam PASS"); $finish;
    end
    initial begin #200000; $fatal(1,"timeout e=%b q=%b phase=%h acc=%h",e,q,dut.phase,dut.accumulator); end
endmodule
