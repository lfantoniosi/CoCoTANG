module sdram_test_fill #(
    parameter integer BYTE_COUNT = 524288
) (
    input wire clk,
    input wire reset_n,
    input wire start,
    output reg done,
    output reg mem_req,
    output wire [22:0] mem_addr,
    output wire [7:0] mem_wdata,
    input wire mem_ack
);
    reg [18:0] address = 19'd0;
    localparam WAIT_START=2'd0, WAIT_ACK=2'd1,
               WAIT_RELEASE=2'd2, COMPLETE=2'd3;
    reg [1:0] state = WAIT_START;

    assign mem_addr = {4'd0,address};
    assign mem_wdata = address[7:0];

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            address <= 19'd0;
            state <= WAIT_START;
            done <= 1'b0;
            mem_req <= 1'b0;
        end else begin
            case (state)
                WAIT_START: if (start) begin
                    address <= 19'd0;
                    mem_req <= 1'b1;
                    state <= WAIT_ACK;
                end
                WAIT_ACK: if (mem_ack) begin
                    mem_req <= 1'b0;
                    if (address == BYTE_COUNT-1) begin
                        done <= 1'b1;
                        state <= COMPLETE;
                    end else begin
                        address <= address + 1'b1;
                        state <= WAIT_RELEASE;
                    end
                end
                WAIT_RELEASE: if (!mem_ack) begin
                    mem_req <= 1'b1;
                    state <= WAIT_ACK;
                end
                default: begin
                    done <= 1'b1;
                    mem_req <= 1'b0;
                end
            endcase
        end
    end
endmodule
