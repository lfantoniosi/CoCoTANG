`timescale 1ns/1ps
module tb_gime_native_video;
    reg clk=0,reset_n=0;
    wire hs_n,fs_n,hblank,vblank;
    integer errors=0;
    integer raster_ticks=0;
    integer frames=0;

    always #5 clk=!clk;

    gime_native_video dut(
        .clk(clk),.reset_n(reset_n),.active_height(8'd192),
        .pixel_rgb(6'd0),.hs_n(hs_n),.fs_n(fs_n),
        .hblank(hblank),.vblank(vblank),.red(),.green(),.blue());

    always @(posedge clk) begin
        if (reset_n && dut.raster_tick) begin
            raster_ticks=raster_ticks+1;
            if (dut.y==9'd262 && dut.x==10'd454) begin
                frames=frames+1;
                if (raster_ticks!=238875) begin
                    $display("native frame %0d was %0d dots, expected 238875",
                             frames,raster_ticks);
                    errors=errors+1;
                end
                raster_ticks=0;
                if (frames==2) begin
                    if (errors==0) $display("tb_gime_native_video PASS");
                    else $display("tb_gime_native_video FAIL: %0d",errors);
                    $finish;
                end
            end
            if (dut.y==9'd262 && dut.x>10'd454) begin
                $display("native half-line overran at x=%0d",dut.x);
                errors=errors+1;
            end
        end
    end

    initial begin
        repeat(3) @(posedge clk);
        reset_n=1;
        // Two 262.5-line frames take about 3.61 million 108 MHz clocks.
        repeat(3700000) @(posedge clk);
        $display("tb_gime_native_video timeout");
        $finish;
    end
endmodule
