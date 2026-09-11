// CoCo 2 Synchronous Address Multiplexer.
module coco_sam #(
    parameter integer SLOW_DIAGNOSTIC = 0
) (
    input         clk,
    input         reset_n,
    input         register_reset_n,
    input  [15:0] addr,
    input         rw_n,
    output reg [2:0] s,
    output reg       e,
    output reg       q,
    output reg       e_rise,
    output reg       e_fall,
    output reg [2:0] video_mode,
    output reg [6:0] video_offset,
    output reg       page,
    output reg [1:0] rate,
    output reg [1:0] memory_size,
    output reg       all_ram
);
    // 108 MHz to the CoCo 14.31818 MHz SAM master tick. The accumulator
    // gives the correct average frequency with one 108 MHz cycle of jitter.
    // A 24-bit NCO is accurate to 0.072 ppm and keeps the shared SAM/VDG
    // carry chain comfortably inside the 108 MHz timing budget.
    // Quarter speed is used only by the physical-CPU delivery diagnostic.
    // It preserves the E/Q phase relationship while expanding every setup
    // and hold interval by four, making marginal external-bus timing obvious.
    localparam [23:0] SAM_STEP = SLOW_DIAGNOSTIC ? 24'd556063 : 24'd2224252;
    reg [23:0] accumulator = 24'd0;
    reg [3:0] phase = 4'd0;
    wire [24:0] sum = {1'b0, accumulator} + {1'b0, SAM_STEP};

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            accumulator <= 24'd0;
            phase <= 4'd0;
            e <= 1'b0;
            q <= 1'b0;
            e_rise <= 1'b0;
            e_fall <= 1'b0;
        end else begin
            accumulator <= sum[23:0];
            e_rise <= 1'b0;
            e_fall <= 1'b0;
            if (sum[24]) begin
                phase <= phase + 1'b1;
                case (phase)
                    4'd2: q <= 1'b1;
                    4'd6: begin e <= 1'b1; e_rise <= 1'b1; end
                    4'd10: q <= 1'b0;
                    4'd14: begin e <= 1'b0; e_fall <= 1'b1; end
                    default: ;
                endcase
            end
        end
    end

    // The SAM continues producing E/Q while the 6809 is in reset.  Its
    // programmable mapping registers, however, return to their reset state.
    always @(posedge clk or negedge register_reset_n) begin
        if (!register_reset_n) begin
            video_mode <= 3'b000;
            video_offset <= 7'b0000000;
            page <= 1'b0;
            rate <= 2'b00;
            memory_size <= 2'b00;
            all_ram <= 1'b0;
        end else if (e_fall && !rw_n && addr[15:5] == 11'b11111111110) begin
            case (addr[4:1])
                4'h0: video_mode[0] <= addr[0];
                4'h1: video_mode[1] <= addr[0];
                4'h2: video_mode[2] <= addr[0];
                4'h3: video_offset[0] <= addr[0];
                4'h4: video_offset[1] <= addr[0];
                4'h5: video_offset[2] <= addr[0];
                4'h6: video_offset[3] <= addr[0];
                4'h7: video_offset[4] <= addr[0];
                4'h8: video_offset[5] <= addr[0];
                4'h9: video_offset[6] <= addr[0];
                4'ha: page <= addr[0];
                4'hb: rate[0] <= addr[0];
                4'hc: rate[1] <= addr[0];
                4'hd: memory_size[0] <= addr[0];
                4'he: memory_size[1] <= addr[0];
                4'hf: all_ram <= addr[0];
            endcase
        end
    end

    always @(*) begin
        if (all_ram && addr[15:8] != 8'hff)
            s = 3'd0;
        else if (!addr[15])
            s = 3'd0;
        else if (addr[15:13] == 3'b100)
            s = 3'd1;
        else if (addr[15:13] == 3'b101)
            s = 3'd2;
        else if (addr[15:8] != 8'hff)
            s = 3'd3;
        else begin
            case (addr[7:5])
                3'b000: s = 3'd4;
                3'b001: s = 3'd5;
                3'b010: s = 3'd6;
                3'b111: s = 3'd2;
                default: s = 3'd7;
            endcase
        end
    end
endmodule
