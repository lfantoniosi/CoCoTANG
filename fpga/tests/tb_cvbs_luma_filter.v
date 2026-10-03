`timescale 1ns/1ps

module tb_cvbs_luma_filter;
    reg clk135 = 0, clk270 = 0, reset_n = 0;
    always #4 clk135 = ~clk135;
    always #2 clk270 = ~clk270;

    coco_cvbs_ntsc #(.CVBS_LUMA_FILTER(1)) filtered (
        .clk135(clk135), .clk270(clk270), .reset_n(reset_n),
        .video_50hz(1'b0), .high_resolution(1'b1),
        .compatibility_mode(1'b0), .framebuffer_data(6'd0),
        .border_rgb(6'd0), .row_border_rgb(6'd0),
        .row_right_border_rgb(6'd0), .row_border_valid(1'b0),
        .vertical_left_border_rgb(6'd0),
        .vertical_right_border_rgb(6'd0),
        .vertical_border_valid(1'b0), .active_height(8'd192));
    coco_cvbs_ntsc legacy (
        .clk135(clk135), .clk270(clk270), .reset_n(reset_n),
        .video_50hz(1'b0), .high_resolution(1'b1),
        .compatibility_mode(1'b0), .framebuffer_data(6'd0),
        .border_rgb(6'd0), .row_border_rgb(6'd0),
        .row_right_border_rgb(6'd0), .row_border_valid(1'b0),
        .vertical_left_border_rgb(6'd0),
        .vertical_right_border_rgb(6'd0),
        .vertical_border_valid(1'b0), .active_height(8'd192));

    task sample;
        input [10:0] luma_sum;
        input [5:0] expected_filtered;
        input [5:0] expected_unfiltered;
        begin
            force filtered.encoder_luma_sum = luma_sum;
            force legacy.encoder_luma_sum = luma_sum;
            force filtered.encoder_sample_tick = 1'b1;
            force legacy.encoder_sample_tick = 1'b1;
            @(posedge clk135); #1;
            force filtered.encoder_sample_tick = 1'b0;
            force legacy.encoder_sample_tick = 1'b0;
            @(posedge clk135); #1;
            if (filtered.level_luma !== expected_filtered ||
                legacy.level_luma !== expected_unfiltered)
                $fatal(1,"CVBS FIR mismatch: filtered=%0d legacy=%0d",
                    filtered.level_luma, legacy.level_luma);
            if (filtered.level_luma_q2 !== legacy.level_luma_q2 ||
                filtered.luma_level !== legacy.luma_level)
                $fatal(1,"S-Video Y changed with CVBS FIR enabled");
        end
    endtask

    initial begin
        repeat (3) @(negedge clk135);
        reset_n = 1;
        sample(11'd0, 6'd10, 6'd10);
        sample(11'd1408, 6'd16, 6'd32);
        sample(11'd1408, 6'd27, 6'd32);
        sample(11'd1408, 6'd32, 6'd32);
        sample(11'd0, 6'd27, 6'd10);
        force filtered.level_sync = 1'b1;
        force filtered.level_picture = 1'b0;
        #1;
        if (filtered.composite_level !== 6'd0)
            $fatal(1,"CVBS FIR changed sync tip");
        force filtered.level_sync = 1'b0;
        #1;
        if (filtered.composite_level !== 6'd10)
            $fatal(1,"CVBS FIR changed blanking level");
        $display("CVBS luma FIR PASS");
        $finish;
    end
endmodule
