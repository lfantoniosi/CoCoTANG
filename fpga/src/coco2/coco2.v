// CoCo 2 machine-specific logic.  External memory, physical bus muxing and
// output scan converters remain common at the board top level so a future
// CoCo 3/GIME core can implement this same outward-facing interface.
module coco2 #(
    parameter integer DEBUG_S2_VIDEO_MODE = 0,
    parameter integer DEBUG_CPU_SLOW = 0
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
    output            cpu_mem_read,
    output            cpu_mem_write,
    output            cpu_mem_is_rom,
    output     [22:0] cpu_mem_addr,
    output      [7:0] core_rdata,
    output            core_data_oe,

    input       [7:0] video_memory_data,
    input             video_memory_valid,
    output            video_memory_request,
    output     [22:0] video_memory_addr,
    output      [7:0] active_height,
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

    coco_sam #(.SLOW_DIAGNOSTIC(DEBUG_CPU_SLOW)) sam (
        .clk(clk), .reset_n(reset_n), .register_reset_n(core_reset_n),
        .addr(cpu_addr), .rw_n(cpu_rw_n),
        .s(sam_s), .e(e), .q(q), .e_rise(e_rise), .e_fall(e_fall),
        .video_mode(sam_video_mode), .video_offset(sam_video_offset),
        .page(sam_page), .rate(sam_rate), .memory_size(sam_memory_size),
        .all_ram(sam_all_ram)
    );

    assign cpu_mem_read = cpu_rw_n && (sam_s <= 3'd2);
    assign cpu_mem_write = !cpu_rw_n && (sam_s == 3'd0);
    assign cpu_mem_is_rom = sam_s == 3'd1 || sam_s == 3'd2;
    assign cpu_mem_addr = (sam_s == 3'd1) ?
                          23'h002000 + {10'd0,cpu_addr[12:0]} :
                          (sam_s == 3'd2) ? {10'd0,cpu_addr[12:0]} :
                                           {7'd0,cpu_addr};
    assign core_rdata = 8'hff;
    assign core_data_oe = 1'b0;
    assign active_height = 8'd192;
    assign video_memory_request = 1'b0;

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
    wire [15:0] vdg_memory_addr;
    assign video_memory_addr = {7'd0,vdg_memory_addr};
    coco_vdg #(.DEBUG_VIDEO_MODE(DEBUG_S2_VIDEO_MODE)) vdg (
        .clk(clk), .reset_n(core_reset_n), .e_fall(e_fall),
        .cpu_rw_n(cpu_rw_n), .cpu_addr(cpu_addr), .cpu_data(cpu_data),
        .sam_video_mode(effective_video_mode),
        .debug_an_g(debug_an_g), .debug_css(debug_css),
        .sam_video_offset(sam_video_offset),
        .memory_data(video_memory_data), .memory_addr(vdg_memory_addr),
        .hs_n(hs_n), .fs_n(fs_n), .red(red), .green(green), .blue(blue),
        .border_rgb(border_rgb), .hblank(hblank), .vblank(vblank),
        .cvbs(unused_vdg_cvbs), .pixel_capture(framebuffer_write),
        .capture_addr(framebuffer_write_addr),
        .capture_rgb(framebuffer_write_data)
    );
endmodule
