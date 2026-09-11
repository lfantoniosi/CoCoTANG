module coco_hdmi (
    input logic pixel_clk,
    input logic serial_clk,
    input logic reset,
    input logic high_resolution,
    input logic [5:0] framebuffer_data,
    input logic [5:0] border_rgb,
    input logic [7:0] active_height,
    input logic debug_enable,
    input logic [319:0] debug_data,
    input logic debug_clk,
    input logic debug_log_we,
    input logic [8:0] debug_log_addr,
    input logic [39:0] debug_log_data,
    input logic [8:0] debug_log_count,
    input logic [1:0] debug_log_page,
    input logic [4:0] debug_status,
    output logic [15:0] framebuffer_addr,
    output logic [9:0] source_x,
    output logic [7:0] source_y,
    output logic source_valid,
    output logic [7:0] prefetch_y,
    output logic prefetch_valid,
    output logic tmds_clk_p, output logic tmds_clk_n,
    output logic [2:0] tmds_data_p, output logic [2:0] tmds_data_n
);
    logic [9:0] x, y;
    logic [23:0] framebuffer_rgb;
    logic [23:0] rgb;
    logic [5:0] border_meta, border_pixel;
    logic [7:0] height_meta, height_pixel;
    always_ff @(posedge pixel_clk) begin
        if (reset) begin
            border_meta <= 6'd0;
            border_pixel <= 6'd0;
            height_meta <= 8'd192;
            height_pixel <= 8'd192;
        end else begin
            border_meta <= border_rgb;
            border_pixel <= border_meta;
            height_meta <= active_height;
            height_pixel <= height_meta;
        end
    end

    logic [9:0] picture_top;
    logic [9:0] picture_bottom;
    always_comb begin
        picture_top = (10'd480 - {height_pixel,1'b0}) >> 1;
        picture_bottom = picture_top + {height_pixel,1'b0};
    end

    always_comb begin
        framebuffer_addr = 16'd0;
        source_x = 10'd0;
        source_y = 8'd0;
        source_valid = 1'b0;
        prefetch_y = 8'd0;
        prefetch_valid = 1'b0;
        framebuffer_rgb = 24'd0;
        if (y + 2'd2 >= picture_top && y < picture_bottom) begin
            // Ask for the following source line from the first of the two
            // HDMI scanlines, leaving almost a full 63.5 us to render it.
            prefetch_y = ((y + 2'd2 - picture_top) >> 1);
            prefetch_valid = 1'b1;
        end
        if (x >= (high_resolution ? 10'd40 : 10'd104) &&
            x <  (high_resolution ? 10'd680 : 10'd616) &&
            y >= picture_top && y < picture_bottom) begin
            source_x = high_resolution ? (x - 10'd40) : ((x - 10'd104) >> 1);
            source_y = (y - picture_top) >> 1;
            source_valid = 1'b1;
            framebuffer_addr = (((y - picture_top) >> 1) << 8) +
                               ((x - 10'd104) >> 1);
            framebuffer_rgb = {{4{framebuffer_data[5:4]}},
                               {4{framebuffer_data[3:2]}},
                               {4{framebuffer_data[1:0]}}};
        end else if (x >= 10'd40 && x < 10'd680 && y < 10'd480) begin
            // 32/32 source-pixel side borders.  The 27-line native top and
            // bottom borders are clipped to 24 lines each by 480p.
            framebuffer_rgb = {{4{border_pixel[5:4]}},
                               {4{border_pixel[3:2]}},
                               {4{border_pixel[1:0]}}};
        end
    end

    logic [319:0] debug_pixel = 320'd0;
    logic debug_enable_meta = 1'b0, debug_enable_pixel = 1'b0;
    logic [8:0] debug_count_meta = 9'd0, debug_count_pixel = 9'd0;
    logic [1:0] debug_page_meta = 2'd0, debug_page_pixel = 2'd0;
    logic [4:0] debug_status_meta = 5'd0, debug_status_pixel = 5'd0;
    always_ff @(posedge pixel_clk) begin
        // Bring-up data is held for roughly 0.31 seconds between updates;
        // one diagnostic-only capture avoids a large duplicate register bank.
        debug_pixel <= debug_data;
        debug_enable_meta <= debug_enable;
        debug_enable_pixel <= debug_enable_meta;
        debug_count_meta <= debug_log_count;
        debug_count_pixel <= debug_count_meta;
        debug_page_meta <= debug_log_page;
        debug_page_pixel <= debug_page_meta;
        debug_status_meta <= debug_status;
        debug_status_pixel <= debug_status_meta;
    end
    hdmi_debug_overlay debug_overlay(
        .pixel_clk(pixel_clk), .x(x), .y(y), .enable(debug_enable_pixel),
        .debug_data(debug_pixel),
        .debug_clk(debug_clk), .log_we(debug_log_we),
        .log_addr(debug_log_addr), .log_data(debug_log_data),
        .log_count(debug_count_pixel), .log_page(debug_page_pixel),
        .debug_status(debug_status_pixel),
        .rgb_in(framebuffer_rgb), .rgb_out(rgb)
    );

    logic [15:0] audio_samples [1:0];
    assign audio_samples[0] = 16'd0;
    assign audio_samples[1] = 16'd0;
    logic [9:0] tmds_internal [2:0];
    hdmi #(
        .VIDEO_ID_CODE(2), .DVI_OUTPUT(1'b1), .VIDEO_REFRESH_RATE(60.0),
        .AUDIO_RATE(48000), .AUDIO_BIT_WIDTH(16), .NUM_CHANNELS(3)
    ) hdmi_encoder (
        .clk_pixel_x5(serial_clk), .clk_pixel(pixel_clk), .clk_audio(pixel_clk),
        .reset(reset), .rgb(rgb), .audio_sample_word(audio_samples),
        .cx(x), .cy(y), .frame_width(), .frame_height(),
        .screen_width(), .screen_height(), .tmds_internal(tmds_internal)
    );
    logic [2:0] tmds;
    logic unused_clock;
    serializer #(.NUM_CHANNELS(3), .VIDEO_RATE(0)) serializer_inst (
        .clk_pixel(pixel_clk), .clk_pixel_x5(serial_clk), .reset(reset),
        .tmds_internal(tmds_internal), .tmds(tmds), .tmds_clock(unused_clock)
    );
    ELVDS_OBUF output_buffers [3:0] (
        .I({pixel_clk,tmds}), .O({tmds_clk_p,tmds_data_p}),
        .OB({tmds_clk_n,tmds_data_n})
    );
endmodule
