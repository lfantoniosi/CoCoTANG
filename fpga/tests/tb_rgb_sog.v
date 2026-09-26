`timescale 1ns/1ps

module tb_rgb_sog;
    reg clk135 = 1'b0;
    reg clk270 = 1'b0;
    reg reset_n = 1'b0;
    wire [15:0] framebuffer_addr;
    wire [9:0] source_x;
    wire [7:0] source_y;
    wire [7:0] prefetch_y;
    wire source_valid, prefetch_valid;
    wire green_sog, blue, red;
    wire unused_chroma, unused_cvbs;
    integer errors = 0;

    coco_cvbs_ntsc #(
        .CANONICAL_640_INPUT(1),
        .RGB_SOG_OUTPUT(1)
    ) dut (
        .clk135(clk135), .clk270(clk270), .reset_n(reset_n),
        .video_50hz(1'b0), .high_resolution(1'b1),
        .compatibility_mode(1'b0), .framebuffer_data(6'd0),
        .border_rgb(6'd0), .row_border_rgb(6'd0),
        .row_border_valid(1'b0), .active_height(8'd192),
        .framebuffer_addr(framebuffer_addr), .source_x(source_x),
        .source_y(source_y), .source_valid(source_valid),
        .prefetch_y(prefetch_y), .prefetch_valid(prefetch_valid),
        .luma_out(green_sog), .chroma_out(unused_chroma),
        .cvbs_out(unused_cvbs), .component_pb_out(blue),
        .component_pr_out(red)
    );

    always #2 clk270 = ~clk270;
    always #4 clk135 = ~clk135;

    task check_levels;
        input sync;
        input picture;
        input [5:0] rgb;
        input [6:0] expected_r;
        input [6:0] expected_g;
        input [6:0] expected_b;
        begin
            force dut.level_sync = sync;
            force dut.level_picture = picture;
            force dut.mod_rgb = rgb;
            #1;
            if (dut.component_pr_level !== expected_r ||
                dut.luma_level !== expected_g ||
                dut.component_pb_level !== expected_b) begin
                $display("RGB SoG levels rgb=%02x sync=%0d picture=%0d: R=%0d G=%0d B=%0d expected %0d/%0d/%0d",
                         rgb,sync,picture,dut.component_pr_level,
                         dut.luma_level,dut.component_pb_level,
                         expected_r,expected_g,expected_b);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        // Blanking is black on R/B and the 0.3-V pedestal on green.
        check_levels(1'b0,1'b0,6'h00,7'd0,7'd40,7'd0);
        // Sync is below black only on green.
        check_levels(1'b1,1'b0,6'h3f,7'd0,7'd0,7'd0);
        check_levels(1'b0,1'b1,6'b000000,7'd0,7'd40,7'd0);
        // Preserve the balanced dark-gray step while independently compressing
        // red and blue at the two brighter levels measured with RGBGRAY.BAS.
        check_levels(1'b0,1'b1,6'b010101,7'd42,7'd60,7'd42);
        check_levels(1'b0,1'b1,6'b101010,7'd75,7'd81,7'd81);
        check_levels(1'b0,1'b1,6'b111111,7'd105,7'd102,7'd117);
        release dut.level_sync;
        release dut.level_picture;
        release dut.mod_rgb;

        // The pipelined sync detector must produce exactly one 270-MHz pulse
        // when luma enters the sync tip.
        reset_n = 1'b1;
        force dut.luma_level_135 = 7'd40;
        repeat (3) @(posedge clk270); #1;
        force dut.luma_level_135 = 7'd0;
        @(posedge clk270); #1;
        if (!dut.dac_line_start) begin
            $display("pipelined DAC line-start pulse missing");
            errors = errors + 1;
        end
        @(posedge clk270); #1;
        if (dut.dac_line_start) begin
            $display("pipelined DAC line-start pulse too long");
            errors = errors + 1;
        end
        release dut.luma_level_135;

        if (errors == 0) $display("tb_rgb_sog PASS");
        else $display("tb_rgb_sog FAIL: %0d",errors);
        $finish;
    end
endmodule
