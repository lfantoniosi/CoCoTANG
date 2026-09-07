module sigma_delta_dac (
    input clk, input reset_n, input [7:0] sample, output reg bit_out
);
    reg [8:0] accumulator = 9'd0;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin accumulator <= 9'd0; bit_out <= 1'b0; end
        else begin
            accumulator <= {1'b0,accumulator[7:0]} + {1'b0,sample};
            bit_out <= accumulator[8];
        end
    end
endmodule
