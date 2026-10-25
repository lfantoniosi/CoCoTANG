// Debug-project timing variant. Normal projects use coco3/gime_timing.v.
module gime_timing (
    input      clk,
    input      reset_n,
    input      fast_mode,
    output reg e,
    output reg q,
    output e_pin,
    output q_pin,
    output reg e_rise,
    output reg e_fall,
    output reg video_tick,
    output reg video_e_fall
);
    // Both E/Q speeds divide a fixed 28.63636 MHz master phase. Changing
    // the accumulator rate on speed writes shifted slow E by half a cycle
    // after an odd count of fast cycles, changing raster interrupt latency.
    localparam [31:0] MASTER_STEP = 32'd1138816942;
    reg [31:0] accumulator = 32'd0;
    reg [4:0] phase = 5'd0;
    // Dedicated pad copies. Preserve them so synthesis cannot merge them
    // back into the high-fanout internal E/Q state registers.
    (* syn_preserve = 1 *) reg e_pad = 1'b0;
    (* syn_preserve = 1 *) reg q_pad = 1'b0;
    assign e_pin=e_pad;
    assign q_pin=q_pad;
    // Carry for the current low-half addition is predicted one clock ahead.
    // This preserves every accumulator value and master tick exactly.
    reg low_carry = 1'b0;
    wire [16:0] low_sum = {1'b0,accumulator[15:0]} +
                          {1'b0,MASTER_STEP[15:0]};
    wire [16:0] high_sum = {1'b0,accumulator[31:16]} +
                           {1'b0,MASTER_STEP[31:16]} + low_carry;
    wire [32:0] sum = {high_sum,low_sum[15:0]};
    wire q_set=fast_mode ? phase[3:0]==4'd2 : phase==5'd5;
    wire e_set=fast_mode ? phase[3:0]==4'd6 : phase==5'd13;
    wire q_clear=fast_mode ? phase[3:0]==4'd10 : phase==5'd21;
    wire e_clear=fast_mode ? phase[3:0]==4'd14 : phase==5'd29;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            accumulator <= 32'd0;
            low_carry <= 1'b0;
            phase <= 5'd0;
            e <= 1'b0;
            q <= 1'b0;
            e_pad <= 1'b0;
            q_pad <= 1'b0;
            e_rise <= 1'b0;
            e_fall <= 1'b0;
            video_tick <= 1'b0;
            video_e_fall <= 1'b0;
        end else begin
            accumulator <= sum[31:0];
            low_carry <= {1'b0,low_sum[15:0]} >=
                         (17'h10000-{1'b0,MASTER_STEP[15:0]});
            e_rise <= 1'b0;
            e_fall <= 1'b0;
            video_tick <= 1'b0;
            video_e_fall <= 1'b0;
            if (sum[32]) begin
                phase <= phase + 1'b1;
                video_tick <= phase[0];
                video_e_fall <= phase==5'd29;
                if(q_set)begin q <= 1'b1; q_pad <= 1'b1; end
                if(e_set&&!e)begin e <= 1'b1; e_pad <= 1'b1; e_rise <= 1'b1; end
                if(q_clear)begin q <= 1'b0; q_pad <= 1'b0; end
                if(e_clear&&e)begin e <= 1'b0; e_pad <= 1'b0; e_fall <= 1'b1; end
            end
        end
    end
endmodule
