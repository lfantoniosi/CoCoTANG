// 720x480 DVI scanout for the CoCo 3 line cache. Native GIME lines may retain
// all 640 dots or use an aspect-correct 512-dot RGB888 reduction.
module coco3_hdmi #(
    parameter integer LOG_ADDR_WIDTH=12,
    parameter integer LOG_COUNT_WIDTH=13,
    parameter integer LOG_PAGE_WIDTH=6,
    parameter integer LOG_DEPTH=4096,
    parameter integer ENABLE_DEBUG_OVERLAY=0,
    parameter integer GIME_TRACE_MODE=0,
    parameter integer NATIVE_HDMI_640=1
) (
    input logic pixel_clk,input logic serial_clk,
    input logic audio_clk,input logic [15:0] audio_pcm,input logic reset,
    input logic debug_clk,input logic log_we,
    input logic [LOG_ADDR_WIDTH-1:0] log_addr,input logic [47:0] log_data,
    input logic [LOG_ADDR_WIDTH-1:0] log_base,
    input logic [LOG_COUNT_WIDTH-1:0] log_count,
    input logic [LOG_PAGE_WIDTH-1:0] log_page,
    input logic gime_trace_arm,input logic [2:0] gime_trace_page,
    input logic gime_trace_sample,input logic [8:0] gime_trace_y,
    input logic [198:0] gime_trace_data,
    input logic [4:0] debug_status,input logic overlay_enable,
    input logic [3:0] interrupt_status,
    input logic [31:0] raster_debug,
    input logic [79:0] gime_register_debug,
    input logic [95:0] mmu_register_debug,
    input logic rom_verify_done,input logic rom_verify_pass,
    input logic [15:0] rom_verify_vector,
    input logic sdram_test_done,input logic sdram_test_pass,
    input logic [18:0] sdram_test_error_addr,
    input logic [7:0] sdram_test_expected,input logic [7:0] sdram_test_actual,
    input logic [1:0] artifact_mode,
    input logic artifact_video_active,input logic artifact_css,
    input logic video_50hz,
    input logic bit_plane,
    input logic [7:0] active_height,input logic compatibility_mode,
    input logic [5:0] border_rgb,
    input logic [5:0] row_left_border_rgb,input logic [5:0] row_right_border_rgb,
    input logic row_border_valid,
    input logic [5:0] vertical_left_border_rgb,input logic [5:0] vertical_right_border_rgb,
    input logic vertical_border_valid,
    input logic [23:0] pixel_data,
    output logic [9:0] source_x,output logic [7:0] source_y,
    output logic source_valid,output logic source_picture_active,
    output logic source_frame_start,output logic [8:0] source_border_raster_y,
    output logic [7:0] prefetch_y,
    output logic prefetch_valid,
    output logic active_video_50hz,
    output logic tmds_clk_p,output logic tmds_clk_n,
    output logic [2:0] tmds_data_p,output logic [2:0] tmds_data_n
);
    logic [9:0] x,y;
    logic [7:0] height_m=8'd192,height_s=8'd192;
    logic compatibility_m=1'b1,compatibility_s=1'b1;
    logic bit_plane_m=1'b0,bit_plane_s=1'b0;
    logic video_50hz_m=1'b0,video_50hz_s=1'b0;
    logic active_50hz_m=1'b0,active_50hz_s=1'b0;
    logic rom_done_m=0,rom_done_s=0,rom_pass_m=0,rom_pass_s=0;
    logic [15:0] rom_vector_m=16'hffff,rom_vector_s=16'hffff;
    logic ram_done_m=0,ram_done_s=0,ram_pass_m=0,ram_pass_s=0;
    logic [18:0] ram_addr_m=0,ram_addr_s=0;
    logic [7:0] ram_expected_m=0,ram_expected_s=0;
    logic [7:0] ram_actual_m=0,ram_actual_s=0;
    logic [3:0] interrupt_m=0,interrupt_s=0;
    logic [31:0] raster_debug_m=0,raster_debug_s=0;
    logic [79:0] gime_register_m=0,gime_register_s=0;
    logic [95:0] mmu_register_m=0,mmu_register_s=0;
    logic [9:0] top,doubled_height,picture_width,picture_lead;
    logic [9:0] source_line,picture_x;
    always_ff @(posedge pixel_clk) begin
        height_m<=active_height;
        height_s<=height_m;
        compatibility_m<=compatibility_mode;
        compatibility_s<=compatibility_m;
        bit_plane_m<=bit_plane;
        bit_plane_s<=bit_plane_m;
        video_50hz_m<=video_50hz;
        video_50hz_s<=video_50hz_m;
        active_50hz_m<=active_video_50hz;
        active_50hz_s<=active_50hz_m;
        rom_done_m<=rom_verify_done; rom_done_s<=rom_done_m;
        rom_pass_m<=rom_verify_pass; rom_pass_s<=rom_pass_m;
        rom_vector_m<=rom_verify_vector; rom_vector_s<=rom_vector_m;
        ram_done_m<=sdram_test_done; ram_done_s<=ram_done_m;
        ram_pass_m<=sdram_test_pass; ram_pass_s<=ram_pass_m;
        ram_addr_m<=sdram_test_error_addr; ram_addr_s<=ram_addr_m;
        ram_expected_m<=sdram_test_expected; ram_expected_s<=ram_expected_m;
        ram_actual_m<=sdram_test_actual; ram_actual_s<=ram_actual_m;
        interrupt_m<=interrupt_status; interrupt_s<=interrupt_m;
        raster_debug_m<=raster_debug;raster_debug_s<=raster_debug_m;
        gime_register_m<=gime_register_debug;
        gime_register_s<=gime_register_m;
        mmu_register_m<=mmu_register_debug;
        mmu_register_s<=mmu_register_m;
    end
    always_comb begin
        doubled_height={1'b0,height_s,1'b0};
        // Align HDMI's logical picture rows with the native GIME body.  In
        // 225-line mode the centered margin is odd, so ordinary centering
        // would put scanout half a native raster ahead of GIME timing.
        // Keep scanout one native raster behind the interrupt generator.
        // The line renderer prefetches N+1 while displaying N; this delay
        // places that prefetch after BOINK's HBORD handler for line N, so
        // FF98.LPR is sampled before the affected row begins rendering.
        top=active_50hz_s ?
            (height_s==8'd225 ? 10'd63 :
             height_s==8'd199 ? 10'd89 : 10'd96) :
            (height_s==8'd225 ? 10'd18 :
             height_s==8'd199 ? 10'd48 : 10'd52);
        // The GIME's 640-dot modes describe the same 4:3 display aperture as
        // its 256-dot modes. Resample every mode into 512x(2*LPF) rather than
        // exposing the CRT's non-square 640-dot sampling as square HDMI pixels.
        picture_width=(NATIVE_HDMI_640!=0&&!compatibility_s)?10'd640:10'd512;
        // Two clocks of scanline-RAM addressing/output latency.
        picture_lead=((10'd720-picture_width)>>1)-2'd2;
        picture_x=(x>=picture_lead)?x-picture_lead:10'd0;
        source_line=(y>=top) ? ((y-top)>>1) : 10'd0;
    end

    // Lead the visible window by one clock for the synchronous line RAM.
    always_comb begin
        source_valid=(x>=picture_lead && x<picture_lead+picture_width &&
                      y>=top && y<top+doubled_height);
        // Unlike source_valid, this stays asserted through the horizontal
        // borders.  Raster-time GIME writes happen there, and the scanline
        // cache must distinguish them from vertical-border frame setup.
        source_picture_active=(y>=top && y<top+doubled_height);
        source_frame_start=(x==0 && y==0);
        // The VDG raster's picture starts at top/2+15 (60 Hz) or +16 (50 Hz).
        // Preserve that offset in the vertical borders as well.
        source_border_raster_y={1'b0,y[9:1]}+(active_50hz_s?9'd16:9'd15);
        // Native GIME can either retain all 640 dots for sharp 80-column
        // text, or use the aspect-correct RGB888 5:4 reduction. VDG and
        // artifact modes always use the centered 512-dot aperture. In the
        // 640 configuration ordinary VDG pixels use exact 2x/4x/8x point
        // replication; artifact pixels retain their composite phase decode.
        source_x=source_valid ? picture_x : 10'd0;
        source_y=source_line[7:0];
        // The ping-pong scan doubler starts producing the next source line
        // while the current one is first displayed:
        // requesting source_line+1 on the first of the two HDMI copies gives
        // the GIME renderer a full source-line period (~63.5 us), rather than
        // only the second 480p line (~31.7 us).  Extended 80-column/640-dot
        // modes need that margin once SDRAM arbitration is included.
        // Prime source line zero only during the final native raster before
        // the picture.  Priming it at HDMI line zero captured the previous
        // frame's GIME state before vertical-blank handlers had installed the
        // new VOFF/mode/raster settings.  Two 480p rows are one complete GIME
        // line (about 63.5 us), which is enough for the renderer while making
        // the first visible row use the finalized frame state.
        prefetch_y=(y<top) ? 8'd0 : source_line[7:0]+1'b1;
        prefetch_valid=(y<top) ? (y+2'd2>=top) :
                       (y<top+doubled_height && source_line+1'b1<height_s);
    end

    logic picture_d=0;
    // Scanout is deliberately one native GIME raster (two 858-pixel HDMI
    // rows) behind the interrupt generator so a horizontal-border handler
    // can finish before the corresponding framebuffer row is prefetched.
    // Associate one border colour with each native row as well.  Delaying
    // the raw pixel-clock stream is subtly wrong: a write made in the right
    // border for the following raster would change only the right edge of
    // the delayed row.  Sampling once per doubled row keeps both borders
    // attached to the same immutable framebuffer scanline.
    logic [5:0] border_row_current=0;
    logic [5:0] border_row_delayed=0;
    logic artifact_active_m=0,artifact_active_s=0;
    logic artifact_css_m=0,artifact_css_s=0;
    logic [23:0] stream_rgb,debug_rgb,rgb;
    always_ff @(posedge pixel_clk) begin
        picture_d<=source_valid;
        artifact_active_m<=artifact_video_active;
        artifact_active_s<=artifact_active_m;
        artifact_css_m<=artifact_css;
        artifact_css_s<=artifact_css_m;
        if(x==0 && !y[0]) begin
            border_row_delayed<=border_row_current;
            border_row_current<=border_rgb;
        end
    end
    // The HDMI encoder samples RGB on the same edge that advances the border
    // row registers. At x=0 it would see the old delayed value, so bypass
    // that one pixel with the current row. The remaining pixels use the
    // newly updated delayed register.
    wire [5:0] scanline_border=(x==0 && !y[0]) ?
                               border_row_current : border_row_delayed;
    wire [23:0] expanded_border={{4{scanline_border[5:4]}},
                                 {4{scanline_border[3:2]}},
                                 {4{scanline_border[1:0]}}};
    // The line cache holds CSS at the first and last VDG bytes so a write
    // in either border cannot recolour a row that was already rendered.
    wire [5:0] row_border=(x<=picture_lead)?row_left_border_rgb:
                                             row_right_border_rgb;
    wire [23:0] expanded_row_border={{4{row_border[5:4]}},
                                     {4{row_border[3:2]}},
                                     {4{row_border[1:0]}}};
    wire [5:0] vertical_border=(x<=picture_lead)?vertical_left_border_rgb:
                                                 vertical_right_border_rgb;
    wire [23:0] expanded_vertical_border={{4{vertical_border[5:4]}},
                                          {4{vertical_border[3:2]}},
                                          {4{vertical_border[1:0]}}};
    wire [23:0] selected_rgb=picture_d ? pixel_data :
        (compatibility_s&&source_picture_active&&row_border_valid?
         expanded_row_border:
         compatibility_s&&!source_picture_active&&vertical_border_valid?
         expanded_vertical_border:expanded_border);

    // Full-precision MAME-compatible palettes. Tokenized artifact pixels are
    // expanded here so normal GIME video keeps its original RGB222 path.
    function automatic [23:0] artifact_rgb888;
        input css;
        input [3:0] index;
        begin
            if(css) begin
                case(index)
                    4'h0:artifact_rgb888=24'h000000;
                    4'h1:artifact_rgb888=24'h3e302e;
                    4'h2:artifact_rgb888=24'h264816;
                    4'h3:artifact_rgb888=24'hbfadad;
                    4'h4:artifact_rgb888=24'ha4c892;
                    4'h5:artifact_rgb888=24'h925428;
                    4'h6:artifact_rgb888=24'h264e5d;
                    4'h7:artifact_rgb888=24'hbf8451;
                    4'h8:artifact_rgb888=24'h50a7ad;
                    4'h9:artifact_rgb888=24'h267cad;
                    4'ha:artifact_rgb888=24'hbf7c16;
                    4'hb:artifact_rgb888=24'hbfbf8d;
                    4'hc:artifact_rgb888=24'h62bfad;
                    4'hd:artifact_rgb888=24'h4a3016;
                    4'he:artifact_rgb888=24'h26303a;
                    default:artifact_rgb888=24'hffffaa;
                endcase
            end else begin
                case(index)
                    4'h0:artifact_rgb888=24'h000000;
                    4'h1:artifact_rgb888=24'h283013;
                    4'h2:artifact_rgb888=24'h264916;
                    4'h3:artifact_rgb888=24'h30b500;
                    4'h4:artifact_rgb888=24'h2ed204;
                    4'h5:artifact_rgb888=24'h2d5613;
                    4'h6:artifact_rgb888=24'h26500c;
                    4'h7:artifact_rgb888=24'h30890d;
                    4'h8:artifact_rgb888=24'h29af00;
                    4'h9:artifact_rgb888=24'h268100;
                    4'ha:artifact_rgb888=24'h308116;
                    4'hb:artifact_rgb888=24'h30c905;
                    4'hc:artifact_rgb888=24'h2ac900;
                    4'hd:artifact_rgb888=24'h283016;
                    4'he:artifact_rgb888=24'h263011;
                    default:artifact_rgb888=24'h30d200;
                endcase
            end
        end
    endfunction
    assign stream_rgb=artifact_active_s ?
        (picture_d && selected_rgb[23:4]==20'ha5c3e ?
            artifact_rgb888(artifact_css_s,selected_rgb[3:0]) :
         !picture_d ? artifact_rgb888(artifact_css_s,4'hf) : selected_rgb) :
        selected_rgb;

    generate if (ENABLE_DEBUG_OVERLAY!=0) begin:overlay_enabled
        hdmi_debug_overlay #(
            .LOG_ADDR_WIDTH(LOG_ADDR_WIDTH),.LOG_COUNT_WIDTH(LOG_COUNT_WIDTH),
            .LOG_PAGE_WIDTH(LOG_PAGE_WIDTH),.LOG_DEPTH(LOG_DEPTH),
            .EXTENDED_HEADER(2),.GIME_TRACE_MODE(GIME_TRACE_MODE)) overlay(
            .pixel_clk(pixel_clk),.x(x),.y(y),.enable(overlay_enable),
                .debug_data({288'd0,raster_debug_s}),.debug_clk(debug_clk),.log_we(log_we),
            .log_addr(log_addr),.log_data(log_data),.log_count(log_count),
            .log_base(log_base),
            .log_page(log_page),.debug_status(debug_status),
            .gime_trace_arm(gime_trace_arm),
            .gime_trace_page(gime_trace_page),
            .gime_trace_sample(gime_trace_sample),
            .gime_trace_y(gime_trace_y),
            .gime_trace_data(gime_trace_data),
            .interrupt_status(interrupt_s),
            .gime_register_debug(gime_register_s),
            .mmu_register_debug(mmu_register_s),
            .rom_verify_done(rom_done_s),.rom_verify_pass(rom_pass_s),
            .rom_verify_vector(rom_vector_s),
            .sdram_test_done(ram_done_s),.sdram_test_pass(ram_pass_s),
            .sdram_test_error_addr(ram_addr_s),
            .sdram_test_expected(ram_expected_s),
            .sdram_test_actual(ram_actual_s),
            .rgb_in(stream_rgb),.rgb_out(debug_rgb));
    end else begin:overlay_disabled
        assign debug_rgb=stream_rgb;
    end endgenerate

    artifact_mode_osd artifact_osd(
        .pixel_clk(pixel_clk),.reset(reset),.mode(artifact_mode),.x(x),.y(y),
        .rgb_in(debug_rgb),.rgb_out(rgb));

    logic [15:0] audio_samples[1:0];
    assign audio_samples[0]=audio_pcm; assign audio_samples[1]=audio_pcm;
    logic [9:0] tmds_internal[2:0];
    hdmi #(.VIDEO_ID_CODE(2),.DYNAMIC_480_576(1),.DVI_OUTPUT(1'b0),
           .VIDEO_REFRESH_RATE(59.94),
           .AUDIO_RATE(48000),.AUDIO_BIT_WIDTH(16),.NUM_CHANNELS(3),
           .START_X(0),.START_Y(0)) encoder(
        .clk_pixel_x5(serial_clk),.clk_pixel(pixel_clk),.clk_audio(audio_clk),
        .reset(reset),.video_50hz(video_50hz_s),.rgb(rgb),
        .audio_sample_word(audio_samples),.cx(x),.cy(y),
        .frame_width(),.frame_height(),.screen_width(),.screen_height(),
        .active_video_50hz(active_video_50hz),
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
