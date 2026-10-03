`timescale 1ns/1ps

module tb_rgb_scanline_dac_phase;
    reg clk135 = 0, clk270 = 0, reset_n = 0;
    always #4 clk135 = ~clk135;
    always #2 clk270 = ~clk270;

    coco_cvbs_ntsc #(.RGB_SOG_OUTPUT(1),
        .RGB_SCANLINE_PHASE_ALTERNATION(1)) dut (
        .clk135(clk135), .clk270(clk270), .reset_n(reset_n),
        .video_50hz(1'b0), .high_resolution(1'b1),
        .compatibility_mode(1'b0), .framebuffer_data(6'd0),
        .border_rgb(6'd0), .row_border_rgb(6'd0),
        .row_right_border_rgb(6'd0), .row_border_valid(1'b0),
        .vertical_left_border_rgb(6'd0),
        .vertical_right_border_rgb(6'd0),
        .vertical_border_valid(1'b0), .active_height(8'd192));

    task check_phase;
        input [7:0] green, blue, red;
        input next_phase;
        begin
            force dut.dac_line_start = 1'b1;
            @(posedge clk270); #1;
            if (dut.luma_sigma !== green ||
                dut.component_pb_sigma !== blue ||
                dut.component_pr_sigma !== red ||
                dut.dac_line_phase !== next_phase)
                $fatal(1,"RGB DAC phase mismatch: G=%0d B=%0d R=%0d phase=%b",
                    dut.luma_sigma, dut.component_pb_sigma,
                    dut.component_pr_sigma, dut.dac_line_phase);
            force dut.dac_line_start = 1'b0;
            @(posedge clk270); #1;
        end
    endtask

    initial begin
        repeat (3) @(negedge clk270);
        reset_n = 1;
        check_phase(8'd0, 8'd42, 8'd85, 1'b1);
        check_phase(8'd64, 8'd106, 8'd21, 1'b0);
        check_phase(8'd0, 8'd42, 8'd85, 1'b1);
        release dut.dac_line_start;
        $display("RGB scanline DAC phase PASS");
        $finish;
    end
endmodule
