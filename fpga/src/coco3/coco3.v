// CoCo 3 machine-specific block. CPU timing, GIME registers/address mapping
// and native video rendering live here; SDRAM and output scan conversion are
// deliberately shared by the board top level with the CoCo 2 implementation.
module coco3 #(
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

    gime_timing timing (
        .clk(clk), .reset_n(core_reset_n), .e(e), .q(q),
        .e_rise(e_rise), .e_fall(e_fall)
    );

    wire [7:0] vmode;
    wire [7:0] vres;
    wire [5:0] border_color;
    wire [3:0] vertical_scroll;
    wire [15:0] video_offset;
    wire [7:0] horizontal_offset;
    wire [95:0] palettes;
    gime_registers registers (
        .clk(clk), .reset_n(core_reset_n), .e(e), .e_fall(e_fall),
        .cpu_addr(cpu_addr), .cpu_rw_n(cpu_rw_n), .cpu_data(cpu_data),
        .core_rdata(core_rdata), .core_data_oe(core_data_oe), .sam_s(sam_s),
        .cpu_mem_read(cpu_mem_read), .cpu_mem_write(cpu_mem_write),
        .cpu_mem_is_rom(cpu_mem_is_rom), .cpu_mem_addr(cpu_mem_addr),
        .vmode(vmode), .vres(vres), .border_color(border_color),
        .vertical_scroll(vertical_scroll), .video_offset(video_offset),
        .horizontal_offset(horizontal_offset), .palettes(palettes)
    );

    wire debug_bit_plane;
    wire [2:0] debug_hres;
    wire [1:0] debug_cres;
    wire [1:0] debug_lpf;
    wire [2:0] debug_lines_per_row_code;
    gime_mode_debug debug_modes (
        .clk(clk), .reset_n(core_reset_n), .button(s2),
        .bit_plane(debug_bit_plane), .hres(debug_hres),
        .cres(debug_cres), .lpf(debug_lpf),
        .lines_per_row_code(debug_lines_per_row_code)
    );

    reg effective_bit_plane = 1'b0;
    reg [2:0] effective_hres = 3'd0;
    reg [1:0] effective_cres = 2'd0;
    reg [1:0] effective_lpf = 2'd0;
    reg [2:0] effective_lines_per_row_code = 3'd3;
    // Debug modes always view physical RAM from zero. Normal operation uses
    // the GIME's 19-bit screen-base register (FF9D:FF9E multiplied by eight).
    reg [18:0] effective_screen_base = 19'd0;
    always @(posedge clk or negedge core_reset_n) begin
        if (!core_reset_n) begin
            effective_bit_plane <= 1'b0;
            effective_hres <= 3'd0;
            effective_cres <= 2'd0;
            effective_lpf <= 2'd0;
            effective_lines_per_row_code <= 3'd3;
            effective_screen_base <= 19'd0;
        end else begin
            effective_bit_plane <= DEBUG_S2_VIDEO_MODE ? debug_bit_plane : vmode[7];
            effective_hres <= DEBUG_S2_VIDEO_MODE ? debug_hres : vres[4:2];
            effective_cres <= DEBUG_S2_VIDEO_MODE ? debug_cres : vres[1:0];
            effective_lpf <= DEBUG_S2_VIDEO_MODE ? debug_lpf : vres[6:5];
            effective_lines_per_row_code <= DEBUG_S2_VIDEO_MODE ?
                                                  debug_lines_per_row_code : vmode[2:0];
            effective_screen_base <= DEBUG_S2_VIDEO_MODE ?
                                                  19'd0 : {video_offset,3'b000};
        end
    end

    gime_video video (
        .clk(clk), .reset_n(core_reset_n),
        .bit_plane(effective_bit_plane), .hres(effective_hres),
        .cres(effective_cres), .lines_per_row_code(effective_lines_per_row_code),
        .lpf(effective_lpf), .screen_base(effective_screen_base),
        .horizontal_offset(horizontal_offset), .palettes(palettes),
        .border_color(border_color), .memory_data(video_memory_data),
        .memory_data_valid(video_memory_valid),
        .video_read_request(video_memory_request), .memory_addr(video_memory_addr),
        .framebuffer_write(framebuffer_write),
        .framebuffer_write_addr(framebuffer_write_addr),
        .framebuffer_write_data(framebuffer_write_data),
        .active_height(active_height), .hs_n(hs_n), .fs_n(fs_n),
        .hblank(hblank), .vblank(vblank), .red(red), .green(green),
        .blue(blue), .border_rgb(border_rgb)
    );

    wire unused_vertical_scroll = ^vertical_scroll;
endmodule
