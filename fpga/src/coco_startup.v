module coco_startup (
    input clk,
    input board_reset_n,
    input sdram_enabled,
    input loader_done,
    output reg sdram_reset_n,
    output reg loader_start,
    output system_ready
);
    localparam FIRST_INIT=3'd0, SECOND_RESET=3'd1, SECOND_INIT=3'd2,
               LOAD_ROM=3'd3, READY=3'd4;
    reg [2:0] state = FIRST_INIT;
    reg [7:0] reset_count = 8'd0;

    always @(posedge clk or negedge board_reset_n) begin
        if (!board_reset_n) begin
            state <= FIRST_INIT;
            reset_count <= 8'd0;
            sdram_reset_n <= 1'b0;
            loader_start <= 1'b0;
        end else begin
            case (state)
                FIRST_INIT: begin
                    sdram_reset_n <= 1'b1;
                    if (sdram_enabled) begin
                        sdram_reset_n <= 1'b0;
                        reset_count <= 8'd0;
                        state <= SECOND_RESET;
                    end
                end
                SECOND_RESET: begin
                    sdram_reset_n <= 1'b0;
                    if (&reset_count) begin
                        sdram_reset_n <= 1'b1;
                        state <= SECOND_INIT;
                    end else reset_count <= reset_count + 1'b1;
                end
                SECOND_INIT: begin
                    sdram_reset_n <= 1'b1;
                    if (sdram_enabled) begin
                        loader_start <= 1'b1;
                        state <= LOAD_ROM;
                    end
                end
                LOAD_ROM: begin
                    sdram_reset_n <= 1'b1;
                    loader_start <= 1'b1;
                    if (loader_done) state <= READY;
                end
                default: begin
                    sdram_reset_n <= 1'b1;
                    loader_start <= 1'b1;
                end
            endcase
        end
    end
    assign system_ready = state == READY;
endmodule
