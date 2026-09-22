// Cycle the artifact selection on the active-low CoCo motherboard RESET.
// The mode register deliberately has no reset input: FPGA configuration starts
// it at INITIAL_MODE, while subsequent CoCo resets preserve and advance it.
module artifact_mode_control #(
    parameter integer DEBOUNCE_CYCLES=1080000,
    // 0=OFF, 1=ON (blue/orange), 2=REVERSE (orange/blue).
    parameter [1:0] INITIAL_MODE=2'd1
) (
    input clk,
    input enable,
    input reset_n,
    output [1:0] mode
);
    localparam integer COUNT_WIDTH=$clog2(DEBOUNCE_CYCLES+1);
    reg reset_meta=1,reset_sync=1,reset_state=1;
    reg armed=0;
    reg [COUNT_WIDTH-1:0] stable_count=0;
    reg [1:0] mode_value=INITIAL_MODE;
    assign mode=mode_value;

    always @(posedge clk) begin
        if(!enable) begin
            reset_meta<=reset_n;
            reset_sync<=reset_n;
            reset_state<=reset_n;
            armed<=reset_n;
            stable_count<=0;
        end else begin
            reset_meta<=reset_n;
            reset_sync<=reset_meta;
            if(reset_sync==reset_state)
                stable_count<=0;
            else if(stable_count==DEBOUNCE_CYCLES-1) begin
                stable_count<=0;
                reset_state<=reset_sync;
                if(!reset_sync && armed) begin
                    mode_value<=(mode_value==2'd2)?2'd0:mode_value+1'b1;
                    armed<=0;
                end else if(reset_sync)
                    armed<=1;
            end else stable_count<=stable_count+1'b1;
        end
    end
endmodule
