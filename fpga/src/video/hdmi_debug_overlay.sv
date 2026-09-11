// Full-screen 6809 bus logger for board bring-up. The 720x480 HDMI active
// area is divided into 90x60 8-pixel character cells. Two columns show the
// 116 bus cycles per page, with four pages captured after CPU reset.
module hdmi_debug_overlay (
    input  logic         pixel_clk,
    input  logic [9:0]   x,
    input  logic [9:0]   y,
    input  logic         enable,
    input  logic [319:0] debug_data,
    input  logic         debug_clk,
    input  logic         log_we,
    input  logic [8:0]   log_addr,
    input  logic [39:0]  log_data,
    input  logic [8:0]   log_count,
    input  logic [1:0]   log_page,
    input  logic [4:0]   debug_status,
    input  logic [23:0]  rgb_in,
    output logic [23:0]  rgb_out
);
    // Cross each completed logger word as bundled data.  The source payload
    // remains unchanged until the following CPU cycle (many pixel clocks),
    // while the toggle passes through a normal two-flop synchronizer.  This
    // avoids asynchronously reading a RAM written by debug_clk, which caused
    // incoherent words and visible pixel tearing on hardware.
    logic [48:0] log_payload_debug = 49'd0;
    logic log_toggle_debug = 1'b0;
    always_ff @(posedge debug_clk) begin
        if (log_we) begin
            log_payload_debug <= {log_addr,log_data};
            log_toggle_debug <= ~log_toggle_debug;
        end
    end

    logic log_toggle_meta = 1'b0, log_toggle_pixel = 1'b0;
    logic log_toggle_previous = 1'b0;
    logic [48:0] log_payload_meta = 49'd0, log_payload_pixel = 49'd0;
    logic [39:0] display_memory [0:511];
    logic [8:0] display_count = 9'd0;
    logic [8:0] entry_index;
    logic [6:0] page_entry_index;
    logic [39:0] entry = 40'd0;
    always_ff @(posedge pixel_clk) begin
        log_toggle_meta <= log_toggle_debug;
        log_toggle_pixel <= log_toggle_meta;
        log_toggle_previous <= log_toggle_pixel;
        log_payload_meta <= log_payload_debug;
        log_payload_pixel <= log_payload_meta;
        // Gowin implements display_memory as synchronous embedded RAM.  Read
        // the selected row explicitly on pixel_clk rather than relying on an
        // asynchronous array access whose hardware behavior does not match
        // the renderer's combinational assumption.
        entry <= display_memory[entry_index];
        if (log_toggle_pixel != log_toggle_previous) begin
            display_memory[log_payload_pixel[48:40]] <= log_payload_pixel[39:0];
            // Address zero starts a fresh warm/cold-reset capture.  Until
            // later entries arrive, stale words from the prior trace remain
            // outside display_count and therefore cannot be rendered.
            if (log_payload_pixel[48:40] == 9'd0)
                display_count <= 9'd1;
            else if (log_payload_pixel[48:40] >= display_count)
                display_count <= log_payload_pixel[48:40] + 1'b1;
        end
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
                "O": glyph={5'b01110,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01110};
                "P": glyph={5'b11110,5'b10001,5'b10001,5'b11110,5'b10000,5'b10000,5'b10000};
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

    always_comb begin
        character_column=x[9:3];
        character_row=y[8:3];
        glyph_column=x[2:0];
        glyph_row=y[2:0];
        in_panel=enable && x < 10'd720 && y < 10'd480;
        local_column=(character_column >= 7'd45) ?
                     character_column-7'd45 : character_column;
        page_entry_index={1'b0,character_row}-7'd2;
        if (character_column >= 7'd45)
            page_entry_index=page_entry_index+7'd58;
        entry_index=({7'd0,log_page} * 9'd116) + page_entry_index;
        valid_entry=(character_row >= 6'd2) &&
                    (entry_index < display_count) && entry[39];
        character=" ";

        if (character_row == 0) begin
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
        end else if (character_row == 1) begin
            case (local_column)
                0:character="I"; 1:character="D"; 3:character="R";
                5:character="A"; 6:character=":"; 7:character="A";
                8:character="D"; 9:character="D"; 10:character="R";
                12:character="D"; 13:character="I"; 15:character="D";
                16:character="O"; 18:character="O"; 19:character="E";
                21:character="S";
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
            rgb_comb=(character_row == 0) ? 24'h40ffff :
                     (valid_entry && !entry[38]) ? 24'hffff40 : 24'hffffff;
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
