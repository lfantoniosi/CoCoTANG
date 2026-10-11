module gime_native_video (
    input clk, input reset_n, input video_50hz, input bit_plane,
    input [3:0] hres, input [7:0] vmode,
    input hdmi_frame_start, input hdmi_active_50hz,
    input [7:0] active_height,
    input compatibility_mode, input compatibility_css,
    input [5:0] compatibility_border_rgb,
    input [5:0] pixel_rgb,
    output wire hs_n, output wire fs_n, output wire hborder_irq_n,
    output wire vborder_irq_n,
    output wire hblank, output wire vblank,
    output [8:0] debug_raster_y,
    output wire trace_line_sample,
    output wire [7:0] trace_active_line,
    output wire [1:0] trace_phase,
    output reg compatibility_sample,
    output reg compatibility_sample_css,
    output reg [7:0] compatibility_sample_y,
    output reg [4:0] compatibility_sample_byte,
    output reg compatibility_border_sample,
    output reg compatibility_border_right,
    output reg [8:0] compatibility_border_y,
    output reg [5:0] compatibility_border_sample_rgb,
    output [7:0] red, output [7:0] green, output [7:0] blue
);
    // 910 GIME dots occupy exactly two 858-dot 27 MHz HDMI lines.  With the
    // 108 MHz system clock the native dot-rate ratio is therefore 35/264.
    // Keeping that exact relationship prevents the CPU-visible raster IRQs
    // from walking horizontally through the independently scanned picture.
    localparam [31:0] RASTER_STEP = 32'd569408543;
    reg [31:0] accumulator=0;
    wire [32:0] sum={1'b0,accumulator}+{1'b0,RASTER_STEP};
    reg raster_tick=0;
    reg [9:0] x=0;
    reg [8:0] y=0;
    reg native_hs_n=1,native_fs_n=1,native_hborder_irq_n=1;
    reg native_vborder_irq_n=1;
    reg native_hblank=1,native_vblank=1;
    // The body is positioned inside the 240 visible raster lines, not the
    // complete 262.5-line field.  The omitted vertical-blank interval is
    // where HDMI is also outside its 480-line visible area.  Centering in
    // all 262 lines delayed HBORD-relative raster effects by 10-11 native
    // lines (most visibly BOINK in the non-standard 225-line mode).
    wire [8:0] live_top=video_50hz ?
        (active_height==8'd225 ? 9'd31 :
         active_height==8'd199 ? 9'd44 : 9'd48) :
        (active_height==8'd225 ? 9'd8 :
         active_height==8'd199 ? 9'd23 : 9'd24);
    wire [8:0] native_top = live_top;
    wire [8:0] native_bottom=native_top+active_height;
    // XRoar's default CoCo 3 is the 1986 GIME. Its HBORD interrupt position
    // is derived from the mode-dependent horizontal timing, relative to HS
    // falling, rather than from the HDMI picture's fixed right edge. The
    // 1986 GIME uses 80 HS clocks, a mode-dependent back porch/left border,
    // and a 512- or 640-clock active area.
    wire timing_hr2 = compatibility_mode ? 1'b0 : hres[2];
    wire timing_hr0 = compatibility_mode ? 1'b0 : hres[0];
    wire timing_graphics = vmode[7];
    wire [10:0] hb_tbp = timing_hr2 ? 11'd63 :
                              timing_graphics ? 11'd57 : 11'd61;
    wire [10:0] hb_tlb = timing_hr2 ? (timing_hr0 ? 11'd42 : 11'd104) :
                         timing_hr0 ? (timing_graphics ? 11'd48 : 11'd44) :
                                      (timing_graphics ? 11'd110 : 11'd106);
    wire [10:0] hb_taa = timing_hr0 ? 11'd640 : 11'd512;
    wire [10:0] hb_irq_position = 11'd80 + hb_tbp + hb_tlb + hb_taa;
    // 1986 GIME vertical events occur near the start of the left border.
    // XRoar's tHS_VB varies with horizontal resolution and text/graphics.
    wire [9:0] vb_irq_position = timing_hr2 ?
        (timing_hr0 ? 10'd163 : 10'd227) :
        timing_hr0 ? (timing_graphics ? 10'd157 : 10'd161) :
                     (timing_graphics ? 10'd221 : 10'd225);
    // Capture after FF98 writes made early in HBORD (BOINK writes at dot 71),
    // at the same left-border point used by XRoar's field trace.
    assign trace_line_sample=raster_tick && x==10'd200;
    assign trace_active_line=y<9'd7 ? y[7:0] :
        y<native_top ? y-9'd7 :
        y<native_bottom ? y-native_top : y-native_bottom;
    assign trace_phase=y<9'd7 ? 2'd0 :
        y>=native_top && y<native_bottom ? 2'd2 : 2'd1;
    reg hdmi_frame_meta=0,hdmi_frame_sync=0,hdmi_frame_prev=0;
    reg hdmi_50_meta=0,hdmi_50_sync=0;
    reg video_50hz_prev=0,standard_60_resync_pending=0;
    // A cold 60 Hz start has a fixed phase relative to HDMI, but it is not
    // necessarily native x/y zero at the HDMI frame marker. Preserve that
    // observed phase before the first 50 Hz field so 50->60 restores the
    // working cold alignment instead of shifting the picture by ~18 rows.
    reg standard_50_seen=0,standard_60_phase_valid=0;
    reg [9:0] standard_60_phase_x=0;
    reg [8:0] standard_60_phase_y=0;
    wire hdmi_frame_rise=hdmi_frame_sync&&!hdmi_frame_prev;
    wire [9:0] line_last_dot = 10'd909;
    wire [9:0] half_line_dot = 10'd454;
    // H50 may change at any point in the field.  Keep the current field's
    // terminal until it wraps; using the live register here can make the
    // terminal unreachable when 50 Hz is cleared below line 262.
    reg native_field_50hz=0;
    wire [8:0] frame_last_line = native_field_50hz ? 9'd312 : 9'd262;
    // The CoCo 3 hires path keeps the HDMI-locked 262.5-line raster above.
    // VDG software counts slow E cycles from FS and needs complete 912-tick
    // lines. Run that clock independently so switching to VDG never changes
    // the native raster cadence or BOINK's border interrupts.
    localparam [31:0] COMPATIBILITY_STEP = 32'd569408471;
    reg [31:0] compatibility_accumulator=0;
    wire [32:0] compatibility_sum=
        {1'b0,compatibility_accumulator}+{1'b0,COMPATIBILITY_STEP};
    reg compatibility_raster_tick=0;
    reg [9:0] compatibility_x=0;
    reg [8:0] compatibility_y=0;
    reg [3:0] compatibility_sample_phase=0;
    reg compatibility_hs_n=1,compatibility_fs_n=1;
    reg compatibility_vborder_irq_n=1;
    reg compatibility_hborder_irq_n=1;
    reg compatibility_hblank=1,compatibility_vblank=1;
    wire [8:0] compatibility_top=live_top+9'd16;
    wire [8:0] compatibility_bottom=
        compatibility_top+{1'b0,active_height};
    reg compatibility_field_50hz=0;
    wire [8:0] compatibility_last_line=
        compatibility_field_50hz?9'd311:9'd261;
    localparam [9:0] COMPATIBILITY_SAMPLE_START=10'd230;
    localparam [9:0] COMPATIBILITY_SAMPLE_END=10'd742;
    assign hs_n=compatibility_mode?compatibility_hs_n:native_hs_n;
    assign fs_n=compatibility_mode?compatibility_fs_n:native_fs_n;
    assign hborder_irq_n=compatibility_mode?
        compatibility_hborder_irq_n:native_hborder_irq_n;
    assign vborder_irq_n=compatibility_mode?
        compatibility_vborder_irq_n:native_vborder_irq_n;
    assign hblank=compatibility_mode?compatibility_hblank:native_hblank;
    assign vblank=compatibility_mode?compatibility_vblank:native_vblank;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            accumulator<=0; raster_tick<=0; x<=0; y<=0;
            native_field_50hz<=0;
            hdmi_frame_meta<=0;hdmi_frame_sync<=0;hdmi_frame_prev<=0;
            hdmi_50_meta<=0;hdmi_50_sync<=0;
            video_50hz_prev<=0;standard_60_resync_pending<=0;
            standard_50_seen<=0;standard_60_phase_valid<=0;
            standard_60_phase_x<=0;standard_60_phase_y<=0;
            native_hs_n<=1; native_fs_n<=1;native_hborder_irq_n<=1;
            native_vborder_irq_n<=1;
            native_hblank<=1; native_vblank<=1;
        end else begin
            hdmi_frame_meta<=hdmi_frame_start;
            hdmi_frame_sync<=hdmi_frame_meta;
            hdmi_frame_prev<=hdmi_frame_sync;
            hdmi_50_meta<=hdmi_active_50hz;
            hdmi_50_sync<=hdmi_50_meta;
            video_50hz_prev<=video_50hz;
            if(video_50hz)standard_50_seen<=1'b1;
            if(hdmi_frame_rise&&!video_50hz&&!standard_50_seen)begin
                standard_60_phase_x<=x;
                standard_60_phase_y<=y;
                standard_60_phase_valid<=1'b1;
            end
            if(video_50hz_prev&&!video_50hz)
                standard_60_resync_pending<=1'b1;
            accumulator<=sum[31:0];
            raster_tick<=sum[32];
            if(standard_60_resync_pending&&
                        !video_50hz&&!hdmi_50_sync&&hdmi_frame_rise)begin
                // Finish the 50 Hz field using its latched terminal, then
                // realign this independent raster to the first 480p field.
                // The working cold-start 60 Hz timing is unchanged.
                x<=standard_60_phase_valid ? standard_60_phase_x : 10'd0;
                y<=standard_60_phase_valid ? standard_60_phase_y : 9'd18;
                native_field_50hz<=1'b0;
                standard_60_resync_pending<=1'b0;
            end else if (raster_tick) begin
                // VBORD is the end of the active picture, independent of
                // FS, which remains the external/PIA frame-sync signal.
                native_vborder_irq_n<=!(y==native_bottom && x==vb_irq_position);
                native_hs_n<=x>=10'd64; native_fs_n<=y>=9'd3;
                native_hblank<=x<10'd200 || x>=10'd840;
                native_vblank<=y<native_top || y>=native_bottom;
                // GIME interrupt bits 4/3 are border events, not the raw
                // HSYNC/FSYNC pins. Match the XRoar 1986-GIME HBORD point;
                // its location changes with HRES and graphics/text mode.
                if(x==hb_irq_position)native_hborder_irq_n<=1'b0;
                else if(x==10'd200)native_hborder_irq_n<=1'b1;
                // A 480p frame is 525 HDMI lines, or 262.5 native line
                // periods.  End the final native row after a half-line so
                // FS/HBORD timing has the same frame cadence as scanout.
                // Wrapping at 262 complete lines made the interrupt raster
                // gain half a line on the displayed image every frame.
                if ((y==frame_last_line && x==half_line_dot) ||
                    x>=line_last_dot) begin
                    x<=0;
                    y<=y==frame_last_line ? 0 : y+1'b1;
                    if (y==frame_last_line) begin
                        native_field_50hz<=video_50hz;
                    end
                end else x<=x+1'b1;
            end
        end
    end
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            compatibility_accumulator<=0;
            compatibility_raster_tick<=0;
            compatibility_x<=0;compatibility_y<=0;
            compatibility_field_50hz<=0;
            compatibility_hs_n<=1;compatibility_fs_n<=1;
            compatibility_hborder_irq_n<=1;
            compatibility_vborder_irq_n<=1;
            compatibility_hblank<=1;compatibility_vblank<=1;
            compatibility_sample<=0;compatibility_sample_css<=0;
            compatibility_sample_y<=0;compatibility_sample_byte<=0;
            compatibility_sample_phase<=0;
            compatibility_border_sample<=0;
            compatibility_border_right<=0;
            compatibility_border_y<=0;
            compatibility_border_sample_rgb<=0;
        end else begin
            compatibility_sample<=0;
            compatibility_border_sample<=0;
            compatibility_accumulator<=compatibility_sum[31:0];
            compatibility_raster_tick<=compatibility_sum[32];
            if (compatibility_raster_tick) begin
                compatibility_vborder_irq_n<=
                    !(compatibility_y==compatibility_bottom &&
                      compatibility_x==vb_irq_position);
                compatibility_hs_n<=compatibility_x>=10'd66;
                compatibility_fs_n<=compatibility_y>=9'd3;
                compatibility_hblank<=compatibility_x<10'd200 ||
                                      compatibility_x>=10'd840;
                compatibility_vblank<=compatibility_y<live_top ||
                                      compatibility_y>=live_top+active_height;
                if(compatibility_x==hb_irq_position)
                    compatibility_hborder_irq_n<=0;
                else if(compatibility_x==10'd200)
                    compatibility_hborder_irq_n<=1;
                if(compatibility_mode&&
                   (compatibility_x==10'd200||compatibility_x==10'd840))begin
                    compatibility_border_sample<=1;
                    compatibility_border_right<=compatibility_x==10'd840;
                    compatibility_border_y<=compatibility_y;
                    compatibility_border_sample_rgb<=compatibility_border_rgb;
                end
                if(compatibility_x==COMPATIBILITY_SAMPLE_START)begin
                    compatibility_sample_phase<=0;
                    compatibility_sample_byte<=0;
                    if(compatibility_mode&&compatibility_y>=compatibility_top&&
                       compatibility_y<compatibility_bottom)begin
                        compatibility_sample<=1;
                        compatibility_sample_css<=compatibility_css;
                        compatibility_sample_y<=compatibility_y-compatibility_top;
                    end
                end else if(compatibility_x>COMPATIBILITY_SAMPLE_START&&
                            compatibility_x<COMPATIBILITY_SAMPLE_END)begin
                    if(compatibility_sample_phase==4'd15)begin
                        compatibility_sample_phase<=0;
                        compatibility_sample_byte<=
                            compatibility_sample_byte+1'b1;
                        if(compatibility_mode&&compatibility_y>=compatibility_top&&
                           compatibility_y<compatibility_bottom)begin
                            compatibility_sample<=1;
                            compatibility_sample_css<=compatibility_css;
                            compatibility_sample_y<=compatibility_y-compatibility_top;
                        end
                    end else compatibility_sample_phase<=
                        compatibility_sample_phase+1'b1;
                end
                if(compatibility_x==10'd911)begin
                    compatibility_x<=0;
                    compatibility_y<=compatibility_y==compatibility_last_line?
                                     0:compatibility_y+1'b1;
                    if(compatibility_y==compatibility_last_line)
                        compatibility_field_50hz<=video_50hz;
                end else compatibility_x<=compatibility_x+1'b1;
            end
        end
    end
    assign red={4{pixel_rgb[5:4]}};
    assign green={4{pixel_rgb[3:2]}};
    assign blue={4{pixel_rgb[1:0]}};
    assign debug_raster_y=compatibility_mode?compatibility_y:y;
endmodule
