`timescale 1ns/1ps
module tb_gime_timing;
    reg clk=0;
    reg reset_n=0;
    reg fast_mode=0;
    wire e,q,e_rise,e_fall;
    wire reference_fall;
    integer last_reference_fall=0;
    integer speed_cycles,release_phase;
    integer clocks=0;
    integer previous_rise=0;
    integer interval=0;

    always #5 clk=~clk;
    always @(posedge clk) clocks=clocks+1;

    gime_timing dut(.clk(clk),.reset_n(reset_n),.fast_mode(fast_mode),
        .e(e),.q(q),.e_rise(e_rise),.e_fall(e_fall));
    gime_timing reference(.clk(clk),.reset_n(reset_n),.fast_mode(1'b0),
        .e_fall(reference_fall));
    always @(posedge reference_fall)last_reference_fall=clocks;

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
        fast_mode=0;
        measure_cycle(119,123);
        // Returning from an odd or even count of fast cycles must return
        // to the same slow phase. Otherwise a PIA HS interrupt can wake
        // SYNC one CPU cycle later, shifting raster CSS by eight pixels.
        for(release_phase=0;release_phase<4;release_phase=release_phase+1)
         for(speed_cycles=1;speed_cycles<=8;speed_cycles=speed_cycles+1)begin
          @(negedge clk);reset_n=0;fast_mode=0;
          repeat(4+release_phase)@(negedge clk);reset_n=1;
          repeat(3)@(posedge e_fall);
          @(negedge clk);fast_mode=1;
          repeat(speed_cycles)@(posedge e_fall);
          @(negedge clk);fast_mode=0;
          repeat(3)@(posedge e_fall);#1;
          if(clocks-last_reference_fall>1)
           $fatal(1,"slow E phase changed after %0d fast cycles: offset %0d clocks",
                    speed_cycles,clocks-last_reference_fall);
         end
        $display("tb_gime_timing PASS");
        $finish;
    end
endmodule
