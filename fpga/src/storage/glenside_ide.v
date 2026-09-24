// Complete Glenside IDE-to-TF-card bridge for the Tang Nano 20K.
module glenside_ide #(
    parameter [15:0] IDE_BASE = 16'hff50,
    // 108 MHz / (2 * 16) = 3.375 MHz.  The TF socket is routed as GPIO,
    // so use a conservative clock with ample DAT0 sampling margin.
    parameter [2:0] SD_CLK_DIV = 3'd4,
    parameter integer INIT_TIMEOUT_CYCLES = 1080000000
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
    wire sd_outen;
    wire [8:0] sd_outaddr;
    wire [7:0] sd_outbyte;
    wire [7:0] sd_inbyte;
    wire sd_crc_error;
    wire sd_timeout_error;
    reg sd_busy_ata;
    reg sd_done_ata;
    reg sd_error_ata;
    wire [3:0] card_stat;
    wire [1:0] card_type;
    wire [21:0] c_size;
    wire [2:0] c_size_mult;
    wire [3:0] read_bl_len;
    reg [31:0] capacity_sectors;
    reg [1:0] capacity_card_type;
    reg [21:0] capacity_c_size;
    reg [2:0] capacity_c_size_mult;
    reg [3:0] capacity_read_bl_len;
    reg [63:0] capacity_work;
    reg [4:0] capacity_shift_count;
    reg capacity_shift_right;
    reg capacity_calc_busy;

    // Isolate the SD command engine from the ATA task-file state machine.
    // Besides making the interface explicitly synchronous, this prevents the
    // SD parser's status decode from becoming part of CPU-visible timing.
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            sd_busy_ata <= 1'b0;
            sd_done_ata <= 1'b0;
            sd_error_ata <= 1'b0;
        end else begin
            sd_busy_ata <= sd_busy;
            sd_done_ata <= sd_done;
            sd_error_ata <= sd_crc_error || sd_timeout_error;
        end
    end

    // DAT1..DAT3 are unused in one-bit SD mode.  Their board-level pull-ups
    // keep them in the required idle state; leaving them undriven is intentional.

    // Calculate the CSD capacity over several clocks instead of placing a
    // variable-width barrel shifter on the CPU/IDENTIFY timing path.  Card
    // metadata is static after initialization, so the few calculation clocks
    // complete long before software can issue IDENTIFY DEVICE.
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            capacity_sectors <= 32'd0;
            capacity_card_type <= 2'd0;
            capacity_c_size <= 22'd0;
            capacity_c_size_mult <= 3'd0;
            capacity_read_bl_len <= 4'd0;
            capacity_work <= 64'd0;
            capacity_shift_count <= 5'd0;
            capacity_shift_right <= 1'b0;
            capacity_calc_busy <= 1'b0;
        end else if (capacity_calc_busy) begin
            if (capacity_shift_count != 0) begin
                if (capacity_shift_right)
                    capacity_work <= capacity_work >> 1;
                else
                    capacity_work <= capacity_work << 1;
                capacity_shift_count <= capacity_shift_count - 1'b1;
            end else begin
                capacity_sectors <= (|capacity_work[63:28]) ?
                                    32'h0fffffff :
                                    {4'b0000,capacity_work[27:0]};
                capacity_calc_busy <= 1'b0;
            end
        end else if ((card_type != 0) &&
                     ((card_type != capacity_card_type) ||
                      (c_size != capacity_c_size) ||
                      (c_size_mult != capacity_c_size_mult) ||
                      (read_bl_len != capacity_read_bl_len))) begin
            capacity_card_type <= card_type;
            capacity_c_size <= c_size;
            capacity_c_size_mult <= c_size_mult;
            capacity_read_bl_len <= read_bl_len;
            capacity_work <= {42'd0,c_size} + 1'b1;
            capacity_shift_right <= 1'b0;
            if (card_type == 2'd3) begin
                // SDHC/SDXC: capacity sectors = (C_SIZE + 1) * 1024.
                capacity_shift_count <= 5'd10;
            end else if (({1'b0,c_size_mult} + read_bl_len) >= 7) begin
                // SDSC: (C_SIZE + 1) << (C_SIZE_MULT + READ_BL_LEN - 7).
                capacity_shift_count <=
                    ({1'b0,c_size_mult} + read_bl_len) - 7;
            end else begin
                capacity_shift_count <=
                    7 - ({1'b0,c_size_mult} + read_bl_len);
                capacity_shift_right <= 1'b1;
            end
            capacity_calc_busy <= 1'b1;
        end
    end

    glenside_ata #(.IDE_BASE(IDE_BASE),
        .INIT_TIMEOUT_CYCLES(INIT_TIMEOUT_CYCLES)) ata(
        .clk(clk),.reset_n(reset_n),.cpu_enable(cpu_enable),.e_fall(e_fall),
        .cpu_addr(cpu_addr),.cpu_rw_n(cpu_rw_n),.cpu_wdata(cpu_wdata),
        .cpu_rdata(cpu_rdata),.cpu_data_oe(cpu_data_oe),
        .sd_init(sd_init),.sd_read_start(sd_read_start),
        .sd_write_start(sd_write_start),.sd_sector(sd_sector),
        .sd_busy(sd_busy_ata),.sd_done(sd_done_ata),
        .sd_error(sd_error_ata),
        .sd_data_valid(sd_outen),.sd_data_addr(sd_outaddr),
        .sd_data_in(sd_outbyte),.sd_data_out(sd_inbyte),
        .capacity_sectors(capacity_sectors));

    sd_reader #(.CLK_DIV(SD_CLK_DIV),.SIMULATE(0)) card(
        .rstn(reset_n),.clk(clk),.sdclk(sd_sclk),.sdcmd(sd_cmd),
        .sddat0(sd_dat0),.card_stat(card_stat),.card_type(card_type),
        .rstart(sd_read_start),.rsector(sd_sector),.rbusy(sd_busy),
        .rdone(sd_done),.outen(sd_outen),.outaddr(sd_outaddr),
        .outbyte(sd_outbyte),.wstart(sd_write_start),.inbyte(sd_inbyte),
        .c_size(c_size),.c_size_mult(c_size_mult),.read_bl_len(read_bl_len),
        .mid(),.oid(),.pnm(),.psn(),.crc_error(sd_crc_error),
        .timeout_error(sd_timeout_error),.init(sd_init));
endmodule
