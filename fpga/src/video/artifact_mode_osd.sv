// Small independent overlay used to acknowledge the warm-reset artifact-mode
// selector even when the optional bus logger overlay is compiled out.
module artifact_mode_osd #(
    parameter integer DISPLAY_CYCLES=108000000
) (
    input  logic        pixel_clk,
    input  logic        reset,
    input  logic [1:0]  mode,
    input  logic [9:0]  x,
    input  logic [9:0]  y,
    input  logic [23:0] rgb_in,
    output logic [23:0] rgb_out
);
    localparam integer TIMER_WIDTH=$clog2(DISPLAY_CYCLES+1);
    logic [1:0] mode_meta=0,mode_sync=0,mode_seen=0;
    logic [TIMER_WIDTH-1:0] timer=0;

    always_ff @(posedge pixel_clk) begin
        if(reset) begin
            mode_meta<=0; mode_sync<=0; mode_seen<=0;
            timer<=DISPLAY_CYCLES;
        end else begin
            mode_meta<=mode;
            mode_sync<=mode_meta;
            if(mode_sync!=mode_seen) begin
                mode_seen<=mode_sync;
                timer<=DISPLAY_CYCLES;
            end else if(timer!=0)
                timer<=timer-1'b1;
        end
    end

    function automatic logic [7:0] message_character(
        input logic [1:0] selected_mode,input logic [4:0] index
    );
        begin
            message_character=" ";
            case(index)
                0:message_character="N"; 1:message_character="T";
                2:message_character="S"; 3:message_character="C";
                5:message_character="A"; 6:message_character="R";
                7:message_character="T"; 8:message_character="I";
                9:message_character="F";10:message_character="A";
               11:message_character="C";12:message_character="T";
               13:message_character="S";
               default:begin
                   case(selected_mode)
                       2'd0:case(index)
                           15:message_character="O";16:message_character="F";
                           17:message_character="F";default:;
                       endcase
                       2'd1:case(index)
                           15:message_character="O";16:message_character="N";
                           default:;
                       endcase
                       default:case(index)
                           15:message_character="R";16:message_character="E";
                           17:message_character="V";18:message_character="E";
                           19:message_character="R";20:message_character="S";
                           21:message_character="E";default:;
                       endcase
                   endcase
               end
            endcase
        end
    endfunction

    function automatic logic [34:0] glyph(input logic [7:0] c);
        begin
            case(c)
                "A":glyph={5'b01110,5'b10001,5'b10001,5'b11111,5'b10001,5'b10001,5'b10001};
                "C":glyph={5'b01111,5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b01111};
                "E":glyph={5'b11111,5'b10000,5'b10000,5'b11110,5'b10000,5'b10000,5'b11111};
                "F":glyph={5'b11111,5'b10000,5'b10000,5'b11110,5'b10000,5'b10000,5'b10000};
                "I":glyph={5'b01110,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100,5'b01110};
                "N":glyph={5'b10001,5'b11001,5'b10101,5'b10011,5'b10001,5'b10001,5'b10001};
                "O":glyph={5'b01110,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01110};
                "R":glyph={5'b11110,5'b10001,5'b10001,5'b11110,5'b10100,5'b10010,5'b10001};
                "S":glyph={5'b01111,5'b10000,5'b10000,5'b01110,5'b00001,5'b00001,5'b11110};
                "T":glyph={5'b11111,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100};
                "V":glyph={5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01010,5'b00100};
                default:glyph=35'd0;
            endcase
        end
    endfunction

    logic panel,text_pixel;
    logic [9:0] local_x,local_y;
    logic [4:0] character_index;
    logic [7:0] character;
    logic [34:0] character_glyph;
    always_comb begin
        panel=(timer!=0 && x>=10'd268 && x<10'd452 &&
              y>=10'd16 && y<10'd32);
        local_x=x-10'd272;
        local_y=y-10'd20;
        character_index=local_x[7:3];
        character=message_character(mode_seen,character_index);
        character_glyph=glyph(character);
        text_pixel=1'b0;
        if(panel && x>=10'd272 && x<10'd448 &&
           y>=10'd20 && y<10'd27 && local_x[2:0]<3'd5)
            text_pixel=character_glyph[34-local_y[2:0]*5-local_x[2:0]];
        if(text_pixel) rgb_out=24'hffffff;
        else if(panel) rgb_out=24'h102040;
        else rgb_out=rgb_in;
    end
endmodule
