// 720x480 monitor for every carrier input and the diagnostic outputs.
module cpu_bus_probe_hdmi(
    input pixel_clk,input serial_clk,input reset,
    input [7:0] test_data,input [7:0] data_readback,
    input [23:0] mux_banks,input [15:0] cpu_address,
    input [7:0] mp_live,input [7:0] extras,input [11:0] outputs,
    output tmds_clk_p,output tmds_clk_n,
    output [2:0] tmds_data_p,output [2:0] tmds_data_n
);
    wire [9:0] x,y;
    wire [23:0] rgb;
    cpu_bus_probe_screen screen(.pixel_clk(pixel_clk),.reset(reset),.x(x),.y(y),
        .test_data(test_data),.data_readback(data_readback),.mux_banks(mux_banks),
        .cpu_address(cpu_address),.mp_live(mp_live),.extras(extras),
        .outputs(outputs),.rgb(rgb));
    wire [15:0] silence[1:0];
    assign silence[0]=0;
    assign silence[1]=0;
    wire [9:0] tmds_internal[2:0];
    hdmi #(.VIDEO_ID_CODE(2),.DVI_OUTPUT(1'b1),.START_X(0),.START_Y(0)) encoder(
        .clk_pixel_x5(serial_clk),.clk_pixel(pixel_clk),.clk_audio(1'b0),
        .reset(reset),.video_50hz(1'b0),.rgb(rgb),.audio_sample_word(silence),
        .cx(x),.cy(y),.frame_width(),.frame_height(),.screen_width(),
        .screen_height(),.active_video_50hz(),.tmds_internal(tmds_internal));
    wire [2:0] tmds;
    wire unused_clock;
    serializer #(.NUM_CHANNELS(3),.VIDEO_RATE(0)) serialize(
        .clk_pixel(pixel_clk),.clk_pixel_x5(serial_clk),.reset(reset),
        .tmds_internal(tmds_internal),.tmds(tmds),.tmds_clock(unused_clock));
    ELVDS_OBUF pads[3:0](.I({pixel_clk,tmds}),
        .O({tmds_clk_p,tmds_data_p}),.OB({tmds_clk_n,tmds_data_n}));
endmodule

