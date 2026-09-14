module input_filter #(
    parameter WIDTH = 1
) (
    input                  clk,
    input                  reset_n,
    input      [WIDTH-1:0] in,
    output reg [WIDTH-1:0] out
);
    reg [WIDTH-1:0] sync0 = {WIDTH{1'b1}};
    reg [WIDTH-1:0] sync1 = {WIDTH{1'b1}};
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            sync0 <= {WIDTH{1'b1}};
            sync1 <= {WIDTH{1'b1}};
            out <= {WIDTH{1'b1}};
        end else begin
            sync0 <= in;
            sync1 <= sync0;
            // Change the output only after both synchronizer stages agree.
            // This rejects a value captured for just one clk period while
            // adding only two complete clk periods of transition latency.
            if (sync0 == sync1)
                out <= sync1;
        end
    end
endmodule
