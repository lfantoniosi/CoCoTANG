// One output-specific, double-buffered 640-pixel GIME scanline cache.
// Rendering runs at 108 MHz; reading runs in the output pixel clock domain.
// Four adjacent bytes are retained from every SDRAM activation.
module gime_scanline_buffer (
    input             clk,
    input             reset_n,
    input             bit_plane,
    input      [2:0]  hres,
    input      [1:0]  cres,
    input      [2:0]  lines_per_row_code,
    input      [18:0] screen_base,
    input      [7:0]  horizontal_offset,
    input      [95:0] palettes,
    input             compatibility_mode,
    input             compatibility_css,
    input             compatibility_int_ext,
    input      [9:0]  output_width,

    input             read_clk,
    input      [9:0]  read_x,
    input      [7:0]  display_y,
    input             display_valid,
    input      [7:0]  prefetch_y,
    input             prefetch_valid,
    output reg [5:0]  pixel_data,

    output reg         memory_request,
    output reg [22:0]  memory_addr,
    input      [31:0] memory_data,
    input             memory_valid
);
    function [5:0] palette_rgb;
        input [5:0] color;
        begin palette_rgb = {color[5],color[2],color[4],color[1],color[3],color[0]}; end
    endfunction

    function [5:0] mc6847_bright_rgb;
        input [2:0] color;
        begin
            case (color)
                3'd0: mc6847_bright_rgb=6'b001100;
                3'd1: mc6847_bright_rgb=6'b111100;
                3'd2: mc6847_bright_rgb=6'b000011;
                3'd3: mc6847_bright_rgb=6'b110000;
                3'd4: mc6847_bright_rgb=6'b111111;
                3'd5: mc6847_bright_rgb=6'b001111;
                3'd6: mc6847_bright_rgb=6'b110011;
                default: mc6847_bright_rgb=6'b111000;
            endcase
        end
    endfunction

    function [7:0] graphics_row_bytes;
        input [2:0] value;
        begin
            case (value)
                3'd0: graphics_row_bytes=8'd16;
                3'd1: graphics_row_bytes=8'd20;
                3'd2: graphics_row_bytes=8'd32;
                3'd3: graphics_row_bytes=8'd40;
                3'd4: graphics_row_bytes=8'd64;
                3'd5: graphics_row_bytes=8'd80;
                3'd6: graphics_row_bytes=8'd128;
                default: graphics_row_bytes=8'd160;
            endcase
        end
    endfunction

    function [6:0] text_columns;
        input [2:0] value;
        begin
            case ({value[2],value[0]})
                2'b00: text_columns=7'd32;
                2'b01: text_columns=7'd40;
                2'b10: text_columns=7'd64;
                default: text_columns=7'd80;
            endcase
        end
    endfunction

    function [3:0] lines_per_row;
        input [2:0] value;
        begin
            case (value)
                3'b000: lines_per_row=4'd1;
                3'b001: lines_per_row=4'd2;
                3'b010: lines_per_row=4'd3;
                3'b011: lines_per_row=4'd8;
                3'b100: lines_per_row=4'd9;
                3'b101: lines_per_row=4'd10;
                3'b110: lines_per_row=4'd11;
                default: lines_per_row=4'd12;
            endcase
        end
    endfunction

    reg [5:0] line0 [0:639];
    reg [5:0] line1 [0:639];
    reg       tag0_valid = 1'b0, tag1_valid = 1'b0;
    reg [7:0] tag0 = 8'd0, tag1 = 8'd0;

    // Coordinates are stable for an entire output line. Two stages make the
    // request crossing deterministic without requiring a high-rate FIFO.
    reg [7:0] display_y_m=0, display_y_s=0, prefetch_y_m=0, prefetch_y_s=0;
    reg display_valid_m=0, display_valid_s=0, prefetch_valid_m=0, prefetch_valid_s=0;
    always @(posedge clk) begin
        display_y_m <= display_y; display_y_s <= display_y_m;
        display_valid_m <= display_valid; display_valid_s <= display_valid_m;
        prefetch_y_m <= prefetch_y; prefetch_y_s <= prefetch_y_m;
        prefetch_valid_m <= prefetch_valid; prefetch_valid_s <= prefetch_valid_m;
    end

    wire display_cached = (tag0_valid && tag0 == display_y_s) ||
                          (tag1_valid && tag1 == display_y_s);
    wire prefetch_cached = (tag0_valid && tag0 == prefetch_y_s) ||
                           (tag1_valid && tag1 == prefetch_y_s);
    wire request_available = (display_valid_s && !display_cached) ||
                             (prefetch_valid_s && !prefetch_cached);
    wire [7:0] requested_y = (display_valid_s && !display_cached) ?
                             display_y_s : prefetch_y_s;
    // Register the cache/tag decision before it fans into the rendering
    // state machine and all of the captured line-configuration registers.
    // This is also a clean CDC settling stage for the output coordinates.
    reg request_available_pipe = 1'b0;
    reg [7:0] requested_y_pipe = 8'd0;

    reg fill_bank = 1'b0;
    reg next_bank = 1'b0;
    reg fill_bit_plane = 1'b0;
    reg [1:0] fill_cres = 2'd0;
    reg fill_attributes = 1'b0;
    reg [3:0] fill_lpr = 4'd8;
    reg [8:0] fill_stride = 9'd32;
    reg [10:0] fill_width = 11'd256;
    reg [18:0] fill_base = 19'd0;
    reg [6:0] fill_hoff = 7'd0;
    reg [95:0] fill_palettes = 96'd0;
    reg fill_compatibility = 1'b0;
    reg fill_compatibility_css = 1'b0;
    reg fill_compatibility_int_ext = 1'b0;
    reg [9:0] fill_output_width = 10'd640;
    reg [7:0] fill_y = 8'd0;
    reg [7:0] row_remainder = 8'd0;
    reg [7:0] source_row = 8'd0;
    reg [3:0] glyph_line = 4'd0;
    reg [9:0] out_x = 10'd0;
    reg [10:0] source_x = 11'd0;
    reg [10:0] scale_phase = 11'd0;
    reg [18:0] row_address = 19'd0;
    reg [18:0] line_address = 19'd0;
    reg [18:0] byte_address = 19'd0;
    reg [31:0] word_cache = 32'd0;
    reg [18:0] word_tag = 19'd0;
    reg word_valid = 1'b0;
    reg [7:0] character = 8'd0;
    reg [7:0] attribute = 8'd0;
    reg [10:0] char_rom_addr = 11'd0;
    wire [7:0] char_rom_data;
    mc6847_char_rom character_rom(.clk(clk),.addr(char_rom_addr),.data(char_rom_data));

    wire [7:0] live_graphics_bytes = graphics_row_bytes(hres);
    wire [6:0] live_columns = text_columns(hres);
    wire live_attributes = !bit_plane && cres[0];
    wire [8:0] live_text_bytes = live_attributes ? {live_columns,1'b0} : live_columns;
    wire [8:0] live_stride = horizontal_offset[7] ? 9'd256 :
                             bit_plane ? {1'b0,live_graphics_bytes} : live_text_bytes;
    wire [10:0] graphics_width = cres == 2'd0 ? {3'd0,live_graphics_bytes,3'b000} :
                                 cres == 2'd1 ? {2'd0,live_graphics_bytes,2'b00} :
                                               {1'd0,live_graphics_bytes,1'b0};
    wire [10:0] live_width = bit_plane ? graphics_width : {1'b0,live_columns,3'b000};
    // Rendering uses the mode captured when this line fill began.  Using the
    // live CRES input here both mixed configurations within a line and left a
    // long live-register-to-address path.
    wire [10:0] graphics_byte_index = fill_cres == 2'd0 ? (source_x >> 3) :
                                        fill_cres == 2'd1 ? (source_x >> 2) : (source_x >> 1);
    wire [6:0] character_column = source_x[9:3];
    // The invariant base/row/horizontal-offset sum is pipelined once per
    // scanline.  PIXEL_ADDRESS then contains only the CRES-dependent index
    // selection and one 19-bit addition instead of a four-operand chain.
    wire [18:0] pixel_byte_index = fill_bit_plane ?
        {8'd0,graphics_byte_index} :
        (fill_attributes ? {11'd0,character_column,1'b0} :
                           {12'd0,character_column});
    wire [18:0] calculated_byte_address = line_address + pixel_byte_index;
    wire [18:0] aligned_address = {byte_address[18:2],2'b00};
    wire [7:0] cached_byte = byte_address[1:0] == 2'd0 ? word_cache[7:0] :
                             byte_address[1:0] == 2'd1 ? word_cache[15:8] :
                             byte_address[1:0] == 2'd2 ? word_cache[23:16] : word_cache[31:24];

    reg [3:0] color_index = 4'd0;
    reg pixel_set = 1'b0;
    reg [5:0] compatibility_rgb = 6'd0;
    reg semigraphics_set = 1'b0;
    always @(*) begin
        case (fill_cres)
            2'd0: color_index = {3'b000,cached_byte[7-source_x[2:0]]};
            2'd1: case (source_x[1:0])
                2'd0: color_index={2'b00,cached_byte[7:6]};
                2'd1: color_index={2'b00,cached_byte[5:4]};
                2'd2: color_index={2'b00,cached_byte[3:2]};
                default: color_index={2'b00,cached_byte[1:0]};
            endcase
            default: color_index = source_x[0] ? cached_byte[3:0] : cached_byte[7:4];
        endcase
        pixel_set = char_rom_data[7-source_x[2:0]];
        semigraphics_set = 1'b0;
        compatibility_rgb = fill_compatibility_css ? 6'b010100 : 6'b000100;
        if (!fill_bit_plane)
            color_index = fill_attributes ?
                (pixel_set ? {1'b0,attribute[5:3]} : {1'b1,attribute[2:0]}) :
                (pixel_set ? 4'd1 : 4'd0);

        if (fill_compatibility) begin
            if (character[7]) begin
                if (!fill_compatibility_int_ext) begin
                    if (glyph_line < 4'd6)
                        semigraphics_set = source_x[2] ? character[2] : character[3];
                    else
                        semigraphics_set = source_x[2] ? character[0] : character[1];
                    if (semigraphics_set)
                        compatibility_rgb = mc6847_bright_rgb(character[6:4]);
                end else begin
                    if (glyph_line < 4'd4)
                        semigraphics_set = source_x[2] ? character[4] : character[5];
                    else if (glyph_line < 4'd8)
                        semigraphics_set = source_x[2] ? character[2] : character[3];
                    else
                        semigraphics_set = source_x[2] ? character[0] : character[1];
                    if (semigraphics_set)
                        compatibility_rgb = mc6847_bright_rgb(
                            {fill_compatibility_css,character[7:6]});
                end
            end else begin
                pixel_set = char_rom_data[7-source_x[2:0]] ^ character[6];
                if (pixel_set)
                    compatibility_rgb = mc6847_bright_rgb(
                        {3{fill_compatibility_css}});
            end
        end
    end
    reg [3:0] pixel_color_index = 4'd0;
    wire [5:0] pixel_palette = fill_palettes[pixel_color_index*6 +: 6];

    localparam IDLE=4'd0, DIVIDE_ROW=4'd1, ROW_ADDRESS=4'd2, LINE_ADDRESS=4'd3,
               PIXEL_ADDRESS=4'd4, CHECK_WORD=4'd5, WAIT_WORD=4'd6,
               GOT_CHARACTER=4'd7, CHECK_ATTRIBUTE=4'd8,
               WAIT_ATTRIBUTE=4'd9, FONT_WAIT=4'd10,
               COLOR_INDEX=4'd11, WRITE_PIXEL=4'd12;
    reg [3:0] state = IDLE;
    reg [10:0] phase_sum;
    reg [11:0] mode_signature = 12'hfff;
    reg [18:0] last_screen_base = 19'h7ffff;
    reg [7:0] last_horizontal_offset = 8'hff;
    reg [9:0] last_output_width = 10'd0;
    wire [11:0] live_signature = {compatibility_mode,compatibility_css,
                                  compatibility_int_ext,bit_plane,hres,cres,
                                  lines_per_row_code};
    wire configuration_diff = live_signature != mode_signature ||
                              screen_base != last_screen_base ||
                              horizontal_offset != last_horizontal_offset ||
                              output_width != last_output_width;
    reg configuration_changed = 1'b1;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            request_available_pipe <= 1'b0;
            requested_y_pipe <= 8'd0;
        end else begin
            request_available_pipe <= (state == IDLE) && request_available;
            requested_y_pipe <= requested_y;
        end
    end

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state<=IDLE; memory_request<=0; memory_addr<=0;
            tag0_valid<=0; tag1_valid<=0; next_bank<=0; mode_signature<=12'hfff;
            last_screen_base<=19'h7ffff; last_horizontal_offset<=8'hff;
            last_output_width<=10'd0;
            configuration_changed<=1'b1;
        end else begin
            configuration_changed <= configuration_diff;
            if (configuration_changed) begin
                mode_signature <= live_signature;
                last_screen_base <= screen_base;
                last_horizontal_offset <= horizontal_offset;
                last_output_width <= output_width;
                tag0_valid <= 1'b0; tag1_valid <= 1'b0;
                state <= IDLE; memory_request <= 1'b0; word_valid <= 1'b0;
            end else case (state)
                IDLE: if (request_available_pipe) begin
                    fill_y <= requested_y_pipe;
                    // Never overwrite a line which is currently being scanned.
                    if (tag0_valid && tag0 == display_y_s) fill_bank <= 1'b1;
                    else if (tag1_valid && tag1 == display_y_s) fill_bank <= 1'b0;
                    else fill_bank <= next_bank;
                    fill_bit_plane<=bit_plane; fill_cres<=cres;
                    fill_attributes<=live_attributes; fill_lpr<=lines_per_row(lines_per_row_code);
                    fill_stride<=live_stride; fill_width<=live_width;
                    fill_base<=screen_base; fill_hoff<=horizontal_offset[6:0];
                    fill_palettes<=palettes;
                    fill_compatibility<=compatibility_mode;
                    fill_compatibility_css<=compatibility_css;
                    fill_compatibility_int_ext<=compatibility_int_ext;
                    fill_output_width<=output_width;
                    row_remainder<=requested_y_pipe; source_row<=0;
                    word_valid<=0; state<=DIVIDE_ROW;
                end
                DIVIDE_ROW: begin
                    if (row_remainder >= fill_lpr) begin
                        row_remainder <= row_remainder - fill_lpr;
                        source_row <= source_row + 1'b1;
                    end else begin
                        glyph_line <= row_remainder[3:0];
                        state <= ROW_ADDRESS;
                    end
                end
                ROW_ADDRESS: begin
                    row_address <= source_row * fill_stride;
                    out_x<=0; source_x<=0; scale_phase<=0;
                    state<=LINE_ADDRESS;
                end
                LINE_ADDRESS: begin
                    line_address<=fill_base+row_address+
                                  {11'd0,fill_hoff,1'b0};
                    state<=PIXEL_ADDRESS;
                end
                PIXEL_ADDRESS: begin byte_address<=calculated_byte_address; state<=CHECK_WORD; end
                CHECK_WORD: begin
                    if (!word_valid || word_tag != aligned_address) begin
                        memory_addr <= {4'd0,aligned_address};
                        memory_request <= 1'b1;
                        state <= WAIT_WORD;
                    end else if (fill_bit_plane) state<=COLOR_INDEX;
                    else begin
                        character<=cached_byte;
                        if (fill_attributes) begin byte_address<=byte_address+1'b1; state<=CHECK_ATTRIBUTE; end
                        else begin char_rom_addr<={cached_byte[6:0],glyph_line}; state<=FONT_WAIT; end
                    end
                end
                WAIT_WORD: if (memory_valid) begin
                    word_cache<=memory_data; word_tag<=aligned_address; word_valid<=1;
                    memory_request<=0; state<=CHECK_WORD;
                end
                CHECK_ATTRIBUTE: begin
                    if (!word_valid || word_tag != aligned_address) begin
                        memory_addr<={4'd0,aligned_address}; memory_request<=1; state<=WAIT_ATTRIBUTE;
                    end else begin
                        attribute<=cached_byte; char_rom_addr<={character[6:0],glyph_line}; state<=FONT_WAIT;
                    end
                end
                WAIT_ATTRIBUTE: if (memory_valid) begin
                    word_cache<=memory_data; word_tag<=aligned_address; word_valid<=1;
                    memory_request<=0; state<=CHECK_ATTRIBUTE;
                end
                FONT_WAIT: state<=COLOR_INDEX;
                COLOR_INDEX: begin pixel_color_index<=color_index; state<=WRITE_PIXEL; end
                WRITE_PIXEL: begin
                    if (fill_bank)
                        line1[out_x] <= fill_compatibility ? compatibility_rgb :
                                        palette_rgb(pixel_palette);
                    else
                        line0[out_x] <= fill_compatibility ? compatibility_rgb :
                                        palette_rgb(pixel_palette);
                    if (out_x == fill_output_width-1'b1) begin
                        if (fill_bank) begin tag1<=fill_y; tag1_valid<=1; end
                        else begin tag0<=fill_y; tag0_valid<=1; end
                        next_bank<=!fill_bank; state<=IDLE;
                    end else begin
                        out_x<=out_x+1'b1;
                        phase_sum = scale_phase + fill_width;
                        if (phase_sum >= fill_output_width) begin
                            scale_phase<=phase_sum-fill_output_width; source_x<=source_x+1'b1;
                        end else scale_phase<=phase_sum;
                        state<=PIXEL_ADDRESS;
                    end
                end
                default: state<=IDLE;
            endcase
        end
    end

    reg [7:0] tag0_m=0,tag0_r=0,tag1_m=0,tag1_r=0;
    reg valid0_m=0,valid0_r=0,valid1_m=0,valid1_r=0;
    always @(posedge read_clk) begin
        tag0_m<=tag0; tag0_r<=tag0_m; tag1_m<=tag1; tag1_r<=tag1_m;
        valid0_m<=tag0_valid; valid0_r<=valid0_m;
        valid1_m<=tag1_valid; valid1_r<=valid1_m;
        if (!display_valid) pixel_data<=0;
        else if (valid0_r && tag0_r==display_y) pixel_data<=line0[read_x];
        else if (valid1_r && tag1_r==display_y) pixel_data<=line1[read_x];
        else pixel_data<=0;
    end
endmodule
