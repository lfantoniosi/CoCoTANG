// 720x480 DVI output for the restored 256x192 VDG framebuffer. The CPU bus
// logger remains available as an optional bring-up overlay.
module cpu_test_hdmi #(
    parameter integer LOG_ADDR_WIDTH = 12,
    parameter integer LOG_COUNT_WIDTH = 13,
    parameter integer LOG_PAGE_WIDTH = 6,
    parameter integer LOG_DEPTH = 4096
) (
    input logic pixel_clk,
    input logic serial_clk,
    input logic reset,
    input logic debug_clk,
    input logic log_we,
    input logic [LOG_ADDR_WIDTH-1:0] log_addr,
    input logic [39:0] log_data,
    input logic [LOG_COUNT_WIDTH-1:0] log_count,
    input logic [LOG_PAGE_WIDTH-1:0] log_page,
    input logic [4:0] debug_status,
    input logic overlay_enable,
    input logic [5:0] framebuffer_data,
    input logic [5:0] border_rgb,
    output logic [15:0] framebuffer_addr,
    output logic tmds_clk_p,
    output logic tmds_clk_n,
    output logic [2:0] tmds_data_p,
    output logic [2:0] tmds_data_n
);
    logic [9:0] x,y;
    logic [7:0] framebuffer_x,framebuffer_y;
    logic [8:0] scaled_x,scaled_y;
    logic [23:0] framebuffer_rgb;
    logic [23:0] rgb;
    always_comb begin
        framebuffer_addr=16'd0;
        framebuffer_x=8'd0;
        framebuffer_y=8'd0;
        scaled_x=9'd0;
        scaled_y=9'd0;
        framebuffer_rgb={{4{border_rgb[5:4]}},
                         {4{border_rgb[3:2]}},
                         {4{border_rgb[1:0]}}};
        if (x >= 10'd104 && x < 10'd616 && y >= 10'd48 && y < 10'd432) begin
            scaled_x=(x-10'd104) >> 1;
            scaled_y=(y-10'd48) >> 1;
            framebuffer_x=scaled_x[7:0];
            framebuffer_y=scaled_y[7:0];
            framebuffer_addr={framebuffer_y,framebuffer_x};
            framebuffer_rgb={{4{framebuffer_data[5:4]}},
                             {4{framebuffer_data[3:2]}},
                             {4{framebuffer_data[1:0]}}};
        end
    end
    hdmi_debug_overlay #(
        .LOG_ADDR_WIDTH(LOG_ADDR_WIDTH),
        .LOG_COUNT_WIDTH(LOG_COUNT_WIDTH),
        .LOG_PAGE_WIDTH(LOG_PAGE_WIDTH),
        .LOG_DEPTH(LOG_DEPTH),
        .EXTENDED_HEADER(1)
    ) overlay (
        .pixel_clk(pixel_clk), .x(x), .y(y), .enable(overlay_enable),
        .debug_data(320'd0), .debug_clk(debug_clk), .log_we(log_we),
        .log_addr(log_addr), .log_data(log_data), .log_count(log_count),
        .log_page(log_page), .debug_status(debug_status),
        .rgb_in(framebuffer_rgb), .rgb_out(rgb)
    );

    logic [15:0] audio_samples [1:0];
    assign audio_samples[0]=16'd0;
    assign audio_samples[1]=16'd0;
    logic [9:0] tmds_internal [2:0];
    hdmi #(
        .VIDEO_ID_CODE(2), .DVI_OUTPUT(1'b1), .VIDEO_REFRESH_RATE(60.0),
        .AUDIO_RATE(48000), .AUDIO_BIT_WIDTH(16), .NUM_CHANNELS(3)
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
