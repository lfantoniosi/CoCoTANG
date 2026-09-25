module gime_native_video #(
    parameter integer PAL_MACHINE = 0
) (
    input clk, input reset_n, input video_50hz, input [7:0] active_height,
    input [5:0] pixel_rgb,
    output reg hs_n, output reg fs_n, output reg hborder_irq_n,
    output reg hblank, output reg vblank,
    output [8:0] debug_raster_y,
    output [7:0] red, output [7:0] green, output [7:0] blue
);
    // 910 GIME dots occupy exactly two 858-dot 27 MHz HDMI lines.  With the
    // 108 MHz system clock the native dot-rate ratio is therefore 35/264.
    // Keeping that exact relationship prevents the CPU-visible raster IRQs
    // from walking horizontally through the independently scanned picture.
    // The physical PAL CoCo uses 28.475 MHz / 2 here (about 15.611 kHz), but
    // this renderer currently shares rows with exact-50-Hz HDMI. Keep the
    // producer on the 14.250 MHz cache cadence until PAL has its own renderer;
    // otherwise the consumers separate and component/CVBS blank.
    localparam [31:0] RASTER_STEP = PAL_MACHINE ?
        32'd566697074 : 32'd569408543;
    reg [31:0] accumulator=0;
    wire [32:0] sum={1'b0,accumulator}+{1'b0,RASTER_STEP};
    reg raster_tick=0;
    reg [9:0] x=0;
    reg [8:0] y=0;
    // The body is positioned inside the 240 visible raster lines, not the
    // complete 262.5-line field.  The omitted vertical-blank interval is
    // where HDMI is also outside its 480-line visible area.  Centering in
    // all 262 lines delayed HBORD-relative raster effects by 10-11 native
    // lines (most visibly BOINK in the non-standard 225-line mode).
    wire [8:0] top=video_50hz ?
        (active_height==8'd225 ? 9'd31 :
         active_height==8'd199 ? 9'd44 : 9'd48) :
        (active_height==8'd225 ? 9'd8 :
         active_height==8'd199 ? 9'd23 : 9'd25);
    wire [9:0] line_last_dot = PAL_MACHINE ? 10'd911 : 10'd909;
    wire [9:0] half_line_dot = PAL_MACHINE ? 10'd455 : 10'd454;
    wire [8:0] frame_last_line = video_50hz ? 9'd312 : 9'd262;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            accumulator<=0; raster_tick<=0; x<=0; y<=0;
            hs_n<=1; fs_n<=1;hborder_irq_n<=1;
            hblank<=1; vblank<=1;
        end else begin
            accumulator<=sum[31:0];
            raster_tick<=sum[32];
            if (raster_tick) begin
                hs_n<=x>=10'd64; fs_n<=y>=9'd3;
                hblank<=x<10'd200 || x>=10'd840;
                vblank<=y<top || y>=top+active_height;
                // GIME interrupt bits 4/3 are border events, not the raw
                // HSYNC/FSYNC pins. HBORD asserts one 1.79 MHz CPU cycle
                // before the 640-dot body ends and releases at body start.
                if(x==10'd830)hborder_irq_n<=1'b0;
                else if(x==10'd200)hborder_irq_n<=1'b1;
                // A 480p frame is 525 HDMI lines, or 262.5 native line
                // periods.  End the final native row after a half-line so
                // FS/HBORD timing has the same frame cadence as scanout.
                // Wrapping at 262 complete lines made the interrupt raster
                // gain half a line on the displayed image every frame.
                if ((y==frame_last_line && x==half_line_dot) ||
                    x==line_last_dot) begin
                    x<=0;
                    y<=y==frame_last_line ? 0 : y+1'b1;
                end else x<=x+1'b1;
            end
        end
    end
    assign red={4{pixel_rgb[5:4]}};
    assign green={4{pixel_rgb[3:2]}};
    assign blue={4{pixel_rgb[1:0]}};
    assign debug_raster_y=y;
endmodule
