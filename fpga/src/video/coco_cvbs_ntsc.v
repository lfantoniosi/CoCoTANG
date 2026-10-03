`timescale 1ns/1ps

// NTSC encoder derived from the hardware-calibrated NTSCVideo generator.
// clk135 is divided by ten to the 13.5 MHz BT.601 sample grid. clk270 drives
// three first-order, one-bit DACs. The composite levels are deliberately the
// same as the proven pin-51 2N3904/75-ohm circuit: sync=0, blank=10, white=32.
module coco_cvbs_ntsc #(
    parameter integer STREAMING_INPUT = 0,
    parameter integer CANONICAL_640_INPUT = 0,
    // Experimental PAL chroma over the existing CoCo/HDMI line timing.  This
    // selects only the analog subcarrier and PAL V/burst line alternation;
    // it must never change the CPU E/Q clocks or video scanline counters.
    parameter integer PAL_CHROMA_OUTPUT = 0,
    // Use a DAC-generated burst and align S-Video picture chroma with CVBS.
    // PAL always uses this; the NTSC experiment enables it independently.
    parameter integer MATCH_SVIDEO_TO_CVBS = 0,
    // Reuse the component DACs as RGB with negative composite sync on green.
    // The component HAT then needs no component changes: Y=G/SoG, Pb=B,
    // and Pr=R.
    parameter integer RGB_SOG_OUTPUT = 0,
    // Restart the RGB DAC accumulators with staggered phases, alternating
    // each channel by half a cycle on successive scanlines.
    parameter integer RGB_SCANLINE_PHASE_ALTERNATION = 0,
    // Diagnostic override for the separate Y output.  -1 selects normal
    // pixel luma; 0..63 forces a constant visible-aperture level while sync
    // and blanking remain valid.  Composite video is deliberately untouched.
    parameter integer FORCE_LUMA_LEVEL = -1
) (
    input  wire        clk135,
    input  wire        clk270,
    input  wire        reset_n,
    input  wire        video_50hz,
    input  wire        high_resolution,
    input  wire        compatibility_mode,
    input  wire [5:0]  framebuffer_data,
    input  wire [5:0]  border_rgb,
    input  wire [5:0]  row_border_rgb,
    input  wire [5:0]  row_right_border_rgb,
    input  wire        row_border_valid,
    input  wire [5:0]  vertical_left_border_rgb,
    input  wire [5:0]  vertical_right_border_rgb,
    input  wire        vertical_border_valid,
    input  wire [7:0]  active_height,
    output wire [15:0] framebuffer_addr,
    output wire [9:0]  source_x,
    output wire [7:0]  source_y,
    output wire        source_valid,
    output wire [7:0]  prefetch_y,
    output wire        prefetch_valid,
    output wire [8:0]  border_raster_y,
    output wire        luma_out,
    output wire        chroma_out,
    output wire        cvbs_out,
    output wire        component_pb_out,
    output wire        component_pr_out
);
    reg video_50hz_meta = 1'b0;
    reg video_50hz_sync = 1'b0;
    reg video_50hz_active = 1'b0;
    // The CoCo 3 scanline cache stores every row in a canonical 640-sample
    // representation. Compatibility video still occupies a 512-sample
    // analogue aperture, so its read coordinate must cover that entire row.
    localparam [9:0] H_SYNC         = 10'd64;
    // Calibrated burst window from the proven NTSCVideo implementation.
    localparam [9:0] BURST_START    = 10'd72;
    // Keep analogue scanout locked to the HDMI-mastered shared line cache.
    wire [9:0] h_total = video_50hz_active ? 10'd864 : 10'd858;
    wire [9:0] burst_end = video_50hz_active ? 10'd108 : 10'd106;
    // A framebuffer scales the 256 source pixels to 512 samples.  A live VDG
    // stream instead occupies its native 256/455 share of the 858-sample
    // line, or approximately 483 samples.
    wire picture_high_resolution = high_resolution && !compatibility_mode;
    wire [9:0] standard_shift = video_50hz_active ? 10'd3 : 10'd0;
    wire [9:0] picture_left  = (picture_high_resolution ? 10'd158 :
                               STREAMING_INPUT ? 10'd271 : 10'd222) +
                               standard_shift;
    wire [9:0] picture_right = (picture_high_resolution ? 10'd798 :
                               STREAMING_INPUT ? 10'd754 : 10'd734) +
                               standard_shift;
    // The analogue active aperture is 720 samples wide. Native GIME uses a
    // centered 640-sample body (40-sample borders); VDG uses a centered
    // 512-sample body (104-sample borders). Neither changes line timing.
    wire [9:0] border_left   = 10'd118 + standard_shift;
    wire [9:0] border_right  = 10'd838 + standard_shift;
    // Alternate complete 262- and 263-line fields.  Two fields are still
    // exactly 525 lines, but every scanline retains normal horizontal timing.
    // The CVBS cache is three rows deep to absorb the resulting +/- one-HDMI-
    // line phase movement.
    reg [7:0] height_meta = 8'd192;
    localparam [8:0] V_PHASE_OFFSET = 9'd17;
    reg [8:0] picture_top = 9'd43;
    reg [8:0] picture_bottom = 9'd235;
    // Explicit field parity: zero is the 262-line short field and one is the
    // 263-line long field.
    (* keep = "true" *) reg field_odd = 1'b0;
    // Center the picture in the analog field. The counter begins 17 lines
    // ahead by the same V_PHASE_OFFSET, so logical row zero is still consumed
    // when HDMI produces it for the shared two-line GIME cache.
    // The scanline renderer is HDMI-mastered.  Each analogue line spans two
    // HDMI rows, while v_line starts V_PHASE_OFFSET lines ahead.  Derive the
    // 50 Hz positions from that relationship so component consumes at most
    // one cached source row behind HDMI; the old +25 approximation lagged by
    // 3..6 rows and every graphics tag had already been evicted.
    wire [8:0] next_picture_top = video_50hz_active ?
        (height_meta == 8'd225 ? 9'd48 :
         height_meta == 8'd199 ? 9'd61 : 9'd65) :
        (height_meta == 8'd225 ? 9'd26 :
         height_meta == 8'd199 ? 9'd41 : 9'd43);
    // Compatibility/VDG video keeps the proven position. Native GIME video
    // is delayed by one line in BOTH fields, keeping its cache consumer
    // behind the HDMI producer without alternating the visible position.
    // picture_top already includes the native-GIME one-line offset. Keeping
    // that selection registered removes an adder from every vertical-window
    // compare and from the line-buffer request path.
    wire [8:0] field_picture_top = picture_top;
    // Updated beside picture_top below; use the registered boundary instead
    // of rebuilding this adder in every source-valid comparison.
    wire [8:0] field_picture_bottom = picture_bottom;
    // Map this analogue field onto the VDG raster that captured the
    // compatibility vertical-border colours. The analogue picture starts
    // 1..3 lines after the corresponding VDG picture, depending on mode.
    reg [8:0] compatibility_raster_lag = 9'd3;
    wire [8:0] border_top = field_picture_top >= 9'd27 ?
                            field_picture_top - 9'd27 : 9'd0;

    localparam [5:0] LEVEL_SYNC     = 6'd0;
    localparam [5:0] LEVEL_BLANK    = 6'd10;
    localparam [5:0] LEVEL_WHITE    = 6'd32;
    // Seven-bit levels used by the separate Y output.  The component-HAT
    // transistor stages are identical: sync-to-black uses 40 codes and the
    // picture uses the same 87-code excursion as the untrimmed RGB outputs.
    localparam [6:0] LUMA_SYNC_Q2  = 7'd0;
    localparam [6:0] LUMA_BLANK_Q2 = 7'd40;
    localparam [5:0] CHROMA_CENTER  = 6'd16;

    reg [3:0] sample_phase = 4'd0;
    reg [9:0] h_sample = 10'd0;
    reg [8:0] v_line = 9'd0;
    // The vertical-border RAM is read a stage later. Register its raster
    // address so the field-standard mux is not on the 135-MHz colour path.
    reg [8:0] border_raster_y_q = 9'd0;
    assign border_raster_y = border_raster_y_q;
    wire [8:0] field_last_line = video_50hz_active ?
        (field_odd ? 9'd312 : 9'd311) :
        (field_odd ? 9'd262 : 9'd261);
    wire [9:0] line_last_sample = h_total-1'b1;

    wire in_picture = (h_sample >= picture_left) &&
                      (h_sample < picture_right) &&
                      (v_line >= field_picture_top) &&
                      (v_line < field_picture_bottom);
    wire in_vdg_window = (h_sample >= border_left) &&
                         (h_sample < border_right) &&
                         (v_line >= border_top) &&
                         (v_line <= field_last_line);
    wire [9:0] picture_offset = h_sample-picture_left;
    wire [11:0] canonical_x_sum = {2'b0,picture_offset}+
                                   ({2'b0,picture_offset}<<2);
    wire [9:0] picture_x = picture_high_resolution ? picture_offset :
        (CANONICAL_640_INPUT && !STREAMING_INPUT) ? canonical_x_sum[11:2] :
                                                   (picture_offset>>1);
    wire [8:0] picture_y_full = v_line - field_picture_top;
    wire [7:0] picture_y = picture_y_full[7:0];
    assign framebuffer_addr = in_picture ? {picture_y, picture_x[7:0]} : 16'd0;
    assign source_x = picture_x;
    assign source_y = picture_y;
    assign source_valid = in_picture;
    assign prefetch_y = (v_line < field_picture_top) ? 8'd0 : picture_y+1'b1;
    assign prefetch_valid = (v_line < field_picture_top) ? 1'b1 :
                            ((v_line < field_picture_bottom) &&
                             (picture_y+1'b1 < height_meta));

    // Six pre-equalizing half-lines, six broad-sync half-lines and six
    // post-equalizing half-lines, followed by conventional horizontal sync.
    wire [9:0] h_half = h_total >> 1;
    wire sync_tip = (v_line < 9'd3) ?
        ((h_sample < 10'd32) ||
         ((h_sample >= h_half) && (h_sample < h_half+10'd32))) :
        (v_line < 9'd6) ?
        ((h_sample < h_half-10'd64) ||
         ((h_sample >= h_half) && (h_sample < h_total-10'd64))) :
        (v_line < 9'd9) ?
        ((h_sample < 10'd32) ||
         ((h_sample >= h_half) && (h_sample < h_half+10'd32))) :
        (h_sample < H_SYNC);

    wire in_burst = (v_line >= 9'd9) &&
                    (h_sample >= BURST_START) && (h_sample < burst_end);

    // NTSC fSC is 455/2 times the line rate. At 135 MHz this accumulator
    // advances 91/3432 of an octant per clock and exactly half a carrier
    // cycle per 858-sample scan line.  The optional PAL DDS is clocked by
    // the SAME 135 MHz PLL output: 2203964/2^26 * 135 MHz = 4,433,619.08 Hz.
    reg [8:0] carrier_fraction = 9'd0;
    reg [2:0] carrier_octant = 3'd0;
    reg [25:0] pal_carrier_acc = 26'd0;
    reg pal_v_invert = 1'b0;
    wire [2:0] carrier_phase = PAL_CHROMA_OUTPUT ?
                               pal_carrier_acc[25:23] : carrier_octant;

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

    function [5:0] add_level_wide;
        input [5:0] base;
        input signed [7:0] delta;
        reg signed [8:0] result;
        begin
            result = $signed({1'b0,base}) + delta;
            if (result < 0) add_level_wide = 6'd0;
            else if (result > 63) add_level_wide = 6'd63;
            else add_level_wide = result[5:0];
        end
    endfunction

    // Seven-bit component-video level with two fractional matrix bits.
    // Midpoint 64/128 is electrically identical to the former 16/32, while
    // retaining coefficient precision that was previously truncated away.
    function [6:0] add_component_level;
        input signed [10:0] delta;
        reg signed [11:0] result;
        begin
            result = 12'sd64 + delta;
            if (result < 0) add_component_level = 7'd0;
            else if (result > 127) add_component_level = 7'd127;
            else add_component_level = result[6:0];
        end
    endfunction

    // RGB monitors expect approximately 0.7 V of picture above black.  CRT
    // calibration showed different high-level response in each analogue
    // channel, so retain independent red and blue transfer curves.
    function [6:0] rgb_red_picture_level;
        input [1:0] channel;
        begin
            case (channel)
                2'd0: rgb_red_picture_level = 7'd0;
                2'd1: rgb_red_picture_level = 7'd42;
                2'd2: rgb_red_picture_level = 7'd74;
                default: rgb_red_picture_level = 7'd96;
            endcase
        end
    endfunction

    function [6:0] rgb_blue_picture_level;
        input [1:0] channel;
        begin
            case (channel)
                2'd0: rgb_blue_picture_level = 7'd0;
                2'd1: rgb_blue_picture_level = 7'd42;
                2'd2: rgb_blue_picture_level = 7'd74;
                default: rgb_blue_picture_level = 7'd96;
            endcase
        end
    endfunction

    // Green carries the sync pedestal and has higher measured analogue gain
    // than red/blue.  With red/blue at full scale, measured CRT calibration
    // brackets neutral green between excursions 44 (magenta cast) and 79
    // (green cast); use the midpoint while retaining maximum brightness.
    function [6:0] rgb_green_picture_level;
        input [1:0] channel;
        begin
            case (channel)
                2'd0: rgb_green_picture_level = 7'd0;
                2'd1: rgb_green_picture_level = 7'd18;
                2'd2: rgb_green_picture_level = 7'd40;
                default: rgb_green_picture_level = 7'd62;
            endcase
        end
    endfunction

    // The framebuffer stores RGB222. Expand each channel to six bits before
    // applying the same RGB-axis and luma conversion proven by NTSCVideo.
    reg [5:0] pixel_rgb = 6'd0;
    reg [5:0] encoder_rgb = 6'd0;
    reg [5:0] mod_rgb = 6'd0;
    reg [5:0] border_meta = 6'd0;
    reg [5:0] border_row_current = 6'd0;
    reg [5:0] border_row_delay1 = 6'd0;
    reg [5:0] border_row_delay2 = 6'd0;
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
    reg source_body = 1'b0;
    reg [2:0] source_carrier = 3'd0;
    reg source_sample_tick = 1'b0;

    reg pixel_sync = 1'b1;
    reg pixel_burst = 1'b0;
    reg pixel_picture = 1'b0;
    reg [2:0] pixel_carrier = 3'd0;
    reg pixel_sample_tick = 1'b0;

    reg encoder_sync = 1'b1;
    reg encoder_burst = 1'b0;
    reg encoder_picture = 1'b0;
    reg [2:0] encoder_carrier = 3'd0;
    reg encoder_sample_tick = 1'b0;
    reg signed [7:0] encoder_x_axis = 8'sd0;
    reg signed [7:0] encoder_y_axis = 8'sd0;
    reg signed [7:0] chroma_x_previous = 8'sd0;
    reg signed [7:0] chroma_y_previous = 8'sd0;
    reg signed [7:0] chroma_x_filtered = 8'sd0;
    reg signed [7:0] chroma_y_filtered = 8'sd0;
    reg [9:0] encoder_luma_rb = 10'd0;
    reg [9:0] encoder_luma_g = 10'd0;

    wire [10:0] encoder_luma_sum = {1'b0,encoder_luma_rb} +
                                             {1'b0,encoder_luma_g};
    // encoder_luma_sum includes the 32-count rounding bias needed by the
    // older six-bit composite path.  Remove it for separate Y, then expand
    // the nominal 0..78 result to 0..87.  The shift-and-add approximation is
    // exact at both endpoints and avoids a divider in the video pipeline.
    wire [10:0] encoder_luma_linear = encoder_luma_sum - 11'd32;
    wire [6:0] encoder_y_picture_excursion =
        encoder_luma_linear[10:4] + encoder_luma_linear[10:7];
    wire signed [10:0] encoder_x = encoder_x_axis;
    wire signed [10:0] encoder_y = encoder_y_axis;
    wire signed [10:0] encoder_sum = encoder_x + encoder_y;
    wire signed [10:0] encoder_difference = encoder_x - encoder_y;

    // Two-tap horizontal chroma filter.  Update once per 13.5-MHz
    // sample, not once per clk135 cycle, because each source sample is held
    // for ten clocks.  Luma remains unfiltered, so text detail is unchanged.
    wire signed [8:0] chroma_x_pair =
        $signed(encoder_x_axis) + $signed(chroma_x_previous);
    wire signed [8:0] chroma_y_pair =
        $signed(encoder_y_axis) + $signed(chroma_y_previous);
    wire signed [7:0] chroma_x_average = chroma_x_pair >>> 1;
    wire signed [7:0] chroma_y_average = chroma_y_pair >>> 1;
    // Consume the registered average in the existing modulator stage.  This
    // avoids duplicating the expensive chroma matrix, which otherwise moves
    // unrelated scanline logic enough to disturb timing on the nearly-full
    // device.  The cost is one 13.5-MHz chroma sample of horizontal delay.
    wire signed [10:0] filtered_x = chroma_x_filtered;
    wire signed [10:0] filtered_y = chroma_y_filtered;
    wire signed [10:0] filtered_sum = filtered_x + filtered_y;
    wire signed [10:0] filtered_difference = filtered_x - filtered_y;

    reg mod_sync = 1'b1;
    reg mod_burst = 1'b0;
    reg mod_picture = 1'b0;
    reg [2:0] mod_carrier = 3'd0;
    reg [5:0] mod_luma = LEVEL_BLANK;
    reg [6:0] mod_luma_q2 = LUMA_BLANK_Q2;
    reg signed [10:0] mod_x4 = 11'sd0;
    reg signed [10:0] mod_y4 = 11'sd0;
    reg signed [10:0] mod_sum3 = 11'sd0;
    reg signed [10:0] mod_difference3 = 11'sd0;
    reg signed [7:0] mod_component_x = 8'sd0;
    reg signed [7:0] mod_component_y = 8'sd0;

    // PAL reverses the V/R-Y contribution on successive physical lines.
    // The existing X/Y matrix uses Y as its V-like axis.  Reversing Y also
    // swaps the X+Y and X-Y diagonal terms, without touching baseband Y,
    // component Pb/Pr, HDMI, or any CoCo raster timing.
    wire signed [10:0] pal_picture_y4 =
        (PAL_CHROMA_OUTPUT && pal_v_invert) ? -mod_y4 : mod_y4;
    wire signed [10:0] pal_picture_sum3 =
        (PAL_CHROMA_OUTPUT && pal_v_invert) ? mod_difference3 : mod_sum3;
    wire signed [10:0] pal_picture_difference3 =
        (PAL_CHROMA_OUTPUT && pal_v_invert) ? mod_sum3 : mod_difference3;
    wire signed [5:0] mod_picture_chroma =
        rgb_chroma(mod_x4,pal_picture_y4,pal_picture_sum3,
                   pal_picture_difference3,mod_carrier);
    wire signed [5:0] mod_svideo_picture_chroma =
        (PAL_CHROMA_OUTPUT || MATCH_SVIDEO_TO_CVBS) ? mod_picture_chroma :
        rgb_chroma(mod_x4,pal_picture_y4,pal_picture_sum3,
                   pal_picture_difference3,mod_carrier + 3'd1);
    // PAL burst swings +/-45 degrees about the negative U axis.  The two
    // octant offsets correspond to -U+V and -U-V respectively; NTSC keeps
    // its original 180-degree burst unchanged.
    wire [2:0] burst_phase_offset = PAL_CHROMA_OUTPUT ?
        (pal_v_invert ? 3'd5 : 3'd3) : 3'd4;
    wire signed [5:0] mod_burst_chroma =
        chroma8(mod_carrier + burst_phase_offset,2'd3);
    wire signed [5:0] mod_selected_chroma = mod_burst ?
        mod_burst_chroma : mod_picture_chroma;

    reg level_sync = 1'b1;
    reg level_burst = 1'b0;
    reg level_picture = 1'b0;
    reg [2:0] level_carrier = 3'd0;
    reg [5:0] level_luma = LEVEL_BLANK;
    reg [6:0] level_luma_q2 = LUMA_BLANK_Q2;
    reg signed [5:0] level_chroma = 6'sd0;
    reg signed [5:0] level_svideo_chroma = 6'sd0;

    // SMPTE-style colour difference from the same RGB/luma coefficients as
    // the composite encoder.  With x=B-G and y=R-G:
    //   Pb ~= (0.500*x - 0.169*y) / 2
    //   Pr ~= (0.500*y - 0.081*x) / 2
    // Q2 arithmetic preserves two fractional bits.  The resulting bipolar
    // excursion is centred at 64 in a 0..127 DAC, which has the same analogue
    // amplitude as the former midpoint-16, modulo-32 representation.
    // Keep the constant-coefficient products at their natural width. The
    // former 16-bit expressions produced unnecessarily long carry chains and
    // disturbed placement of the unrelated 108-MHz CPU/SDRAM request path.
    wire signed [10:0] component_pb_y =
        ($signed(mod_component_y) <<< 3) +
        ($signed(mod_component_y) <<< 1) + $signed(mod_component_y);
    wire signed [9:0] component_pr_x =
        ($signed(mod_component_x) <<< 2) + $signed(mod_component_x);
    wire signed [10:0] component_pb_delta_q2 =
        $signed(mod_component_x) - (component_pb_y >>> 5);
    wire signed [10:0] component_pr_delta_q2 =
        $signed(mod_component_y) - (component_pr_x >>> 5);

    // The legacy NTSC S-Video path uses a fixed-polarity square-wave burst,
    // with inverted picture chroma advanced by one octant. The matched path
    // uses the same DAC phase for S-Video burst and picture on either carrier.
    // Retain the x4 picture gain required by the Q8 emitter follower.
    wire signed [7:0] svideo_chroma_extended = level_svideo_chroma;
    wire signed [7:0] svideo_picture_chroma =
        (PAL_CHROMA_OUTPUT || MATCH_SVIDEO_TO_CVBS) ?
        (svideo_chroma_extended <<< 2) : -(svideo_chroma_extended <<< 2);

    wire [6:0] selected_luma_level_q2 = (FORCE_LUMA_LEVEL >= 0) ?
                                        {FORCE_LUMA_LEVEL[4:0],2'b00} :
                                        level_luma_q2;
    wire [6:0] rgb_red_level = level_picture ?
                           rgb_red_picture_level(mod_rgb[5:4]) : 7'd0;
    wire [6:0] rgb_blue_level = level_picture ?
                          rgb_blue_picture_level(mod_rgb[1:0]) : 7'd0;
    wire [6:0] rgb_green_level = level_sync ? 7'd0 :
        LUMA_BLANK_Q2 + (level_picture ?
                         rgb_green_picture_level(mod_rgb[3:2]) : 7'd0);
    wire [6:0] luma_level = RGB_SOG_OUTPUT ? rgb_green_level :
                            level_sync ? LUMA_SYNC_Q2 :
                            level_picture ? selected_luma_level_q2 :
                                            LUMA_BLANK_Q2;
    // The receiver derives hue and saturation from the picture-to-burst ratio.
    wire [5:0] chroma_level = level_picture ?
        add_level_wide(CHROMA_CENTER,svideo_picture_chroma) :
        level_burst ? add_level(CHROMA_CENTER,level_chroma) :
        CHROMA_CENTER;
    wire [5:0] composite_level = level_sync ? LEVEL_SYNC :
        level_burst ? add_level(LEVEL_BLANK,level_chroma) :
        level_picture ? add_level(level_luma,level_chroma) : LEVEL_BLANK;
    wire [6:0] component_pb_level = RGB_SOG_OUTPUT ? rgb_blue_level :
        level_picture ? add_component_level(component_pb_delta_q2) : 7'd64;
    wire [6:0] component_pr_level = RGB_SOG_OUTPUT ? rgb_red_level :
        level_picture ? add_component_level(component_pr_delta_q2) : 7'd64;

    reg [6:0] luma_level_135 = LUMA_SYNC_Q2;
    reg [5:0] chroma_level_135 = CHROMA_CENTER;
    reg [5:0] cvbs_level_135 = LEVEL_SYNC;
    reg [6:0] component_pb_level_135 = 7'd64;
    reg [6:0] component_pr_level_135 = 7'd64;
    reg chroma_burst_135 = 1'b0;
    reg chroma_burst_bit_135 = 1'b0;

    always @(posedge clk135) begin
        if (!reset_n) begin
            sample_phase <= 4'd0;
            height_meta <= 8'd192;
            picture_top <= 9'd43;
            picture_bottom <= 9'd235;
            video_50hz_meta <= 1'b0;
            video_50hz_sync <= 1'b0;
            video_50hz_active <= 1'b0;
            border_raster_y_q <= 9'd0;
            // Offset the progressive analog raster without changing the time
            // at which logical row zero meets HDMI's shared line cache.
            h_sample <= 10'd0;
            v_line <= V_PHASE_OFFSET;
            field_odd <= 1'b0;
            carrier_fraction <= 9'd0;
            carrier_octant <= 3'd0;
            pal_carrier_acc <= 26'd0;
            pal_v_invert <= 1'b0;
            source_sync <= 1'b1;
            source_burst <= 1'b0;
            source_picture <= 1'b0;
            source_active <= 1'b0;
            source_body <= 1'b0;
            source_carrier <= 3'd0;
            source_sample_tick <= 1'b0;
            pixel_sync <= 1'b1;
            pixel_burst <= 1'b0;
            pixel_picture <= 1'b0;
            pixel_carrier <= 3'd0;
            pixel_sample_tick <= 1'b0;
            pixel_rgb <= 6'd0;
            encoder_rgb <= 6'd0;
            mod_rgb <= 6'd0;
            border_meta <= 6'd0;
            border_row_current <= 6'd0;
            border_row_delay1 <= 6'd0;
            border_row_delay2 <= 6'd0;
            border_sample <= 6'd0;
            encoder_sync <= 1'b1;
            encoder_burst <= 1'b0;
            encoder_picture <= 1'b0;
            encoder_carrier <= 3'd0;
            encoder_sample_tick <= 1'b0;
            encoder_x_axis <= 8'sd0;
            encoder_y_axis <= 8'sd0;
            chroma_x_previous <= 8'sd0;
            chroma_y_previous <= 8'sd0;
            chroma_x_filtered <= 8'sd0;
            chroma_y_filtered <= 8'sd0;
            encoder_luma_rb <= 10'd0;
            encoder_luma_g <= 10'd0;
            mod_sync <= 1'b1;
            mod_burst <= 1'b0;
            mod_picture <= 1'b0;
            mod_carrier <= 3'd0;
            mod_luma <= LEVEL_BLANK;
            mod_luma_q2 <= LUMA_BLANK_Q2;
            mod_x4 <= 11'sd0;
            mod_y4 <= 11'sd0;
            mod_sum3 <= 11'sd0;
            mod_difference3 <= 11'sd0;
            mod_component_x <= 8'sd0;
            mod_component_y <= 8'sd0;
            level_sync <= 1'b1;
            level_burst <= 1'b0;
            level_picture <= 1'b0;
            level_carrier <= 3'd0;
            level_luma <= LEVEL_BLANK;
            level_luma_q2 <= LUMA_BLANK_Q2;
            level_chroma <= 6'sd0;
            level_svideo_chroma <= 6'sd0;
            luma_level_135 <= LUMA_SYNC_Q2;
            chroma_level_135 <= CHROMA_CENTER;
            cvbs_level_135 <= LEVEL_SYNC;
            component_pb_level_135 <= 7'd64;
            component_pr_level_135 <= 7'd64;
            chroma_burst_135 <= 1'b0;
            chroma_burst_bit_135 <= 1'b0;
        end else begin
            video_50hz_meta <= video_50hz;
            video_50hz_sync <= video_50hz_meta;
            if (video_50hz_sync != video_50hz_active)
                video_50hz_active <= video_50hz_sync;
            height_meta <= active_height;
            compatibility_raster_lag <= video_50hz_active ? 9'd1 :
                (height_meta == 8'd192 ? 9'd3 : 9'd2);
            border_raster_y_q <= v_line >= compatibility_raster_lag ?
                                 v_line-compatibility_raster_lag : 9'd0;
            picture_top <= next_picture_top +
                           (!compatibility_mode ? 9'd1 : 9'd0);
            picture_bottom <= next_picture_top +
                              (!compatibility_mode ? 9'd1 : 9'd0) +
                              {1'b0,height_meta};
            luma_level_135 <= luma_level;
            chroma_level_135 <= chroma_level;
            cvbs_level_135 <= composite_level;
            component_pb_level_135 <= component_pb_level;
            component_pr_level_135 <= component_pr_level;
            chroma_burst_135 <= level_burst;
            chroma_burst_bit_135 <= ~level_carrier[2];

            // Keep one immutable border colour for the complete analogue
            // scanline. The cached picture emerges two physical scanlines
            // behind the live GIME border register, so carry the captured
            // border through the same two-line phase before displaying it.
            border_meta <= border_rgb;
            if(h_sample==0 && sample_phase==0) begin
                border_row_delay2 <= border_row_delay1;
                border_row_delay1 <= border_row_current;
                border_row_current <= border_meta;
            end

            source_sync <= sync_tip;
            source_burst <= in_burst;
            source_picture <= in_vdg_window;
            source_active <= in_picture;
            source_body <= (v_line >= field_picture_top) &&
                           (v_line < field_picture_bottom);
            source_carrier <= carrier_phase;
            source_sample_tick <= (sample_phase == 4'd0);

            // Register the synchronous BSRAM output before RGB arithmetic.
            // source_* is delayed by the same stage to retain alignment.
            pixel_sync <= source_sync;
            pixel_burst <= source_burst;
            pixel_picture <= source_picture;
            pixel_carrier <= source_carrier;
            pixel_sample_tick <= source_sample_tick;
            border_sample <= source_body && row_border_valid ?
                (h_sample < picture_right ? row_border_rgb : row_right_border_rgb) :
                compatibility_mode && !source_body && vertical_border_valid ?
                (h_sample < picture_left ? vertical_left_border_rgb :
                                           vertical_right_border_rgb) :
                border_row_delay2;
            pixel_rgb <= source_active ? framebuffer_data : border_sample;

            encoder_sync <= pixel_sync;
            encoder_burst <= pixel_burst;
            encoder_picture <= pixel_picture;
            encoder_carrier <= pixel_carrier;
            encoder_sample_tick <= pixel_sample_tick;
            encoder_rgb <= pixel_rgb;
            encoder_x_axis <= fb_x_axis;
            encoder_y_axis <= fb_y_axis;
            encoder_luma_rb <= fb_luma_rb;
            encoder_luma_g <= fb_luma_g;

            if (encoder_sample_tick) begin
                chroma_x_previous <= encoder_x_axis;
                chroma_y_previous <= encoder_y_axis;
                chroma_x_filtered <= chroma_x_average;
                chroma_y_filtered <= chroma_y_average;
            end

            mod_sync <= encoder_sync;
            mod_burst <= encoder_burst;
            mod_picture <= encoder_picture;
            mod_carrier <= encoder_carrier;
            mod_rgb <= encoder_rgb;
            mod_luma <= LEVEL_BLANK + encoder_luma_sum[10:6];
            mod_luma_q2 <= LUMA_BLANK_Q2 + encoder_y_picture_excursion;
            mod_x4 <= filtered_x <<< 2;
            mod_y4 <= filtered_y <<< 2;
            mod_sum3 <= (filtered_sum <<< 1) + filtered_sum;
            mod_difference3 <=
                (filtered_difference <<< 1) + filtered_difference;
            // Component video keeps the full colour-difference bandwidth;
            // the composite-only two-tap chroma filter is intentionally not
            // inserted in these paths.
            mod_component_x <= encoder_x_axis;
            mod_component_y <= encoder_y_axis;

            level_sync <= mod_sync;
            level_burst <= mod_burst;
            level_picture <= mod_picture;
            level_carrier <= mod_carrier;
            level_luma <= mod_luma > LEVEL_WHITE ? LEVEL_WHITE : mod_luma;
            level_luma_q2 <= mod_luma_q2;
            level_chroma <= mod_selected_chroma;
            level_svideo_chroma <= mod_svideo_picture_chroma;

            if (carrier_fraction >= 9'd338) begin
                carrier_fraction <= carrier_fraction - 9'd338;
                carrier_octant <= carrier_octant + 1'b1;
            end else begin
                carrier_fraction <= carrier_fraction + 9'd91;
            end
            pal_carrier_acc <= pal_carrier_acc + 26'd2203964;

            // The input is HDMI's frame-committed standard.  Re-establish
            // the intentional 17-line phase lead exactly when that standard
            // changes; otherwise HDMI enters 576p at frame wrap while the
            // analogue counter changes limits mid-field and requests cache
            // rows tens of lines away from the producer.
            if (video_50hz_sync != video_50hz_active) begin
                sample_phase <= 4'd0;
                h_sample <= 10'd0;
                v_line <= V_PHASE_OFFSET;
                field_odd <= 1'b0;
            end else if(sample_phase == 4'd9) begin
                sample_phase <= 4'd0;
                if (h_sample == line_last_sample) begin
                    h_sample <= 10'd0;
                    pal_v_invert <= ~pal_v_invert;
                    if (v_line == field_last_line) begin
                        v_line <= 9'd0;
                        field_odd <= ~field_odd;
                    end else
                        v_line <= v_line + 1'b1;
                end else begin
                    h_sample <= h_sample + 1'b1;
                end
            end else begin
                sample_phase <= sample_phase + 1'b1;
            end
        end
    end

    reg [6:0] luma_dac_level = LUMA_SYNC_Q2;
    reg [5:0] chroma_dac_level = CHROMA_CENTER;
    reg [5:0] cvbs_dac_level = LEVEL_SYNC;
    reg [6:0] component_pb_dac_level = 7'd64;
    reg [6:0] component_pr_dac_level = 7'd64;
    // Keep the DAC output bit and five-bit error accumulator in one register.
    // This is the same first-order sigma-delta recurrence, and lets the carry
    // destination pack beside the adder instead of in a distant output flop.
    reg [7:0] luma_sigma = 8'd0;
    reg [5:0] chroma_sigma = 6'd0;
    reg [5:0] cvbs_sigma = 6'd0;
    reg [7:0] component_pb_sigma = 8'd0;
    reg [7:0] component_pr_sigma = 8'd0;
    reg luma_out_reg = 1'b0;
    reg chroma_out_reg = 1'b0;
    reg cvbs_out_reg = 1'b0;
    reg component_pb_out_reg = 1'b0;
    reg component_pr_out_reg = 1'b0;
    // Decorrelate the luma pulse-density pattern between scanlines.  A fixed
    // accumulator phase (or a two-line 0/16 alternation) produces coherent
    // vertical beat patterns after the analogue reconstruction filter.  This
    // maximal-length x^16+x^14+x^13+x^11+1 sequence has a 65535-line period;
    // selecting five bits changes phase only, never the requested DC level.
    reg [15:0] luma_phase_lfsr = 16'h1ace;
    wire luma_phase_feedback = luma_phase_lfsr[15] ^
                               luma_phase_lfsr[13] ^
                               luma_phase_lfsr[12] ^
                               luma_phase_lfsr[10];
    reg chroma_burst_270 = 1'b0;
    reg chroma_burst_bit_270 = 1'b0;
    reg [2:0] burst_shape_phase = 3'd0;
    // Pipeline the luma zero comparison before using it to reset the 270-MHz
    // sigma-delta accumulators.  The former direct seven-bit comparison fed
    // the accumulator mux in the same cycle and was the critical setup path.
    // Edge detection delays the event by one 270-MHz clock, still safely
    // inside the horizontal sync tip.
    reg luma_sync_270 = 1'b1;
    reg luma_sync_270_d = 1'b1;
    wire dac_line_start = luma_sync_270 && !luma_sync_270_d;
    reg rgb_line_phase = 1'b0;
    wire [7:0] rgb_green_seed = rgb_line_phase ? 8'd64 : 8'd0;
    wire [7:0] rgb_blue_seed = rgb_line_phase ? 8'd106 : 8'd42;
    wire [7:0] rgb_red_seed = rgb_line_phase ? 8'd21 : 8'd85;
    wire [7:0] luma_sum = {1'b0,luma_sigma[6:0]} +
                          {1'b0,luma_dac_level};
    wire [5:0] chroma_sum = {1'b0,chroma_sigma[4:0]} + chroma_dac_level;
    wire [5:0] cvbs_sum = {1'b0,cvbs_sigma[4:0]} + cvbs_dac_level;
    wire [7:0] component_pb_sum =
        {1'b0,component_pb_sigma[6:0]} +
        {1'b0,component_pb_dac_level};
    wire [7:0] component_pr_sum =
        {1'b0,component_pr_sigma[6:0]} +
        {1'b0,component_pr_dac_level};

    assign luma_out = luma_out_reg;
    assign chroma_out = chroma_out_reg;
    assign cvbs_out = cvbs_out_reg;
    assign component_pb_out = component_pb_out_reg;
    assign component_pr_out = component_pr_out_reg;

    // Preserve a coherent fSC reference through the transistor output stage,
    // but attenuate its fundamental without an analogue DAC.  Two of every
    // eight 270-MHz samples invert the carrier.  The monitor rejects those
    // high-frequency products while the wanted 3.58-MHz carrier is 1/2 of
    // the full-swing diagnostic burst.  This is the lowest level that the
    // tested CRT reliably reacquires after switching inputs.
    wire burst_shape_invert = (burst_shape_phase == 3'd1) ||
                              (burst_shape_phase == 3'd5);
    wire shaped_burst_bit = chroma_burst_bit_270 ^ burst_shape_invert;

    always @(posedge clk270) begin
        if (!reset_n) begin
            luma_dac_level <= LUMA_SYNC_Q2;
            chroma_dac_level <= CHROMA_CENTER;
            cvbs_dac_level <= LEVEL_SYNC;
            component_pb_dac_level <= 7'd64;
            component_pr_dac_level <= 7'd64;
            luma_sigma <= 8'd64;
            chroma_sigma <= 6'd0;
            cvbs_sigma <= 6'd16;
            component_pb_sigma <= 8'd0;
            component_pr_sigma <= 8'd0;
            luma_out_reg <= 1'b0;
            chroma_out_reg <= 1'b0;
            cvbs_out_reg <= 1'b0;
            component_pb_out_reg <= 1'b0;
            component_pr_out_reg <= 1'b0;
            luma_phase_lfsr <= 16'h1ace;
            luma_sync_270 <= 1'b1;
            luma_sync_270_d <= 1'b1;
            rgb_line_phase <= 1'b0;
            chroma_burst_270 <= 1'b0;
            chroma_burst_bit_270 <= 1'b0;
            burst_shape_phase <= 3'd0;
        end else begin
            luma_dac_level <= luma_level_135;
            chroma_dac_level <= chroma_level_135;
            cvbs_dac_level <= cvbs_level_135;
            component_pb_dac_level <= component_pb_level_135;
            component_pr_dac_level <= component_pr_level_135;
            luma_sync_270 <= (luma_level_135 == LUMA_SYNC_Q2);
            luma_sync_270_d <= luma_sync_270;
            if (dac_line_start && RGB_SOG_OUTPUT &&
                RGB_SCANLINE_PHASE_ALTERNATION)
                rgb_line_phase <= ~rgb_line_phase;
            chroma_burst_270 <= chroma_burst_135;
            chroma_burst_bit_270 <= chroma_burst_bit_135;
            burst_shape_phase <= burst_shape_phase + 1'b1;
            // Phase-lock only the signals containing luma.  The event lands
            // in the horizontal sync tip, so the accumulator transient is
            // invisible; Pb/Pr and S-Video chroma retain continuous phase.
            luma_sigma <= dac_line_start ?
                          ((RGB_SOG_OUTPUT && RGB_SCANLINE_PHASE_ALTERNATION) ?
                           rgb_green_seed : {1'b0,luma_phase_lfsr[6:0]}) :
                          luma_sum;
            chroma_sigma <= chroma_sum;
            cvbs_sigma <= dac_line_start ?
                          {1'b0,luma_phase_lfsr[4:0]} : cvbs_sum;
            // Keep colour-difference error continuous in component mode.
            // RGB mode restarts both channels during sync for the scanline
            // phase experiment, before either channel has picture output.
            component_pb_sigma <= (dac_line_start && RGB_SOG_OUTPUT &&
                                   RGB_SCANLINE_PHASE_ALTERNATION) ?
                                  rgb_blue_seed : component_pb_sum;
            component_pr_sigma <= (dac_line_start && RGB_SOG_OUTPUT &&
                                   RGB_SCANLINE_PHASE_ALTERNATION) ?
                                  rgb_red_seed : component_pr_sum;
            if (dac_line_start)
                luma_phase_lfsr <= {luma_phase_lfsr[14:0],
                                    luma_phase_feedback};
            luma_out_reg <= luma_sigma[7];
            // Keep the legacy shaper only for the original NTSC S-Video path.
            chroma_out_reg <= (!PAL_CHROMA_OUTPUT &&
                               !MATCH_SVIDEO_TO_CVBS && chroma_burst_270) ?
                              shaped_burst_bit : chroma_sigma[5];
            cvbs_out_reg <= cvbs_sigma[5];
            component_pb_out_reg <= component_pb_sigma[7];
            component_pr_out_reg <= component_pr_sigma[7];
        end
    end
endmodule
