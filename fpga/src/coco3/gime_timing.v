module gime_timing #(
    // The motherboard crystal is a hardware property, not an FF98 mode.
    // NTSC machines use 28.63636 MHz; PAL machines use 28.475 MHz.
    parameter integer PAL_MACHINE = 0
) (
    input      clk,
    input      reset_n,
    input      fast_mode,
    input      pal_hires_60hz,
    output reg e,
    output reg q,
    output e_pin,
    output q_pin,
    output reg e_rise,
    output reg e_fall
);
    // CoCo master timing: 108 MHz -> average 14.31818 MHz, divided into the
    // sixteen SAM/GIME phases which produce E and Q.
    localparam [31:0] SLOW_STEP = PAL_MACHINE ?
        32'd566199971 : 32'd569408471;
    localparam [31:0] FAST_STEP = PAL_MACHINE ?
        32'd1132399942 : 32'd1138816942;
    // PAL hires raster is locked to the 27 MHz encoder at 14.250 MHz.
    // Cycle-counted 60 Hz effects (notably BOINK's FF98.LPR writes) must
    // use that same cadence or their write position walks down the frame.
    // Keep the physical PAL crystal rate for VDG and 50 Hz software.
    localparam [31:0] PAL_HIRES_SLOW_STEP = 32'd566697074;
    localparam [31:0] PAL_HIRES_FAST_STEP = 32'd1133394148;
    reg [31:0] accumulator = 32'd0;
    reg [3:0] phase = 4'd0;
    // Dedicated pad copies. Preserve them so synthesis cannot merge them
    // back into the high-fanout internal E/Q state registers.
    (* syn_preserve = 1 *) reg e_pad = 1'b0;
    (* syn_preserve = 1 *) reg q_pad = 1'b0;
    assign e_pin=e_pad;
    assign q_pin=q_pad;
    wire [31:0] selected_step = PAL_MACHINE && pal_hires_60hz ?
        (fast_mode ? PAL_HIRES_FAST_STEP : PAL_HIRES_SLOW_STEP) :
        (fast_mode ? FAST_STEP : SLOW_STEP);
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
