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
    output            compatibility_video,
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
    output      [5:0] framebuffer_write_data,

    input             hdmi_read_clk,
    input       [9:0] hdmi_source_x,
    input       [7:0] hdmi_source_y,
    input             hdmi_source_valid,
    input       [7:0] hdmi_prefetch_y,
    input             hdmi_prefetch_valid,
    output      [5:0] hdmi_pixel_data,
    input             cvbs_read_clk,
    input       [9:0] cvbs_source_x,
    input       [7:0] cvbs_source_y,
    input             cvbs_source_valid,
    input       [7:0] cvbs_prefetch_y,
    input             cvbs_prefetch_valid,
    output      [5:0] cvbs_pixel_data
);
    wire core_reset_n = reset_n && cpu_reset_n;

    wire fast_mode;
    gime_timing timing (
        // E/Q must run while the physical CPU is held in RESET; register and
        // video state remain reset until cpu_reset_n is released.
        .clk(clk), .reset_n(reset_n), .fast_mode(fast_mode), .e(e), .q(q),
        .e_pin(e_pin), .q_pin(q_pin),
        .e_rise(e_rise), .e_fall(e_fall)
    );

    wire [7:0] vmode;
    wire [7:0] vres;
    wire [5:0] border_color;
    wire [3:0] vertical_scroll;
    wire [15:0] video_offset;
    wire [7:0] horizontal_offset;
    wire compatibility_mode;
    assign compatibility_video = compatibility_mode;
    wire [6:0] sam_video_offset;
    wire [95:0] palettes;
    gime_registers registers (
        .clk(clk), .reset_n(core_reset_n), .e(e), .e_fall(e_fall),
        .cpu_addr(cpu_addr), .cpu_rw_n(cpu_rw_n), .cpu_data(cpu_data),
        .serint_n(serint_n), .keyint_n(keyint_n), .cart_n(cart_n),
        .hs_n(hs_n), .fs_n(fs_n),
        .irq_assert(irq_assert), .firq_assert(firq_assert),
        .fast_mode(fast_mode),
        .core_rdata(core_rdata), .core_data_oe(core_data_oe), .sam_s(sam_s),
        .cpu_mem_read(cpu_mem_read), .cpu_mem_write(cpu_mem_write),
        .cpu_mem_is_rom(cpu_mem_is_rom), .cpu_mem_addr(cpu_mem_addr),
        .vmode(vmode), .vres(vres), .border_color(border_color),
        .vertical_scroll(vertical_scroll), .video_offset(video_offset),
        .horizontal_offset(horizontal_offset),
        .compatibility_mode(compatibility_mode),
        .sam_video_offset(sam_video_offset), .palettes(palettes)
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
        input [2:0] gm;
        begin
            if (gm <= 3'd2) compatibility_lpr=3'b010;      // 64 lines, 3x
            else if (gm <= 3'd4) compatibility_lpr=3'b001; // 96 lines, 2x
            else compatibility_lpr=3'b000;                 // 192 lines
        end
    endfunction

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
            effective_bit_plane <= DEBUG_S2_VIDEO_MODE ? debug_bit_plane :
                                   compatibility_mode ? compatibility_an_g : vmode[7];
            effective_hres <= DEBUG_S2_VIDEO_MODE ? debug_hres :
                              compatibility_mode ? compatibility_hres(compatibility_gm) :
                                                   vres[4:2];
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
                (compatibility_an_g ? compatibility_lpr(compatibility_gm) : 3'b111) :
                vmode[2:0];
            effective_screen_base <= DEBUG_S2_VIDEO_MODE ? 19'd0 :
                compatibility_mode ?
                    19'h70000 + {sam_video_offset,9'b0} :
                    {video_offset,3'b000};
        end
    end

    function [5:0] palette_rgb;
        input [5:0] color;
        begin palette_rgb={color[5],color[2],color[4],color[1],color[3],color[0]}; end
    endfunction
    assign border_rgb=compatibility_mode ?
        (compatibility_an_g ?
            (pia1_effective[3] ? 6'b111111 : 6'b001100) : 6'b000000) :
        palette_rgb(border_color);
    assign framebuffer_write=1'b0;
    assign framebuffer_write_addr=16'd0;
    assign framebuffer_write_data=6'd0;

    wire hdmi_req,cvbs_req;
    wire [22:0] hdmi_addr,cvbs_addr;
    reg hdmi_valid=0,cvbs_valid=0;
    gime_scanline_buffer hdmi_lines (
        .clk(clk),.reset_n(core_reset_n),
        .bit_plane(effective_bit_plane), .hres(effective_hres),
        .cres(effective_cres), .lines_per_row_code(effective_lines_per_row_code),
        .screen_base(effective_screen_base),
        .horizontal_offset(horizontal_offset), .palettes(palettes),
        .compatibility_mode(compatibility_mode),
        .compatibility_an_g(compatibility_an_g),
        .compatibility_css(pia1_effective[3]),
        .compatibility_int_ext(pia1_effective[4]),
        .output_width(10'd512),
        .read_clk(hdmi_read_clk),.read_x(hdmi_source_x),
        .display_y(hdmi_source_y),.display_valid(hdmi_source_valid),
        .prefetch_y(hdmi_prefetch_y),.prefetch_valid(hdmi_prefetch_valid),
        .pixel_data(hdmi_pixel_data),.memory_request(hdmi_req),.memory_addr(hdmi_addr),
        .memory_data(video_memory_data32),.memory_valid(hdmi_valid)
    );
    gime_scanline_buffer cvbs_lines (
        .clk(clk),.reset_n(core_reset_n),
        .bit_plane(effective_bit_plane),.hres(effective_hres),.cres(effective_cres),
        .lines_per_row_code(effective_lines_per_row_code),.screen_base(effective_screen_base),
        .horizontal_offset(horizontal_offset),.palettes(palettes),
        .compatibility_mode(compatibility_mode),
        .compatibility_an_g(compatibility_an_g),
        .compatibility_css(pia1_effective[3]),
        .compatibility_int_ext(pia1_effective[4]),
        .output_width(10'd640),
        .read_clk(cvbs_read_clk),.read_x(cvbs_source_x),
        .display_y(cvbs_source_y),.display_valid(cvbs_source_valid),
        .prefetch_y(cvbs_prefetch_y),.prefetch_valid(cvbs_prefetch_valid),
        .pixel_data(cvbs_pixel_data),.memory_request(cvbs_req),.memory_addr(cvbs_addr),
        .memory_data(video_memory_data32),.memory_valid(cvbs_valid)
    );

    // Lock ownership from request through response; wait for the selected
    // renderer to drop its request before accepting another transaction.
    // The request must remain asserted until memory acknowledges it: SDRAM
    // accepts video traffic only in an interleaved E-low slot, so a one-clock
    // pulse can miss that window and leave the renderer waiting forever.
    localparam M_IDLE=2'd0,M_WAIT=2'd1,M_DROP=2'd2;
    reg [1:0] mux_state=0;
    reg mux_owner=0;
    reg round_robin=0;
    reg video_request_reg=0;
    reg [22:0] video_addr_reg=0;
    assign video_memory_request=video_request_reg;
    assign video_memory_addr=video_addr_reg;
    always @(posedge clk or negedge core_reset_n) begin
        if (!core_reset_n) begin
            mux_state<=M_IDLE; mux_owner<=0; round_robin<=0;
            video_request_reg<=0; video_addr_reg<=0; hdmi_valid<=0; cvbs_valid<=0;
        end else begin
            hdmi_valid<=0; cvbs_valid<=0;
            case (mux_state)
                M_IDLE: if (hdmi_req || cvbs_req) begin
                    mux_owner <= hdmi_req && cvbs_req ? round_robin : cvbs_req;
                    video_addr_reg <= (hdmi_req && (!cvbs_req || !round_robin)) ? hdmi_addr : cvbs_addr;
                    video_request_reg<=1;
                    mux_state<=M_WAIT;
                end
                M_WAIT: if (video_memory_valid) begin
                    video_request_reg<=0;
                    if (mux_owner) cvbs_valid<=1; else hdmi_valid<=1;
                    round_robin<=!mux_owner; mux_state<=M_DROP;
                end
                M_DROP: if (mux_owner ? !cvbs_req : !hdmi_req) mux_state<=M_IDLE;
            endcase
        end
    end

    function [7:0] line_count;
        input [1:0] value;
        begin case(value) 2'b00:line_count=192; 2'b01:line_count=199;
              2'b11:line_count=225; default:line_count=0; endcase end
    endfunction
    assign active_height=line_count(effective_lpf);
    gime_native_video native_video(
        .clk(clk),.reset_n(core_reset_n),.active_height(active_height),
        .pixel_rgb(hdmi_pixel_data),.hs_n(hs_n),.fs_n(fs_n),
        .hblank(hblank),.vblank(vblank),.red(red),.green(green),.blue(blue));

    wire unused_vertical_scroll = ^vertical_scroll;
    wire unused_video_byte = ^video_memory_data;
endmodule
