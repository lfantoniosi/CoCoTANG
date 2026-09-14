`timescale 1ns/1ps
module tb_cpu_sdram_arbiter;
    reg clk=0, reset_n=0;
    reg e=0, q=0;
    reg cpu_req=0, cpu_wr=0;
    reg [22:0] cpu_addr=0;
    reg [7:0] cpu_wdata=0;
    wire cpu_ack;
    wire [7:0] cpu_rdata;
    reg video_req=0, video_slot_open=0, refresh_slot_open=0;
    reg [22:0] video_addr=0;
    wire video_ack;
    wire [31:0] video_rdata;
    reg loader_req=0;
    reg [22:0] loader_addr=0;
    reg [7:0] loader_wdata=0;
    wire loader_ack;
    wire rd,wr,refresh;
    wire [22:0] addr;
    wire [15:0] din;
    wire [1:0] wdm;
    reg [15:0] dout=16'h5aa5;
    reg [31:0] dout32=32'h44332211;
    reg data_ready=0, busy=0, enabled=1;
    reg saw_video_ack=0, saw_cpu_ack=0;

    always #5 clk=~clk;
    always @(posedge clk) begin
        if (video_ack) saw_video_ack <= 1'b1;
        if (cpu_ack) saw_cpu_ack <= 1'b1;
    end

    cpu_sdram_arbiter dut (
        .clk(clk),.reset_n(reset_n),.e(e),.q(q),
        .cpu_req(cpu_req),.cpu_wr(cpu_wr),.cpu_addr(cpu_addr),
        .cpu_wdata(cpu_wdata),.cpu_ack(cpu_ack),.cpu_rdata(cpu_rdata),
        .video_req(video_req),.video_addr(video_addr),
        .video_slot_open(video_slot_open),.video_ack(video_ack),
        .refresh_slot_open(refresh_slot_open),
        .video_rdata(video_rdata),.loader_req(loader_req),
        .loader_addr(loader_addr),.loader_wdata(loader_wdata),
        .loader_ack(loader_ack),.rd(rd),.wr(wr),.refresh(refresh),
        .addr(addr),.din(din),.wdm(wdm),.dout(dout),.dout32(dout32),
        .data_ready(data_ready),.busy(busy),.enabled(enabled)
    );

    task finish_read;
        begin
            @(negedge clk); busy=1;
            repeat (3) @(negedge clk);
            data_ready=1;
            @(negedge clk); data_ready=0; busy=0;
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        reset_n=1;

        // Refresh must be able to run during the post-load reset hold, when
        // video is disabled and therefore has no open video slot.
        repeat (1082) @(posedge clk);
        @(negedge clk); refresh_slot_open=1;
        @(posedge clk); #1;
        if (!refresh) $fatal(1,"refresh did not launch without a video slot");
        @(negedge clk); refresh_slot_open=0; busy=1;
        @(negedge clk); busy=0;
        repeat (2) @(negedge clk);

        // A queued VDG read must remain dormant outside its SAM slot.
        video_addr=23'h001235;
        video_req=1;
        repeat (4) begin
            @(posedge clk); #1;
            if (rd || wr) $fatal(1,"video launched outside its slot");
        end

        // Opening the early E-low/Q-low slot launches the aligned read.
        @(negedge clk); video_slot_open=1;
        @(posedge clk); #1;
        if (!rd) $fatal(1,"video did not launch in its slot");
        if (addr !== 23'h00091a)
            $fatal(1,"video SDRAM address conversion is wrong: %h",addr);
        @(negedge clk); video_slot_open=0;
        finish_read();
        @(posedge clk); #1;
        if (!saw_video_ack || video_rdata !== 32'h44332211)
            $fatal(1,"video response was not returned");
        @(negedge clk); video_req=0;
        repeat (2) @(negedge clk);

        // If both clients are ready at the slot boundary, CPU wins.
        video_req=1;
        video_slot_open=1;
        cpu_req=1;
        cpu_addr=23'h000021;
        @(posedge clk); #1;
        if (!rd) $fatal(1,"CPU read did not launch");
        if (addr !== 23'h000010)
            $fatal(1,"CPU did not win arbitration: %h",addr);
        @(negedge clk); video_slot_open=0;
        finish_read();
        @(posedge clk); #1;
        if (!saw_cpu_ack || cpu_rdata !== 8'h5a)
            $fatal(1,"CPU response/lane was wrong: %h",cpu_rdata);
        @(negedge clk); cpu_req=0; video_req=0;

        $display("tb_cpu_sdram_arbiter PASS");
        $finish;
    end
endmodule
