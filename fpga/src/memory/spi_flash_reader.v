module spi_flash_reader
#(
    parameter integer CLK_DIV = 2
)
(
    input clk,
    input reset_n,
    input start,
    input stop,
    input [23:0] start_addr,
    input byte_ready,
    output reg [7:0] byte_data,
    output reg byte_valid,
    output reg busy,
    output reg mspi_cs,
    output reg mspi_sclk,
    input mspi_miso,
    output mspi_mosi
);

    localparam [7:0] READ_DATA_COMMAND = 8'h03;

    reg [31:0] tx_shift = 32'd0;
    reg [5:0] tx_bits_left = 6'd0;
    reg [7:0] rx_shift = 8'd0;
    reg [2:0] rx_bit_count = 3'd0;
    reg [15:0] divider = 16'd0;
    reg mosi_reg = 1'b0;
    reg pause_after_fall = 1'b0;

    assign mspi_mosi = mosi_reg;

    always_ff @(posedge clk or negedge reset_n)
    begin
        if (!reset_n) begin
            tx_shift <= 32'd0;
            tx_bits_left <= 6'd0;
            rx_shift <= 8'd0;
            rx_bit_count <= 3'd0;
            divider <= 16'd0;
            byte_data <= 8'hff;
            byte_valid <= 1'b0;
            busy <= 1'b0;
            mspi_cs <= 1'b1;
            mspi_sclk <= 1'b0;
            mosi_reg <= 1'b0;
            pause_after_fall <= 1'b0;
        end else begin
            if (stop) begin
                busy <= 1'b0;
                byte_valid <= 1'b0;
                mspi_cs <= 1'b1;
                mspi_sclk <= 1'b0;
                mosi_reg <= 1'b0;
                pause_after_fall <= 1'b0;
            end else if (start && !busy) begin
                tx_shift <= {READ_DATA_COMMAND, start_addr};
                tx_bits_left <= 6'd32;
                rx_shift <= 8'd0;
                rx_bit_count <= 3'd0;
                divider <= 16'd0;
                byte_valid <= 1'b0;
                busy <= 1'b1;
                mspi_cs <= 1'b0;
                mspi_sclk <= 1'b0;
                mosi_reg <= READ_DATA_COMMAND[7];
                pause_after_fall <= 1'b0;
            end else if (busy) begin
                if (byte_valid && byte_ready) begin
                    byte_valid <= 1'b0;
                    divider <= 16'd0;
                end

                if (!byte_valid && !pause_after_fall) begin
                    if (divider == CLK_DIV - 1) begin
                        divider <= 16'd0;
                        if (!mspi_sclk) begin
                            // Mode 0: the flash samples DI and changes DO
                            // around the rising edge; capture DO here.
                            mspi_sclk <= 1'b1;
                            if (tx_bits_left != 0) begin
                                tx_bits_left <= tx_bits_left - 1'b1;
                            end else begin
                                rx_shift <= {rx_shift[6:0], mspi_miso};
                                if (rx_bit_count == 3'd7) begin
                                    byte_data <= {rx_shift[6:0], mspi_miso};
                                    rx_bit_count <= 3'd0;
                                    pause_after_fall <= 1'b1;
                                end else begin
                                    rx_bit_count <= rx_bit_count + 1'b1;
                                end
                            end
                        end else begin
                            mspi_sclk <= 1'b0;
                            if (tx_bits_left != 0) begin
                                tx_shift <= {tx_shift[30:0], 1'b0};
                                mosi_reg <= tx_shift[30];
                            end else begin
                                mosi_reg <= 1'b0;
                            end
                        end
                    end else begin
                        divider <= divider + 1'b1;
                    end
                end else if (pause_after_fall) begin
                    // Complete the last falling edge before pausing the SPI
                    // clock while SDRAM accepts this byte.
                    if (divider == CLK_DIV - 1) begin
                        divider <= 16'd0;
                        mspi_sclk <= 1'b0;
                        pause_after_fall <= 1'b0;
                        byte_valid <= 1'b1;
                    end else begin
                        divider <= divider + 1'b1;
                    end
                end
            end else begin
                mspi_cs <= 1'b1;
                mspi_sclk <= 1'b0;
            end
        end
    end

endmodule

