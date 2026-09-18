// 720x480 DVI output sampled directly from the MC6847 scan-doubled stream.
// The source and DVI line rates are identical; no full-frame store is used.
// The CPU bus logger remains available as an optional bring-up overlay.
module coco_hdmi #(
    parameter integer LOG_ADDR_WIDTH = 12,
    parameter integer LOG_COUNT_WIDTH = 13,
    parameter integer LOG_PAGE_WIDTH = 6,
    parameter integer LOG_DEPTH = 4096,
    parameter integer ENABLE_DEBUG_OVERLAY = 1
) (
    input logic pixel_clk,
    input logic serial_clk,
    input logic reset,
    input logic vdg_clk,
    input logic vdg_pixel_tick,
    input logic debug_clk,
    input logic log_we,
    input logic [LOG_ADDR_WIDTH-1:0] log_addr,
    input logic [39:0] log_data,
    input logic [LOG_COUNT_WIDTH-1:0] log_count,
    input logic [LOG_PAGE_WIDTH-1:0] log_page,
    input logic [4:0] debug_status,
    input logic overlay_enable,
    input logic [7:0] vdg_red,
    input logic [7:0] vdg_green,
    input logic [7:0] vdg_blue,
    input logic vdg_hblank,
    input logic vdg_vblank,
    output logic tmds_clk_p,
    output logic tmds_clk_n,
    output logic [2:0] tmds_data_p,
    output logic [2:0] tmds_data_n,
    output logic vdg_start
);
    logic [9:0] x,y;
    // A complete MC6847 visible/border line is 371 master pixels.  Capture it
    // into alternating halves of a dual-clock line store.  Directly sampling
    // RGB here made the left edge depend on the phase between the 108 MHz and
    // 27 MHz PLLs and allowed pixel transitions to flicker by one HDMI pixel.
    logic [5:0] line_memory [0:1023];
    logic write_bank = 1'b0;
    logic complete_bank = 1'b0;
    logic prior_vdg_hblank = 1'b1;
    logic [8:0] write_x = 9'd0;
    always_ff @(posedge vdg_clk) begin
        if (reset) begin
            write_bank <= 1'b0;
            complete_bank <= 1'b0;
            prior_vdg_hblank <= 1'b1;
            write_x <= 9'd0;
        end else if (vdg_pixel_tick) begin
            prior_vdg_hblank <= vdg_hblank;
            if (!vdg_hblank) begin
                if (prior_vdg_hblank) begin
                    write_x <= 9'd1;
                    line_memory[{write_bank,9'd0}] <=
                        {vdg_red[7:6],vdg_green[7:6],vdg_blue[7:6]};
                end else if (write_x < 9'd371) begin
                    line_memory[{write_bank,write_x}] <=
                        {vdg_red[7:6],vdg_green[7:6],vdg_blue[7:6]};
                    write_x <= write_x + 1'b1;
                end
            end else if (!prior_vdg_hblank) begin
                complete_bank <= write_bank;
                write_bank <= !write_bank;
                write_x <= 9'd0;
            end
        end
    end

    logic complete_bank_meta = 1'b0;
    logic complete_bank_sync = 1'b0;
    logic display_bank = 1'b0;
    logic [8:0] line_read_addr = 9'd0;
    logic [5:0] line_rgb = 6'd0;
    logic line_active = 1'b0;
    logic [23:0] stream_rgb;
    logic [23:0] rgb;
    // Start the VDG 38 lines before HDMI wraps.  Its native reset-to-active
    // interval then places the 384 active scan-doubled lines near the vertical
    // center, without changing the VDG or memory timing after release.
    assign vdg_start = (x == 10'd0) && (y == 10'd487);

    // Display 350 centered source pixels at exactly 2x, cropping 10/11 pixels
    // from the MC6847 border.  This keeps every text stroke the same width.
    // Select the finished bank during horizontal blanking so the CDC cannot
    // change buffers part-way through a displayed line.
    always_ff @(posedge pixel_clk) begin
        if (reset) begin
            complete_bank_meta <= 1'b0;
            complete_bank_sync <= 1'b0;
            display_bank <= 1'b0;
            line_read_addr <= 9'd0;
            line_rgb <= 6'd0;
            line_active <= 1'b0;
        end else begin
            complete_bank_meta <= complete_bank;
            complete_bank_sync <= complete_bank_meta;
            if (x == 10'd800)
                display_bank <= complete_bank_sync;

            line_rgb <= line_memory[{display_bank,line_read_addr}];
            line_active <= (x >= 10'd10) && (x < 10'd710);
            if (x == 10'd7) begin
                line_read_addr <= 9'd10;
            end else if (x >= 10'd9 && x < 10'd709) begin
                // Advance after the first pixel of each pair.  The
                // synchronous line-memory read then presents each source
                // pixel for exactly two consecutive HDMI clocks.
                if ((x >= 10'd10) && !x[0] &&
                    (line_read_addr < 9'd359))
                    line_read_addr <= line_read_addr + 1'b1;
            end
        end
    end
    assign stream_rgb = line_active ?
                        {{4{line_rgb[5:4]}},{4{line_rgb[3:2]}},
                         {4{line_rgb[1:0]}}} : 24'd0;

    // START_X makes the first HDMI x=0 transition approximately coincide
    // with the VDG left border.  Never reset the encoder once running: even a
    // one-pixel reset every VDG field breaks the fixed 858x525 TMDS cadence
    // and prevents some monitors from locking.
    generate
        if (ENABLE_DEBUG_OVERLAY != 0) begin : debug_overlay_enabled
            hdmi_debug_overlay #(
                .LOG_ADDR_WIDTH(LOG_ADDR_WIDTH),
                .LOG_COUNT_WIDTH(LOG_COUNT_WIDTH),
                .LOG_PAGE_WIDTH(LOG_PAGE_WIDTH),
                .LOG_DEPTH(LOG_DEPTH),
                .EXTENDED_HEADER(1)
            ) overlay (
                .pixel_clk(pixel_clk), .x(x), .y(y),
                .enable(overlay_enable), .debug_data(320'd0),
                .debug_clk(debug_clk), .log_we(log_we),
                .log_addr(log_addr), .log_data(log_data),
                .log_count(log_count), .log_page(log_page),
                .debug_status(debug_status),
                .interrupt_status(4'b0000),
                .rom_verify_done(1'b0), .rom_verify_pass(1'b0),
                .rom_verify_vector(16'hffff),
                .sdram_test_done(1'b0),.sdram_test_pass(1'b0),
                .sdram_test_error_addr(16'h0000),
                .sdram_test_expected(8'h00),.sdram_test_actual(8'h00),
                .rgb_in(stream_rgb),
                .rgb_out(rgb)
            );
        end else begin : debug_overlay_disabled
            assign rgb=stream_rgb;
        end
    endgenerate

    logic [15:0] audio_samples [1:0];
    assign audio_samples[0]=16'd0;
    assign audio_samples[1]=16'd0;
    logic [9:0] tmds_internal [2:0];
    hdmi #(
        .VIDEO_ID_CODE(2), .DVI_OUTPUT(1'b1), .VIDEO_REFRESH_RATE(60.0),
        .AUDIO_RATE(48000), .AUDIO_BIT_WIDTH(16), .NUM_CHANNELS(3),
        .START_X(0), .START_Y(0)
    ) encoder (
        .clk_pixel_x5(serial_clk), .clk_pixel(pixel_clk),
        .clk_audio(pixel_clk), .reset(reset), .rgb(rgb),
        .audio_sample_word(audio_samples), .cx(x), .cy(y),
        .frame_width(), .frame_height(), .screen_width(), .screen_height(),
        .tmds_internal(tmds_internal)
    );

    logic [2:0] tmds;
    logic unused_clock;
    serializer #(.NUM_CHANNELS(3),.VIDEO_RATE(0)) serializer_inst (
        .clk_pixel(pixel_clk), .clk_pixel_x5(serial_clk), .reset(reset),
        .tmds_internal(tmds_internal), .tmds(tmds),
        .tmds_clock(unused_clock)
    );
    ELVDS_OBUF output_buffers [3:0] (
        .I({pixel_clk,tmds}), .O({tmds_clk_p,tmds_data_p}),
        .OB({tmds_clk_n,tmds_data_n})
    );
endmodule
