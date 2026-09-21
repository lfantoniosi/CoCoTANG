// Destructive cold-boot SDRAM clear/verify pass.  Write and read all 512 KiB
// available to the GIME so every physical address is left at zero before the
// CPU and video renderer are released.
module coco_sdram_startup_test (
    input clk,
    input reset_n,
    input start,
    output reg mem_req,
    output reg mem_wr,
    output [22:0] mem_addr,
    output [7:0] mem_wdata,
    input [7:0] mem_rdata,
    input mem_ack,
    output reg done,
    output reg passed,
    output reg failed,
    output reg [18:0] error_addr,
    output reg [7:0] error_expected,
    output reg [7:0] error_actual
);
    localparam [18:0] LAST_TEST_ADDR = 19'h7ffff;
    localparam WAIT_START=3'd0, WRITE_WAIT=3'd1, WRITE_GAP=3'd2,
               READ_WAIT=3'd3, READ_GAP=3'd4, PASS=3'd5, FAIL=3'd6;

    reg [2:0] state = WAIT_START;
    reg [18:0] address = 19'd0;

    assign mem_addr = {4'd0,address};
    assign mem_wdata = 8'h00;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state <= WAIT_START;
            address <= 19'd0;
            mem_req <= 1'b0;
            mem_wr <= 1'b1;
            done <= 1'b0;
            passed <= 1'b0;
            failed <= 1'b0;
            error_addr <= 19'd0;
            error_expected <= 8'd0;
            error_actual <= 8'd0;
        end else begin
            case (state)
                WAIT_START: if (start) begin
                    address <= 19'd0;
                    mem_wr <= 1'b1;
                    mem_req <= 1'b1;
                    state <= WRITE_WAIT;
                end

                WRITE_WAIT: if (mem_ack) begin
                    mem_req <= 1'b0;
                    if (address == LAST_TEST_ADDR) begin
                        address <= 19'd0;
                        mem_wr <= 1'b0;
                        state <= READ_GAP;
                    end else begin
                        address <= address + 1'b1;
                        state <= WRITE_GAP;
                    end
                end

                WRITE_GAP: begin
                    mem_req <= 1'b1;
                    state <= WRITE_WAIT;
                end

                READ_WAIT: if (mem_ack) begin
                    mem_req <= 1'b0;
                    if (mem_rdata != 8'h00) begin
                        error_addr <= address;
                        error_expected <= 8'h00;
                        error_actual <= mem_rdata;
                        done <= 1'b1;
                        failed <= 1'b1;
                        state <= FAIL;
                    end else if (address == LAST_TEST_ADDR) begin
                        done <= 1'b1;
                        passed <= 1'b1;
                        state <= PASS;
                    end else begin
                        address <= address + 1'b1;
                        state <= READ_GAP;
                    end
                end

                READ_GAP: begin
                    mem_req <= 1'b1;
                    state <= READ_WAIT;
                end

                PASS: mem_req <= 1'b0;
                default: begin
                    mem_req <= 1'b0;
                    done <= 1'b1;
                    failed <= 1'b1;
                    state <= FAIL;
                end
            endcase
        end
    end
endmodule
