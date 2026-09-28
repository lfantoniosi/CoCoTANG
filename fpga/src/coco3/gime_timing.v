module gime_timing (
    input      clk,
    input      reset_n,
    input      fast_mode,
    output reg e,
    output reg q,
    output e_pin,
    output q_pin,
    output reg e_rise,
    output reg e_fall
);
    // CoCo master timing: 108 MHz -> average 14.31818 MHz, divided into the
    // sixteen SAM/GIME phases which produce E and Q.
    localparam [31:0] SLOW_STEP = 32'd569408471;
    localparam [31:0] FAST_STEP = 32'd1138816942;
    reg [31:0] accumulator = 32'd0;
    reg [3:0] phase = 4'd0;
    // Dedicated pad copies. Preserve them so synthesis cannot merge them
    // back into the high-fanout internal E/Q state registers.
    (* syn_preserve = 1 *) reg e_pad = 1'b0;
    (* syn_preserve = 1 *) reg q_pad = 1'b0;
    assign e_pin=e_pad;
    assign q_pin=q_pad;
    wire [31:0] selected_step = fast_mode ? FAST_STEP : SLOW_STEP;
    wire [32:0] sum = {1'b0,accumulator} + {1'b0,selected_step};

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            accumulator <= 32'd0;
            phase <= 4'd0;
            e <= 1'b0;
            q <= 1'b0;
            e_pad <= 1'b0;
            q_pad <= 1'b0;
            e_rise <= 1'b0;
            e_fall <= 1'b0;
        end else begin
            accumulator <= sum[31:0];
            e_rise <= 1'b0;
            e_fall <= 1'b0;
            if (sum[32]) begin
                phase <= phase + 1'b1;
                case (phase)
                    4'd2: begin q <= 1'b1; q_pad <= 1'b1; end
                    4'd6: begin e <= 1'b1; e_pad <= 1'b1; e_rise <= 1'b1; end
                    4'd10: begin q <= 1'b0; q_pad <= 1'b0; end
                    4'd14: begin e <= 1'b0; e_pad <= 1'b0; e_fall <= 1'b1; end
                    default: ;
                endcase
            end
        end
    end
endmodule
