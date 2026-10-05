`timescale 1ns/1ps

module tb_coco_cvbs_ntsc_svideo;
    reg clk135 = 0;
    reg clk270 = 0;
    reg reset_n = 0;
    always #4 clk135 = ~clk135;
    always #2 clk270 = ~clk270;
    wire matched_cvbs;

    coco_cvbs_ntsc matched (
        .clk135(clk135),.clk270(clk270),.reset_n(reset_n),
        .video_50hz(1'b0),.high_resolution(1'b1),
        .compatibility_mode(1'b0),.framebuffer_data(6'h0c),
        .border_rgb(6'h0c),.row_border_rgb(6'h0c),
        .row_right_border_rgb(6'h0c),.row_border_valid(1'b0),
        .vertical_left_border_rgb(6'h0c),
        .vertical_right_border_rgb(6'h0c),
        .vertical_border_valid(1'b0),.active_height(8'd192),
        .cvbs_out(matched_cvbs)
    );
    integer count;
    initial begin
        repeat (3) @(negedge clk135);
        reset_n = 1;
        for (count = 0; count < 10000; count = count + 1) begin
            @(negedge clk270);
        end
        if (matched.carrier_phase !== matched.carrier_octant ||
            matched.burst_phase_offset !== 3'd4 ||
            matched.h_total !== 10'd858)
            $fatal(1,"NTSC carrier, burst phase, or line timing changed");
        force matched.mod_y4 = 11'sd64;
        force matched.mod_carrier = 3'd0;
        #1;
        if (matched.mod_svideo_picture_chroma !==
            matched.mod_picture_chroma)
            $fatal(1,"matched S-Video picture phase differs from CVBS");
        force matched.level_svideo_chroma = 6'sd3;
        #1;
        if (matched.svideo_picture_chroma !== 8'sd12)
            $fatal(1,"matched S-Video picture polarity/gain is wrong");
        release matched.level_svideo_chroma;
        release matched.mod_carrier;
        release matched.mod_y4;
        $display("NTSC S-Video/CVBS phase match PASS");
        $finish;
    end
endmodule
