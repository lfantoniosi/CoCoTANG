// Small independent overlay used to acknowledge the warm-reset artifact-mode
// selector even when the optional bus logger overlay is compiled out.
module artifact_mode_osd #(
    parameter integer DISPLAY_CYCLES=108000000,
    parameter integer PANEL_X=268,
    parameter integer PANEL_Y=16,
    parameter integer TIMER_DIVIDER=1,
    parameter integer REGISTER_PIXELS=0,
    parameter integer FONT_SCALE_LOG2=0
) (
    input  logic        pixel_clk,
    input  logic        reset,
    input  logic [1:0]  mode,
    input  logic        ssc_enabled,
    input  logic [9:0]  x,
    input  logic [9:0]  y,
    input  logic [23:0] rgb_in,
    output logic [23:0] rgb_out
);
    localparam integer TIMER_TICKS=(DISPLAY_CYCLES+TIMER_DIVIDER-1)/TIMER_DIVIDER;
    localparam integer TIMER_WIDTH=$clog2(TIMER_TICKS+1);
    localparam integer DIVIDER_WIDTH=TIMER_DIVIDER>1 ? $clog2(TIMER_DIVIDER) : 1;
    localparam integer FONT_SCALE=1<<FONT_SCALE_LOG2;
    localparam integer PADDING=4*FONT_SCALE;
    logic [2:0] mode_meta=0,mode_sync=0,mode_seen=0;
    logic [TIMER_WIDTH-1:0] timer=0;
    logic [DIVIDER_WIDTH-1:0] divider=0;
    logic visible=0;
    always_ff @(posedge pixel_clk) visible<=timer!=0;

    always_ff @(posedge pixel_clk) begin
        if(reset) begin
            mode_meta<=0; mode_sync<=0; mode_seen<=0;
            timer<=TIMER_TICKS;divider<=TIMER_DIVIDER-1;
        end else begin
            mode_meta<={ssc_enabled,mode};
            mode_sync<=mode_meta;
            if(mode_sync!=mode_seen) begin
                mode_seen<=mode_sync;
                timer<=TIMER_TICKS;divider<=TIMER_DIVIDER-1;
            end else if(timer!=0)begin
                if(divider==0)begin
                    timer<=timer-1'b1;divider<=TIMER_DIVIDER-1;
                end else divider<=divider-1'b1;
            end
        end
    end

    function automatic logic [7:0] message_character(
        input logic [2:0] selected_mode,input logic [4:0] index
    );
        logic [175:0] message_text;
        begin
            case(selected_mode[1:0])
                2'd0:message_text="NO ARTIFACT           ";
                2'd1:message_text="ARTIFACT NORMAL       ";
                default:message_text="ARTIFACT REVERSE      ";
            endcase
            if(selected_mode[2]) begin
                case(selected_mode[1:0])
                    2'd0:message_text="NO ARTIFACT - SSC     ";
                    2'd1:message_text="ARTIFACT NORMAL - SSC ";
                    default:message_text="ARTIFACT REVERSE - SSC";
                endcase
            end
            message_character=index<22 ? message_text[175-index*8 -: 8] : " ";
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
                "L":glyph={5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b11111};
                "M":glyph={5'b10001,5'b11011,5'b10101,5'b10101,5'b10001,5'b10001,5'b10001};
                "-":glyph={5'b00000,5'b00000,5'b00000,5'b11111,5'b00000,5'b00000,5'b00000};
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

    // Prepare the whole glyph row before reaching the panel's left edge.
    // This keeps string/glyph lookup out of the 135-MHz analogue pixel path.
    function automatic logic [175:0] message_row(
        input logic [2:0] selected_mode,input logic [2:0] row
    );
        logic [34:0] character_glyph;
        integer i;
        begin
            message_row=0;
            if(row<7)for(i=0;i<22;i=i+1)begin
                character_glyph=glyph(message_character(selected_mode,5'(i)));
                message_row[175-i*8 -: 8]={character_glyph[(6-row)*5 +: 5],3'b000};
            end
        end
    endfunction

    logic panel,text_pixel;
    logic panel_q=0,text_pixel_q=0;
    always_ff @(posedge pixel_clk)begin
        panel_q<=panel;text_pixel_q<=text_pixel;
    end
    wire [9:0] local_x=(x-(PANEL_X+PADDING))>>FONT_SCALE_LOG2;
    wire [9:0] local_y=(y-(PANEL_Y+PADDING))>>FONT_SCALE_LOG2;
    logic [175:0] text_row=0;
    // Pad to a power of two so reversing the pixel index only inverts bits;
    // subtracting from 175 added another carry chain to the analog path.
    wire [255:0] indexed_text_row={text_row,80'b0};
    always_ff @(posedge pixel_clk)
        text_row<=message_row(mode_seen,local_y[2:0]);
    always_comb begin
        panel=(visible && x>=PANEL_X && x<PANEL_X+184*FONT_SCALE &&
              y>=PANEL_Y && y<PANEL_Y+16*FONT_SCALE);
        text_pixel=1'b0;
        if(panel && x>=PANEL_X+PADDING && x<PANEL_X+180*FONT_SCALE &&
           y>=PANEL_Y+PADDING && y<PANEL_Y+11*FONT_SCALE)
            text_pixel=indexed_text_row[~local_x[7:0]];
        if(REGISTER_PIXELS ? text_pixel_q : text_pixel) rgb_out=24'hffffff;
        else if(REGISTER_PIXELS ? panel_q : panel) rgb_out=24'h102040;
        else rgb_out=rgb_in;
    end
endmodule
