module gime_video (
    input clk, input reset_n,
    input bit_plane, input [2:0] hres, input [1:0] cres,
    input [2:0] lines_per_row_code, input [1:0] lpf,
    input [18:0] screen_base, input [7:0] horizontal_offset,
    input [95:0] palettes, input [5:0] border_color,
    input [7:0] memory_data, input memory_data_valid,
    output reg video_read_request, output reg [22:0] memory_addr,
    output reg framebuffer_write, output reg [15:0] framebuffer_write_addr,
    output reg [5:0] framebuffer_write_data,
    output reg [7:0] active_height,
    output reg hs_n, output reg fs_n, output reg hblank, output reg vblank,
    output [7:0] red, output [7:0] green, output [7:0] blue,
    output [5:0] border_rgb
);
    function [5:0] palette_rgb;
        input [5:0] color;
        begin
            // GIME RGB palette bits are R1,G1,B1,R0,G0,B0.
            palette_rgb = {color[5],color[2],color[4],color[1],color[3],color[0]};
        end
    endfunction

    function [7:0] line_count;
        input [1:0] value;
        begin
            case (value)
                2'b00: line_count = 8'd192;
                2'b01: line_count = 8'd199; // real GIME 200-line off-by-one
                2'b11: line_count = 8'd225;
                default: line_count = 8'd0;
            endcase
        end
    endfunction

    function [7:0] row_bytes_graphics;
        input [2:0] value;
        begin
            case (value)
                3'd0: row_bytes_graphics=8'd16;
                3'd1: row_bytes_graphics=8'd20;
                3'd2: row_bytes_graphics=8'd32;
                3'd3: row_bytes_graphics=8'd40;
                3'd4: row_bytes_graphics=8'd64;
                3'd5: row_bytes_graphics=8'd80;
                3'd6: row_bytes_graphics=8'd128;
                default: row_bytes_graphics=8'd160;
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

    wire [7:0] next_graphics_row_bytes = row_bytes_graphics(hres);
    wire [6:0] next_columns = text_columns(hres);
    wire next_attributes = !bit_plane && cres[0];
    wire [8:0] next_text_row_bytes = next_attributes ?
                                      {next_columns,1'b0} : next_columns;
    wire [8:0] next_row_stride = horizontal_offset[7] ? 9'd256 :
                                  bit_plane ? {1'b0,next_graphics_row_bytes} :
                                              next_text_row_bytes;
    wire [10:0] next_source_width = bit_plane ?
            ({3'd0,next_graphics_row_bytes} << (3-cres)) :
            ({4'd0,next_columns} << 3);

    reg render_bit_plane = 1'b0;
    reg [1:0] render_cres = 2'd0;
    reg render_attributes = 1'b0;
    reg [2:0] render_lines_per_row_code = 3'd3;
    reg [8:0] render_row_stride = 9'd32;
    reg [10:0] render_source_width = 11'd256;
    reg [18:0] render_screen_base = 19'd0;
    reg [6:0] render_horizontal_offset = 7'd0;

    reg [7:0] render_x = 8'd0;
    reg [7:0] render_y = 8'd0;
    reg [7:0] text_row = 8'd0;
    reg [3:0] glyph_line = 4'd0;
    wire [18:0] x_product = render_x * render_source_width;
    wire [10:0] calculated_source_x = x_product[18:8];
    wire [18:0] calculated_row_address = render_bit_plane ?
                 render_y * render_row_stride : text_row * render_row_stride;
    reg [10:0] pixel_source_x = 11'd0;
    reg [18:0] pixel_row_address = 19'd0;
    wire [10:0] shifted_graphics_byte =
                pixel_source_x >> (3-render_cres);
    wire [7:0] pixel_graphics_byte = shifted_graphics_byte[7:0];
    wire [6:0] pixel_character_column = pixel_source_x[9:3];
    wire [18:0] prepared_byte_address = render_bit_plane ?
        render_screen_base + pixel_row_address + pixel_graphics_byte +
            {11'd0,render_horizontal_offset,1'b0} :
        render_screen_base + pixel_row_address +
        (render_attributes ? {11'd0,pixel_character_column,1'b0} :
                             {12'd0,pixel_character_column}) +
            {11'd0,render_horizontal_offset,1'b0};
    reg [18:0] pixel_byte_address = 19'd0;

    reg cache_valid = 1'b0;
    reg [18:0] cache_addr = 19'd0;
    reg [7:0] cache_data = 8'd0;
    reg attr_valid = 1'b0;
    reg [18:0] attr_addr = 19'd0;
    reg [7:0] attr_data = 8'd0;
    reg [10:0] char_rom_addr = 11'd0;
    wire [7:0] char_rom_data;
    mc6847_char_rom character_rom(.clk(clk),.addr(char_rom_addr),.data(char_rom_data));

    reg [10:0] mode_signature = 11'h7ff;
    wire [10:0] current_signature = {bit_plane,hres,cres,lpf,lines_per_row_code};
    localparam PREPARE=4'd0, ADDRESS=4'd1, CHECK=4'd2, WAIT_DATA=4'd3,
               REQUEST_ATTR=4'd4, WAIT_ATTR=4'd5, WAIT_FONT=4'd6,
               COLOR_INDEX=4'd7, WRITE_PIXEL=4'd8;
    reg [3:0] state = PREPARE;

    reg [3:0] color_index;
    reg pixel_set;
    always @(*) begin
        case (render_cres)
            2'b00: color_index = {3'b000,cache_data[7-pixel_source_x[2:0]]};
            2'b01: begin
                case (pixel_source_x[1:0])
                    2'd0: color_index={2'b00,cache_data[7:6]};
                    2'd1: color_index={2'b00,cache_data[5:4]};
                    2'd2: color_index={2'b00,cache_data[3:2]};
                    default: color_index={2'b00,cache_data[1:0]};
                endcase
            end
            default: color_index = pixel_source_x[0] ? cache_data[3:0] : cache_data[7:4];
        endcase
        pixel_set = char_rom_data[7-pixel_source_x[2:0]];
        if (!render_bit_plane)
            color_index = render_attributes ?
                (pixel_set ? {1'b0,attr_data[5:3]} : {1'b1,attr_data[2:0]}) :
                (pixel_set ? 4'd1 : 4'd0);
    end
    reg [3:0] pixel_color_index = 4'd0;
    wire [5:0] selected_palette = palettes[pixel_color_index*6 +: 6];

    task advance_pixel;
        begin
            if (render_x == 8'd255) begin
                render_x <= 8'd0;
                if (render_y + 1'b1 >= active_height) begin
                    render_y <= 8'd0;
                    text_row <= 8'd0;
                    glyph_line <= 4'd0;
                end else begin
                    render_y <= render_y + 1'b1;
                    if (glyph_line + 1'b1 >= lines_per_row(render_lines_per_row_code)) begin
                        glyph_line <= 4'd0;
                        text_row <= text_row + 1'b1;
                    end else glyph_line <= glyph_line + 1'b1;
                end
            end else render_x <= render_x + 1'b1;
        end
    endtask

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            render_x<=0; render_y<=0; text_row<=0; glyph_line<=0;
            cache_valid<=0; attr_valid<=0; state<=PREPARE;
            memory_addr<=0; video_read_request<=0; framebuffer_write<=0;
            framebuffer_write_addr<=0; framebuffer_write_data<=0;
            active_height<=8'd192; mode_signature<=11'h7ff;
        end else begin
            video_read_request <= 1'b0;
            framebuffer_write <= 1'b0;
            active_height <= line_count(lpf);
            render_bit_plane <= bit_plane;
            render_cres <= cres;
            render_attributes <= next_attributes;
            render_lines_per_row_code <= lines_per_row_code;
            render_row_stride <= next_row_stride;
            render_source_width <= next_source_width;
            render_screen_base <= screen_base;
            render_horizontal_offset <= horizontal_offset[6:0];
            if (current_signature != mode_signature) begin
                mode_signature <= current_signature;
                render_x<=0; render_y<=0; text_row<=0; glyph_line<=0;
                cache_valid<=0; attr_valid<=0; state<=PREPARE;
            end else if (active_height != 0) begin
                case (state)
                    PREPARE: begin
                        pixel_source_x <= calculated_source_x;
                        pixel_row_address <= calculated_row_address;
                        state <= ADDRESS;
                    end
                    ADDRESS: begin
                        pixel_byte_address <= prepared_byte_address;
                        state <= CHECK;
                    end
                    CHECK: begin
                        if (!cache_valid || cache_addr != pixel_byte_address) begin
                            memory_addr <= {4'd0,pixel_byte_address};
                            video_read_request <= 1'b1;
                            state <= WAIT_DATA;
                        end else if (!render_bit_plane) begin
                            if (render_attributes &&
                                (!attr_valid || attr_addr != pixel_byte_address+1'b1))
                                state <= REQUEST_ATTR;
                            else begin
                                char_rom_addr <= {cache_data[6:0],glyph_line};
                                state <= WAIT_FONT;
                            end
                        end else state <= COLOR_INDEX;
                    end
                    WAIT_DATA: if (memory_data_valid) begin
                        cache_data <= memory_data;
                        cache_addr <= memory_addr[18:0];
                        cache_valid <= 1'b1;
                        if (!render_bit_plane && render_attributes) state <= REQUEST_ATTR;
                        else if (!render_bit_plane) begin
                            char_rom_addr <= {memory_data[6:0],glyph_line};
                            state <= WAIT_FONT;
                        end else state <= COLOR_INDEX;
                    end
                    REQUEST_ATTR: begin
                        memory_addr <= {4'd0,pixel_byte_address+1'b1};
                        video_read_request <= 1'b1;
                        state <= WAIT_ATTR;
                    end
                    WAIT_ATTR: if (memory_data_valid) begin
                        attr_data <= memory_data;
                        attr_addr <= memory_addr[18:0];
                        attr_valid <= 1'b1;
                        char_rom_addr <= {cache_data[6:0],glyph_line};
                        state <= WAIT_FONT;
                    end
                    WAIT_FONT: state <= COLOR_INDEX;
                    COLOR_INDEX: begin
                        pixel_color_index <= color_index;
                        state <= WRITE_PIXEL;
                    end
                    default: begin
                        framebuffer_write_addr <= {render_y,render_x};
                        framebuffer_write_data <= palette_rgb(selected_palette);
                        framebuffer_write <= 1'b1;
                        advance_pixel();
                        state <= PREPARE;
                    end
                endcase
            end
        end
    end

    assign border_rgb = palette_rgb(border_color);
    assign red   = {4{framebuffer_write_data[5:4]}};
    assign green = {4{framebuffer_write_data[3:2]}};
    assign blue  = {4{framebuffer_write_data[1:0]}};

    // Native-frequency syncs for the external CoCo timing inputs.  The shared
    // HDMI/CVBS paths scan the completed framebuffer independently.
    localparam [31:0] RASTER_STEP = 32'd569408471;
    reg [31:0] raster_accumulator = 32'd0;
    wire [32:0] raster_sum = {1'b0,raster_accumulator}+{1'b0,RASTER_STEP};
    reg [9:0] raster_x = 10'd0;
    reg [8:0] raster_y = 9'd0;
    wire [8:0] raster_top = (9'd262-{1'b0,active_height}) >> 1;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            raster_accumulator<=0; raster_x<=0; raster_y<=0;
            hs_n<=1; fs_n<=1; hblank<=1; vblank<=1;
        end else begin
            raster_accumulator <= raster_sum[31:0];
            if (raster_sum[32]) begin
                hs_n <= raster_x >= 10'd64;
                fs_n <= raster_y >= 9'd3;
                hblank <= raster_x < 10'd200 || raster_x >= 10'd840;
                vblank <= raster_y < raster_top || raster_y >= raster_top+active_height;
                if (raster_x == 10'd909) begin
                    raster_x <= 0;
                    raster_y <= raster_y == 9'd261 ? 9'd0 : raster_y+1'b1;
                end else raster_x <= raster_x+1'b1;
            end
        end
    end
endmodule
