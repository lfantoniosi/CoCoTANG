`timescale 1ns/1ps

// NTSC encoder derived from the hardware-calibrated NTSCVideo generator.
// The line raster uses a 13.5 MHz BT.601 grid; RGB can advance source dots
// at the original CoCo rate independently of that grid. clk270 drives
// three first-order, one-bit DACs. The composite levels are deliberately the
// same as the proven pin-51 2N3904/75-ohm circuit: sync=0, blank=10, white=32.
module coco_cvbs_ntsc #(
    // Opt in only for composite builds; RGB/component retain the original
    // continuous carrier and burst paths.
    parameter integer CVBS_FIELD_PHASE_ALIGN = 0,
    parameter integer CVBS_INCREMENTAL_DOTS = 0,
    parameter integer CVBS_FAST_PREFETCH = 0,
    parameter integer STREAMING_INPUT = 0,
    parameter integer CANONICAL_640_INPUT = 0,
    // Experimental PAL chroma over the existing CoCo/HDMI line timing.  This
    // selects only the analog subcarrier and PAL V/burst line alternation;
    // it must never change the CPU E/Q clocks or video scanline counters.
    parameter integer PAL_CHROMA_OUTPUT = 0,
    // S-Video picture chroma and burst use the same DAC phase as CVBS.
    // Reuse the component DACs as RGB with negative composite sync on green.
    // The component HAT then needs no component changes: Y=G/SoG, Pb=B,
    // and Pr=R.
    parameter integer RGB_SOG_OUTPUT = 0,
    // Match NTSC CoCo RGB dot timing while retaining the shared line raster.
    // Set to zero to restore the former BT.601-width RGB aperture.
    parameter integer RGB_COCO_APERTURE = 1,
    // Restart the RGB DAC accumulators with staggered phases, alternating
    // each channel by half a cycle on successive scanlines.
    parameter integer RGB_SCANLINE_PHASE_ALTERNATION = 0,
    // Stagger the baseband Pb/Pr DACs as in RGB. At neutral grey both
    // request midpoint 64; identical phases switch both pins in the same direction.
    parameter integer COMPONENT_DAC_PHASE_STAGGER = 0,
    // Apply the RGB green DAC's alternating phase to separate Y, including
    // component mode where the CVBS/S-Video phase option is disabled.
    parameter integer LUMA_SCANLINE_PHASE_ALTERNATION = 0,
    // RGB's calibrated levels are all even. Match that DAC precision on Y
    // to avoid odd-code 128-clock pulse trains (2.109 MHz at clk270), keeping
    // the longest constant-level train to 64 clocks as in RGB. Drops one LSB.
    parameter integer LUMA_DAC_EVEN_LEVELS = 0,
    // Alternate the separate Y and CVBS DAC phases by half a cycle on
    // successive scanlines, without changing their requested levels.
    parameter integer CVBS_SVIDEO_SCANLINE_PHASE_ALTERNATION = 0,
    // Four-sample 1:3:3:1 low-pass filter on composite picture luma only.
    // Separate S-Video Y, sync, blanking, burst and chroma are unchanged.
    parameter integer CVBS_LUMA_FILTER = 0,
    // Tune the four-sample CVBS FIR into a luma trap at the selected
    // standard's colour carrier. Requires CVBS_LUMA_FILTER; Y/C is untouched.
    parameter integer CVBS_LUMA_NOTCH = 0,
    // Four-sample box low-pass on CVBS colour differences before modulation.
    // S-Video keeps its original two-sample chroma path and burst amplitude.
    parameter integer CVBS_CHROMA_FILTER = 0,
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
    output wire [9:0]  source_read_address,
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
    // Both native and compatibility video trail the HDMI producer by a
    // complete line in BOTH fields. PMODE 4's artifact pass can finish after
    // the old VDG deadline in the 263-line field, blanking that whole field.
    // Three retained cache rows cover this fixed consumer delay.
    // picture_top already includes the shared one-line offset. Keeping
    // that selection registered removes an adder from every vertical-window
    // compare and from the line-buffer request path.
    wire [8:0] field_picture_top = picture_top;
    // Updated beside picture_top below; use the registered boundary instead
    // of rebuilding this adder in every source-valid comparison.
    wire [8:0] field_picture_bottom = picture_bottom;
    // Map this analogue field onto the VDG raster that captured the
    // compatibility vertical-border colours. Include the two-line CSS
    // capture-origin correction also used by HDMI and the picture renderer.
    reg compatibility_border_lead = 0;
    reg [1:0] compatibility_border_lag = 1;
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

    localparam RGB_DOT_TIMING = RGB_SOG_OUTPUT && RGB_COCO_APERTURE &&
                               CANONICAL_640_INPUT && !STREAMING_INPUT;
    // 135 MHz * (28/264) = 14.3181818 MHz for native 640-dot RGB.
    // Compatibility expands each pair of original dots into 3+2 canonical
    // samples. Hold them for 7+6+6 and 10+9 clk135 ticks respectively:
    // every original dot is exactly 19 clocks, without subpixel jitter.
    // The 4864-clock body is 36 clocks wider than the exact CoCo cadence.
    reg [9:0] rgb_dot_x=0;
    reg [9:0] rgb_cache_x=0;
    // Native dot intervals repeat 10,9,10,9,10,9,9 clocks (66/7).
    // Compatibility intervals repeat 7,6,6,10,9 clocks. A four-bit
    // countdown implements both without a fractional adder/subtractor.
    reg [3:0] rgb_ticks_remaining=9;
    reg [2:0] rgb_dot_step=0;
    reg rgb_dot_active=0;
    wire rgb_advance=rgb_ticks_remaining==0;
    // Advance the body by 75 clk135 ticks: approximately eight native
    // CoCo hi-res pixels. Keep its dot cadence and width unchanged.
    wire [9:0] rgb_picture_left=(picture_high_resolution ? 10'd168 : 10'd229)+standard_shift;
    wire [3:0] rgb_picture_phase=picture_high_resolution ? 4'd8 : 4'd1;
    always @(posedge clk135 or negedge reset_n)begin
        if(!reset_n)begin
            rgb_dot_x<=0;rgb_cache_x<=0;rgb_ticks_remaining<=9;
            rgb_dot_step<=0;rgb_dot_active<=0;
        end else if(h_sample==0&&sample_phase==0)begin
            rgb_dot_x<=0;rgb_cache_x<=0;
            rgb_ticks_remaining<=picture_high_resolution?4'd9:4'd6;
            rgb_dot_step<=0;rgb_dot_active<=0;
        end else if(h_sample==rgb_picture_left&&sample_phase==rgb_picture_phase)begin
            rgb_dot_x<=0;rgb_cache_x<=0;
            rgb_ticks_remaining<=picture_high_resolution?4'd9:4'd6;
            rgb_dot_step<=0;rgb_dot_active<=1;
        end else if(rgb_dot_active)begin
            if(rgb_advance)begin
                if(picture_high_resolution)begin
                    rgb_dot_step<=rgb_dot_step==6?0:rgb_dot_step+1'b1;
                    case(rgb_dot_step)
                        1,3,6:rgb_ticks_remaining<=9;
                        default:rgb_ticks_remaining<=8;
                    endcase
                end else begin
                    rgb_dot_step<=rgb_dot_step==4?0:rgb_dot_step+1'b1;
                    case(rgb_dot_step)
                        2:rgb_ticks_remaining<=9;
                        3:rgb_ticks_remaining<=8;
                        4:rgb_ticks_remaining<=6;
                        default:rgb_ticks_remaining<=5;
                    endcase
                end
                rgb_cache_x<=rgb_dot_x;
                rgb_dot_x<=rgb_dot_x+1'b1;
                if(rgb_dot_x==10'd639)rgb_dot_active<=0;
            end else rgb_ticks_remaining<=rgb_ticks_remaining-1'b1;
        end
    end
    // Put RGB vertical sync two lines earlier, moving the displayed body
    // down without delaying cache consumption or changing GIME raster IRQs.
    // The registered mapping settles at the beginning of each scanline,
    // before any equalizing/broad-sync pulse can differ from normal HS.
    reg rgb_equalizing=0,rgb_broad_sync=0;
    always @(posedge clk135 or negedge reset_n)begin
        if(!reset_n)begin rgb_equalizing<=0;rgb_broad_sync<=0;end
        else begin
            // Only the sync sections are needed, not a full translated
            // vertical counter. N+2 maps the broad pulse to lines 1..3.
            rgb_equalizing<=v_line==0 || (v_line>=4&&v_line<7) ||
                            (video_50hz_active ?
                             (v_line>=9'd311 || (!field_odd&&v_line==9'd310)) :
                             (v_line>=9'd261 || (!field_odd&&v_line==9'd260)));
            rgb_broad_sync<=v_line>=1&&v_line<4;
        end
    end
    wire sync_equalizing=RGB_DOT_TIMING ? rgb_equalizing :
                         (v_line<3 || (v_line>=6&&v_line<9));
    wire sync_broad=RGB_DOT_TIMING ? rgb_broad_sync : (v_line>=3&&v_line<6);
    localparam CVBS_DOT_COUNTERS=CVBS_INCREMENTAL_DOTS &&
        CANONICAL_640_INPUT && !STREAMING_INPUT && !RGB_SOG_OUTPUT;
    // Select constant-window comparisons, rather than adding the standard
    // shift before comparing the live horizontal counter.
    wire cvbs_native_window=video_50hz_active ?
        (h_sample>=10'd161&&h_sample<10'd801) :
        (h_sample>=10'd158&&h_sample<10'd798);
    wire cvbs_compat_window=video_50hz_active ?
        (h_sample>=10'd225&&h_sample<10'd737) :
        (h_sample>=10'd222&&h_sample<10'd734);
    wire cvbs_border_window=video_50hz_active ?
        (h_sample>=10'd121&&h_sample<10'd841) :
        (h_sample>=10'd118&&h_sample<10'd838);
    wire horizontal_picture = RGB_DOT_TIMING ? rgb_dot_active :
        CVBS_DOT_COUNTERS ? (picture_high_resolution?cvbs_native_window:cvbs_compat_window) :
        (h_sample>=picture_left&&h_sample<picture_right);
    wire in_picture = horizontal_picture &&
                      (v_line >= field_picture_top) &&
                      (v_line < field_picture_bottom);
    wire in_vdg_window = (!RGB_DOT_TIMING || (!sync_equalizing&&!sync_broad)) &&
                         (CVBS_DOT_COUNTERS ? cvbs_border_window :
                          (h_sample>=border_left&&h_sample<border_right)) &&
                         (v_line >= border_top) &&
                         (v_line <= field_last_line);
    wire [9:0] picture_offset = h_sample-picture_left;
    wire [11:0] canonical_x_sum = {2'b0,picture_offset}+
                                   ({2'b0,picture_offset}<<2);
    wire [9:0] picture_x = RGB_DOT_TIMING ? rgb_dot_x :
        picture_high_resolution ? picture_offset :
        (CANONICAL_640_INPUT && !STREAMING_INPUT) ? canonical_x_sum[11:2] :
                                                   (picture_offset>>1);
    // In CVBS builds, derive cache coordinates from the sample cadence
    // instead of subtracting and scaling the live horizontal counter.
    // Track both windows continuously so mid-line mode writes select the
    // same coordinate as the original arithmetic implementation.
    wire [9:0] cvbs_incremental_x;
    generate if(CVBS_INCREMENTAL_DOTS && CANONICAL_640_INPUT &&
                !STREAMING_INPUT && !RGB_SOG_OUTPUT)begin:cvbs_dot_counters
        reg [9:0] native_x=0,compat_x=0;
        reg [9:0] native_read_x=1,compat_read_x=1;
        reg [1:0] compat_fraction=0;
        reg native_running=0,compat_running=0;
        always @(posedge clk135 or negedge reset_n)begin
            if(!reset_n)begin
                native_x<=0;compat_x<=0;compat_fraction<=0;
                native_read_x<=1;compat_read_x<=1;
                native_running<=0;compat_running<=0;
            end else if(h_sample==0 || video_50hz_sync!=video_50hz_active)begin
                native_x<=0;compat_x<=0;compat_fraction<=0;
                native_read_x<=1;compat_read_x<=1;
                native_running<=0;compat_running<=0;
            end else if(sample_phase==9)begin
                if(h_sample==(video_50hz_active?10'd160:10'd157))begin
                    native_x<=0;native_read_x<=1;native_running<=1;
                end else if(native_running)begin
                    native_x<=native_x+1'b1;
                    if(native_read_x!=10'd639)native_read_x<=native_read_x+1'b1;
                end
                if(h_sample==(video_50hz_active?10'd224:10'd221))begin
                    compat_x<=0;compat_read_x<=1;compat_fraction<=0;compat_running<=1;
                end else if(compat_running)begin
                    compat_x<=compat_x+(compat_fraction==3?10'd2:10'd1);
                    compat_read_x<=compat_read_x+(compat_fraction==3?10'd2:10'd1);
                    compat_fraction<=compat_fraction+1'b1;
                end
            end
        end
        assign cvbs_incremental_x=picture_high_resolution?native_x:compat_x;
        assign source_read_address=picture_high_resolution?native_read_x:compat_read_x;
    end else begin:original_dot_address
        assign cvbs_incremental_x=picture_x;
        assign source_read_address=10'd0;
    end endgenerate
    wire [8:0] picture_y_full = v_line - field_picture_top;
    wire [7:0] picture_y = picture_y_full[7:0];
    assign framebuffer_addr = in_picture ? {picture_y, picture_x[7:0]} : 16'd0;
    // The canonical scanline cache reads one address ahead. Compensate
    // that address bias for RGB compatibility timing so the 3+2 groups
    // above line up with the actual returned pixels, including page edges.
    // At the left edge samples zero and one belong to the same VDG dot.
    assign source_x = RGB_DOT_TIMING && !picture_high_resolution ?
                      rgb_cache_x : cvbs_incremental_x;
    assign source_y = picture_y;
    assign source_valid = in_picture;
    // Parallel boundary comparisons replace subtract/increment/compare.
    // The origin is captured beside picture_top and is always top-1.
    reg [8:0] cvbs_prefetch_origin=9'd42;
    // Use the same captured geometry as picture_bottom. Prefetch no longer
    // carries a height adder and pixel-row comparator in one clock.
    reg [8:0] cvbs_prefetch_limit=9'd234;
    wire [8:0] cvbs_prefetch_row=v_line-cvbs_prefetch_origin;
    assign prefetch_y = (v_line < field_picture_top) ? 8'd0 :
        (CVBS_FAST_PREFETCH&&!RGB_SOG_OUTPUT ? cvbs_prefetch_row[7:0] : picture_y+1'b1);
    assign prefetch_valid = CVBS_FAST_PREFETCH&&!RGB_SOG_OUTPUT ?
        ((v_line<field_picture_top) ||
         ((v_line<field_picture_bottom)&&(v_line<cvbs_prefetch_limit))) :
        (v_line < field_picture_top) ? 1'b1 :
        ((v_line < field_picture_bottom) && (picture_y+1'b1 < height_meta));

    // Six pre-equalizing half-lines, six broad-sync half-lines and six
    // post-equalizing half-lines, followed by conventional horizontal sync.
    wire [9:0] h_half = h_total >> 1;
    wire sync_tip = sync_equalizing ?
        ((h_sample < 10'd32) ||
         ((h_sample >= h_half) && (h_sample < h_half+10'd32))) :
        sync_broad ?
        ((h_sample < h_half-10'd64) ||
         ((h_sample >= h_half) && (h_sample < h_total-10'd64))) :
        (h_sample < H_SYNC);

    wire in_burst = !sync_equalizing && !sync_broad &&
                    (h_sample >= BURST_START) && (h_sample < burst_end);

    // NTSC fSC is 455/2 times the line rate. At 135 MHz this accumulator
    // advances 91/3432 of an octant per clock and exactly half a carrier
    // cycle per 858-sample scan line.  The optional PAL DDS is clocked by
    // the SAME 135 MHz PLL output: 2203964/2^26 * 135 MHz = 4,433,619.08 Hz.
    reg [8:0] carrier_fraction = 9'd0;
    reg [2:0] carrier_octant = 3'd0;
    reg [25:0] pal_carrier_acc = 26'd0;
    reg pal_v_invert = 1'b0;
    // At 858 samples/line, the field origin differs only by 180 degrees.
    // Align composite picture and burst without disturbing the S-Video DDS.
    // Make the entire feature a compile-time no-op for RGB and PAL,
    // including if the opt-in parameter is accidentally set for those modes.
    localparam CVBS_PHASE_ALIGNMENT=CVBS_FIELD_PHASE_ALIGN &&
                                    !RGB_SOG_OUTPUT && !PAL_CHROMA_OUTPUT;
    wire cvbs_phase_flip;
    generate if (CVBS_PHASE_ALIGNMENT) begin:cvbs_field_phase
        reg phase_flip=0;
        always @(posedge clk135)begin
            if(!reset_n)phase_flip<=0;
            else if(!video_50hz_active &&
                    v_line==0 && h_sample==0 && sample_phase==0)
                phase_flip<=carrier_octant[2];
        end
        assign cvbs_phase_flip=phase_flip;
    end else begin:continuous_field_phase
        assign cvbs_phase_flip=1'b0;
    end endgenerate
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
        reg signed [4:0] quantized;
        begin
            case (phase[1:0])
                2'd0: mix = y4;
                2'd1: mix = sum3;
                2'd2: mix = x4;
                default: mix = difference3;
            endcase
            // Keep the original 11-bit wrap and arithmetic-shift semantics.
            // floor(-mix/64) = ~floor(mix/64) + (remainder == 0).
            quantized = mix[10:6];
            if (phase[2])
                quantized = ~quantized + {4'b0, !(|mix[5:0])};
            rgb_chroma = quantized;
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

    // The S-Video DAC uses a modulo-32 residue and a single carry bit.
    // Saturate at its physical full scale: allowing levels 33..63 makes the
    // carry overflow and turns bright chroma peaks into low-duty-cycle pulses.
    function [5:0] add_svideo_level;
        input [5:0] base;
        input signed [7:0] delta;
        reg signed [8:0] result;
        begin
            result = $signed({1'b0,base}) + delta;
            if (result[8]) add_svideo_level = 6'd0;
            else if (|result[7:5]) add_svideo_level = 6'd32;
            else add_svideo_level = {1'b0,result[4:0]};
        end
    endfunction

    // Factor the exact RGB222 matrix into four-input corrections and a
    // two-input channel level. Every reachable component result is 1..127,
    // so modulo-128 addition gives the original unsaturated result exactly.
    function [6:0] component_pb_base;
        input [3:0] pair;
        begin
            case(pair)
                4'd0: component_pb_base=7'd64;
                4'd1: component_pb_base=7'd51;
                4'd2: component_pb_base=7'd37;
                4'd3: component_pb_base=7'd23;
                4'd4: component_pb_base=7'd57;
                4'd5: component_pb_base=7'd43;
                4'd6: component_pb_base=7'd30;
                4'd7: component_pb_base=7'd16;
                4'd8: component_pb_base=7'd50;
                4'd9: component_pb_base=7'd36;
                4'd10: component_pb_base=7'd22;
                4'd11: component_pb_base=7'd9;
                4'd12: component_pb_base=7'd43;
                4'd13: component_pb_base=7'd29;
                4'd14: component_pb_base=7'd15;
                4'd15: component_pb_base=7'd1;
                default: component_pb_base=7'd64;
            endcase
        end
    endfunction

    function [6:0] component_pr_base;
        input [3:0] pair;
        begin
            case(pair)
                4'd0: component_pr_base=7'd64;
                4'd1: component_pr_base=7'd47;
                4'd2: component_pr_base=7'd29;
                4'd3: component_pr_base=7'd11;
                4'd4: component_pr_base=7'd61;
                4'd5: component_pr_base=7'd43;
                4'd6: component_pr_base=7'd26;
                4'd7: component_pr_base=7'd8;
                4'd8: component_pr_base=7'd58;
                4'd9: component_pr_base=7'd40;
                4'd10: component_pr_base=7'd22;
                4'd11: component_pr_base=7'd5;
                4'd12: component_pr_base=7'd55;
                4'd13: component_pr_base=7'd37;
                4'd14: component_pr_base=7'd19;
                4'd15: component_pr_base=7'd1;
                default: component_pr_base=7'd64;
            endcase
        end
    endfunction

    function [5:0] component_channel;
        input [1:0] channel;
        begin
            case(channel)
                0:component_channel=0;
                1:component_channel=21;
                2:component_channel=42;
                default:component_channel=63;
            endcase
        end
    endfunction
    reg [6:0] encoder_component_pb_base=64,encoder_component_pr_base=64;
    reg [5:0] encoder_component_blue=0,encoder_component_red=0;

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
    // RGB222 has only four levels per channel. Exact lookup tables avoid
    // widening repeated-bit components through subtract/constant-add trees.
    function signed [7:0] rgb222_difference;
        input [1:0] positive,negative;
        begin case({positive,negative})
            4'h0:rgb222_difference=8'sd0;
            4'h1:rgb222_difference=-8'sd21;
            4'h2:rgb222_difference=-8'sd42;
            4'h3:rgb222_difference=-8'sd63;
            4'h4:rgb222_difference=8'sd21;
            4'h5:rgb222_difference=8'sd0;
            4'h6:rgb222_difference=-8'sd21;
            4'h7:rgb222_difference=-8'sd42;
            4'h8:rgb222_difference=8'sd42;
            4'h9:rgb222_difference=8'sd21;
            4'ha:rgb222_difference=8'sd0;
            4'hb:rgb222_difference=-8'sd21;
            4'hc:rgb222_difference=8'sd63;
            4'hd:rgb222_difference=8'sd42;
            4'he:rgb222_difference=8'sd21;
            4'hf:rgb222_difference=8'sd0;
        endcase end
    endfunction
    function [9:0] rgb222_luma_rb;
        input [3:0] red_blue;
        begin case(red_blue)
            4'h0:rgb222_luma_rb=10'd32;
            4'h1:rgb222_luma_rb=10'd74;
            4'h2:rgb222_luma_rb=10'd116;
            4'h3:rgb222_luma_rb=10'd158;
            4'h4:rgb222_luma_rb=10'd158;
            4'h5:rgb222_luma_rb=10'd200;
            4'h6:rgb222_luma_rb=10'd242;
            4'h7:rgb222_luma_rb=10'd284;
            4'h8:rgb222_luma_rb=10'd284;
            4'h9:rgb222_luma_rb=10'd326;
            4'ha:rgb222_luma_rb=10'd368;
            4'hb:rgb222_luma_rb=10'd410;
            4'hc:rgb222_luma_rb=10'd410;
            4'hd:rgb222_luma_rb=10'd452;
            4'he:rgb222_luma_rb=10'd494;
            4'hf:rgb222_luma_rb=10'd536;
        endcase end
    endfunction
    function [9:0] rgb222_luma_green;
        input [1:0] green;
        begin case(green)
            2'd0:rgb222_luma_green=10'd0;
            2'd1:rgb222_luma_green=10'd252;
            2'd2:rgb222_luma_green=10'd504;
            2'd3:rgb222_luma_green=10'd756;
        endcase end
    endfunction
    wire signed [7:0] fb_x_axis=rgb222_difference(pixel_rgb[1:0],pixel_rgb[3:2]);
    wire signed [7:0] fb_y_axis=rgb222_difference(pixel_rgb[5:4],pixel_rgb[3:2]);
    wire [9:0] fb_luma_rb=rgb222_luma_rb({pixel_rgb[5:4],pixel_rgb[1:0]});
    wire [9:0] fb_luma_g=rgb222_luma_green(pixel_rgb[3:2]);

    reg source_sync = 1'b1;
    reg source_burst = 1'b0;
    reg source_picture = 1'b0;
    reg source_active = 1'b0;
    reg source_body = 1'b0;
    // Carry horizontal border-side decisions through the source stage. Doing
    // these comparisons here keeps the standard-dependent picture bounds out
    // of the later border-colour mux on the 135 MHz sample clock.
    reg source_left_of_picture = 1'b1;
    reg source_left_of_right_edge = 1'b0;
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
    // for ten clocks.
    wire signed [8:0] chroma_x_pair =
        $signed(encoder_x_axis) + $signed(chroma_x_previous);
    wire signed [8:0] chroma_y_pair =
        $signed(encoder_y_axis) + $signed(chroma_y_previous);
    wire signed [7:0] chroma_x_average = chroma_x_pair >>> 1;
    wire signed [7:0] chroma_y_average = chroma_y_pair >>> 1;
    reg signed [7:0] cvbs_chroma_x_older=0,cvbs_chroma_x_oldest=0;
    reg signed [7:0] cvbs_chroma_y_older=0,cvbs_chroma_y_oldest=0;
    wire signed [8:0] cvbs_chroma_x_history_pair=
        $signed(chroma_x_previous)+$signed(cvbs_chroma_x_older);
    wire signed [8:0] cvbs_chroma_y_history_pair=
        $signed(chroma_y_previous)+$signed(cvbs_chroma_y_older);
    reg signed [9:0] cvbs_chroma_x_history=0,cvbs_chroma_y_history=0;
    wire signed [9:0] cvbs_chroma_x_sum=
        $signed(encoder_x_axis)+cvbs_chroma_x_history+10'sd2;
    wire signed [9:0] cvbs_chroma_y_sum=
        $signed(encoder_y_axis)+cvbs_chroma_y_history+10'sd2;
    reg signed [7:0] cvbs_chroma_x_filtered=0,cvbs_chroma_y_filtered=0;
    reg signed [7:0] cvbs_chroma_x_delayed=0,cvbs_chroma_y_delayed=0;
    wire signed [10:0] cvbs_filtered_x=cvbs_chroma_x_delayed;
    wire signed [10:0] cvbs_filtered_y=cvbs_chroma_y_delayed;
    wire signed [10:0] cvbs_filtered_sum=cvbs_filtered_x+cvbs_filtered_y;
    wire signed [10:0] cvbs_filtered_difference=cvbs_filtered_x-cvbs_filtered_y;
    // Apply the optional composite-only FIR on the same sample enable.
    // Its symmetric taps soften edges and give luma a 1.5-sample
    // group delay, while the separate Y output keeps its original bandwidth.
    wire [5:0] encoder_cvbs_luma =
        LEVEL_BLANK + encoder_luma_sum[10:6];
    reg [5:0] cvbs_luma_previous = LEVEL_BLANK;
    reg [5:0] cvbs_luma_older = LEVEL_BLANK;
    reg [5:0] cvbs_luma_oldest = LEVEL_BLANK;
    reg [5:0] cvbs_luma_filtered = LEVEL_BLANK;
    // History changes only every tenth clk135 edge. Compute its weighted
    // sum on the intervening clocks, keeping that arithmetic out of the
    // live RGB-to-luma path sampled by the FIR. One free clock suffices.
    wire [6:0] cvbs_luma_middle_pair =
        {1'b0,cvbs_luma_previous} + {1'b0,cvbs_luma_older};
    wire [8:0] cvbs_luma_middle_weighted =
        {1'b0,cvbs_luma_middle_pair,1'b0} + {2'b00,cvbs_luma_middle_pair};
    wire [6:0] cvbs_luma_oldest_biased = {1'b0,cvbs_luma_oldest} + 7'd4;
    reg [8:0] cvbs_luma_history_sum = (7 * LEVEL_BLANK) + 4;
    wire [8:0] cvbs_luma_filter_sum =
        {3'b000,encoder_cvbs_luma} + cvbs_luma_history_sum;
    // Symmetric four-tap trap, normalised by 128:
    // NTSC [29,35,35,29], zero at 3.5977 MHz (13.5 MHz sample rate).
    // PAL  [22,42,42,22], zero near 4.39 MHz. Coefficient rounding keeps
    // carrier rejection below the resolution of the six-bit luma DAC.
    // Both keep the existing FIR's 1.5-sample group delay. Two extra fast
    // pipeline clocks (14.8 ns) isolate RGB conversion from the products
    // and final sum; sync, burst, carrier phase and S-Video are unchanged.
    localparam [5:0] CVBS_TRAP_OUTER = PAL_CHROMA_OUTPUT ? 6'd22 : 6'd29;
    localparam [5:0] CVBS_TRAP_INNER = PAL_CHROMA_OUTPUT ? 6'd42 : 6'd35;
    localparam [12:0] CVBS_TRAP_HISTORY_RESET =
        ((2 * CVBS_TRAP_INNER + CVBS_TRAP_OUTER) * LEVEL_BLANK) + 64;
    reg [6:0] cvbs_trap_middle_pair = 2 * LEVEL_BLANK;
    reg [5:0] cvbs_trap_oldest = LEVEL_BLANK;
    reg [12:0] cvbs_trap_inner_product = 2 * CVBS_TRAP_INNER * LEVEL_BLANK;
    reg [10:0] cvbs_trap_outer_product = CVBS_TRAP_OUTER * LEVEL_BLANK;
    reg [12:0] cvbs_trap_history_sum = CVBS_TRAP_HISTORY_RESET;
    reg [5:0] cvbs_trap_current = LEVEL_BLANK;
    reg [12:0] cvbs_trap_history = CVBS_TRAP_HISTORY_RESET;
    reg [10:0] cvbs_trap_current_product = CVBS_TRAP_OUTER * LEVEL_BLANK;
    reg [12:0] cvbs_trap_history_delayed = CVBS_TRAP_HISTORY_RESET;
    reg [1:0] cvbs_trap_tick = 0;
    reg [5:0] cvbs_luma_notched = LEVEL_BLANK;
    wire [12:0] cvbs_trap_sum =
        {2'b00,cvbs_trap_current_product} + cvbs_trap_history_delayed;
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
    reg signed [10:0] cvbs_mod_x4=0,cvbs_mod_y4=0;
    reg signed [10:0] cvbs_mod_sum3=0,cvbs_mod_difference3=0;
    reg [6:0] mod_component_pb_level=7'd64, mod_component_pr_level=7'd64;
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
    wire pal_picture_invert = PAL_CHROMA_OUTPUT && pal_v_invert;
    wire [2:0] pal_picture_carrier = mod_carrier ^
        {pal_picture_invert && !(|mod_carrier[1:0]),
         pal_picture_invert && mod_carrier[0],1'b0};
    wire signed [5:0] mod_picture_chroma =
        rgb_chroma(mod_x4,mod_y4,mod_sum3,mod_difference3,
                   pal_picture_carrier);
    wire signed [5:0] mod_svideo_picture_chroma = mod_picture_chroma;
    // Delay baseband colour, never the modulated carrier. The four-tap
    // chroma group delay and fast pipeline now match the CVBS luma trap;
    // the shared carrier and burst keep their original phase relationship.
    wire signed [10:0] cvbs_pal_y4=
        (PAL_CHROMA_OUTPUT && pal_v_invert) ? -cvbs_mod_y4 : cvbs_mod_y4;
    wire signed [10:0] cvbs_pal_sum3=
        (PAL_CHROMA_OUTPUT && pal_v_invert) ? cvbs_mod_difference3 : cvbs_mod_sum3;
    wire signed [10:0] cvbs_pal_difference3=
        (PAL_CHROMA_OUTPUT && pal_v_invert) ? cvbs_mod_sum3 : cvbs_mod_difference3;
    wire [2:0] cvbs_mod_carrier=mod_carrier ^
        {(!PAL_CHROMA_OUTPUT && !video_50hz_active && cvbs_phase_flip),2'b00};
    // Reuse the existing unfiltered matrix for a 180-degree correction.
    // For mix=64*q+r, floor(-mix/64)=-q-(r!=0). Preserve this rounding
    // exactly instead of duplicating the eleven-bit chroma matrix.
    reg cvbs_fraction_nonzero;
    always @(*)begin
        case(mod_carrier[1:0])
            0:cvbs_fraction_nonzero=|pal_picture_y4[5:0];
            1:cvbs_fraction_nonzero=|pal_picture_sum3[5:0];
            2:cvbs_fraction_nonzero=|mod_x4[5:0];
            default:cvbs_fraction_nonzero=|pal_picture_difference3[5:0];
        endcase
    end
    wire signed [5:0] cvbs_opposite_chroma=
        ~mod_picture_chroma+{5'b0,!cvbs_fraction_nonzero};
    wire signed [5:0] cvbs_unfiltered_picture_chroma=
        (!PAL_CHROMA_OUTPUT && !video_50hz_active && cvbs_phase_flip) ?
        cvbs_opposite_chroma : mod_picture_chroma;
    wire signed [5:0] cvbs_picture_chroma=
        rgb_chroma(cvbs_mod_x4,cvbs_pal_y4,cvbs_pal_sum3,
                   cvbs_pal_difference3,cvbs_mod_carrier);
    // PAL burst swings +/-45 degrees about the negative U axis.  The two
    // octant offsets correspond to -U+V and -U-V respectively; NTSC keeps
    // its original 180-degree burst unchanged.
    wire [2:0] burst_phase_offset = PAL_CHROMA_OUTPUT ?
        (pal_v_invert ? 3'd5 : 3'd3) : 3'd4;
    wire signed [5:0] mod_burst_chroma =
        chroma8(cvbs_mod_carrier + burst_phase_offset,2'd3);
    wire signed [5:0] mod_selected_chroma = mod_burst ?
        mod_burst_chroma : (CVBS_CHROMA_FILTER ? cvbs_picture_chroma :
            CVBS_PHASE_ALIGNMENT ? cvbs_unfiltered_picture_chroma : mod_picture_chroma);

    reg level_sync = 1'b1;
    reg level_burst = 1'b0;
    reg level_picture = 1'b0;
    reg [2:0] level_carrier = 3'd0;
    reg [5:0] level_luma = LEVEL_BLANK;
    reg [6:0] level_luma_q2 = LUMA_BLANK_Q2;
    reg signed [5:0] level_chroma = 6'sd0;
    reg signed [5:0] level_svideo_chroma = 6'sd0;
    wire [5:0] selected_cvbs_luma =
        CVBS_LUMA_FILTER ? (CVBS_LUMA_NOTCH ? cvbs_luma_notched :
                           cvbs_luma_filtered) : mod_luma;

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

    // S-Video uses the same picture phase as CVBS, with x4 gain for the
    // Q8 emitter follower.
    wire signed [7:0] svideo_chroma_extended = level_svideo_chroma;
    wire signed [7:0] svideo_picture_chroma = svideo_chroma_extended <<< 2;

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
    wire signed [5:0] svideo_burst_chroma=
        chroma8(level_carrier + burst_phase_offset,2'd3);
    wire [5:0] chroma_level = level_picture ?
        add_svideo_level(CHROMA_CENTER,svideo_picture_chroma) :
        level_burst ? add_level(CHROMA_CENTER,
            CVBS_PHASE_ALIGNMENT ? svideo_burst_chroma : level_chroma) :
        CHROMA_CENTER;
    wire [5:0] composite_level = level_sync ? LEVEL_SYNC :
        level_burst ? add_level(LEVEL_BLANK,level_chroma) :
        level_picture ? add_level(level_luma,level_chroma) : LEVEL_BLANK;
    wire [6:0] component_pb_level = RGB_SOG_OUTPUT ? rgb_blue_level :
        mod_component_pb_level;
    wire [6:0] component_pr_level = RGB_SOG_OUTPUT ? rgb_red_level :
        mod_component_pr_level;

    reg [6:0] luma_level_135 = LUMA_SYNC_Q2;
    reg [5:0] chroma_level_135 = CHROMA_CENTER;
    reg [5:0] cvbs_level_135 = LEVEL_SYNC;
    reg [6:0] component_pb_level_135 = 7'd64;
    reg [6:0] component_pr_level_135 = 7'd64;

    always @(posedge clk135) begin
        if (!reset_n) begin
            sample_phase <= 4'd0;
            height_meta <= 8'd192;
            picture_top <= 9'd43;
            cvbs_prefetch_origin <= 9'd42;
            cvbs_prefetch_limit <= 9'd234;
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
            source_left_of_picture <= 1'b1;
            source_left_of_right_edge <= 1'b0;
            source_carrier <= 3'd0;
            source_sample_tick <= 1'b0;
            pixel_sync <= 1'b1;
            pixel_burst <= 1'b0;
            pixel_picture <= 1'b0;
            pixel_carrier <= 3'd0;
            pixel_sample_tick <= 1'b0;
            pixel_rgb <= 6'd0;
            encoder_component_pb_base<=64;
            encoder_component_pr_base<=64;
            encoder_component_blue<=0;
            encoder_component_red<=0;
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
            cvbs_chroma_x_older<=0;cvbs_chroma_x_oldest<=0;
            cvbs_chroma_y_older<=0;cvbs_chroma_y_oldest<=0;
            cvbs_chroma_x_history<=0;cvbs_chroma_y_history<=0;
            cvbs_chroma_x_filtered<=0;cvbs_chroma_y_filtered<=0;
            cvbs_chroma_x_delayed<=0;cvbs_chroma_y_delayed<=0;
            cvbs_luma_previous <= LEVEL_BLANK;
            cvbs_luma_older <= LEVEL_BLANK;
            cvbs_luma_oldest <= LEVEL_BLANK;
            cvbs_luma_filtered <= LEVEL_BLANK;
            cvbs_luma_history_sum <= (7 * LEVEL_BLANK) + 4;
            cvbs_trap_middle_pair <= 2 * LEVEL_BLANK;
            cvbs_trap_oldest <= LEVEL_BLANK;
            cvbs_trap_inner_product <= 2 * CVBS_TRAP_INNER * LEVEL_BLANK;
            cvbs_trap_outer_product <= CVBS_TRAP_OUTER * LEVEL_BLANK;
            cvbs_trap_history_sum <= CVBS_TRAP_HISTORY_RESET;
            cvbs_trap_current <= LEVEL_BLANK;
            cvbs_trap_history <= CVBS_TRAP_HISTORY_RESET;
            cvbs_trap_current_product <= CVBS_TRAP_OUTER * LEVEL_BLANK;
            cvbs_trap_history_delayed <= CVBS_TRAP_HISTORY_RESET;
            cvbs_trap_tick <= 0;
            cvbs_luma_notched <= LEVEL_BLANK;
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
            cvbs_mod_x4<=0;cvbs_mod_y4<=0;
            cvbs_mod_sum3<=0;cvbs_mod_difference3<=0;
            mod_component_pb_level <= 7'd64;
            mod_component_pr_level <= 7'd64;
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
        end else begin
            video_50hz_meta <= video_50hz;
            video_50hz_sync <= video_50hz_meta;
            if (video_50hz_sync != video_50hz_active)
                video_50hz_active <= video_50hz_sync;
            height_meta <= active_height;
            compatibility_border_lead <= video_50hz_active&&!compatibility_mode;
            compatibility_border_lag <= video_50hz_active ? 2'd0 :
                ((height_meta==8'd192 ? 2'd1 : 2'd0)+
                 (compatibility_mode ? 2'd1 : 2'd0));
            border_raster_y_q <= compatibility_border_lead ? v_line+9'd1 :
                v_line>=compatibility_border_lag ?
                    v_line-compatibility_border_lag : 9'd0;
            picture_top <= next_picture_top+9'd1;
            cvbs_prefetch_origin <= next_picture_top;
            cvbs_prefetch_limit <= next_picture_top+{1'b0,height_meta};
            picture_bottom <= next_picture_top+9'd1+{1'b0,height_meta};
            luma_level_135 <= LUMA_DAC_EVEN_LEVELS ?
                              {luma_level[6:1],1'b0} : luma_level;
            chroma_level_135 <= chroma_level;
            cvbs_level_135 <= composite_level;
            component_pb_level_135 <= component_pb_level;
            component_pr_level_135 <= component_pr_level;

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
            source_left_of_picture <= RGB_DOT_TIMING ?
                (h_sample<rgb_picture_left || (h_sample==rgb_picture_left&&
                                              sample_phase<=rgb_picture_phase)) :
                (h_sample < picture_left);
            source_left_of_right_edge <= RGB_DOT_TIMING ? rgb_dot_x<10'd640 :
                                        (h_sample < picture_right);
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
                (source_left_of_right_edge ? row_border_rgb : row_right_border_rgb) :
                compatibility_mode && !source_body && vertical_border_valid ?
                (source_left_of_picture ? vertical_left_border_rgb :
                                          vertical_right_border_rgb) :
                border_row_delay2;
            pixel_rgb <= source_active ? framebuffer_data : border_sample;

            encoder_sync <= pixel_sync;
            encoder_burst <= pixel_burst;
            encoder_picture <= pixel_picture;
            encoder_carrier <= pixel_carrier;
            encoder_sample_tick <= pixel_sample_tick;
            encoder_component_pb_base<=component_pb_base(pixel_rgb[5:2]);
            encoder_component_pr_base<=component_pr_base({pixel_rgb[1:0],pixel_rgb[3:2]});
            encoder_component_blue<=component_channel(pixel_rgb[1:0]);
            encoder_component_red<=component_channel(pixel_rgb[5:4]);
            encoder_rgb <= pixel_rgb;
            encoder_x_axis <= fb_x_axis;
            encoder_y_axis <= fb_y_axis;
            encoder_luma_rb <= fb_luma_rb;
            encoder_luma_g <= fb_luma_g;

            cvbs_luma_history_sum <= cvbs_luma_middle_weighted +
                                     {2'b00,cvbs_luma_oldest_biased};
            cvbs_chroma_x_history<=cvbs_chroma_x_history_pair+
                                   $signed(cvbs_chroma_x_oldest);
            cvbs_chroma_y_history<=cvbs_chroma_y_history_pair+
                                   $signed(cvbs_chroma_y_oldest);
            cvbs_chroma_x_delayed<=cvbs_chroma_x_filtered;
            cvbs_chroma_y_delayed<=cvbs_chroma_y_filtered;
            // Three fast clocks settle the history products between the
            // 13.5 MHz sample enables, which are ten clk135 edges apart.
            cvbs_trap_middle_pair <= cvbs_luma_middle_pair;
            cvbs_trap_oldest <= cvbs_luma_oldest;
            cvbs_trap_inner_product <= cvbs_trap_middle_pair * CVBS_TRAP_INNER;
            cvbs_trap_outer_product <= cvbs_trap_oldest * CVBS_TRAP_OUTER;
            cvbs_trap_history_sum <= cvbs_trap_inner_product +
                                    {2'b00,cvbs_trap_outer_product} + 13'd64;
            cvbs_trap_tick <= {cvbs_trap_tick[0],encoder_sample_tick};
            cvbs_trap_current_product <= cvbs_trap_current * CVBS_TRAP_OUTER;
            cvbs_trap_history_delayed <= cvbs_trap_history;
            if(cvbs_trap_tick[1])cvbs_luma_notched <= cvbs_trap_sum[12:7];
            if (encoder_sample_tick) begin
                cvbs_chroma_x_oldest<=cvbs_chroma_x_older;
                cvbs_chroma_x_older<=chroma_x_previous;
                cvbs_chroma_y_oldest<=cvbs_chroma_y_older;
                cvbs_chroma_y_older<=chroma_y_previous;
                cvbs_chroma_x_filtered<=cvbs_chroma_x_sum>>>2;
                cvbs_chroma_y_filtered<=cvbs_chroma_y_sum>>>2;
                cvbs_trap_current <= encoder_cvbs_luma;
                cvbs_trap_history <= cvbs_trap_history_sum;
                chroma_x_previous <= encoder_x_axis;
                chroma_y_previous <= encoder_y_axis;
                chroma_x_filtered <= chroma_x_average;
                chroma_y_filtered <= chroma_y_average;
                cvbs_luma_oldest <= cvbs_luma_older;
                cvbs_luma_older <= cvbs_luma_previous;
                cvbs_luma_previous <= encoder_cvbs_luma;
                cvbs_luma_filtered <= cvbs_luma_filter_sum[8:3];
            end

            mod_sync <= encoder_sync;
            mod_burst <= encoder_burst;
            mod_picture <= encoder_picture;
            mod_carrier <= encoder_carrier;
            mod_rgb <= encoder_rgb;
            mod_luma <= encoder_cvbs_luma;
            mod_luma_q2 <= LUMA_BLANK_Q2 + encoder_y_picture_excursion;
            mod_x4 <= filtered_x <<< 2;
            mod_y4 <= filtered_y <<< 2;
            mod_sum3 <= (filtered_sum <<< 1) + filtered_sum;
            mod_difference3 <=
                (filtered_difference <<< 1) + filtered_difference;
            cvbs_mod_x4<=cvbs_filtered_x<<<2;
            cvbs_mod_y4<=cvbs_filtered_y<<<2;
            cvbs_mod_sum3<=(cvbs_filtered_sum<<<1)+cvbs_filtered_sum;
            cvbs_mod_difference3<=
                (cvbs_filtered_difference<<<1)+cvbs_filtered_difference;
            // Component video keeps the full colour-difference bandwidth;
            // the composite-only two-tap chroma filter is intentionally not
            // inserted in these paths.
            mod_component_pb_level <= mod_picture ?
                encoder_component_pb_base+{1'b0,encoder_component_blue} : 7'd64;
            mod_component_pr_level <= mod_picture ?
                encoder_component_pr_base+{1'b0,encoder_component_red} : 7'd64;
            mod_component_x <= encoder_x_axis;
            mod_component_y <= encoder_y_axis;

            level_sync <= mod_sync;
            level_burst <= mod_burst;
            level_picture <= mod_picture;
            level_carrier <= mod_carrier;
            level_luma <= selected_cvbs_luma > LEVEL_WHITE ?
                          LEVEL_WHITE : selected_cvbs_luma;
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
    reg component_pb_selected = 1'b0;
    reg component_pr_selected = (COMPONENT_DAC_PHASE_STAGGER != 0);
    reg component_midpoint_phase = 1'b0;
    reg component_pb_midpoint = 1'b1;
    reg component_pr_midpoint = 1'b1;
    reg component_pb_midpoint_output = 1'b1;
    reg component_pr_midpoint_output = 1'b1;
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
    // Pipeline the luma zero comparison before using it to reset the 270-MHz
    // sigma-delta accumulators.  The former direct seven-bit comparison fed
    // the accumulator mux in the same cycle and was the critical setup path.
    // Edge detection delays the event by one 270-MHz clock, still safely
    // inside the horizontal sync tip.
    reg luma_sync_270 = 1'b1;
    reg luma_sync_270_d = 1'b1;
    wire dac_line_start = luma_sync_270 && !luma_sync_270_d;
    reg dac_line_phase = 1'b0;
    wire [7:0] luma_alternate_seed = dac_line_phase ? 8'd64 : 8'd0;
    wire [7:0] rgb_blue_seed = dac_line_phase ? 8'd106 : 8'd42;
    wire [7:0] rgb_red_seed = dac_line_phase ? 8'd21 : 8'd85;
    wire [5:0] cvbs_seed = dac_line_phase ? 6'd16 : 6'd0;
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
            component_pb_selected <= 1'b0;
            component_pr_selected <= (COMPONENT_DAC_PHASE_STAGGER != 0);
            component_midpoint_phase <= 1'b0;
            component_pb_midpoint <= 1'b1;
            component_pr_midpoint <= 1'b1;
            component_pb_midpoint_output <= 1'b1;
            component_pr_midpoint_output <= 1'b1;
            luma_out_reg <= 1'b0;
            chroma_out_reg <= 1'b0;
            cvbs_out_reg <= 1'b0;
            component_pb_out_reg <= 1'b0;
            component_pr_out_reg <= 1'b0;
            luma_phase_lfsr <= 16'h1ace;
            luma_sync_270 <= 1'b1;
            luma_sync_270_d <= 1'b1;
            dac_line_phase <= 1'b0;
        end else begin
            luma_dac_level <= luma_level_135;
            chroma_dac_level <= chroma_level_135;
            cvbs_dac_level <= cvbs_level_135;
            component_pb_dac_level <= component_pb_level_135;
            component_pr_dac_level <= component_pr_level_135;
            component_midpoint_phase <= ~component_midpoint_phase;
            // Register comparisons with the levels, then delay once more
            // to align the neutral flags with the sigma carry output.
            component_pb_midpoint <= (component_pb_level_135 == 7'd64);
            component_pr_midpoint <= (component_pr_level_135 == 7'd64);
            component_pb_midpoint_output <= component_pb_midpoint;
            component_pr_midpoint_output <= component_pr_midpoint;
            luma_sync_270 <= (luma_level_135 == LUMA_SYNC_Q2);
            luma_sync_270_d <= luma_sync_270;
            if (dac_line_start &&
                ((RGB_SOG_OUTPUT && RGB_SCANLINE_PHASE_ALTERNATION) ||
                 LUMA_SCANLINE_PHASE_ALTERNATION ||
                 CVBS_SVIDEO_SCANLINE_PHASE_ALTERNATION))
                dac_line_phase <= ~dac_line_phase;
            // Phase-lock only the signals containing luma.  The event lands
            // in the horizontal sync tip, so the accumulator transient is
            // invisible; S-Video chroma retains continuous phase.
            luma_sigma <= dac_line_start ?
                          (((RGB_SOG_OUTPUT &&
                             RGB_SCANLINE_PHASE_ALTERNATION) ||
                             LUMA_SCANLINE_PHASE_ALTERNATION ||
                             CVBS_SVIDEO_SCANLINE_PHASE_ALTERNATION) ?
                           luma_alternate_seed : {1'b0,luma_phase_lfsr[6:0]}) :
                          luma_sum;
            chroma_sigma <= chroma_sum;
            cvbs_sigma <= dac_line_start ?
                          (CVBS_SVIDEO_SCANLINE_PHASE_ALTERNATION ?
                           cvbs_seed : {1'b0,luma_phase_lfsr[4:0]}) :
                          cvbs_sum;
            // Restart baseband colour DACs only during horizontal sync.
            // Opposite midpoint phases avoid in-phase Pb/Pr switching on grey.
            // S-Video's modulated chroma DAC above remains continuous.
            component_pb_sigma <= (dac_line_start &&
                                  ((RGB_SOG_OUTPUT && RGB_SCANLINE_PHASE_ALTERNATION) ||
                                   COMPONENT_DAC_PHASE_STAGGER)) ?
                                  (COMPONENT_DAC_PHASE_STAGGER ? 8'd42 : rgb_blue_seed) :
                                  component_pb_sum;
            component_pr_sigma <= (dac_line_start &&
                                  ((RGB_SOG_OUTPUT && RGB_SCANLINE_PHASE_ALTERNATION) ||
                                   COMPONENT_DAC_PHASE_STAGGER)) ?
                                  (COMPONENT_DAC_PHASE_STAGGER ? 8'd85 : rgb_red_seed) :
                                  component_pr_sum;
            if (dac_line_start)
                luma_phase_lfsr <= {luma_phase_lfsr[14:0],
                                    luma_phase_feedback};
            luma_out_reg <= luma_sigma[7];
            chroma_out_reg <= chroma_sigma[5];
            cvbs_out_reg <= cvbs_sigma[5];
            // At midpoint, ordinary sigma-delta output is a 50% square wave
            // whose phase remembers preceding colours. Use fixed opposite
            // phases instead, while preserving the accumulator underneath.
            // Each 13.5-MHz sample spans 20 DAC clocks, so a neutral sample
            // still emits exactly ten pulses. Coloured samples keep their
            // original output bits and accumulated quantisation error.
            // Select the NEXT sigma carry one clock earlier. The final IO
            // flops now have a direct registered input; output latency and
            // neutral phase are unchanged. Keep the sigma residue untouched.
            component_pb_selected <= (COMPONENT_DAC_PHASE_STAGGER &&
                                       component_pb_midpoint) ?
                ~component_midpoint_phase :
                ((dac_line_start && ((RGB_SOG_OUTPUT &&
                  RGB_SCANLINE_PHASE_ALTERNATION) || COMPONENT_DAC_PHASE_STAGGER)) ?
                 1'b0 : component_pb_sum[7]);
            component_pr_selected <= (COMPONENT_DAC_PHASE_STAGGER &&
                                       component_pr_midpoint) ?
                component_midpoint_phase :
                ((dac_line_start && ((RGB_SOG_OUTPUT &&
                  RGB_SCANLINE_PHASE_ALTERNATION) || COMPONENT_DAC_PHASE_STAGGER)) ?
                 1'b0 : component_pr_sum[7]);
            component_pb_out_reg <= component_pb_selected;
            component_pr_out_reg <= component_pr_selected;
        end
    end
endmodule
