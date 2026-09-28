`timescale 1ns/1ps
module tb_gime_50_to_60_field_wrap;
    reg clk=0,reset_n=0,video_50hz=0;
    wire ntsc_done,pal_done;
    always #5 clk=~clk;

    gime_50_to_60_field_case #(.PAL_MACHINE(0)) ntsc_case(
        .clk(clk),.reset_n(reset_n),.video_50hz(video_50hz),.done(ntsc_done));
    gime_50_to_60_field_case #(.PAL_MACHINE(1)) pal_case(
        .clk(clk),.reset_n(reset_n),.video_50hz(video_50hz),.done(pal_done));

    initial begin
        repeat(4) @(negedge clk);
        reset_n=1;
        @(negedge clk); video_50hz=1;
        repeat(4) @(negedge clk);
        video_50hz=0;
        wait(ntsc_done && pal_done);
        $display("tb_gime_50_to_60_field_wrap PASS");
        $finish;
    end
endmodule

module gime_50_to_60_field_case #(
    parameter integer PAL_MACHINE=0
) (
    input clk,reset_n,video_50hz,
    output reg done=0
);
    gime_native_video #(.PAL_MACHINE(PAL_MACHINE)) dut(
        .clk(clk),.reset_n(reset_n),.video_50hz(video_50hz),
        .bit_plane(1'b0),.hdmi_frame_start(1'b0),
        .hdmi_active_50hz(1'b0),.active_height(8'd225),
        .compatibility_mode(1'b0),.compatibility_css(1'b0),
        .compatibility_border_rgb(6'd0),.pixel_rgb(6'd0),
        .hs_n(),.fs_n(),.hborder_irq_n(),.hblank(),.vblank(),
        .debug_raster_y(),.compatibility_sample(),
        .compatibility_sample_css(),.compatibility_sample_y(),
        .compatibility_sample_byte(),.compatibility_border_sample(),
        .compatibility_border_right(),.compatibility_border_y(),
        .compatibility_border_sample_rgb(),.red(),.green(),.blue());

    initial begin
        wait(reset_n);
        wait(video_50hz);
        @(negedge clk);
        dut.native_field_50hz=1;
        dut.compatibility_field_50hz=1;
        dut.y=9'd300;
        dut.x=10'd0;
        dut.compatibility_y=9'd300;
        dut.compatibility_x=10'd0;
        wait(!video_50hz);
        @(negedge clk);
        if(dut.frame_last_line!==9'd312 ||
           dut.compatibility_last_line!==9'd311)
            $fatal(1,"PAL_MACHINE=%0d truncated the current 50 Hz field",
                   PAL_MACHINE);
        dut.y=9'd312;
        dut.x=PAL_MACHINE ? 10'd455 : 10'd454;
        dut.compatibility_y=9'd311;
        dut.compatibility_x=10'd911;
        force dut.raster_tick=1'b1;
        force dut.compatibility_raster_tick=1'b1;
        @(negedge clk);
        release dut.raster_tick;
        release dut.compatibility_raster_tick;
        if(dut.y!==9'd0 || dut.compatibility_y!==9'd0 ||
           dut.native_field_50hz!==1'b0 ||
           dut.compatibility_field_50hz!==1'b0)
            $fatal(1,"PAL_MACHINE=%0d did not wrap before adopting 60 Hz",
                   PAL_MACHINE);
        if(dut.frame_last_line!==9'd262 ||
           dut.compatibility_last_line!==9'd261)
            $fatal(1,"PAL_MACHINE=%0d did not adopt 60 Hz terminal",
                   PAL_MACHINE);
        done=1;
    end
endmodule
