`timescale 1ns/1ps
module tb_coco3_hdmi_pal_alignment;
    logic clk=0;
    always #5 clk=~clk;

    coco3_hdmi #(.PAL_MACHINE(1)) pal(
        .pixel_clk(clk),.serial_clk(clk),.audio_clk(clk),.reset(1'b1),
        .video_50hz(1'b1),.bit_plane(1'b1),.active_height(8'd192),
        .compatibility_mode(1'b0),.border_rgb(6'd0),
        .row_left_border_rgb(6'd0),.row_right_border_rgb(6'd0),
        .row_border_valid(1'b0),.vertical_left_border_rgb(6'd0),
        .vertical_right_border_rgb(6'd0),.vertical_border_valid(1'b0),
        .pixel_data(24'd0));
    coco3_hdmi #(.PAL_MACHINE(0)) ntsc(
        .pixel_clk(clk),.serial_clk(clk),.audio_clk(clk),.reset(1'b1),
        .video_50hz(1'b1),.bit_plane(1'b1),.active_height(8'd192),
        .compatibility_mode(1'b0),.border_rgb(6'd0),
        .row_left_border_rgb(6'd0),.row_right_border_rgb(6'd0),
        .row_border_valid(1'b0),.vertical_left_border_rgb(6'd0),
        .vertical_right_border_rgb(6'd0),.vertical_border_valid(1'b0),
        .pixel_data(24'd0));

    integer errors=0;
    logic [7:0] cold_source16,cold_prefetch16;
    task check_top;
        input [7:0] height;
        input [9:0] pal_expected,ntsc_expected;
        begin
            force pal.height_s=height;
            force ntsc.height_s=height;
            #1;
            if(pal.top!==pal_expected||ntsc.top!==ntsc_expected)begin
                $display("height %0d: PAL top %0d NTSC top %0d",height,pal.top,ntsc.top);
                errors=errors+1;
            end
        end
    endtask

    initial begin
        // BOINK's 225-line 60 Hz picture begins at HDMI line 18.  Check
        // both the first output line and a line safely inside the picture;
        // later compare them after exercising the 50 Hz mapping.
        force ntsc.height_s=8'd225;
        force ntsc.active_50hz_s=1'b0;
        force ntsc.compatibility_s=1'b0;
        force ntsc.x=10'd40;
        force ntsc.y=10'd18;
        #1;
        if(ntsc.source_y!==8'd0||!ntsc.source_valid||
           ntsc.prefetch_y!==8'd1)begin
            $display("cold 60Hz first HDMI line maps to row %0d",ntsc.source_y);
            errors=errors+1;
        end
        force ntsc.y=10'd50;
        #1;
        cold_source16=ntsc.source_y;
        cold_prefetch16=ntsc.prefetch_y;
        $display("HDMI MAP cold60 physical_y=50 source_y=%0d prefetch_y=%0d",
                 cold_source16,cold_prefetch16);
        if(cold_source16!==8'd16||cold_prefetch16!==8'd17||
           !ntsc.source_valid)errors=errors+1;
        release ntsc.x;release ntsc.y;
        release ntsc.height_s;release ntsc.active_50hz_s;
        release ntsc.compatibility_s;

        force pal.active_50hz_s=1'b1;
        force ntsc.active_50hz_s=1'b1;
        force pal.compatibility_s=1'b0;
        force ntsc.compatibility_s=1'b0;
        check_top(192,98,96);
        check_top(199,90,89);
        check_top(225,64,63);
        force pal.compatibility_s=1'b1;
        check_top(192,96,96);
        check_top(199,89,89);
        check_top(225,63,63);
        force pal.compatibility_s=1'b0;
        force pal.active_50hz_s=1'b0;
        force ntsc.active_50hz_s=1'b0;
        force pal.bit_plane_s=1'b1;
        check_top(192,52,52);
        check_top(199,48,48);
        check_top(225,18,18);
        force pal.y=10'd18;
        force ntsc.y=10'd18;
        force pal.x=10'd0;
        force ntsc.x=10'd0;
        force ntsc.bit_plane_s=1'b1;
        #1;
        if(pal.prefetch_valid||!ntsc.prefetch_valid)begin
            $display("PAL first-half prefetch gate changed");
            errors=errors+1;
        end
        force pal.x=10'd319;
        #1;
        if(pal.prefetch_valid)begin
            $display("PAL first-half prefetch gate ended early");
            errors=errors+1;
        end
        force pal.x=10'd320;
        #1;
        if(!pal.prefetch_valid)begin
            $display("PAL first-half prefetch gate stayed active");
            errors=errors+1;
        end
        force pal.x=10'd0;
        force pal.bit_plane_s=1'b0;
        #1;
        if(!pal.prefetch_valid||pal.top!=10'd18)begin
            $display("PAL native text prefetch changed");
            errors=errors+1;
        end
        force pal.bit_plane_s=1'b1;
        force pal.compatibility_s=1'b1;
        #1;
        if(!pal.prefetch_valid)begin
            $display("PAL VDG prefetch changed");
            errors=errors+1;
        end
        force pal.compatibility_s=1'b0;
        force pal.active_50hz_s=1'b1;
        force pal.y=10'd128;
        #1;
        if(!pal.prefetch_valid)begin
            $display("PAL 50Hz prefetch changed");
            errors=errors+1;
        end
        // A returned 60 Hz field must select the exact same source row as
        // cold 60 Hz, independent of its prior 50 Hz top margin.
        force ntsc.active_50hz_s=1'b0;
        force ntsc.compatibility_s=1'b0;
        force ntsc.height_s=8'd225;
        force ntsc.x=10'd40;
        force ntsc.y=10'd50;
        #1;
        $display("HDMI MAP warm60 physical_y=50 source_y=%0d prefetch_y=%0d",
                 ntsc.source_y,ntsc.prefetch_y);
        if(ntsc.source_y!==cold_source16||
           ntsc.prefetch_y!==cold_prefetch16||!ntsc.source_valid)begin
            $display("50->60 HDMI source row drifted at physical line 50");
            errors=errors+1;
        end
        if(errors==0)$display("tb_coco3_hdmi_pal_alignment PASS");
        else $display("tb_coco3_hdmi_pal_alignment FAIL: %0d",errors);
        $finish;
    end
endmodule

// Gowin output primitives have no bearing on the source-row geometry.
module OSER10(output Q,input D0,D1,D2,D3,D4,D5,D6,D7,D8,D9,
              input PCLK,FCLK,RESET);
    assign Q=1'b0;
endmodule
module ELVDS_OBUF(input I,output O,OB);
    assign O=I;
    assign OB=~I;
endmodule
module serializer #(parameter integer NUM_CHANNELS=3,parameter real VIDEO_RATE=0)(
    input clk_pixel,clk_pixel_x5,reset,
    input [9:0] tmds_internal [NUM_CHANNELS-1:0],
    output [2:0] tmds,output tmds_clock);
    assign tmds=0;
    assign tmds_clock=0;
endmodule
module hdmi #(
    parameter integer VIDEO_ID_CODE=2,DYNAMIC_480_576=1,PAL_MACHINE=0,
    parameter integer DVI_OUTPUT=0,AUDIO_RATE=48000,AUDIO_BIT_WIDTH=16,
    parameter integer NUM_CHANNELS=3,START_X=0,START_Y=0,
    parameter real VIDEO_REFRESH_RATE=59.94)(
    input clk_pixel_x5,clk_pixel,clk_audio,reset,video_50hz,
    input [23:0] rgb,input [AUDIO_BIT_WIDTH-1:0] audio_sample_word [1:0],
    output [9:0] cx,cy,frame_width,frame_height,screen_width,screen_height,
    output active_video_50hz,output [9:0] tmds_internal [NUM_CHANNELS-1:0]);
    assign cx=0;
    assign cy=0;
    assign frame_width=864;
    assign frame_height=625;
    assign screen_width=720;
    assign screen_height=576;
    assign active_video_50hz=1;
endmodule
