// 720x480 DVI scanout for the CoCo 3 line cache.  Native GIME lines are 640
// pixels wide and are centered without a framebuffer or horizontal scaling.
module coco3_hdmi #(
    parameter integer LOG_ADDR_WIDTH=12,
    parameter integer LOG_COUNT_WIDTH=13,
    parameter integer LOG_PAGE_WIDTH=6,
    parameter integer LOG_DEPTH=4096,
    parameter integer ENABLE_DEBUG_OVERLAY=0
) (
    input logic pixel_clk,input logic serial_clk,input logic reset,
    input logic debug_clk,input logic log_we,
    input logic [LOG_ADDR_WIDTH-1:0] log_addr,input logic [39:0] log_data,
    input logic [LOG_COUNT_WIDTH-1:0] log_count,
    input logic [LOG_PAGE_WIDTH-1:0] log_page,
    input logic [4:0] debug_status,input logic overlay_enable,
    input logic [3:0] interrupt_status,
    input logic rom_verify_done,input logic rom_verify_pass,
    input logic [15:0] rom_verify_vector,
    input logic sdram_test_done,input logic sdram_test_pass,
    input logic [15:0] sdram_test_error_addr,
    input logic [7:0] sdram_test_expected,input logic [7:0] sdram_test_actual,
    input logic [7:0] active_height,input logic compatibility_mode,
    input logic [5:0] border_rgb,
    input logic [5:0] pixel_data,
    output logic [9:0] source_x,output logic [7:0] source_y,
    output logic source_valid,output logic [7:0] prefetch_y,
    output logic prefetch_valid,
    output logic tmds_clk_p,output logic tmds_clk_n,
    output logic [2:0] tmds_data_p,output logic [2:0] tmds_data_n
);
    logic [9:0] x,y;
    logic [7:0] height_m=8'd192,height_s=8'd192;
    logic compatibility_m=1'b1,compatibility_s=1'b1;
    logic rom_done_m=0,rom_done_s=0,rom_pass_m=0,rom_pass_s=0;
    logic [15:0] rom_vector_m=16'hffff,rom_vector_s=16'hffff;
    logic ram_done_m=0,ram_done_s=0,ram_pass_m=0,ram_pass_s=0;
    logic [15:0] ram_addr_m=0,ram_addr_s=0;
    logic [7:0] ram_expected_m=0,ram_expected_s=0;
    logic [7:0] ram_actual_m=0,ram_actual_s=0;
    logic [3:0] interrupt_m=0,interrupt_s=0;
    logic [9:0] top,doubled_height,picture_width,picture_lead;
    logic [9:0] source_line,next_source_line;
    always_ff @(posedge pixel_clk) begin
        height_m<=active_height;
        height_s<=height_m;
        compatibility_m<=compatibility_mode;
        compatibility_s<=compatibility_m;
        rom_done_m<=rom_verify_done; rom_done_s<=rom_done_m;
        rom_pass_m<=rom_verify_pass; rom_pass_s<=rom_pass_m;
        rom_vector_m<=rom_verify_vector; rom_vector_s<=rom_vector_m;
        ram_done_m<=sdram_test_done; ram_done_s<=ram_done_m;
        ram_pass_m<=sdram_test_pass; ram_pass_s<=ram_pass_m;
        ram_addr_m<=sdram_test_error_addr; ram_addr_s<=ram_addr_m;
        ram_expected_m<=sdram_test_expected; ram_expected_s<=ram_expected_m;
        ram_actual_m<=sdram_test_actual; ram_actual_s<=ram_actual_m;
        interrupt_m<=interrupt_status; interrupt_s<=interrupt_m;
    end
    always_comb begin
        doubled_height={1'b0,height_s,1'b0};
        top=(10'd480-doubled_height)>>1;
        picture_width=compatibility_s ? 10'd512 : 10'd640;
        picture_lead=((10'd720-picture_width)>>1)-1'b1;
        source_line=(y>=top) ? ((y-top)>>1) : 10'd0;
        next_source_line=(y+1'b1>=top) ? ((y+1'b1-top)>>1) : 10'd0;
    end

    // Lead the visible window by one clock for the synchronous line RAM.
    always_comb begin
        source_valid=(x>=picture_lead && x<picture_lead+picture_width &&
                      y>=top && y<top+doubled_height);
        source_x=source_valid ? x-picture_lead : 10'd0;
        source_y=source_line[7:0];
        prefetch_y=next_source_line[7:0];
        prefetch_valid=(y+1'b1>=top && y+1'b1<top+doubled_height);
    end

    logic picture_d=0;
    logic [5:0] border_d=0;
    logic [23:0] stream_rgb,rgb;
    always_ff @(posedge pixel_clk) begin
        picture_d<=source_valid;
        border_d<=border_rgb;
    end
    wire [5:0] selected_rgb=picture_d ? pixel_data : border_d;
    assign stream_rgb={{4{selected_rgb[5:4]}},{4{selected_rgb[3:2]}},
                       {4{selected_rgb[1:0]}}};

    generate if (ENABLE_DEBUG_OVERLAY!=0) begin:overlay_enabled
        hdmi_debug_overlay #(
            .LOG_ADDR_WIDTH(LOG_ADDR_WIDTH),.LOG_COUNT_WIDTH(LOG_COUNT_WIDTH),
            .LOG_PAGE_WIDTH(LOG_PAGE_WIDTH),.LOG_DEPTH(LOG_DEPTH),
            .EXTENDED_HEADER(2)) overlay(
            .pixel_clk(pixel_clk),.x(x),.y(y),.enable(overlay_enable),
            .debug_data(320'd0),.debug_clk(debug_clk),.log_we(log_we),
            .log_addr(log_addr),.log_data(log_data),.log_count(log_count),
            .log_page(log_page),.debug_status(debug_status),
            .interrupt_status(interrupt_s),
            .rom_verify_done(rom_done_s),.rom_verify_pass(rom_pass_s),
            .rom_verify_vector(rom_vector_s),
            .sdram_test_done(ram_done_s),.sdram_test_pass(ram_pass_s),
            .sdram_test_error_addr(ram_addr_s),
            .sdram_test_expected(ram_expected_s),
            .sdram_test_actual(ram_actual_s),
            .rgb_in(stream_rgb),.rgb_out(rgb));
    end else begin:overlay_disabled
        assign rgb=stream_rgb;
    end endgenerate

    logic [15:0] audio_samples[1:0];
    assign audio_samples[0]=0; assign audio_samples[1]=0;
    logic [9:0] tmds_internal[2:0];
    hdmi #(.VIDEO_ID_CODE(2),.DVI_OUTPUT(1'b1),.VIDEO_REFRESH_RATE(60.0),
           .AUDIO_RATE(48000),.AUDIO_BIT_WIDTH(16),.NUM_CHANNELS(3),
           .START_X(0),.START_Y(0)) encoder(
        .clk_pixel_x5(serial_clk),.clk_pixel(pixel_clk),.clk_audio(pixel_clk),
        .reset(reset),.rgb(rgb),.audio_sample_word(audio_samples),.cx(x),.cy(y),
        .frame_width(),.frame_height(),.screen_width(),.screen_height(),
        .tmds_internal(tmds_internal));
    logic [2:0] tmds; logic unused_clock;
    serializer #(.NUM_CHANNELS(3),.VIDEO_RATE(0)) serializer_inst(
        .clk_pixel(pixel_clk),.clk_pixel_x5(serial_clk),.reset(reset),
        .tmds_internal(tmds_internal),.tmds(tmds),
        .tmds_clock(unused_clock));
    ELVDS_OBUF output_buffers[3:0](
        .I({pixel_clk,tmds}),.O({tmds_clk_p,tmds_data_p}),
        .OB({tmds_clk_n,tmds_data_n}));
endmodule
