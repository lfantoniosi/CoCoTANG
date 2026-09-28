`timescale 1ns/1ps
module tb_gime_timing;
    reg clk=0;
    reg reset_n=0;
    reg fast_mode=0;
    wire e,q,e_rise,e_fall;
    integer clocks=0;
    integer previous_rise=0;
    integer interval=0;

    always #5 clk=~clk;
    always @(posedge clk) clocks=clocks+1;

    gime_timing dut(.clk(clk),.reset_n(reset_n),.fast_mode(fast_mode),
        .e(e),.q(q),.e_rise(e_rise),.e_fall(e_fall));

    task measure_cycle;
        input integer minimum;
        input integer maximum;
        begin
            @(posedge e_rise); previous_rise=clocks;
            @(posedge e_rise); interval=clocks-previous_rise;
            if (interval < minimum || interval > maximum) begin
                $display("FAIL: E interval %0d outside %0d..%0d",interval,minimum,maximum);
                $fatal;
            end
        end
    endtask

    initial begin
        repeat(4) @(posedge clk);
        reset_n=1;
        measure_cycle(119,123);
        reset_n=0; fast_mode=1;
        repeat(4) @(posedge clk);
        reset_n=1;
        measure_cycle(59,62);
        #1;
        if(dut.selected_step!==32'd1138816942) $fatal(1,"fast CPU clock changed");
        fast_mode=0;
        #1;
        if(dut.selected_step!==32'd569408471) $fatal(1,"slow CPU clock changed");
        $display("tb_gime_timing PASS");
        $finish;
    end
endmodule
