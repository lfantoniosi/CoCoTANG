`timescale 1ns/1ps
module tb_coco_cvbs_ntsc;
    reg clk270 = 1'b0;
    reg clk135 = 1'b0;
    reg reset_n = 1'b0;
    reg video_50hz = 1'b0;
    reg high_resolution = 1'b0;
    reg compatibility_mode = 1'b1;
    reg [5:0] framebuffer_data = 6'b111111;
    reg [5:0] border_rgb = 6'b001100;
    reg [5:0] row_border_rgb = 6'b001100;
    reg [5:0] row_right_border_rgb = 6'b001100;
    reg row_border_valid = 1'b0;
    reg [5:0] vertical_left_border_rgb = 6'h3f;
    reg [5:0] vertical_right_border_rgb = 6'h3f;
    reg vertical_border_valid = 1'b1;
    wire [15:0] framebuffer_addr;
    wire [9:0] source_x;
    wire [7:0] source_y,prefetch_y;
    wire source_valid,prefetch_valid;
    wire [8:0] border_raster_y;
    wire luma_out, chroma_out, cvbs_out,component_pb_out,component_pr_out;
    integer errors = 0;
    integer ones;
    integer luma_ones;
    integer i;
    reg [8:0] saved_fraction;
    reg [2:0] saved_octant;

    coco_cvbs_ntsc #(.CANONICAL_640_INPUT(1)) dut(
        .clk135(clk135),.clk270(clk270),.reset_n(reset_n),
        .video_50hz(video_50hz),.high_resolution(high_resolution),
        .compatibility_mode(compatibility_mode),
        .framebuffer_data(framebuffer_data),.border_rgb(border_rgb),
        .row_border_rgb(row_border_rgb),
        .row_right_border_rgb(row_right_border_rgb),
        .row_border_valid(row_border_valid),
        .vertical_left_border_rgb(vertical_left_border_rgb),
        .vertical_right_border_rgb(vertical_right_border_rgb),
        .vertical_border_valid(vertical_border_valid),
        .active_height(8'd192),
        .framebuffer_addr(framebuffer_addr),
        .source_x(source_x),.source_y(source_y),.source_valid(source_valid),
        .prefetch_y(prefetch_y),.prefetch_valid(prefetch_valid),
        .border_raster_y(border_raster_y),
        .luma_out(luma_out),.chroma_out(chroma_out),.cvbs_out(cvbs_out),
        .component_pb_out(component_pb_out),.component_pr_out(component_pr_out));

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

        seek(10'd71,9'd10);
        if (dut.in_burst) begin $display("burst starts too early"); errors = errors + 1; end
        seek(10'd72,9'd10);
        if (!dut.in_burst) begin $display("burst window"); errors = errors + 1; end
        saved_fraction = dut.carrier_fraction;
        saved_octant = dut.carrier_octant;
        seek(10'd72,9'd11);
        if ((dut.carrier_fraction != saved_fraction) ||
            (dut.carrier_octant != saved_octant + 3'd4))
            begin $display("carrier line phase"); errors = errors + 1; end

        seek(10'd117,9'd17);
        if (dut.in_vdg_window) begin $display("border starts too early"); errors = errors + 1; end
        seek(10'd118,9'd17);
        if (!dut.in_vdg_window || dut.in_picture) begin $display("top-left border window"); errors = errors + 1; end

        seek(10'd222,9'd44);
        if (!source_valid || source_x != 10'd0) begin $display("VDG first pixel"); errors = errors + 1; end
        seek(10'd224,9'd44);
        if (source_x != 10'd2) begin $display("VDG canonical scale: %0d",source_x); errors = errors + 1; end
        seek(10'd733,9'd235);
        if (!source_valid || source_x != 10'd638 || source_y != 8'd191) begin
            $display("VDG last pixel: %0d,%0d",source_x,source_y); errors = errors + 1; end
        // The first lower-border line must take the captured VDG raster
        // border, even if an old picture-cache row is still marked valid.
        row_border_valid = 1'b1;
        row_border_rgb = 6'h0c;
        seek(10'd222,9'd236);
        repeat (4) @(posedge clk135); #1;
        if (border_raster_y != 9'd234 || dut.pixel_rgb !== 6'h3f) begin
            $display("compatibility lower border: raster=%0d rgb=%h",
                     border_raster_y,dut.pixel_rgb); errors = errors + 1; end
        row_border_valid = 1'b0;

        high_resolution = 1'b1;
        compatibility_mode = 1'b0;
        // Both borders of the active raster come from its committed cache
        // record, not from the current FF9A colour or the opposite endpoint.
        row_border_valid = 1'b1;
        row_border_rgb = 6'h0c;
        row_right_border_rgb = 6'h3f;
        border_rgb = 6'h15;
        seek(10'd150,9'd44);
        @(posedge clk135); #1;
        if (dut.border_sample !== 6'h0c) begin
            $display("native left border used live/other-row colour"); errors=errors+1;
        end
        seek(10'd158,9'd44);
        if (!source_valid || source_x != 10'd0 || source_y != 8'd0) begin
            $display("640-wide first pixel: %0d,%0d",source_x,source_y); errors=errors+1;
        end
        seek(10'd797,9'd44);
        if (!source_valid || !dut.in_vdg_window || source_x != 10'd639) begin
            $display("640-wide last pixel: %0d",source_x); errors=errors+1;
        end
        seek(10'd800,9'd44);
        @(posedge clk135); #1;
        if (dut.border_sample !== 6'h3f) begin
            $display("native right border used live/left colour"); errors=errors+1;
        end
        row_border_valid = 1'b0;
        compatibility_mode = 1'b1;
        high_resolution = 1'b0;

        // Component outputs are baseband differences, not colour-subcarrier
        // waveforms. Check the Q2 matrix levels around midpoint 64.
        force dut.level_picture=1'b1;
        force dut.mod_component_x=8'sd63;force dut.mod_component_y=8'sd0;#1;
        if(dut.component_pb_level!=7'd127||dut.component_pr_level!=7'd55)begin
            $display("blue component Pb=%0d Pr=%0d",
                     dut.component_pb_level,dut.component_pr_level);errors=errors+1;end
        force dut.mod_component_x=8'sd0;force dut.mod_component_y=8'sd63;#1;
        if(dut.component_pb_level!=7'd43||dut.component_pr_level!=7'd127)begin
            $display("red component Pb=%0d Pr=%0d",
                     dut.component_pb_level,dut.component_pr_level);errors=errors+1;end
        release dut.mod_component_y;release dut.mod_component_x;
        release dut.level_picture;

        // Separate component/S-Video Y uses the same physical output stage
        // and 87-code picture excursion as the untrimmed RGB channels.  Its
        // black and white endpoints must therefore be 40 and 127.
        force dut.encoder_luma_rb=10'd32;
        force dut.encoder_luma_g=10'd0;
        #1;
        if(dut.encoder_y_picture_excursion!=7'd0)begin
            $display("separate Y black excursion=%0d",
                     dut.encoder_y_picture_excursion);errors=errors+1;end
        force dut.encoder_luma_rb=10'd536;
        force dut.encoder_luma_g=10'd756;
        #1;
        if(dut.encoder_y_picture_excursion!=7'd87)begin
            $display("separate Y white excursion=%0d",
                     dut.encoder_y_picture_excursion);errors=errors+1;end
        release dut.encoder_luma_g;release dut.encoder_luma_rb;

        // Move to an ordinary blank interval and allow the encoder pipeline
        // to settle. Level 10 in a modulo-32 DAC is exactly 40 ones/128.
        seek(10'd110,9'd236);
        repeat (20) @(negedge clk135);
        ones = 0;
        luma_ones = 0;
        for (i=0;i<128;i=i+1) begin
            if (cvbs_out) ones = ones + 1;
            if (luma_out) luma_ones = luma_ones + 1;
            @(negedge clk270);
        end
        if (ones != 40) begin
            $display("blank density: %0d level135=%0d dac=%0d acc=%0d sync=%0d h=%0d v=%0d",
                ones,dut.cvbs_level_135,dut.cvbs_dac_level,dut.cvbs_sigma[4:0],
                dut.level_sync,dut.h_sample,dut.v_line);
            errors = errors + 1;
        end
        if (luma_ones != 40) begin
            $display("Q2 luma blank density: %0d level135=%0d dac=%0d acc=%0d",
                luma_ones,dut.luma_level_135,dut.luma_dac_level,
                dut.luma_sigma[6:0]);
            errors = errors + 1;
        end

        seek(10'd837,9'd261);
        if (!dut.in_vdg_window || dut.in_picture) begin $display("bottom-right border window"); errors = errors + 1; end
        seek(10'd838,9'd261);
        if (dut.in_vdg_window) begin $display("border ends too late"); errors = errors + 1; end

        // The backwards seek used by the high-resolution checks has advanced
        // us to the short field. Compatibility/VDG uses the same fixed one-line cache delay.
        if (dut.field_odd !== 1'b0) begin
            $display("short field parity"); errors = errors + 1;
        end
        seek(10'd857,9'd261);
        repeat (10) @(posedge clk135); #1;
        if (dut.h_sample != 0 || dut.v_line != 0 || dut.sample_phase != 0) begin
            $display("262-line field wrap: h=%0d v=%0d p=%0d",
                     dut.h_sample,dut.v_line,dut.sample_phase);
            errors = errors + 1;
        end
        if (dut.field_odd !== 1'b1) begin
            $display("field parity did not toggle"); errors = errors + 1;
        end

        // Native GIME starts one line later in every field. This is a fixed
        // cache phase delay, not an alternating vertical displacement.
        compatibility_mode = 1'b0;
        seek(10'd222,9'd44);
        if (!source_valid || source_y != 0 || dut.field_odd !== 1'b1) begin
            $display("native 263-line field top margin"); errors = errors + 1;
        end

        video_50hz = 1'b1;
        repeat (3) @(posedge clk135); #1;
        if (!dut.video_50hz_sync || !dut.video_50hz_active ||
            dut.field_last_line != 9'd311 ||
            dut.next_picture_top != 9'd65 || dut.h_total != 10'd864 ||
            dut.h_sample != 10'd0 || dut.v_line != dut.V_PHASE_OFFSET) begin
            $display("50Hz analog geometry last=%0d top=%0d",
                     dut.field_last_line,dut.next_picture_top);
            errors = errors + 1;
        end

        if (errors == 0) $display("tb_coco_cvbs_ntsc PASS");
        else $display("tb_coco_cvbs_ntsc FAIL: %0d",errors);
        $finish;
    end
endmodule
