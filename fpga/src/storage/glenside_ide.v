// Complete Glenside IDE-to-TF-card bridge for the Tang Nano 20K.
//
// The card is operated in SD SPI mode:
//   SD_CLK  = SCLK
//   SD_CMD  = MOSI
//   SD_DAT0 = MISO
//   SD_DAT3 = CS_n
// DAT1 and DAT2 are unused and left high impedance.
module glenside_ide #(
    parameter [15:0] IDE_BASE = 16'hff50,
    parameter integer SPI_INIT_DIV = 135,
    parameter integer SPI_DATA_DIV = 54,
    parameter integer INIT_TIMEOUT_CYCLES = 1080000000,
    parameter integer CPU_ENABLE_PREDECODED = 0
) (
    input wire clk,
    input wire reset_n,
    input wire cpu_enable,
    input wire e_fall,
    input wire [15:0] cpu_addr,
    input wire cpu_rw_n,
    input wire [7:0] cpu_wdata,
    output wire [7:0] cpu_rdata,
    output wire cpu_data_oe,
    output wire sd_sclk,
    inout wire sd_cmd,
    inout wire sd_dat0,
    inout wire sd_dat1,
    inout wire sd_dat2,
    inout wire sd_dat3
);
    wire sd_init;
    wire sd_read_start;
    wire sd_write_start;
    wire [31:0] sd_sector;
    wire sd_busy;
    wire sd_done;
    wire sd_error;
    wire sd_data_valid;
    wire [8:0] sd_data_addr;
    wire [7:0] sd_data_from_card;
    wire [7:0] sd_data_to_card;
    wire [31:0] capacity_sectors;
    wire spi_cs_n;
    wire spi_mosi;

    glenside_ata #(
        .IDE_BASE(IDE_BASE),
        .INIT_TIMEOUT_CYCLES(INIT_TIMEOUT_CYCLES),
        .CPU_ENABLE_PREDECODED(CPU_ENABLE_PREDECODED)
    ) ata (
        .clk(clk), .reset_n(reset_n),
        .cpu_enable(cpu_enable), .e_fall(e_fall),
        .cpu_addr(cpu_addr), .cpu_rw_n(cpu_rw_n), .cpu_wdata(cpu_wdata),
        .cpu_rdata(cpu_rdata), .cpu_data_oe(cpu_data_oe),
        .sd_init(sd_init), .sd_read_start(sd_read_start),
        .sd_write_start(sd_write_start), .sd_sector(sd_sector),
        .sd_busy(sd_busy), .sd_done(sd_done), .sd_error(sd_error),
        .sd_data_valid(sd_data_valid), .sd_data_addr(sd_data_addr),
        .sd_data_in(sd_data_from_card), .sd_data_out(sd_data_to_card),
        .capacity_sectors(capacity_sectors)
    );

    sd_spi_block #(
        .INIT_DIV(SPI_INIT_DIV),
        .DATA_DIV(SPI_DATA_DIV)
    ) card (
        .clk(clk), .reset_n(reset_n), .init(sd_init),
        .read_start(sd_read_start), .write_start(sd_write_start),
        .sector(sd_sector), .busy(sd_busy), .done(sd_done),
        .error(sd_error), .data_valid(sd_data_valid),
        .data_addr(sd_data_addr), .data_out(sd_data_from_card),
        .data_in(sd_data_to_card), .capacity_sectors(capacity_sectors),
        .sd_sclk(sd_sclk), .sd_cs_n(spi_cs_n),
        .sd_mosi(spi_mosi), .sd_miso(sd_dat0)
    );

    assign sd_cmd = spi_mosi;
    assign sd_dat0 = 1'bz;
    assign sd_dat1 = 1'bz;
    assign sd_dat2 = 1'bz;
    assign sd_dat3 = spi_cs_n;
endmodule
