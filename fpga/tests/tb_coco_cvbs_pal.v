`timescale 1ns/1ps

module tb_coco_cvbs_pal;
    reg clk135 = 0;
    reg clk270 = 0;
    reg reset_n = 0;
    always #4 clk135 = ~clk135;
    always #2 clk270 = ~clk270;

    coco_cvbs_ntsc #(.PAL_CHROMA_OUTPUT(1)) dut (
        .clk135(clk135),.clk270(clk270),.reset_n(reset_n),
        .video_50hz(1'b0),.high_resolution(1'b1),
        .compatibility_mode(1'b0),.framebuffer_data(6'b0),
        .border_rgb(6'b0),.row_border_rgb(6'b0),
        .row_right_border_rgb(6'b0),.row_border_valid(1'b0),
        .vertical_left_border_rgb(6'b0),
        .vertical_right_border_rgb(6'b0),
        .vertical_border_valid(1'b0),.active_height(8'd192)
    );

    integer count;
    reg [25:0] expected_phase;
    initial begin
        repeat (3) @(negedge clk135);
        reset_n = 1;
        expected_phase = 0;
        for (count = 0; count < 8580; count = count + 1) begin
            @(posedge clk135);
            expected_phase = expected_phase + 26'd2203964;
            #1;
            if (dut.pal_carrier_acc !== expected_phase)
                $fatal(1,"PAL carrier step mismatch at clock %0d",count);
            if (dut.carrier_phase !== expected_phase[25:23])
                $fatal(1,"PAL carrier phase is not selected");
        end
        if (dut.h_sample !== 0 || dut.v_line !== 18 ||
            dut.pal_v_invert !== 1 || dut.burst_phase_offset !== 5)
            $fatal(1,"PAL line or burst phase did not alternate");
        for (count = 0; count < 8580; count = count + 1)
            @(posedge clk135);
        #1;
        if (dut.h_sample !== 0 || dut.v_line !== 19 ||
            dut.pal_v_invert !== 0 || dut.burst_phase_offset !== 3)
            $fatal(1,"PAL line or burst phase did not alternate back");
        if (dut.h_total !== 858)
            $fatal(1,"PAL chroma changed NTSC horizontal timing");
        force dut.mod_y4 = 11'sd64;
        force dut.mod_carrier = 3'd0;
        #1;
        if (dut.mod_picture_chroma !== 6'sd1)
            $fatal(1,"PAL picture V is wrong on the first line parity");
        if (dut.mod_svideo_picture_chroma !== dut.mod_picture_chroma)
            $fatal(1,"PAL S-Video picture phase differs from CVBS");
        force dut.pal_v_invert = 1'b1;
        #1;
        if (dut.mod_picture_chroma !== -6'sd1)
            $fatal(1,"PAL picture V did not invert on alternate lines");
        if (dut.mod_svideo_picture_chroma !== dut.mod_picture_chroma)
            $fatal(1,"PAL S-Video picture phase differs on alternate lines");
        force dut.level_svideo_chroma = 6'sd3;
        #1;
        if (dut.svideo_picture_chroma !== 8'sd12)
            $fatal(1,"PAL S-Video picture polarity/gain is wrong");
        release dut.level_svideo_chroma;
        release dut.pal_v_invert;
        release dut.mod_carrier;
        release dut.mod_y4;
        $display("PAL CVBS chroma PASS");
        $finish;
    end
endmodule
