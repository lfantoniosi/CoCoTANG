module coco_vdg #(
    parameter integer DEBUG_VIDEO_MODE = 0
) (
    input clk,
    input reset_n,
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
    output [7:0] cvbs,
    output reg pixel_capture,
    output reg [15:0] capture_addr,
    output reg [5:0] capture_rgb
);
    // This MC6847 core's 400-dot horizontal timing table is designed for a
    // 12.571428 MHz enable (32 MHz * 11 / 28), not the SAM's 14.31818 MHz
    // master rate.  The core divides this enable by two for its native scan,
    // producing about 15.714 kHz lines and 59.978 Hz frames.  Keeping this
    // NCO separate from the SAM also leaves E/Q at the physical CPU rate.
    localparam [23:0] VDG_STEP = 24'd1952903;
    reg [23:0] accumulator = 24'd0;
    reg vdg_enable_reg = 1'b0;
    wire [24:0] accumulator_sum = {1'b0,accumulator} + {1'b0,VDG_STEP};
    wire vdg_enable = vdg_enable_reg;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            accumulator <= 24'd0;
            vdg_enable_reg <= 1'b0;
        end else begin
            accumulator <= accumulator_sum[23:0];
            // Register the carry before it fans out through the MC6847 and
            // framebuffer capture logic. This changes only the fixed startup
            // phase by one clk108 tick, not the VDG rate.
            vdg_enable_reg <= accumulator_sum[24];
        end
    end

    // Shadow PIA1 port B so A/G, INT/EXT and CSS remain available even
    // though those physical MC6847 pins are not routed to the FPGA.
    reg [7:0] pia1_pb = 8'd0;
    reg [7:0] pia1_ddrb = 8'd0;
    reg [7:0] pia1_crb = 8'd0;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
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
    wire [10:0] char_address;
    wire [7:0] char_data;
    wire unused_hsync, unused_vsync;
    mc6847_char_rom character_rom (
        .clk(clk), .addr(char_address), .data(char_data)
    );

    mc6847 #(.CVBS_NOT_VGA(1'b1)) vdg (
        .clk(clk), .clk_ena(vdg_enable), .reset(!reset_n),
        .da0(da0), .videoaddr(video_address), .dd(memory_data),
        .hs_n(hs_n), .fs_n(fs_n),
        .an_g(effective_an_g), .an_s(memory_data[7]),
        .intn_ext(pia1_effective[4]), .gm(sam_video_mode),
        .css(effective_css), .inv(memory_data[6]),
        .red(red), .green(green), .blue(blue),
        .hsync(unused_hsync), .vsync(unused_vsync),
        .hblank(hblank), .vblank(vblank),
        .artifact_en(1'b1), .artifact_set(1'b0), .artifact_phase(1'b0),
        .cvbs(cvbs), .black_backgnd(1'b0),
        .char_a(char_address), .char_d_o(char_data)
    );
    assign memory_addr = {sam_video_offset,9'b0} + {3'b000,video_address};

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
