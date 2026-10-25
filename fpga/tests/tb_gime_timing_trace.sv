`timescale 1ns/1ps
module tb_gime_timing_trace;
    reg clk=0,reset_n=0,fast_mode=0;
    wire [7:0] actual,expected;
    always #5 clk=~clk;
    gime_timing dut(.clk(clk),.reset_n(reset_n),.fast_mode(fast_mode),
        .e(actual[7]),.q(actual[6]),.e_pin(actual[5]),.q_pin(actual[4]),
        .e_rise(actual[3]),.e_fall(actual[2]),
        .video_tick(actual[1]),.video_e_fall(actual[0]));
    gime_timing_reference reference(.clk(clk),.reset_n(reset_n),.fast_mode(fast_mode),
        .e(expected[7]),.q(expected[6]),.e_pin(expected[5]),.q_pin(expected[4]),
        .e_rise(expected[3]),.e_fall(expected[2]),
        .video_tick(expected[1]),.video_e_fall(expected[0]));
    initial begin
        repeat(4)@(negedge clk);
        reset_n=1;
        for(integer cycle=0;cycle<131072;cycle=cycle+1)begin
            @(negedge clk);
            if(cycle%511==0)fast_mode=~fast_mode;
            if(cycle==65000)reset_n=0;
            if(cycle==65004)reset_n=1;
            @(posedge clk);#1;
            if(actual!==expected || dut.accumulator!==reference.accumulator)
                $fatal(1,"trace timing differs from normal core at cycle %0d",cycle);
        end
        $display("PASS: trace accumulator and all E/Q/video outputs match normal core cycle by cycle");
        $finish;
    end
endmodule
