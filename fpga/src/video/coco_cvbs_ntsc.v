`timescale 1ns/1ps

// NTSC encoder derived from the hardware-calibrated NTSCVideo generator.
// clk135 is divided by ten to the 13.5 MHz BT.601 sample grid. clk270 drives
// three first-order, one-bit DACs. The composite levels are deliberately the
// same as the proven pin-51 2N3904/75-ohm circuit: sync=0, blank=10, white=32.
module coco_cvbs_ntsc (
    input  wire        clk135,
    input  wire        clk270,
    input  wire        reset_n,
    input  wire        high_resolution,
    input  wire [5:0]  framebuffer_data,
    input  wire [5:0]  border_rgb,
    input  wire [7:0]  active_height,
    output wire [15:0] framebuffer_addr,
    output wire [9:0]  source_x,
    output wire [7:0]  source_y,
    output wire        source_valid,
    output wire [7:0]  prefetch_y,
    output wire        prefetch_valid,
    output wire        luma_out,
    output wire        chroma_out,
    output wire        cvbs_out
);
    parameter integer STREAMING_INPUT = 0;
    localparam [9:0] H_TOTAL        = 10'd858;
    localparam [9:0] H_SYNC         = 10'd64;
    // Advance the calibrated back-porch content by four 13.5 MHz samples.
    // Horizontal sync remains fixed; burst and active picture move together.
    localparam [9:0] BURST_START    = 10'd68;
    localparam [9:0] BURST_END      = 10'd102;
    // A framebuffer scales the 256 source pixels to 512 samples.  A live VDG
    // stream instead occupies its native 256/455 share of the 858-sample
    // line, or approximately 483 samples.
    wire [9:0] picture_left  = high_resolution ? 10'd158 :
                               STREAMING_INPUT ? 10'd271 : 10'd222;
    wire [9:0] picture_right = high_resolution ? 10'd798 :
                               STREAMING_INPUT ? 10'd754 : 10'd734;
    wire [9:0] border_left   = 10'd158;
    wire [9:0] border_right  = high_resolution ? 10'd798 : 10'd796;
    localparam [8:0] V_TOTAL        = 9'd262;
    reg [7:0] height_meta = 8'd192;
    reg [8:0] picture_top = 9'd44;
    reg [8:0] picture_bottom = 9'd236;
    wire [8:0] next_picture_top = (9'd280 - {1'b0,height_meta}) >> 1;
    wire [8:0] border_top = picture_top >= 9'd27 ? picture_top - 9'd27 : 9'd0;

    localparam [5:0] LEVEL_SYNC     = 6'd0;
    localparam [5:0] LEVEL_BLANK    = 6'd10;
    localparam [5:0] LEVEL_WHITE    = 6'd32;
    localparam [5:0] CHROMA_CENTER  = 6'd16;

    reg [3:0] sample_phase = 4'd0;
    reg [9:0] h_sample = 10'd0;
    reg [8:0] v_line = 9'd0;

    wire in_picture = (h_sample >= picture_left) &&
                      (h_sample < picture_right) &&
                      (v_line >= picture_top) &&
                      (v_line < picture_bottom);
    wire in_vdg_window = (h_sample >= border_left) &&
                         (h_sample < border_right) &&
                         (v_line >= border_top) &&
                         (v_line < V_TOTAL);
    wire [9:0] picture_x = high_resolution ? (h_sample-picture_left) :
                                              ((h_sample-picture_left) >> 1);
    wire [8:0] picture_y_full = v_line - picture_top;
    wire [7:0] picture_y = picture_y_full[7:0];
    assign framebuffer_addr = in_picture ? {picture_y, picture_x[7:0]} : 16'd0;
    assign source_x = picture_x;
    assign source_y = picture_y;
    assign source_valid = in_picture;
    assign prefetch_y = (v_line + 1'b1 >= picture_top) ?
                        (v_line + 1'b1 - picture_top) : 8'd0;
    assign prefetch_valid = (v_line + 1'b1 >= picture_top) &&
                            (v_line + 1'b1 < picture_bottom);

    // Six pre-equalizing half-lines, six broad-sync half-lines and six
    // post-equalizing half-lines, followed by conventional horizontal sync.
    wire sync_tip = (v_line < 9'd3) ?
        ((h_sample < 10'd32) ||
         ((h_sample >= 10'd429) && (h_sample < 10'd461))) :
        (v_line < 9'd6) ?
        ((h_sample < 10'd365) ||
         ((h_sample >= 10'd429) && (h_sample < 10'd794))) :
        (v_line < 9'd9) ?
        ((h_sample < 10'd32) ||
         ((h_sample >= 10'd429) && (h_sample < 10'd461))) :
        (h_sample < H_SYNC);

    wire in_burst = (v_line >= 9'd9) &&
                    (h_sample >= BURST_START) && (h_sample < BURST_END);

    // NTSC fSC is 455/2 times the line rate. At 135 MHz this accumulator
    // advances 91/3432 of an octant per clock and exactly half a carrier
    // cycle per 858-sample scan line.
    reg [8:0] carrier_fraction = 9'd0;
    reg [2:0] carrier_octant = 3'd0;

    function signed [5:0] chroma8;
        input [2:0] phase;
        input [1:0] strength;
        reg signed [5:0] peak;
        reg signed [5:0] diagonal;
        begin
            case (strength)
                2'd1: begin peak = 6'sd2; diagonal = 6'sd1; end
                2'd2: begin peak = 6'sd3; diagonal = 6'sd2; end
                2'd3: begin peak = 6'sd4; diagonal = 6'sd3; end
                default: begin peak = 6'sd0; diagonal = 6'sd0; end
            endcase
            case (phase)
                3'd0: chroma8 = 0;
                3'd1: chroma8 = diagonal;
                3'd2: chroma8 = peak;
                3'd3: chroma8 = diagonal;
                3'd4: chroma8 = 0;
                3'd5: chroma8 = -diagonal;
                3'd6: chroma8 = -peak;
                default: chroma8 = -diagonal;
            endcase
        end
    endfunction

    function signed [5:0] rgb_chroma;
        input signed [10:0] x4;
        input signed [10:0] y4;
        input signed [10:0] sum3;
        input signed [10:0] difference3;
        input [2:0] phase;
        reg signed [10:0] mix;
        begin
            case (phase)
                3'd0: mix = y4;
                3'd1: mix = sum3;
                3'd2: mix = x4;
                3'd3: mix = difference3;
                3'd4: mix = -y4;
                3'd5: mix = -sum3;
                3'd6: mix = -x4;
                default: mix = -difference3;
            endcase
            rgb_chroma = mix >>> 6;
        end
    endfunction

    function [5:0] add_level;
        input [5:0] base;
        input signed [5:0] delta;
        reg signed [6:0] result;
        begin
            result = $signed({1'b0,base}) + delta;
            if (result < 0) add_level = 6'd0;
            else if (result > 63) add_level = 6'd63;
            else add_level = result[5:0];
        end
    endfunction

    // The framebuffer stores RGB222. Expand each channel to six bits before
    // applying the same RGB-axis and luma conversion proven by NTSCVideo.
    reg [5:0] pixel_rgb = 6'd0;
    reg [5:0] border_meta = 6'd0;
    reg [5:0] border_sample = 6'd0;
    wire [5:0] fb_red   = {3{pixel_rgb[5:4]}};
    wire [5:0] fb_green = {3{pixel_rgb[3:2]}};
    wire [5:0] fb_blue  = {3{pixel_rgb[1:0]}};
    wire signed [7:0] fb_x_axis = $signed({1'b0,fb_blue}) -
                                          $signed({1'b0,fb_green});
    wire signed [7:0] fb_y_axis = $signed({1'b0,fb_red}) -
                                          $signed({1'b0,fb_green});
    wire [9:0] fb_luma_rb = ({4'd0,fb_red} << 2) +
                            ({4'd0,fb_red} << 1) +
                            ({4'd0,fb_blue} << 1) + 10'd32;
    wire [9:0] fb_luma_g = ({4'd0,fb_green} << 3) +
                           ({4'd0,fb_green} << 2);

    reg source_sync = 1'b1;
    reg source_burst = 1'b0;
    reg source_picture = 1'b0;
    reg source_active = 1'b0;
    reg [2:0] source_carrier = 3'd0;

    reg pixel_sync = 1'b1;
    reg pixel_burst = 1'b0;
    reg pixel_picture = 1'b0;
    reg [2:0] pixel_carrier = 3'd0;

    reg encoder_sync = 1'b1;
    reg encoder_burst = 1'b0;
    reg encoder_picture = 1'b0;
    reg [2:0] encoder_carrier = 3'd0;
    reg signed [7:0] encoder_x_axis = 8'sd0;
    reg signed [7:0] encoder_y_axis = 8'sd0;
    reg [9:0] encoder_luma_rb = 10'd0;
    reg [9:0] encoder_luma_g = 10'd0;

    wire [10:0] encoder_luma_sum = {1'b0,encoder_luma_rb} +
                                             {1'b0,encoder_luma_g};
    wire signed [10:0] encoder_x = encoder_x_axis;
    wire signed [10:0] encoder_y = encoder_y_axis;
    wire signed [10:0] encoder_sum = encoder_x + encoder_y;
    wire signed [10:0] encoder_difference = encoder_x - encoder_y;

    reg mod_sync = 1'b1;
    reg mod_burst = 1'b0;
    reg mod_picture = 1'b0;
    reg [2:0] mod_carrier = 3'd0;
    reg [5:0] mod_luma = LEVEL_BLANK;
    reg signed [10:0] mod_x4 = 11'sd0;
    reg signed [10:0] mod_y4 = 11'sd0;
    reg signed [10:0] mod_sum3 = 11'sd0;
    reg signed [10:0] mod_difference3 = 11'sd0;

    wire signed [5:0] mod_picture_chroma =
        rgb_chroma(mod_x4,mod_y4,mod_sum3,mod_difference3,mod_carrier);
    wire signed [5:0] mod_selected_chroma = mod_burst ?
        chroma8(mod_carrier + 3'd4,2'd3) : mod_picture_chroma;

    reg level_sync = 1'b1;
    reg level_burst = 1'b0;
    reg level_picture = 1'b0;
    reg [5:0] level_luma = LEVEL_BLANK;
    reg signed [5:0] level_chroma = 6'sd0;

    wire [5:0] luma_level = level_sync ? LEVEL_SYNC :
                            level_picture ? level_luma : LEVEL_BLANK;
    wire [5:0] chroma_level = (level_burst || level_picture) ?
        add_level(CHROMA_CENTER,level_chroma) : CHROMA_CENTER;
    wire [5:0] composite_level = level_sync ? LEVEL_SYNC :
        level_burst ? add_level(LEVEL_BLANK,level_chroma) :
        level_picture ? add_level(level_luma,level_chroma) : LEVEL_BLANK;

    reg [5:0] luma_level_135 = LEVEL_SYNC;
    reg [5:0] chroma_level_135 = CHROMA_CENTER;
    reg [5:0] cvbs_level_135 = LEVEL_SYNC;

    always @(posedge clk135) begin
        if (!reset_n) begin
            sample_phase <= 4'd0;
            height_meta <= 8'd192;
            picture_top <= 9'd44;
            picture_bottom <= 9'd236;
            h_sample <= 10'd0;
            v_line <= 9'd0;
            carrier_fraction <= 9'd0;
            carrier_octant <= 3'd0;
            source_sync <= 1'b1;
            source_burst <= 1'b0;
            source_picture <= 1'b0;
            source_active <= 1'b0;
            source_carrier <= 3'd0;
            pixel_sync <= 1'b1;
            pixel_burst <= 1'b0;
            pixel_picture <= 1'b0;
            pixel_carrier <= 3'd0;
            pixel_rgb <= 6'd0;
            border_meta <= 6'd0;
            border_sample <= 6'd0;
            encoder_sync <= 1'b1;
            encoder_burst <= 1'b0;
            encoder_picture <= 1'b0;
            encoder_carrier <= 3'd0;
            encoder_x_axis <= 8'sd0;
            encoder_y_axis <= 8'sd0;
            encoder_luma_rb <= 10'd0;
            encoder_luma_g <= 10'd0;
            mod_sync <= 1'b1;
            mod_burst <= 1'b0;
            mod_picture <= 1'b0;
            mod_carrier <= 3'd0;
            mod_luma <= LEVEL_BLANK;
            mod_x4 <= 11'sd0;
            mod_y4 <= 11'sd0;
            mod_sum3 <= 11'sd0;
            mod_difference3 <= 11'sd0;
            level_sync <= 1'b1;
            level_burst <= 1'b0;
            level_picture <= 1'b0;
            level_luma <= LEVEL_BLANK;
            level_chroma <= 6'sd0;
            luma_level_135 <= LEVEL_SYNC;
            chroma_level_135 <= CHROMA_CENTER;
            cvbs_level_135 <= LEVEL_SYNC;
        end else begin
            height_meta <= active_height;
            picture_top <= next_picture_top;
            picture_bottom <= next_picture_top + {1'b0,height_meta};
            luma_level_135 <= luma_level;
            chroma_level_135 <= chroma_level;
            cvbs_level_135 <= composite_level;

            source_sync <= sync_tip;
            source_burst <= in_burst;
            source_picture <= in_vdg_window;
            source_active <= in_picture;
            source_carrier <= carrier_octant;

            // Register the synchronous BSRAM output before RGB arithmetic.
            // source_* is delayed by the same stage to retain alignment.
            pixel_sync <= source_sync;
            pixel_burst <= source_burst;
            pixel_picture <= source_picture;
            pixel_carrier <= source_carrier;
            border_meta <= border_rgb;
            border_sample <= border_meta;
            pixel_rgb <= source_active ? framebuffer_data : border_sample;

            encoder_sync <= pixel_sync;
            encoder_burst <= pixel_burst;
            encoder_picture <= pixel_picture;
            encoder_carrier <= pixel_carrier;
            encoder_x_axis <= fb_x_axis;
            encoder_y_axis <= fb_y_axis;
            encoder_luma_rb <= fb_luma_rb;
            encoder_luma_g <= fb_luma_g;

            mod_sync <= encoder_sync;
            mod_burst <= encoder_burst;
            mod_picture <= encoder_picture;
            mod_carrier <= encoder_carrier;
            mod_luma <= LEVEL_BLANK + encoder_luma_sum[10:6];
            mod_x4 <= encoder_x <<< 2;
            mod_y4 <= encoder_y <<< 2;
            mod_sum3 <= (encoder_sum <<< 1) + encoder_sum;
            mod_difference3 <= (encoder_difference <<< 1) + encoder_difference;

            level_sync <= mod_sync;
            level_burst <= mod_burst;
            level_picture <= mod_picture;
            level_luma <= mod_luma > LEVEL_WHITE ? LEVEL_WHITE : mod_luma;
            level_chroma <= mod_selected_chroma;

            if (carrier_fraction >= 9'd338) begin
                carrier_fraction <= carrier_fraction - 9'd338;
                carrier_octant <= carrier_octant + 1'b1;
            end else begin
                carrier_fraction <= carrier_fraction + 9'd91;
            end

            if (sample_phase == 4'd9) begin
                sample_phase <= 4'd0;
                if (h_sample == H_TOTAL - 1'b1) begin
                    h_sample <= 10'd0;
                    if (v_line == V_TOTAL - 1'b1)
                        v_line <= 9'd0;
                    else
                        v_line <= v_line + 1'b1;
                end else begin
                    h_sample <= h_sample + 1'b1;
                end
            end else begin
                sample_phase <= sample_phase + 1'b1;
            end
        end
    end

    reg [5:0] luma_dac_level = LEVEL_SYNC;
    reg [5:0] chroma_dac_level = CHROMA_CENTER;
    reg [5:0] cvbs_dac_level = LEVEL_SYNC;
    // Keep the DAC output bit and five-bit error accumulator in one register.
    // This is the same first-order sigma-delta recurrence, and lets the carry
    // destination pack beside the adder instead of in a distant output flop.
    reg [5:0] luma_sigma = 6'd0;
    reg [5:0] chroma_sigma = 6'd0;
    reg [5:0] cvbs_sigma = 6'd0;
    reg luma_out_reg = 1'b0;
    reg chroma_out_reg = 1'b0;
    reg cvbs_out_reg = 1'b0;
    wire [5:0] luma_sum = {1'b0,luma_sigma[4:0]} + luma_dac_level;
    wire [5:0] chroma_sum = {1'b0,chroma_sigma[4:0]} + chroma_dac_level;
    wire [5:0] cvbs_sum = {1'b0,cvbs_sigma[4:0]} + cvbs_dac_level;
    assign luma_out = luma_out_reg;
    assign chroma_out = chroma_out_reg;
    assign cvbs_out = cvbs_out_reg;

    always @(posedge clk270) begin
        if (!reset_n) begin
            luma_dac_level <= LEVEL_SYNC;
            chroma_dac_level <= CHROMA_CENTER;
            cvbs_dac_level <= LEVEL_SYNC;
            luma_sigma <= 6'd0;
            chroma_sigma <= 6'd0;
            cvbs_sigma <= 6'd0;
            luma_out_reg <= 1'b0;
            chroma_out_reg <= 1'b0;
            cvbs_out_reg <= 1'b0;
        end else begin
            luma_dac_level <= luma_level_135;
            chroma_dac_level <= chroma_level_135;
            cvbs_dac_level <= cvbs_level_135;
            luma_sigma <= luma_sum;
            chroma_sigma <= chroma_sum;
            cvbs_sigma <= cvbs_sum;
            luma_out_reg <= luma_sigma[5];
            chroma_out_reg <= chroma_sigma[5];
            cvbs_out_reg <= cvbs_sigma[5];
        end
    end
endmodule
