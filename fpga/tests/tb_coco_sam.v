`timescale 1ns/1ps
module tb_coco_sam;
    reg clk=0, reset_n=0, register_reset_n=0, rw_n=1, memory_wait=0;
    integer release_cycles;
    reg [15:0] addr=0;
    wire [2:0] s, video_mode;
    wire e,q,e_rise,e_fall,master_tick;
    wire [6:0] video_offset;
    wire page,all_ram;
    wire [1:0] rate,memory_size;
    coco_sam dut(.clk(clk),.reset_n(reset_n),.register_reset_n(register_reset_n),
      .memory_wait(memory_wait),
      .addr(addr),.rw_n(rw_n),.s(s),
      .e(e),.q(q),.e_rise(e_rise),.e_fall(e_fall),.video_mode(video_mode),
      .master_tick(master_tick),
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
      repeat(4) @(posedge clk); reset_n=1; register_reset_n=1;
      addr=16'h1234; #1; if(s!==0) $fatal(1,"RAM decode");
      addr=16'h8123; #1; if(s!==1) $fatal(1,"EXTROM decode");
      addr=16'ha123; #1; if(s!==2) $fatal(1,"ROM decode");
      addr=16'hff22; #1; if(s!==5) $fatal(1,"PIA1 decode");
      addr=16'hff40; #1; if(s!==6) $fatal(1,"cartridge decode");
      addr=16'hffdf; #1; if(s!==7) $fatal(1,"SAM register decode");
      addr=16'hffe0; #1; if(s!==2) $fatal(1,"vector decode");
      sam_write(16'hffc1); if(video_mode[0]!==1) $fatal(1,"V0 latch");
      sam_write(16'hffdf); addr=16'h8123; #1;
      if(!all_ram || s!==0) $fatal(1,"all-RAM mapping");
      register_reset_n=0; repeat(2) @(posedge clk);
      if(all_ram) $fatal(1,"CPU reset did not clear SAM registers");
      // A pending memory cycle must freeze at the pre-E phase and resume
      // without shortening either clock edge interval.
      wait(q && !e && dut.phase == 4'd6);
      memory_wait=1;
      repeat(30) begin
        @(posedge clk);
        if(!q || e || dut.phase != 4'd6)
          $fatal(1,"memory wait did not hold Q high/E low");
      end
      memory_wait=0;
      release_cycles=0;
      while (!e_rise) begin
        @(posedge clk); #1;
        release_cycles=release_cycles+1;
      end
      if(release_cycles < 6)
        $fatal(1,"E rose without a full post-wait setup interval");
      if(e_rise || e_fall) @(posedge clk);
      repeat(200) begin
        @(posedge clk);
        if(e_rise || e_fall) begin
          register_reset_n=1;
          $display("tb_coco_sam PASS"); $finish;
        end
      end
      $fatal(1,"E/Q stopped during CPU reset");
    end
    initial begin #200000; $fatal(1,"timeout e=%b q=%b phase=%h acc=%h",e,q,dut.phase,dut.accumulator); end
endmodule
