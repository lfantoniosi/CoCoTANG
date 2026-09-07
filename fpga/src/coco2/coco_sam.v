// CoCo 2 Synchronous Address Multiplexer.
module coco_sam (
    input         clk,
    input         reset_n,
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
    localparam [31:0] SAM_STEP = 32'd569408471;
    reg [31:0] accumulator = 32'd0;
    reg [3:0] phase = 4'd0;
    wire [32:0] sum = {1'b0, accumulator} + {1'b0, SAM_STEP};

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            accumulator <= 32'd0;
            phase <= 4'd0;
            e <= 1'b0;
            q <= 1'b0;
            e_rise <= 1'b0;
            e_fall <= 1'b0;
        end else begin
            accumulator <= sum[31:0];
            e_rise <= 1'b0;
            e_fall <= 1'b0;
            if (sum[32]) begin
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

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
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
        if (all_ram && addr < 16'hff00)
            s = 3'd0;
        else if (addr < 16'h8000)
            s = 3'd0;
        else if (addr < 16'ha000)
            s = 3'd1;
        else if (addr < 16'hc000)
            s = 3'd2;
        else if (addr < 16'hff00)
            s = 3'd3;
        else if (addr < 16'hff20)
            s = 3'd4;
        else if (addr < 16'hff40)
            s = 3'd5;
        else if (addr < 16'hff60)
            s = 3'd6;
        else if (addr >= 16'hffe0)
            s = 3'd2;
        else
            s = 3'd7;
    end
endmodule
