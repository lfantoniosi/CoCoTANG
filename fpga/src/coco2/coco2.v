// CoCo 2 machine-specific logic.  External memory, physical bus muxing and
// output scan converters remain common at the board top level so a future
// CoCo 3/GIME core can implement this same outward-facing interface.
module coco2 #(
    parameter integer DEBUG_S2_VIDEO_MODE = 0
) (
    input             clk,
    input             reset_n,
    input             cpu_reset_n,
    input             s2,
    input      [15:0] cpu_addr,
    input             cpu_rw_n,
    input       [7:0] cpu_data,
    output      [2:0] sam_s,
    output            e,
    output            q,
    output            e_rise,
    output            e_fall,

    input       [7:0] video_memory_data,
    output     [15:0] video_memory_addr,
    output            hs_n,
    output            fs_n,
    output      [7:0] red,
    output      [7:0] green,
    output      [7:0] blue,
    output      [5:0] border_rgb,
    output            hblank,
    output            vblank,
    output            framebuffer_write,
    output     [15:0] framebuffer_write_addr,
    output      [5:0] framebuffer_write_data
);
    wire core_reset_n = reset_n && cpu_reset_n;

    wire [2:0] sam_video_mode;
    wire [6:0] sam_video_offset;
    wire sam_page;
    wire sam_all_ram;
    wire [1:0] sam_rate;
    wire [1:0] sam_memory_size;

    coco_sam sam (
        .clk(clk), .reset_n(core_reset_n), .addr(cpu_addr), .rw_n(cpu_rw_n),
        .s(sam_s), .e(e), .q(q), .e_rise(e_rise), .e_fall(e_fall),
        .video_mode(sam_video_mode), .video_offset(sam_video_offset),
        .page(sam_page), .rate(sam_rate), .memory_size(sam_memory_size),
        .all_ram(sam_all_ram)
    );

    wire [2:0] debug_video_mode;
    wire debug_an_g;
    wire debug_css;
    wire [2:0] effective_video_mode = DEBUG_S2_VIDEO_MODE ?
                                      debug_video_mode : sam_video_mode;
    video_mode_debug s2_video_mode (
        .clk(clk), .reset_n(reset_n), .button(s2),
        .an_g(debug_an_g), .css(debug_css), .gm(debug_video_mode)
    );

    wire [7:0] unused_vdg_cvbs;
    coco_vdg #(.DEBUG_VIDEO_MODE(DEBUG_S2_VIDEO_MODE)) vdg (
        .clk(clk), .reset_n(core_reset_n), .e_fall(e_fall),
        .cpu_rw_n(cpu_rw_n), .cpu_addr(cpu_addr), .cpu_data(cpu_data),
        .sam_video_mode(effective_video_mode),
        .debug_an_g(debug_an_g), .debug_css(debug_css),
        .sam_video_offset(sam_video_offset),
        .memory_data(video_memory_data), .memory_addr(video_memory_addr),
        .hs_n(hs_n), .fs_n(fs_n), .red(red), .green(green), .blue(blue),
        .border_rgb(border_rgb), .hblank(hblank), .vblank(vblank),
        .cvbs(unused_vdg_cvbs), .pixel_capture(framebuffer_write),
        .capture_addr(framebuffer_write_addr),
        .capture_rgb(framebuffer_write_data)
    );
endmodule
