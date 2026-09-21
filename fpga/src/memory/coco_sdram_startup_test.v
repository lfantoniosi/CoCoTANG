// Destructive cold-boot SDRAM test adapted from new-juice.  Exercise all
// 512 KiB available to the GIME, using a pattern in which every physical
// address bit participates.  Testing only 64 KiB with address[7:0] allowed
// 64/128 KiB address aliases to pass unnoticed.
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
    function [7:0] hex_ascii;
        input [3:0] nibble;
        begin
            hex_ascii = nibble < 10 ? 8'h30+nibble : 8'h41+nibble-10;
        end
    endfunction

    // Leave every aligned 16-byte block as eight native GIME text cells:
    // "Axxxxx- ", where xxxxx is that block's physical 19-bit address.
    // Odd bytes are a white-on-black FFFBBB attribute.  If bad MMU state
    // maps untouched test RAM onto the screen, the physical source address
    // is therefore readable directly instead of appearing as random glyphs.
    // The address-dependent ASCII data still exercises every SDRAM address
    // line and is verified with exactly the same function on the read pass.
    reg [7:0] address_character;
    always @(*) begin
        case (address[3:1])
            3'd0: address_character = "A";
            3'd1: address_character = hex_ascii({1'b0,address[18:16]});
            3'd2: address_character = hex_ascii(address[15:12]);
            3'd3: address_character = hex_ascii(address[11:8]);
            3'd4: address_character = hex_ascii(address[7:4]);
            3'd5: address_character = "0";
            3'd6: address_character = "-";
            default: address_character = " ";
        endcase
    end
    wire [7:0] address_pattern = address[0] ? 8'h38 : address_character;
    assign mem_wdata = address_pattern;

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
                    if (mem_rdata != address_pattern) begin
                        error_addr <= address;
                        error_expected <= address_pattern;
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
