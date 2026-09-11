`timescale 1ns/1ps
module tb_coco_cvbs_ntsc;
    reg clk270 = 1'b0;
    reg clk135 = 1'b0;
    reg reset_n = 1'b0;
    reg high_resolution = 1'b0;
    reg [5:0] framebuffer_data = 6'b111111;
    reg [5:0] border_rgb = 6'b001100;
    wire [15:0] framebuffer_addr;
    wire [9:0] source_x;
    wire [7:0] source_y,prefetch_y;
    wire source_valid,prefetch_valid;
    wire luma_out, chroma_out, cvbs_out;
    integer errors = 0;
    integer ones;
    integer i;
    reg [8:0] saved_fraction;
    reg [2:0] saved_octant;

    coco_cvbs_ntsc dut(
        .clk135(clk135),.clk270(clk270),.reset_n(reset_n),.high_resolution(high_resolution),
        .framebuffer_data(framebuffer_data),.border_rgb(border_rgb),.active_height(8'd192),
        .framebuffer_addr(framebuffer_addr),
        .source_x(source_x),.source_y(source_y),.source_valid(source_valid),
        .prefetch_y(prefetch_y),.prefetch_valid(prefetch_valid),
        .luma_out(luma_out),.chroma_out(chroma_out),.cvbs_out(cvbs_out));

    always #1.85185 clk270 = ~clk270;
    always #3.70370 clk135 = ~clk135;

    task seek;
        input [9:0] h;
        input [8:0] v;
        begin
            while ((dut.h_sample != h) || (dut.v_line != v) ||
                   (dut.sample_phase != 0))
                @(negedge clk135);
        end
    endtask

    initial begin
        repeat (4) @(negedge clk135);
        reset_n = 1'b1;

        seek(10'd0,9'd0);
        if (!dut.sync_tip) begin $display("pre-equalizing sync start"); errors = errors + 1; end
        seek(10'd32,9'd0);
        if (dut.sync_tip) begin $display("pre-equalizing sync end"); errors = errors + 1; end
        seek(10'd0,9'd10);
        if (!dut.sync_tip) begin $display("horizontal sync start"); errors = errors + 1; end
        seek(10'd64,9'd10);
        if (dut.sync_tip) begin $display("horizontal sync end"); errors = errors + 1; end

        seek(10'd67,9'd10);
        if (dut.in_burst) begin $display("burst starts too early"); errors = errors + 1; end
        seek(10'd68,9'd10);
        if (!dut.in_burst) begin $display("burst window"); errors = errors + 1; end
        saved_fraction = dut.carrier_fraction;
        saved_octant = dut.carrier_octant;
        seek(10'd68,9'd11);
        if ((dut.carrier_fraction != saved_fraction) ||
            (dut.carrier_octant != saved_octant + 3'd4))
            begin $display("carrier line phase"); errors = errors + 1; end

        seek(10'd157,9'd17);
        if (dut.in_vdg_window) begin $display("border starts too early"); errors = errors + 1; end
        seek(10'd158,9'd17);
        if (!dut.in_vdg_window || dut.in_picture) begin $display("top-left border window"); errors = errors + 1; end

        seek(10'd222,9'd44);
        if (framebuffer_addr != 16'd0) begin $display("framebuffer first pixel"); errors = errors + 1; end
        seek(10'd224,9'd44);
        if (framebuffer_addr != 16'd1) begin $display("framebuffer horizontal scale"); errors = errors + 1; end
        seek(10'd732,9'd235);
        if (framebuffer_addr != {8'd191,8'd255}) begin $display("framebuffer last pixel: %h",framebuffer_addr); errors = errors + 1; end

        high_resolution = 1'b1;
        seek(10'd158,9'd44);
        if (!source_valid || source_x != 10'd0 || source_y != 8'd0) begin
            $display("640-wide first pixel: %0d,%0d",source_x,source_y); errors=errors+1;
        end
        seek(10'd797,9'd44);
        if (!source_valid || !dut.in_vdg_window || source_x != 10'd639) begin
            $display("640-wide last pixel: %0d",source_x); errors=errors+1;
        end
        high_resolution = 1'b0;

        // Move to an ordinary blank interval and allow the encoder pipeline
        // to settle. Level 10 in a modulo-32 DAC is exactly 40 ones/128.
        seek(10'd130,9'd236);
        repeat (20) @(negedge clk135);
        ones = 0;
        for (i=0;i<128;i=i+1) begin
            if (cvbs_out) ones = ones + 1;
            @(negedge clk270);
        end
        if (ones != 40) begin
            $display("blank density: %0d level135=%0d dac=%0d acc=%0d sync=%0d h=%0d v=%0d",
                ones,dut.cvbs_level_135,dut.cvbs_dac_level,dut.cvbs_sigma[4:0],
                dut.level_sync,dut.h_sample,dut.v_line);
            errors = errors + 1;
        end

        seek(10'd795,9'd261);
        if (!dut.in_vdg_window || dut.in_picture) begin $display("bottom-right border window"); errors = errors + 1; end

        if (errors == 0) $display("tb_coco_cvbs_ntsc PASS");
        else $display("tb_coco_cvbs_ntsc FAIL: %0d",errors);
        $finish;
    end
endmodule
