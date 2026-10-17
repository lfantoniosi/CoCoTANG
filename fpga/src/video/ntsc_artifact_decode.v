// MAME-compatible NTSC artifact lookup for the MC6847/GIME PMODE 4 stream.
// Each output dot depends on the six monochrome dots x-2 through x+3.  The
// correction ROM is the table used by MAME's mc6847 artifacter; only the
// final analog palette is quantized to the GIME renderer's RGB222 line-buffer format.
module ntsc_artifact_decode (
    input      [5:0] neighborhood,
    input            odd_pixel,
    input            reverse_phase,
    input            css,
    output     [3:0] color_index,
    output reg [5:0] rgb
);
    localparam [511:0] CORRECTION = {
        256'hffffbfbf9c9c1c1cbafaaaaa2202d2d2fcccff4f9999e969b13170702e6e0e0e,
        256'hffffbbbb9f9f1313bafaaaaa2d0dd5d5fcccf4449898e868b131757520600000
    };

    wire [6:0] correction_address={neighborhood,odd_pixel};
    wire [3:0] correction=CORRECTION[correction_address*4 +: 4];
    // MAME calls its phase-swapped table "Standard" and the unswapped table
    // "Reverse".  Entries zero and fifteen are the two original levels.
    wire [3:0] color=(reverse_phase || correction==0 || correction==15) ?
                     correction : ((((correction-1)^1)+1)&4'hf);
    assign color_index=color;

    always @(*) begin
        if(css) begin
            case(color)
                0:rgb=6'h00;  1:rgb=6'h15;  2:rgb=6'h04;  3:rgb=6'h2a;
                4:rgb=6'h2a;  5:rgb=6'h24;  6:rgb=6'h05;  7:rgb=6'h29;
                // RGB222: give PMODE 4's blue and orange their full blue/red
                // channel while keeping the six-bit scanline cache unchanged.
                8:rgb=6'h1f;  9:rgb=6'h07; 10:rgb=6'h34; 11:rgb=6'h2a;
               12:rgb=6'h1f; 13:rgb=6'h14; 14:rgb=6'h05; default:rgb=6'h3e;
            endcase
        end else begin
            case(color)
                0:rgb=6'h00;  1:rgb=6'h04;  2:rgb=6'h04;  3:rgb=6'h18;
                4:rgb=6'h18;  5:rgb=6'h14;  6:rgb=6'h04;  7:rgb=6'h18;
                8:rgb=6'h08;  9:rgb=6'h08; 10:rgb=6'h18; 11:rgb=6'h18;
               12:rgb=6'h08; 13:rgb=6'h04; 14:rgb=6'h04; default:rgb=6'h18;
            endcase
        end
    end
endmodule
