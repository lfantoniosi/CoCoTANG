// CoCo 3 machine-specific block. CPU timing, GIME registers/address mapping
// and native video rendering live here; SDRAM and output scan conversion are
// provided by the board top level.
module coco3 #(
    parameter integer DEBUG_S2_VIDEO_MODE = 0,
    parameter integer DISTO_2MB = 0
) (
    input             clk,
    input             reset_n,
    input             cpu_reset_n,
    input             s2,
    input       [1:0] artifact_mode,
    input      [15:0] cpu_addr,
    input             cpu_rw_n,
    input       [7:0] cpu_data,
    input             serint_n,
    input             keyint_n,
    input             cart_n,
    output            irq_assert,
    output            firq_assert,
    output      [2:0] sam_s,
    output            e,
    output            q,
    output            e_pin,
    output            q_pin,
    output            e_rise,
    output            e_fall,
    output            cpu_mem_read,
    output            cpu_mem_write,
    output            cpu_mem_is_rom,
    output     [22:0] cpu_mem_addr,
    output      [7:0] core_rdata,
    output            core_data_oe,

    input       [7:0] video_memory_data,
    input      [31:0] video_memory_data32,
    input             video_memory_valid,
    output            video_memory_request,
    output     [22:0] video_memory_addr,
    output      [7:0] active_height,
    output            video_50hz,
    output            native_bit_plane,
    output            compatibility_video,
    output            hs_n,
    output            fs_n,
    output      [7:0] red,
    output      [7:0] green,
    output      [7:0] blue,
    output      [5:0] border_rgb,
    output            artifact_video_active,
    output            artifact_css,
    output            hblank,
    output            vblank,
    output            framebuffer_write,
    output     [15:0] framebuffer_write_addr,
    output      [5:0] framebuffer_write_data,

    input             hdmi_read_clk,
    input       [9:0] hdmi_source_x,
    input       [7:0] hdmi_source_y,
    input             hdmi_source_valid,
    input             hdmi_source_picture_active,
    input       [7:0] hdmi_prefetch_y,
    input             hdmi_prefetch_valid,
    output     [23:0] hdmi_pixel_data,
    output      [5:0] hdmi_left_border_data,
    output      [5:0] hdmi_right_border_data,
    output            hdmi_border_valid,
    output      [5:0] hdmi_vertical_left_border_data,
    output      [5:0] hdmi_vertical_right_border_data,
    output            hdmi_vertical_border_valid,
    input             hdmi_frame_start,
    input             hdmi_active_50hz,
    input       [8:0] hdmi_border_raster_y,
    input             cvbs_read_clk,
    input       [9:0] cvbs_source_x,
    input       [7:0] cvbs_source_y,
    input             cvbs_source_valid,
    input       [7:0] cvbs_prefetch_y,
    input             cvbs_prefetch_valid,
    input       [8:0] cvbs_border_raster_y,
    output      [5:0] cvbs_pixel_data,
    output      [5:0] cvbs_border_data,
    output      [5:0] cvbs_right_border_data,
    output            cvbs_border_valid,
    output      [5:0] cvbs_vertical_left_border_data,
    output      [5:0] cvbs_vertical_right_border_data,
    output            cvbs_vertical_border_valid,
    output      [5:0] mmu_task0_page_debug,
    output      [5:0] mmu_task1_page_debug,
    output            mmu_task_debug,
    output            mmu_enabled_debug,
    output     [79:0] gime_register_debug,
    output     [127:0] gime_trace_registers,
    output             gime_trace_sample,
    output     [8:0]   gime_trace_y,
    output     [7:0]   gime_trace_active_line,
    output     [1:0]   gime_trace_phase,
    output     [7:0]   gime_trace_cache_y,
    output             gime_trace_cache_valid,
    output     [20:0]  gime_trace_cache_start,
    output     [18:0]  gime_trace_dma_next_address,
    output     [7:0]   gime_trace_dma_next_y,
    output     [3:0]   gime_trace_dma_line,
    output     [95:0] mmu_register_debug,
    output reg [31:0] raster_debug
);
    wire core_reset_n = reset_n && cpu_reset_n;

    wire fast_mode;
    wire compatibility_mode;
    wire [7:0] vmode;
    reg effective_bit_plane = 1'b0;
    gime_timing timing (
        // E/Q must run while the physical CPU is held in RESET; register and
        // video state remain reset until cpu_reset_n is released.
        .clk(clk), .reset_n(reset_n), .fast_mode(fast_mode),
        .e(e), .q(q),
        .e_pin(e_pin), .q_pin(q_pin),
        .e_rise(e_rise), .e_fall(e_fall)
    );

    wire [7:0] vres;
    wire [5:0] border_color;
    wire [3:0] vertical_scroll;
    wire [15:0] video_offset;
    wire [7:0] horizontal_offset;
    wire [1:0] video_bank;
    assign compatibility_video = compatibility_mode;
    wire [2:0] sam_video_mode;
    wire [6:0] sam_video_offset;
    wire [95:0] palettes;
    wire hborder_irq_n;
    assign video_50hz = vmode[3];
    gime_registers #(.DISTO_2MB(DISTO_2MB)) registers (
        .clk(clk), .reset_n(core_reset_n), .e(e), .e_fall(e_fall),
        .cpu_addr(cpu_addr), .cpu_rw_n(cpu_rw_n), .cpu_data(cpu_data),
        .serint_n(serint_n), .keyint_n(keyint_n), .cart_n(cart_n),
        .hs_n(hborder_irq_n), .fs_n(fs_n),
        .irq_assert(irq_assert), .firq_assert(firq_assert),
        .fast_mode(fast_mode),
        .core_rdata(core_rdata), .core_data_oe(core_data_oe), .sam_s(sam_s),
        .cpu_mem_read(cpu_mem_read), .cpu_mem_write(cpu_mem_write),
        .cpu_mem_is_rom(cpu_mem_is_rom), .cpu_mem_addr(cpu_mem_addr),
        .vmode(vmode), .vres(vres), .border_color(border_color),
        .vertical_scroll(vertical_scroll), .video_offset(video_offset),
        .horizontal_offset(horizontal_offset),
        .video_bank(video_bank),
        .compatibility_mode(compatibility_mode),
        .sam_video_mode(sam_video_mode),
        .sam_video_offset(sam_video_offset), .palettes(palettes),
        .mmu_task0_page_debug(mmu_task0_page_debug),
        .mmu_task1_page_debug(mmu_task1_page_debug),
        .mmu_task_debug(mmu_task_debug),
        .mmu_enabled_debug(mmu_enabled_debug),
        .gime_register_debug(gime_register_debug),
        .gime_trace_registers(gime_trace_registers),
        .mmu_register_debug(mmu_register_debug)
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

    // PIA1 PB drives the compatibility-mode MC6847 controls on a real
    // CoCo 3. Shadow the DDR/data selection for A/G, GM, CSS and SG4/SG6.
    reg [7:0] pia1_pb = 8'd0;
    reg [7:0] pia1_ddrb = 8'd0;
    reg [7:0] pia1_crb = 8'd0;
    always @(posedge clk or negedge core_reset_n) begin
        if (!core_reset_n) begin
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
    wire compatibility_an_g = pia1_effective[7];
    wire [2:0] compatibility_gm = pia1_effective[6:4];

    function [2:0] compatibility_hres;
        input [2:0] gm;
        begin
            case (gm)
                3'd2,3'd4,3'd6,3'd7: compatibility_hres=3'd2; // 32 bytes
                default: compatibility_hres=3'd0;              // 16 bytes
            endcase
        end
    endfunction

    function [2:0] compatibility_lpr;
        input [2:0] sam_mode;
        begin
            if (sam_mode <= 3'd3) compatibility_lpr=3'b010;      // 64 lines, 3x
            else if (sam_mode <= 3'd5) compatibility_lpr=3'b001; // 96 lines, 2x
            else compatibility_lpr=3'b000;                 // 192 lines
        end
    endfunction

    assign native_bit_plane = effective_bit_plane;
    reg [3:0] effective_hres = 4'd0;
    reg [1:0] effective_cres = 2'd0;
    reg [1:0] effective_lpf = 2'd0;
    reg [2:0] effective_lines_per_row_code = 3'd3;
    // Debug modes always view physical RAM from zero.  Native GIME video uses
    // FF9D:FF9E multiplied by eight.  In compatibility mode the SAM F bits
    // supply the legacy display offset, while the GIME still contributes the
    // implemented high FF9D bits and low FF9E bits.  In particular, do not
    // assume the legacy screen is in the power-up $70000 compatibility bank:
    // CoVDG can allocate it in any physical 8K block.
    reg [18:0] effective_screen_base = 19'd0;
    always @(posedge clk or negedge core_reset_n) begin
        if (!core_reset_n) begin
            effective_bit_plane <= 1'b0;
            effective_hres <= 4'd0;
            effective_cres <= 2'd0;
            effective_lpf <= 2'd0;
            effective_lines_per_row_code <= 3'd3;
            effective_screen_base <= 19'd0;
        end else begin
            effective_bit_plane <= DEBUG_S2_VIDEO_MODE ? debug_bit_plane :
                                   compatibility_mode ? compatibility_an_g : vmode[7];
            // FF98 bit 6 is HRES[3] in the MiSTer/CoCo3FPGA extended
            // decoder; FF99 bits 4:2 are the standard GIME HRES field.
            effective_hres <= DEBUG_S2_VIDEO_MODE ? {1'b0,debug_hres} :
                              compatibility_mode ?
                                  {1'b0,compatibility_hres(compatibility_gm)} :
                                  {vmode[6],vres[4:2]};
            effective_cres <= DEBUG_S2_VIDEO_MODE ? debug_cres :
                              compatibility_mode ?
                                  (compatibility_an_g ?
                                      (compatibility_gm[0] ? 2'b00 : 2'b01) :
                                      2'b00) : vres[1:0];
            effective_lpf <= DEBUG_S2_VIDEO_MODE ? debug_lpf :
                             compatibility_mode ? 2'b00 : vres[6:5];
            // GIME LPR=000 means one raster line in native mode.  It must
            // not be used as the reset value while COCO=1: compatible
            // 32-column text is the MC6847 twelve-raster character cell.
            effective_lines_per_row_code <= DEBUG_S2_VIDEO_MODE ?
                debug_lines_per_row_code : compatibility_mode ?
                (compatibility_an_g ? compatibility_lpr(sam_video_mode) : 3'b111) :
                vmode[2:0];
            effective_screen_base <= DEBUG_S2_VIDEO_MODE ? 19'd0 :
                compatibility_mode ?
                    ({video_offset[15:13],16'b0} +
                     {10'd0,video_offset[5:0],3'b0} +
                     {3'd0,sam_video_offset,9'b0}) :
                    {video_offset,3'b000};
        end
    end

    function [5:0] palette_rgb;
        input [5:0] color;
        begin palette_rgb={color[5],color[2],color[4],color[1],color[3],color[0]}; end
    endfunction
    wire artifact_pmode4=compatibility_mode && compatibility_an_g &&
                         compatibility_gm==3'd7 && artifact_mode!=0;
    assign artifact_video_active=artifact_pmode4;
    assign artifact_css=pia1_effective[3];
    // Artifacting applies only to the picture. The border remains the PMODE
    // source endpoint, matching MAME and avoiding a false edge-transition.
    assign border_rgb=artifact_pmode4 ?
        (pia1_effective[3] ? 6'h3e : 6'h18) : compatibility_mode ?
        (compatibility_an_g ?
            (pia1_effective[3] ? 6'b111111 : 6'b001100) : 6'b000000) :
        palette_rgb(border_color);
    assign framebuffer_write=1'b0;
    assign framebuffer_write_addr=16'd0;
    assign framebuffer_write_data=6'd0;

    reg [25:0] blink_divider=0;
    always @(posedge clk or negedge core_reset_n) begin
        if(!core_reset_n) blink_divider<=0;
        else blink_divider<=blink_divider+1'b1;
    end
    // Register the translated physical write address before it fans out into
    // two sets of line-tag range comparators.  Besides making the snoop a
    // clean one-clock event, this avoids a long MMU-decode-to-cache-tag path.
    reg video_cpu_write_strobe = 1'b0;
    reg [20:0] video_cpu_write_addr = 21'd0;
    always @(posedge clk or negedge core_reset_n) begin
        if (!core_reset_n) begin
            video_cpu_write_strobe <= 1'b0;
            video_cpu_write_addr <= 21'd0;
        end else begin
            video_cpu_write_strobe <= e_fall && cpu_mem_write;
            if (e_fall && cpu_mem_write)
                video_cpu_write_addr <= cpu_mem_addr[20:0];
        end
    end
    // One MiSTer-compatible renderer services both scanline consumers.  The
    // module mirrors only its two-line output RAM for the unrelated HDMI and
    // CVBS read clocks; SDRAM fetch, tags and mode/address logic are shared.
    wire [7:0] debug_dma_next_y,debug_fill_y;
    assign gime_trace_dma_next_y=debug_dma_next_y;
    wire [3:0] debug_scanline_state;
    wire compatibility_raster_sample;
    wire compatibility_raster_css;
    wire [7:0] compatibility_raster_y;
    wire [4:0] compatibility_raster_byte;
    wire compatibility_border_sample;
    wire compatibility_border_right;
    wire [8:0] compatibility_border_y;
    wire [5:0] compatibility_border_sample_rgb;
    gime_scanline_buffer scanlines (
        .clk(clk),.reset_n(core_reset_n),
        .bit_plane(effective_bit_plane),
        .hres(effective_hres),
        .cres(effective_cres),
        .active_height(active_height),
        .lines_per_row_code(effective_lines_per_row_code),
        .vertical_scroll(vertical_scroll),
        .screen_base(effective_screen_base),
        .video_bank(video_bank),
        .horizontal_offset(horizontal_offset),
        .palettes(palettes),
        .border_rgb(border_rgb),
        .compatibility_mode(compatibility_mode),
        .compatibility_an_g(compatibility_an_g),
        .compatibility_gm(compatibility_gm),
        .compatibility_sam_mode(sam_video_mode),
        .compatibility_css(pia1_effective[3]),
        .compatibility_raster_write(compatibility_raster_sample&&compatibility_mode),
        .compatibility_raster_y(compatibility_raster_y),
        .compatibility_raster_byte(compatibility_raster_byte),
        .compatibility_raster_css(compatibility_raster_css),
        .compatibility_border_write(compatibility_border_sample),
        .compatibility_border_right(compatibility_border_right),
        .compatibility_border_y(compatibility_border_y),
        .compatibility_border_rgb(compatibility_border_sample_rgb),
        .artifact_mode(artifact_mode),
        .blink(blink_divider[25]),
        .cpu_write_strobe(video_cpu_write_strobe),
        .cpu_write_addr(video_cpu_write_addr),
        .hdmi_read_clk(hdmi_read_clk),.hdmi_read_x(hdmi_source_x),
        .hdmi_display_y(hdmi_source_y),.hdmi_display_valid(hdmi_source_valid),
        .hdmi_picture_active(hdmi_source_picture_active),
        .hdmi_prefetch_y(hdmi_prefetch_y),.hdmi_prefetch_valid(hdmi_prefetch_valid),
        .hdmi_pixel_data(hdmi_pixel_data),
        .hdmi_left_border_data(hdmi_left_border_data),
        .hdmi_right_border_data(hdmi_right_border_data),
        .hdmi_border_valid(hdmi_border_valid),
        .hdmi_vertical_left_border_data(hdmi_vertical_left_border_data),
        .hdmi_vertical_right_border_data(hdmi_vertical_right_border_data),
        .hdmi_vertical_border_valid(hdmi_vertical_border_valid),
        .hdmi_frame_start(hdmi_frame_start),
        .hdmi_active_50hz(hdmi_active_50hz),
        .hdmi_border_raster_y(hdmi_border_raster_y),
        .cvbs_read_clk(cvbs_read_clk),.cvbs_read_x(cvbs_source_x),
        .cvbs_display_y(cvbs_source_y),.cvbs_display_valid(cvbs_source_valid),
        .cvbs_prefetch_y(cvbs_prefetch_y),.cvbs_prefetch_valid(cvbs_prefetch_valid),
        .cvbs_border_raster_y(cvbs_border_raster_y),
        .cvbs_pixel_data(cvbs_pixel_data),.cvbs_border_data(cvbs_border_data),
        .cvbs_right_border_data(cvbs_right_border_data),
        .cvbs_border_valid(cvbs_border_valid),
        .cvbs_vertical_left_border_data(cvbs_vertical_left_border_data),
        .cvbs_vertical_right_border_data(cvbs_vertical_right_border_data),
        .cvbs_vertical_border_valid(cvbs_vertical_border_valid),
        .memory_request(video_memory_request),.memory_addr(video_memory_addr),
        .memory_data(video_memory_data32),.memory_valid(video_memory_valid),
        .debug_dma_next_y(debug_dma_next_y),.debug_fill_y(debug_fill_y),
        .debug_state(debug_scanline_state),
        .trace_cache_y(gime_trace_cache_y),
        .trace_cache_valid(gime_trace_cache_valid),
        .trace_cache_start(gime_trace_cache_start),
        .trace_dma_next_address(gime_trace_dma_next_address),
        .trace_dma_line(gime_trace_dma_line)
    );

    function [7:0] line_count;
        input [1:0] value;
        begin case(value) 2'b00:line_count=192; 2'b01:line_count=199;
              2'b11:line_count=225; default:line_count=0; endcase end
    endfunction
    assign active_height=line_count(effective_lpf);
    wire [8:0] debug_native_y;
    assign gime_trace_y=debug_native_y;
    gime_native_video native_video(
        .clk(clk),.reset_n(core_reset_n),.video_50hz(video_50hz),
        .bit_plane(effective_bit_plane),
        .hdmi_frame_start(hdmi_frame_start),
        .hdmi_active_50hz(hdmi_active_50hz),
        .active_height(active_height),.compatibility_mode(compatibility_mode),
        .compatibility_css(pia1_effective[3]),
        .compatibility_border_rgb(border_rgb),
        .pixel_rgb({hdmi_pixel_data[23:22],hdmi_pixel_data[15:14],
                    hdmi_pixel_data[7:6]}),.hs_n(hs_n),.fs_n(fs_n),
        .hborder_irq_n(hborder_irq_n),
        .hblank(hblank),.vblank(vblank),.debug_raster_y(debug_native_y),
        .trace_line_sample(gime_trace_sample),
        .trace_active_line(gime_trace_active_line),
        .trace_phase(gime_trace_phase),
        .compatibility_sample(compatibility_raster_sample),
        .compatibility_sample_css(compatibility_raster_css),
        .compatibility_sample_y(compatibility_raster_y),
        .compatibility_sample_byte(compatibility_raster_byte),
        .compatibility_border_sample(compatibility_border_sample),
        .compatibility_border_right(compatibility_border_right),
        .compatibility_border_y(compatibility_border_y),
        .compatibility_border_sample_rgb(compatibility_border_sample_rgb),
        .red(red),.green(green),.blue(blue));

    // Snapshot renderer/raster phase on each video-register write.  This is
    // diagnostic-only and does not feed any video or interrupt decision.
    always @(posedge clk or negedge core_reset_n) begin
        if(!core_reset_n) raster_debug<=0;
        else if(e_fall&&!cpu_rw_n&&cpu_addr>=16'hff98&&cpu_addr<=16'hff9f)
            raster_debug<={cpu_addr[3:0],debug_scanline_state,
                           debug_native_y[7:0],debug_dma_next_y,debug_fill_y};
    end

    wire unused_video_byte = ^video_memory_data;
endmodule
