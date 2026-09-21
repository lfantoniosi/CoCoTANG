// Full-screen 6809 bus logger for board bring-up. The 720x480 HDMI active
// area is divided into 90x60 8-pixel character cells.  The CoCo 3 layout has
// two fixed status rows plus headings, so its two columns show 114 cycles.
module hdmi_debug_overlay #(
    parameter integer LOG_ADDR_WIDTH = 9,
    parameter integer LOG_COUNT_WIDTH = 9,
    parameter integer LOG_PAGE_WIDTH = 2,
    parameter integer LOG_DEPTH = 512,
    parameter integer EXTENDED_HEADER = 0
) (
    input  logic         pixel_clk,
    input  logic [9:0]   x,
    input  logic [9:0]   y,
    input  logic         enable,
    input  logic [319:0] debug_data,
    input  logic         debug_clk,
    input  logic         log_we,
    input  logic [LOG_ADDR_WIDTH-1:0] log_addr,
    input  logic [47:0]  log_data,
    input  logic [LOG_COUNT_WIDTH-1:0] log_count,
    input  logic [LOG_ADDR_WIDTH-1:0] log_base,
    input  logic [LOG_PAGE_WIDTH-1:0] log_page,
    input  logic [4:0]   debug_status,
    input  logic [3:0]   interrupt_status,
    input  logic [79:0]  gime_register_debug,
    input  logic [95:0]  mmu_register_debug,
    input  logic         rom_verify_done,
    input  logic         rom_verify_pass,
    input  logic [15:0]  rom_verify_vector,
    input  logic         sdram_test_done,
    input  logic         sdram_test_pass,
    input  logic [18:0]  sdram_test_error_addr,
    input  logic [7:0]   sdram_test_expected,
    input  logic [7:0]   sdram_test_actual,
    input  logic [23:0]  rgb_in,
    output logic [23:0]  rgb_out
);
    // Infer a true simple dual-port RAM: every debug-clock write is retained,
    // while the renderer reads an independent port on pixel_clk.  A one-bit
    // event toggle cannot be used here because consecutive 108 MHz log writes
    // can occur before the 27 MHz pixel domain observes either edge.
    logic [47:0] display_memory [0:LOG_DEPTH-1];
    // Pipeline the logger output for a full 108 MHz cycle before writing the
    // embedded RAM.  Consecutive CPU cycles are far slower than this clock,
    // and the full-cycle path gives the large 8192-entry RAM safe margin.
    logic log_we_half = 1'b0;
    logic [LOG_ADDR_WIDTH-1:0] log_addr_half = '0;
    logic [47:0] log_data_half = '0;
    always_ff @(posedge debug_clk) begin
        log_we_half <= log_we;
        log_addr_half <= log_addr;
        log_data_half <= log_data;
    end
    always_ff @(posedge debug_clk) begin
        if (log_we_half)
            display_memory[log_addr_half] <= log_data_half;
    end

    // Only the monotonically increasing count crosses domains.  Gray coding
    // guarantees that at most one synchronized bit changes at a time, so the
    // HDMI side never constructs a torn binary count.
    wire [LOG_COUNT_WIDTH-1:0] log_count_gray =
        log_count ^ (log_count >> 1);
    logic [LOG_COUNT_WIDTH-1:0] count_gray_meta = '0;
    logic [LOG_COUNT_WIDTH-1:0] count_gray_pixel = '0;
    logic [LOG_COUNT_WIDTH-1:0] display_count = '0;
    wire [LOG_ADDR_WIDTH-1:0] log_base_gray = log_base ^ (log_base >> 1);
    logic [LOG_ADDR_WIDTH-1:0] base_gray_meta = '0;
    logic [LOG_ADDR_WIDTH-1:0] base_gray_pixel = '0;
    logic [LOG_ADDR_WIDTH-1:0] display_base = '0;
    logic [LOG_ADDR_WIDTH-1:0] entry_index;
    logic [LOG_ADDR_WIDTH:0] entry_index_full;
    logic [6:0] page_entry_index;
    logic [47:0] entry = 48'd0;

    function automatic [LOG_COUNT_WIDTH-1:0] gray_to_binary(
        input logic [LOG_COUNT_WIDTH-1:0] gray
    );
        integer bit_index;
        begin
            gray_to_binary[LOG_COUNT_WIDTH-1]=gray[LOG_COUNT_WIDTH-1];
            for (bit_index=LOG_COUNT_WIDTH-2; bit_index>=0;
                 bit_index=bit_index-1)
                gray_to_binary[bit_index]=gray_to_binary[bit_index+1] ^
                                          gray[bit_index];
        end
    endfunction

    function automatic [LOG_ADDR_WIDTH-1:0] base_gray_to_binary(
        input logic [LOG_ADDR_WIDTH-1:0] gray
    );
        integer bit_index;
        begin
            base_gray_to_binary[LOG_ADDR_WIDTH-1]=gray[LOG_ADDR_WIDTH-1];
            for (bit_index=LOG_ADDR_WIDTH-2; bit_index>=0;
                 bit_index=bit_index-1)
                base_gray_to_binary[bit_index]=
                    base_gray_to_binary[bit_index+1]^gray[bit_index];
        end
    endfunction

    always_ff @(posedge pixel_clk) begin
        count_gray_meta <= log_count_gray;
        count_gray_pixel <= count_gray_meta;
        display_count <= gray_to_binary(count_gray_pixel);
        base_gray_meta <= log_base_gray;
        base_gray_pixel <= base_gray_meta;
        display_base <= base_gray_to_binary(base_gray_pixel);
        // Gowin implements display_memory as synchronous embedded RAM.  Read
        // the selected row explicitly on pixel_clk rather than relying on an
        // asynchronous array access whose hardware behavior does not match
        // the renderer's combinational assumption.
        entry <= display_memory[entry_index];
    end

    function automatic logic [7:0] hex_char(input logic [3:0] value);
        hex_char = value < 10 ? (8'h30 + value) : (8'h41 + value - 10);
    endfunction

    function automatic logic [7:0] bit_char(input logic value);
        bit_char = value ? "1" : "0";
    endfunction

    function automatic logic [34:0] glyph(input logic [7:0] c);
        begin
            case (c)
                "0": glyph={5'b01110,5'b10001,5'b10011,5'b10101,5'b11001,5'b10001,5'b01110};
                "1": glyph={5'b00100,5'b01100,5'b00100,5'b00100,5'b00100,5'b00100,5'b01110};
                "2": glyph={5'b01110,5'b10001,5'b00001,5'b00010,5'b00100,5'b01000,5'b11111};
                "3": glyph={5'b11110,5'b00001,5'b00001,5'b01110,5'b00001,5'b00001,5'b11110};
                "4": glyph={5'b00010,5'b00110,5'b01010,5'b10010,5'b11111,5'b00010,5'b00010};
                "5": glyph={5'b11111,5'b10000,5'b10000,5'b11110,5'b00001,5'b00001,5'b11110};
                "6": glyph={5'b01110,5'b10000,5'b10000,5'b11110,5'b10001,5'b10001,5'b01110};
                "7": glyph={5'b11111,5'b00001,5'b00010,5'b00100,5'b01000,5'b01000,5'b01000};
                "8": glyph={5'b01110,5'b10001,5'b10001,5'b01110,5'b10001,5'b10001,5'b01110};
                "9": glyph={5'b01110,5'b10001,5'b10001,5'b01111,5'b00001,5'b00001,5'b01110};
                "A": glyph={5'b01110,5'b10001,5'b10001,5'b11111,5'b10001,5'b10001,5'b10001};
                "B": glyph={5'b11110,5'b10001,5'b10001,5'b11110,5'b10001,5'b10001,5'b11110};
                "C": glyph={5'b01111,5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b01111};
                "D": glyph={5'b11110,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b11110};
                "E": glyph={5'b11111,5'b10000,5'b10000,5'b11110,5'b10000,5'b10000,5'b11111};
                "F": glyph={5'b11111,5'b10000,5'b10000,5'b11110,5'b10000,5'b10000,5'b10000};
                "G": glyph={5'b01111,5'b10000,5'b10000,5'b10111,5'b10001,5'b10001,5'b01111};
                "H": glyph={5'b10001,5'b10001,5'b10001,5'b11111,5'b10001,5'b10001,5'b10001};
                "I": glyph={5'b01110,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100,5'b01110};
                "L": glyph={5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b11111};
                "M": glyph={5'b10001,5'b11011,5'b10101,5'b10101,5'b10001,5'b10001,5'b10001};
                "O": glyph={5'b01110,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01110};
                "P": glyph={5'b11110,5'b10001,5'b10001,5'b11110,5'b10000,5'b10000,5'b10000};
                "Q": glyph={5'b01110,5'b10001,5'b10001,5'b10001,5'b10101,5'b10010,5'b01101};
                "R": glyph={5'b11110,5'b10001,5'b10001,5'b11110,5'b10100,5'b10010,5'b10001};
                "S": glyph={5'b01111,5'b10000,5'b10000,5'b01110,5'b00001,5'b00001,5'b11110};
                "T": glyph={5'b11111,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100};
                "U": glyph={5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01110};
                "W": glyph={5'b10001,5'b10001,5'b10001,5'b10101,5'b10101,5'b10101,5'b01010};
                ":": glyph={5'b00000,5'b00100,5'b00100,5'b00000,5'b00100,5'b00100,5'b00000};
                "/": glyph={5'b00001,5'b00010,5'b00100,5'b01000,5'b10000,5'b00000,5'b00000};
                "-": glyph={5'b00000,5'b00000,5'b00000,5'b11111,5'b00000,5'b00000,5'b00000};
                default: glyph=35'd0;
            endcase
        end
    endfunction

    logic [6:0] character_column;
    logic [5:0] character_row;
    logic [6:0] local_column;
    logic [7:0] character;
    logic [34:0] character_glyph;
    logic [2:0] glyph_column,glyph_row;
    logic valid_entry,text_pixel,in_panel;
    logic [23:0] rgb_comb;
    logic [15:0] entry_index_16;
    logic [15:0] display_count_16;
    logic [7:0] log_page_8;
    logic [3:0] status_mmu_index;
    logic [5:0] status_mmu_page;

    localparam integer TRACE_FIRST_ROW = (EXTENDED_HEADER==2) ? 3 : 2;
    localparam integer TRACE_ROWS_PER_COLUMN =
        (EXTENDED_HEADER==2) ? 57 : 58;
    localparam integer TRACE_ENTRIES_PER_PAGE =
        TRACE_ROWS_PER_COLUMN * 2;

    always_comb begin
        character_column=x[9:3];
        character_row=y[8:3];
        glyph_column=x[2:0];
        glyph_row=y[2:0];
        in_panel=enable && x < 10'd720 && y < 10'd480;
        local_column=(character_column >= 7'd45) ?
                     character_column-7'd45 : character_column;
        page_entry_index={1'b0,character_row}-TRACE_FIRST_ROW;
        if (character_column >= 7'd45)
            page_entry_index=page_entry_index+TRACE_ROWS_PER_COLUMN;
        entry_index_full=(log_page * TRACE_ENTRIES_PER_PAGE)+page_entry_index;
        entry_index=display_base+entry_index_full[LOG_ADDR_WIDTH-1:0];
        entry_index_16={{(15-LOG_ADDR_WIDTH){1'b0}},entry_index_full};
        display_count_16={{(16-LOG_COUNT_WIDTH){1'b0}},display_count};
        log_page_8={{(8-LOG_PAGE_WIDTH){1'b0}},log_page};
        valid_entry=(character_row >= TRACE_FIRST_ROW) &&
                    (entry_index_full < LOG_DEPTH) &&
                    (entry_index_full < display_count) &&
                    ((EXTENDED_HEADER==2) ? entry[47] : entry[39]);
        character=" ";
        status_mmu_index=0;
        status_mmu_page=0;

        if (character_row == 0 && EXTENDED_HEADER != 0) begin
            case (character_column)
                0:character="C"; 1:character="P"; 2:character="U";
                4:character="B"; 5:character="U"; 6:character="S";
                8:character="L"; 9:character="O"; 10:character="G";
                13:character="C"; 14:character="A"; 15:character="P";
                16:character=":";
                17:character=hex_char(display_count_16[15:12]);
                18:character=hex_char(display_count_16[11:8]);
                19:character=hex_char(display_count_16[7:4]);
                20:character=hex_char(display_count_16[3:0]);
                22:character="P"; 23:character=":";
                24:character=hex_char(log_page_8[7:4]);
                25:character=hex_char(log_page_8[3:0]);
                28:character=(EXTENDED_HEADER==2) ? "K" : "R";
                29:character=":";
                30:character=bit_char((EXTENDED_HEADER==2) ?
                                      interrupt_status[3] : debug_status[3]);
                32:character=(EXTENDED_HEADER==2) ? "S" : "H";
                33:character=":";
                34:character=bit_char((EXTENDED_HEADER==2) ?
                                      interrupt_status[2] : debug_status[2]);
                36:character="I"; 37:character=":";
                38:character=bit_char((EXTENDED_HEADER==2) ?
                                      interrupt_status[1] : debug_status[1]);
                40:character=(EXTENDED_HEADER==2) ? "F" : "S";
                41:character=":";
                42:character=bit_char((EXTENDED_HEADER==2) ?
                                      interrupt_status[0] : debug_status[0]);
                44:character="R";45:character="G";46:character=":";
                47:character=hex_char(debug_data[31:28]);
                49:character="S";50:character="T";51:character=":";
                52:character=hex_char(debug_data[27:24]);
                54:character="N";55:character="Y";56:character=":";
                57:character=hex_char(debug_data[23:20]);
                58:character=hex_char(debug_data[19:16]);
                60:character="D";61:character="Y";62:character=":";
                63:character=hex_char(debug_data[15:12]);
                64:character=hex_char(debug_data[11:8]);
                66:character="F";67:character="Y";68:character=":";
                69:character=hex_char(debug_data[7:4]);
                70:character=hex_char(debug_data[3:0]);
                default: ;
            endcase
        end else if (character_row == 0) begin
            case (character_column)
                0:character="C"; 1:character="O"; 2:character="C";
                3:character="O"; 4:character="2"; 6:character="B";
                7:character="U"; 8:character="S"; 10:character="L";
                11:character="O"; 12:character="G"; 15:character="C";
                16:character="A"; 17:character="P"; 18:character=":";
                19:character=hex_char(display_count[8]);
                20:character=hex_char(display_count[7:4]);
                21:character=hex_char(display_count[3:0]);
                23:character="P"; 24:character=hex_char({2'b00,log_page});
                26:character="S"; 27:character="2"; 29:character="H";
                30:character="I"; 31:character="D"; 32:character="E";
                35:character="Y"; 36:character=":";
                37:character=bit_char(debug_status[4]);
                39:character="R"; 40:character=":";
                41:character=bit_char(debug_status[3]);
                43:character="H"; 44:character=":";
                45:character=bit_char(debug_status[2]);
                47:character="A"; 48:character=":";
                49:character=bit_char(debug_status[1]);
                51:character="S"; 52:character=":";
                53:character=bit_char(debug_status[0]);
                default: ;
            endcase
        end else if (character_row == 1 && EXTENDED_HEADER == 2) begin
            // Complete live GIME state. Labels are register low bytes:
            // 90/91/98/99, A=FF9A, C=FF9C, D=FF9D:E, F=FF9F,
            // S=legacy SAM display offset, then all task-0/task-1 MMU pages.
            case (character_column)
                0:character="9"; 1:character="0"; 2:character=":";
                3:character=hex_char(gime_register_debug[79:76]);
                4:character=hex_char(gime_register_debug[75:72]);
                6:character="9"; 7:character="1"; 8:character=":";
                9:character=hex_char(gime_register_debug[71:68]);
                10:character=hex_char(gime_register_debug[67:64]);
                12:character="9"; 13:character="8"; 14:character=":";
                15:character=hex_char(gime_register_debug[63:60]);
                16:character=hex_char(gime_register_debug[59:56]);
                18:character="9"; 19:character="9"; 20:character=":";
                21:character=hex_char(gime_register_debug[55:52]);
                22:character=hex_char(gime_register_debug[51:48]);
                24:character="A"; 25:character=":";
                26:character=hex_char(gime_register_debug[47:44]);
                27:character=hex_char(gime_register_debug[43:40]);
                29:character="C"; 30:character=":";
                31:character=hex_char(gime_register_debug[35:32]);
                33:character="D"; 34:character=":";
                35:character=hex_char(gime_register_debug[31:28]);
                36:character=hex_char(gime_register_debug[27:24]);
                37:character=hex_char(gime_register_debug[23:20]);
                38:character=hex_char(gime_register_debug[19:16]);
                40:character="F"; 41:character=":";
                42:character=hex_char(gime_register_debug[15:12]);
                43:character=hex_char(gime_register_debug[11:8]);
                45:character="S"; 46:character=":";
                47:character=hex_char(gime_register_debug[7:4]);
                48:character=hex_char(gime_register_debug[3:0]);
                50:character="0"; 51:character=":";
                69:character="1"; 70:character=":";
                default: begin
                    if (character_column>=52 && character_column<=67) begin
                        status_mmu_index=(character_column-52)>>1;
                        status_mmu_page=
                            mmu_register_debug[status_mmu_index*6 +: 6];
                        character=character_column[0] ?
                            hex_char(status_mmu_page[3:0]) :
                            hex_char({2'b00,status_mmu_page[5:4]});
                    end else if (character_column>=71 &&
                                 character_column<=86) begin
                        status_mmu_index=8+((character_column-71)>>1);
                        status_mmu_page=
                            mmu_register_debug[status_mmu_index*6 +: 6];
                        character=character_column[0] ?
                            hex_char({2'b00,status_mmu_page[5:4]}) :
                            hex_char(status_mmu_page[3:0]);
                    end
                end
            endcase
        end else if (character_row == 1 && EXTENDED_HEADER == 1) begin
            case (local_column)
                0:character="I"; 1:character="D"; 5:character="R";
                7:character="A"; 8:character=":"; 9:character="A";
                10:character="D"; 11:character="D"; 12:character="R";
                14:character="D"; 15:character="I"; 17:character="D";
                18:character="O"; 20:character="O"; 21:character="E";
                31:character="S"; 35:character="T";
                default: ;
            endcase
        end else if (character_row == ((EXTENDED_HEADER==2) ? 2 : 1)) begin
            if (EXTENDED_HEADER == 2) begin
                case (local_column)
                    0:character="I"; 1:character="D"; 5:character="R";
                    7:character="A"; 8:character=":"; 9:character="A";
                    10:character="D";11:character="D";12:character="R";
                    14:character="D";15:character=":";16:character="I";
                    17:character="O";22:character="M";23:character=":";
                    24:character="0";27:character="1";
                    30:character="T";34:character="E";
                    default: ;
                endcase
            end else begin
                case (local_column)
                    0:character="I"; 1:character="D"; 3:character="R";
                    5:character="A"; 6:character=":"; 7:character="A";
                    8:character="D"; 9:character="D"; 10:character="R";
                    12:character="D"; 13:character="I"; 15:character="D";
                    16:character="O"; 18:character="O"; 19:character="E";
                    21:character="S";
                    default: ;
                endcase
            end
        end else if (valid_entry && EXTENDED_HEADER != 0) begin
            case (local_column)
                0:character=hex_char(entry_index_16[15:12]);
                1:character=hex_char(entry_index_16[11:8]);
                2:character=hex_char(entry_index_16[7:4]);
                3:character=hex_char(entry_index_16[3:0]);
                5:character=entry[46] ? "R" : "W";
                7:character="A"; 8:character=":";
                9:character=hex_char(entry[45:42]);
                10:character=hex_char(entry[41:38]);
                11:character=hex_char(entry[37:34]);
                12:character=hex_char(entry[33:30]);
                14:character="D";15:character=":";
                16:character=hex_char(entry[29:26]);
                17:character=hex_char(entry[25:22]);
                18:character=":";
                19:character=hex_char(entry[21:18]);
                20:character=hex_char(entry[17:14]);
                22:character="M";23:character=":";
                24:character=hex_char({2'b00,entry[11:10]});
                25:character=hex_char(entry[9:6]);
                26:character=":";
                27:character=hex_char({2'b00,entry[5:4]});
                28:character=hex_char(entry[3:0]);
                30:character="T";31:character=":";
                32:character=bit_char(entry[12]);
                34:character="E";35:character=":";
                36:character=bit_char(entry[13]);
                default: ;
            endcase
        end else if (valid_entry) begin
            case (local_column)
                0:character=hex_char({1'b0,page_entry_index[6:4]});
                1:character=hex_char(page_entry_index[3:0]);
                3:character=entry[38] ? "R" : "W";
                5:character="A"; 6:character=":";
                7:character=hex_char(entry[33:30]);
                8:character=hex_char(entry[29:26]);
                9:character=hex_char(entry[25:22]);
                10:character=hex_char(entry[21:18]);
                12:character="D"; 13:character="I"; 14:character=":";
                15:character=hex_char(entry[17:14]);
                16:character=hex_char(entry[13:10]);
                18:character="D"; 19:character="O"; 20:character=":";
                21:character=entry[34] ? hex_char(entry[9:6]) : "-";
                22:character=entry[34] ? hex_char(entry[5:2]) : "-";
                24:character="O"; 25:character="E"; 26:character=":";
                27:character=bit_char(entry[34]);
                29:character="S"; 30:character=":";
                31:character=hex_char({1'b0,entry[37:35]});
                default: ;
            endcase
        end

        character_glyph=glyph(character);
        text_pixel=in_panel && glyph_column < 3'd5 && glyph_row < 3'd7 &&
                   character_glyph[34-glyph_row*5-glyph_column];
        if (!in_panel)
            rgb_comb=rgb_in;
        else if (text_pixel)
            rgb_comb=(character_row == 0 && character_column >= 7'd44 &&
                      character_column <= 7'd57 &&
                      rom_verify_done && !rom_verify_pass) ? 24'hff4040 :
                     (character_row == 0 && character_column >= 7'd60 &&
                      sdram_test_done && !sdram_test_pass) ? 24'hff4040 :
                     (character_row == 0 ||
                      (EXTENDED_HEADER==2 && character_row==1)) ? 24'h40ffff :
                     (EXTENDED_HEADER==2 && valid_entry && !entry[46]) ?
                         24'hffff40 :
                     (EXTENDED_HEADER!=2 && valid_entry && !entry[38]) ?
                         24'hffff40 : 24'hffffff;
        else
            rgb_comb=24'h001020;
    end

    // Break the asynchronous RAM/character-rendering path before it reaches
    // the HDMI encoder.  The one-pixel pipeline delay is harmless, while the
    // registered RGB value cannot change during TMDS encoding.
    always_ff @(posedge pixel_clk)
        rgb_out <= rgb_comb;

    // Summary remains connected for compatibility and future header fields.
    logic unused_debug_data;
    assign unused_debug_data=^debug_data ^ ^log_count;
endmodule
