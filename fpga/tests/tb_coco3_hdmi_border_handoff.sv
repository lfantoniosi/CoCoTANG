`timescale 1ns/1ps
module tb_coco3_hdmi_border_handoff;
    logic clk=0;
    logic [5:0] border_rgb=6'h15;
    always #5 clk=~clk;

    coco3_hdmi dut(
        .pixel_clk(clk),.serial_clk(clk),.audio_clk(clk),.reset(1'b1),
        .video_50hz(1'b0),.bit_plane(1'b1),.active_height(8'd192),
        .compatibility_mode(1'b0),.border_rgb(border_rgb),
        .artifact_mode(2'd0),.artifact_video_active(1'b0),
        .artifact_css(1'b0),.overlay_enable(1'b0),
        .row_left_border_rgb(6'd0),.row_right_border_rgb(6'd0),
        .row_border_valid(1'b0),.vertical_left_border_rgb(6'd0),
        .vertical_right_border_rgb(6'd0),.vertical_border_valid(1'b0),
        .pixel_data(24'd0));

    initial begin
        force dut.x=10'd0;
        force dut.y=10'd0;
        @(posedge clk); #1;
        if (dut.border_row_current!==6'h15)
            $fatal(1,"first border colour was not captured");

        border_rgb=6'h2a;
        force dut.y=10'd2;
        @(posedge clk); #1;
        if (dut.encoder.sampled_rgb!==24'h555555)
            $fatal(1,"first pixel used the previous border row");
        force dut.x=10'd1;
        @(posedge clk); #1;
        if (dut.encoder.sampled_rgb!==24'h555555)
            $fatal(1,"second pixel changed colour within the row: %h current=%h delayed=%h",dut.encoder.sampled_rgb,dut.border_row_current,dut.border_row_delayed);

        force dut.x=10'd0;
        force dut.y=10'd4;
        @(posedge clk); #1;
        if (dut.encoder.sampled_rgb!==24'haaaaaa)
            $fatal(1,"following row did not receive the new colour");
        $display("tb_coco3_hdmi_border_handoff PASS");
        $finish;
    end
endmodule

// Output primitives and the HDMI timing engine are irrelevant to this
// scanline-border handoff test.
module serializer #(parameter integer NUM_CHANNELS=3,parameter real VIDEO_RATE=0)(
    input clk_pixel,clk_pixel_x5,reset,
    input [9:0] tmds_internal [NUM_CHANNELS-1:0],
    output [2:0] tmds,output tmds_clock);
    assign tmds=0;
    assign tmds_clock=0;
endmodule
module hdmi #(
    parameter integer VIDEO_ID_CODE=2,DYNAMIC_480_576=1,
    parameter integer DVI_OUTPUT=0,AUDIO_RATE=48000,AUDIO_BIT_WIDTH=16,
    parameter integer NUM_CHANNELS=3,START_X=0,START_Y=0,
    parameter real VIDEO_REFRESH_RATE=59.94)(
    input clk_pixel_x5,clk_pixel,clk_audio,reset,video_50hz,
    input [23:0] rgb,input [AUDIO_BIT_WIDTH-1:0] audio_sample_word [1:0],
    output [9:0] cx,cy,frame_width,frame_height,screen_width,screen_height,
    output active_video_50hz,output [9:0] tmds_internal [NUM_CHANNELS-1:0]);
    logic [23:0] sampled_rgb;
    always @(posedge clk_pixel) sampled_rgb<=rgb;
    assign cx=0;
    assign cy=0;
    assign frame_width=858;
    assign frame_height=525;
    assign screen_width=720;
    assign screen_height=480;
    assign active_video_50hz=0;
endmodule
module ELVDS_OBUF(input I, output O, OB);
    assign O=I;
    assign OB=~I;
endmodule