module cpu_bus_probe_screen(
    input pixel_clk,input reset,input [9:0] x,input [9:0] y,
    input [7:0] test_data,input [7:0] data_readback,
    input [23:0] mux_banks,input [15:0] cpu_address,
    input [7:0] mp_live,input [7:0] extras,input [11:0] outputs,
    output reg [23:0] rgb
);
    // Capture inputs twice and freeze the view for each frame. The screen
    // describes FPGA observations; it cannot read the far side of the 245.
    reg [83:0] meta=0,sync=0,frame=0;
    always @(posedge pixel_clk) begin
        meta<={test_data,data_readback,mux_banks,cpu_address,mp_live,extras,outputs};
        sync<=meta;
        if (reset) frame<=0;
        else if (x==0 && y==0) frame<=sync;
    end
    wire [7:0] value,readback,mp_bits,extra;
    wire [23:0] banks;
    wire [15:0] addr;
    wire [11:0] pins;
    assign {value,readback,banks,addr,mp_bits,extra,pins}=frame;
    wire [7:0] control=banks[23:16];
    function automatic [7:0] hex_char(input [3:0] v);
        hex_char=v<10 ? "0"+v : "A"+v-10;
    endfunction
    function automatic [15:0] hex_byte(input [7:0] v);
        hex_byte={hex_char(v[7:4]),hex_char(v[3:0])};
    endfunction
    function automatic [63:0] bits(input [7:0] v);
        for (integer i=0;i<8;i=i+1) bits[63-i*8 -:8]=v[7-i] ? "1" : "0";
    endfunction
    function automatic [7:0] bit_char(input v);
        bit_char=v ? "1" : "0";
    endfunction
    // Strings are left aligned to the same 42-character width.
    function automatic [335:0] text_line(input [4:0] row);
        reg [335:0] line_text;
        begin
            line_text="                                          ";
            case (row)
                0:line_text="COCOTANG CPU PIN PROBE                    ";
                1:line_text={"DATA OUT:",hex_byte(value),"  BITS:",bits(value),"                "};
                2:line_text={"FPGA IN :",hex_byte(readback),"  BITS:",bits(readback),"                "};
                3:line_text={"MODE:",pins[7] ? "HOLD " : "SWEEP"," DRIVE:",bit_char(pins[8])," READY:",bit_char(pins[9]),"                "};
                4:line_text={"CPU ADDRESS:",hex_byte(addr[15:8]),hex_byte(addr[7:0]),"                          "};
                5:line_text={"A15-A8:",bits(addr[15:8])," A7-A0:",bits(addr[7:0]),"            "};
                6:line_text={"MUX0 LOW :",hex_byte(banks[7:0]),"  MP7-0:",bits(banks[7:0]),"              "};
                7:line_text={"MUX1 HIGH:",hex_byte(banks[15:8]),"  MP7-0:",bits(banks[15:8]),"              "};
                8:line_text={"MUX2 CTRL:",hex_byte(control),"  MP7-0:",bits(control),"              "};
                9:line_text={"RW:",bit_char(control[0])," RESET_N:",bit_char(control[1])," SLENB_N:",bit_char(control[2])," SERNT:",bit_char(control[3]),"          "};
                10:line_text={"CART_N:",bit_char(control[4])," KEYINT:",bit_char(control[5])," HALT_N:",bit_char(control[6])," NMI_N:",bit_char(control[7]),"        "};
                11:line_text={"LIVE MP:",hex_byte(mp_bits)," BITS:",bits(mp_bits)," MSEL:",bit_char(pins[11]),bit_char(pins[10]),"          "};
                12:line_text={"OUT IRQ_N:",bit_char(pins[6])," FIRQ_N:",bit_char(pins[5])," HS_N:",bit_char(pins[4])," FS_N:",bit_char(pins[3]),"        "};
                13:line_text={"S2-S0:",bit_char(pins[2]),bit_char(pins[1]),bit_char(pins[0])," CODE:",hex_char({1'b0,pins[2:0]})," E/Q:1.6875MHZ            "};
                14:line_text={"BTN1:",bit_char(extra[6])," BTN2:",bit_char(extra[7])," FLASH MISO:",bit_char(extra[5]),"                "};
                15:line_text={"SD CMD:",bit_char(extra[4])," DAT0-3:",bit_char(extra[3]),bit_char(extra[2]),bit_char(extra[1]),bit_char(extra[0]),"                      "};
                16:line_text="S2:RUN/HOLD S1:ZERO OR STEP WHEN HELD     ";
                17:line_text="RESET HELD LOW  S0-2 DRIVE / S3-7 RELEASE ";
                18:line_text="D7-D0 CPU PINS:24 25 26 27 28 29 30 31    ";
                default:begin end
            endcase
            text_line=line_text;
        end
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
                "K": glyph={5'b10001,5'b10010,5'b10100,5'b11000,5'b10100,5'b10010,5'b10001};
                "L": glyph={5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b11111};
                "M": glyph={5'b10001,5'b11011,5'b10101,5'b10101,5'b10001,5'b10001,5'b10001};
                "N": glyph={5'b10001,5'b11001,5'b10101,5'b10011,5'b10001,5'b10001,5'b10001};
                "O": glyph={5'b01110,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01110};
                "P": glyph={5'b11110,5'b10001,5'b10001,5'b11110,5'b10000,5'b10000,5'b10000};
                "Q": glyph={5'b01110,5'b10001,5'b10001,5'b10001,5'b10101,5'b10010,5'b01101};
                "R": glyph={5'b11110,5'b10001,5'b10001,5'b11110,5'b10100,5'b10010,5'b10001};
                "S": glyph={5'b01111,5'b10000,5'b10000,5'b01110,5'b00001,5'b00001,5'b11110};
                "T": glyph={5'b11111,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100};
                "U": glyph={5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01110};
                "V": glyph={5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01010,5'b00100};
                "W": glyph={5'b10001,5'b10001,5'b10001,5'b10101,5'b10101,5'b10101,5'b01010};
                "X": glyph={5'b10001,5'b10001,5'b01010,5'b00100,5'b01010,5'b10001,5'b10001};
                "Y": glyph={5'b10001,5'b10001,5'b01010,5'b00100,5'b00100,5'b00100,5'b00100};
                "Z": glyph={5'b11111,5'b00001,5'b00010,5'b00100,5'b01000,5'b10000,5'b11111};
                ":": glyph={5'b00000,5'b00100,5'b00100,5'b00000,5'b00100,5'b00100,5'b00000};
                "/": glyph={5'b00001,5'b00010,5'b00100,5'b01000,5'b10000,5'b00000,5'b00000};
                "-": glyph={5'b00000,5'b00000,5'b00000,5'b11111,5'b00000,5'b00000,5'b00000};
                "_": glyph={5'b00000,5'b00000,5'b00000,5'b00000,5'b00000,5'b00000,5'b11111};
                ".": glyph={5'b00000,5'b00000,5'b00000,5'b00000,5'b00000,5'b00100,5'b00100};
                default: glyph=35'd0;
            endcase
        end
    endfunction


    integer column,row,local_x,local_y;
    reg [335:0] line_text;
    reg [7:0] character;
    reg [34:0] shape;
    always @* begin
        rgb=24'h081320;
        column=0;row=0;local_x=0;local_y=0;
        line_text=0;character=" ";shape=0;
        if (x>=24 && x<696 && y>=12 && y<468) begin
            column=(x-24)>>4;row=(y-12)/24;
            local_x=((x-24)>>1)&7;
            local_y=((y-12)%24)>>1;
            line_text=text_line(row);
            character=line_text[335-column*8 -:8];
            shape=glyph(character);
            if (local_x<5 && local_y<7 && shape[34-local_y*5-local_x])
                rgb=row==0 ? 24'h40e0ff :
                    (row==1 || row==4) ? 24'hffff60 :
                    character=="1" ? 24'h40ff80 : 24'hd0e0f0;
        end
    end
endmodule
