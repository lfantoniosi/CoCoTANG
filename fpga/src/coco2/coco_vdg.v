module coco_vdg #(
    parameter integer DEBUG_VIDEO_MODE = 0,
    parameter integer ENABLE_ARTIFACT_COLOR = 0,
    // The MC6847 core always renders its native stream and stores one line.
    // Select 0 for native RGB or 1 for the line-buffered, scan-doubled RGB
    // output used by a 480p display.  The cvbs port remains the native stream.
    parameter integer SCAN_DOUBLED_OUTPUT = 0
) (
    input clk,
    input reset_n,
    input bus_reset_n,
    input sam_tick,
    input e_fall,
    input cpu_rw_n,
    input [15:0] cpu_addr,
    input [7:0] cpu_data,
    input [2:0] sam_video_mode,
    input debug_an_g,
    input debug_css,
    input [6:0] sam_video_offset,
    input [7:0] memory_data,
    output [15:0] memory_addr,
    output hs_n,
    output fs_n,
    output [7:0] red,
    output [7:0] green,
    output [7:0] blue,
    output [5:0] border_rgb,
    output hblank,
    output vblank,
    output row_prefetch,
    output [7:0] cvbs,
    output reg [5:0] native_rgb,
    output reg pixel_capture,
    output reg [15:0] capture_addr,
    output reg [5:0] capture_rgb
);
    // The real MC6847 and SAM share the 14.31818 MHz master cadence.  Do not
    // run an independent video NCO: using the SAM tick keeps every VDG byte
    // boundary at a deterministic phase of the CPU E/Q cycle.
    wire vdg_enable = sam_tick;

    // Shadow PIA1 port B so A/G, INT/EXT and CSS remain available even
    // though those physical MC6847 pins are not routed to the FPGA.
    reg [7:0] pia1_pb = 8'd0;
    reg [7:0] pia1_ddrb = 8'd0;
    reg [7:0] pia1_crb = 8'd0;
    // The renderer is deliberately released on an HDMI frame boundary, but
    // PIA initialization starts as soon as the CPU runs.  Keep this shadow in
    // the board-reset domain so early DDR/data writes are not discarded while
    // the MC6847 timing core is still held reset.
    always @(posedge clk or negedge bus_reset_n) begin
        if (!bus_reset_n) begin
            pia1_pb <= 8'd0;
            pia1_ddrb <= 8'd0;
            pia1_crb <= 8'd0;
        end else if (e_fall && !cpu_rw_n) begin
            if (cpu_addr == 16'hff23)
                pia1_crb <= cpu_data;
            else if (cpu_addr == 16'hff22) begin
                if (pia1_crb[2]) pia1_pb <= cpu_data;
                else pia1_ddrb <= cpu_data;
            end
        end
    end
    wire [7:0] pia1_effective = pia1_pb & pia1_ddrb;
    wire effective_an_g = DEBUG_VIDEO_MODE ? debug_an_g : pia1_effective[7];
    wire effective_css = DEBUG_VIDEO_MODE ? debug_css : pia1_effective[3];
    // The MC6847 graphics border is green in color set 0 and buff/white in
    // color set 1.  Alpha modes use a black border.
    assign border_rgb = effective_an_g ?
                        (effective_css ? 6'b111111 : 6'b001100) : 6'b000000;

    wire da0;
    wire [12:0] video_address;
    reg [6:0] video_offset_pipe = 7'd0;
    wire [10:0] char_address;
    wire [7:0] char_data;
    wire unused_hsync, unused_vsync;
    mc6847_char_rom character_rom (
        .clk(clk), .addr(char_address), .data(char_data)
    );

    // SAM's display offset changes only through its memory-mapped control
    // registers. Register it locally so that the offset adder is not fed by
    // the long SAM-register route on every video-cache lookup.
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            video_offset_pipe <= 7'd0;
        else
            video_offset_pipe <= sam_video_offset;
    end

    mc6847 #(.CVBS_NOT_VGA(SCAN_DOUBLED_OUTPUT == 0)) vdg (
        .clk(clk), .clk_ena(vdg_enable), .reset(!reset_n),
        .da0(da0), .videoaddr(video_address), .dd(memory_data),
        .hs_n(hs_n), .fs_n(fs_n),
        .an_g(effective_an_g), .an_s(memory_data[7]),
        // PIA1 PB6:PB4 directly drive the physical MC6847 GM2:GM0 pins.
        // The SAM mode is programmed separately to select the matching memory
        // geometry (PMODE 3 and PMODE 4 both use SAM mode 110).
        .intn_ext(pia1_effective[4]),
        .gm(pia1_effective[6:4]),
        .css(effective_css), .inv(memory_data[6]),
        .red(red), .green(green), .blue(blue),
        .hsync(unused_hsync), .vsync(unused_vsync),
        .hblank(hblank), .vblank(vblank), .row_prefetch(row_prefetch),
        // When artifact colour is disabled, CSS selects black/green
        // (SCREEN 1,0) or black/white (SCREEN 1,1).
        .artifact_en(ENABLE_ARTIFACT_COLOR != 0),
        .artifact_set(1'b0), .artifact_phase(1'b0),
        .cvbs(cvbs), .black_backgnd(1'b0),
        .char_a(char_address), .char_d_o(char_data)
    );
    assign memory_addr = {video_offset_pipe,9'b0} + {3'b000,video_address};

    // Decode the native MC6847 pixel token independently of the selected RGB
    // output.  This lets CVBS consume the native 15.7 kHz stream while HDMI
    // consumes the core's scan-doubled stream, without a full-frame store.
    // Active tokens are {0,CSS,A/G,A/S,LUMA,CHROMA[2:0]}.
    always @(*) begin
        native_rgb = 6'b000000;
        if (hs_n && fs_n) begin
            if (cvbs[3]) begin
                case (cvbs[2:0])
                    3'd0: native_rgb = 6'b001100; // green
                    3'd1: native_rgb = 6'b111100; // yellow
                    3'd2: native_rgb = 6'b000011; // blue
                    3'd3: native_rgb = 6'b110000; // red
                    3'd4: native_rgb = 6'b111111; // white
                    3'd5: native_rgb = 6'b001111; // cyan
                    3'd6: native_rgb = 6'b110011; // magenta
                    default: native_rgb = 6'b111000; // orange
                endcase
            end else if (!cvbs[5] && !cvbs[4]) begin
                // MC6847's dark alpha background (green or orange).
                native_rgb = {1'b0,cvbs[6],2'b01,2'b00};
            end
        end
    end

    reg pixel_half = 1'b0;
    reg prior_hblank = 1'b1;
    reg prior_vblank = 1'b1;
    reg [7:0] capture_x = 8'd0;
    reg [7:0] capture_y = 8'd0;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            pixel_half <= 1'b0;
            prior_hblank <= 1'b1;
            prior_vblank <= 1'b1;
            capture_x <= 8'd0;
            capture_y <= 8'd0;
            pixel_capture <= 1'b0;
            capture_addr <= 16'd0;
            capture_rgb <= 6'd0;
        end else begin
            pixel_capture <= 1'b0;
            if (vdg_enable) begin
                pixel_half <= !pixel_half;
                if (pixel_half) begin
                    prior_hblank <= hblank;
                    prior_vblank <= vblank;
                    if (vblank) begin
                        capture_x <= 8'd0;
                        capture_y <= 8'd0;
                    end else if (hblank) begin
                        capture_x <= 8'd0;
                        if (!prior_hblank && capture_y != 8'd191)
                            capture_y <= capture_y + 1'b1;
                    end else begin
                        if (capture_x < 8'd255) capture_x <= capture_x + 1'b1;
                        if (capture_y < 8'd192) begin
                            capture_addr <= {capture_y,capture_x};
                            capture_rgb <= {red[7:6],green[7:6],blue[7:6]};
                            pixel_capture <= 1'b1;
                        end
                    end
                end
            end
        end
    end
endmodule
