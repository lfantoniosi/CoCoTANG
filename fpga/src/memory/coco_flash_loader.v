module coco_flash_loader #(
    parameter [23:0] FLASH_ADDRESS = 24'h100000,
    parameter [22:0] SDRAM_ADDRESS = 23'h010000,
    parameter integer BYTE_COUNT = 16384
) (
    input clk, input reset_n, input start,
    output reg done,
    output reg mem_req, output [22:0] mem_addr, output [7:0] mem_wdata,
    input mem_ack,
    output mspi_cs, output mspi_sclk, input mspi_miso, output mspi_mosi
);
    reg flash_start = 1'b0;
    reg flash_stop = 1'b0;
    reg byte_ready = 1'b0;
    reg [14:0] offset = 15'd0;
    wire [7:0] flash_byte;
    wire flash_valid;

    spi_flash_reader #(.CLK_DIV(2)) reader (
        .clk(clk), .reset_n(reset_n), .start(flash_start), .stop(flash_stop),
        .start_addr(FLASH_ADDRESS), .byte_ready(byte_ready),
        .byte_data(flash_byte), .byte_valid(flash_valid), .busy(),
        .mspi_cs(mspi_cs), .mspi_sclk(mspi_sclk),
        .mspi_miso(mspi_miso), .mspi_mosi(mspi_mosi)
    );

    assign mem_addr = SDRAM_ADDRESS + offset;
    assign mem_wdata = flash_byte;

    localparam WAIT_START=3'd0, WAIT_BYTE=3'd1, WRITE_BYTE=3'd2,
               WAIT_RELEASE=3'd3, COMPLETE=3'd4;
    reg [2:0] state = WAIT_START;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state <= WAIT_START;
            done <= 1'b0;
            mem_req <= 1'b0;
            flash_start <= 1'b0;
            flash_stop <= 1'b0;
            byte_ready <= 1'b0;
            offset <= 15'd0;
        end else begin
            flash_start <= 1'b0;
            flash_stop <= 1'b0;
            byte_ready <= 1'b0;
            case (state)
                WAIT_START: if (start) begin
                    flash_start <= 1'b1;
                    state <= WAIT_BYTE;
                end
                WAIT_BYTE: if (flash_valid) begin
                    mem_req <= 1'b1;
                    state <= WRITE_BYTE;
                end
                WRITE_BYTE: if (mem_ack) begin
                    mem_req <= 1'b0;
                    byte_ready <= 1'b1;
                    if (offset == BYTE_COUNT-1) begin
                        flash_stop <= 1'b1;
                        done <= 1'b1;
                        state <= COMPLETE;
                    end else begin
                        offset <= offset + 1'b1;
                        state <= WAIT_RELEASE;
                    end
                end
                WAIT_RELEASE: if (!flash_valid) state <= WAIT_BYTE;
                default: begin done <= 1'b1; mem_req <= 1'b0; end
            endcase
        end
    end
endmodule
