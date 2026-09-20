module gime_native_video (
    input clk, input reset_n, input [7:0] active_height,
    input [5:0] pixel_rgb,
    output reg hs_n, output reg fs_n, output reg hblank, output reg vblank,
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
    wire [8:0] top=(9'd262-{1'b0,active_height})>>1;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            accumulator<=0; raster_tick<=0; x<=0; y<=0;
            hs_n<=1; fs_n<=1; hblank<=1; vblank<=1;
        end else begin
            accumulator<=sum[31:0];
            raster_tick<=sum[32];
            if (raster_tick) begin
                hs_n<=x>=10'd64; fs_n<=y>=9'd3;
                hblank<=x<10'd200 || x>=10'd840;
                vblank<=y<top || y>=top+active_height;
                // A 480p frame is 525 HDMI lines, or 262.5 native line
                // periods.  End the final native row after a half-line so
                // FS/HBORD timing has the same frame cadence as scanout.
                // Wrapping at 262 complete lines made the interrupt raster
                // gain half a line on the displayed image every frame.
                if ((y==9'd262 && x==10'd454) || x==10'd909) begin
                    x<=0;
                    y<=y==9'd262 ? 0 : y+1'b1;
                end else x<=x+1'b1;
            end
        end
    end
    assign red={4{pixel_rgb[5:4]}};
    assign green={4{pixel_rgb[3:2]}};
    assign blue={4{pixel_rgb[1:0]}};
endmodule
