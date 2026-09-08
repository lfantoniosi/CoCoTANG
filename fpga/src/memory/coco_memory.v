module coco_memory #(
    parameter integer TEST_FILL = 1,
    parameter integer ROM_BYTES = 16384
) (
    input clk, input reset_n, input loader_start,
    input e, input e_rise, input e_fall,
    input [7:0] cpu_wdata,
    input cpu_mem_read, input cpu_mem_write, input cpu_mem_is_rom,
    input [22:0] cpu_mem_addr,
    output [7:0] cpu_rdata, output cpu_data_oe,
    input video_read_request, input [22:0] video_addr, output [7:0] video_data,
    output reg video_data_valid,
    output loader_done,
    output mspi_cs, output mspi_sclk, input mspi_miso, output mspi_mosi,
    input sdram_enabled,
    output sd_rd, output sd_wr, output sd_refresh,
    output [22:0] sd_addr, output [15:0] sd_din, output [1:0] sd_wdm,
    input [15:0] sd_dout, input sd_data_ready, input sd_busy
);
    localparam [22:0] RAM_BASE = 23'h000000;
    // Keep the flash-backed ROM cache above the GIME's complete 512 KiB RAM
    // address space so MMU page selections can never alias it.
    localparam [22:0] ROM_BASE = 23'h080000;

    reg cpu_req = 1'b0;
    reg cpu_wr = 1'b0;
    reg [22:0] cpu_sdram_addr = 23'd0;
    reg [7:0] cpu_mem_wdata = 8'd0;
    wire cpu_ack;
    wire [7:0] cpu_read_value;
    reg [7:0] cpu_rdata_reg = 8'hff;
    reg cpu_data_valid = 1'b0;

    wire [22:0] selected_read_addr = cpu_mem_is_rom ?
                                      ROM_BASE + cpu_mem_addr :
                                      RAM_BASE + cpu_mem_addr;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            cpu_req <= 1'b0;
            cpu_wr <= 1'b0;
            cpu_sdram_addr <= 23'd0;
            cpu_mem_wdata <= 8'd0;
            cpu_rdata_reg <= 8'hff;
            cpu_data_valid <= 1'b0;
        end else begin
            if (cpu_ack) begin
                cpu_req <= 1'b0;
                if (!cpu_wr) begin
                    cpu_rdata_reg <= cpu_read_value;
                    cpu_data_valid <= 1'b1;
                end
            end
            if (e_fall) begin
                cpu_data_valid <= 1'b0;
                if (cpu_mem_write && !cpu_req) begin
                    cpu_wr <= 1'b1;
                    cpu_sdram_addr <= RAM_BASE + cpu_mem_addr;
                    cpu_mem_wdata <= cpu_wdata;
                    cpu_req <= 1'b1;
                end
            end else if (e_rise && cpu_mem_read && !cpu_req) begin
                cpu_wr <= 1'b0;
                cpu_sdram_addr <= selected_read_addr;
                cpu_req <= 1'b1;
            end
        end
    end
    assign cpu_rdata = cpu_rdata_reg;
    assign cpu_data_oe = e && cpu_mem_read && cpu_data_valid;

    reg video_req = 1'b0;
    reg [22:0] video_mem_addr = 23'd0;
    reg [22:0] last_video_addr = 23'h7fffff;
    reg [7:0] video_data_reg = 8'd0;
    wire video_ack;
    wire [7:0] video_read_value;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            video_req <= 1'b0;
            video_mem_addr <= 23'd0;
            last_video_addr <= 23'h7fffff;
            video_data_reg <= 8'd0;
            video_data_valid <= 1'b0;
        end else begin
            video_data_valid <= 1'b0;
            if (video_ack) begin
                video_req <= 1'b0;
                video_data_reg <= video_read_value;
                video_data_valid <= 1'b1;
            end
            if (!video_req && (video_read_request || video_addr != last_video_addr)) begin
                last_video_addr <= video_addr;
                video_mem_addr <= RAM_BASE + video_addr;
                video_req <= 1'b1;
            end
        end
    end
    assign video_data = video_data_reg;

    wire loader_req, loader_ack;
    wire [22:0] loader_addr;
    wire [7:0] loader_wdata;
    wire fill_req, fill_ack, fill_done;
    wire [22:0] fill_addr;
    wire [7:0] fill_wdata;
    sdram_test_fill fill (
        .clk(clk), .reset_n(reset_n), .start(loader_start), .done(fill_done),
        .mem_req(fill_req), .mem_addr(fill_addr), .mem_wdata(fill_wdata),
        .mem_ack(fill_ack)
    );

    wire rom_req, rom_ack, rom_done;
    wire [22:0] rom_addr;
    wire [7:0] rom_wdata;
    wire rom_start = loader_start && ((TEST_FILL == 0) || fill_done);
    coco_flash_loader #(.SDRAM_ADDRESS(ROM_BASE), .BYTE_COUNT(ROM_BYTES)) loader (
        .clk(clk), .reset_n(reset_n), .start(rom_start), .done(rom_done),
        .mem_req(rom_req), .mem_addr(rom_addr), .mem_wdata(rom_wdata),
        .mem_ack(rom_ack), .mspi_cs(mspi_cs), .mspi_sclk(mspi_sclk),
        .mspi_miso(mspi_miso), .mspi_mosi(mspi_mosi)
    );
    assign loader_req = ((TEST_FILL != 0) && !fill_done) ? fill_req : rom_req;
    assign loader_addr = ((TEST_FILL != 0) && !fill_done) ? fill_addr : rom_addr;
    assign loader_wdata = ((TEST_FILL != 0) && !fill_done) ? fill_wdata : rom_wdata;
    assign fill_ack = ((TEST_FILL != 0) && !fill_done) ? loader_ack : 1'b0;
    assign rom_ack = ((TEST_FILL == 0) || fill_done) ? loader_ack : 1'b0;
    assign loader_done = rom_done;

    sdram_arbiter arbiter (
        .clk(clk), .reset_n(reset_n),
        .cpu_req(cpu_req), .cpu_wr(cpu_wr), .cpu_addr(cpu_sdram_addr),
        .cpu_wdata(cpu_mem_wdata), .cpu_ack(cpu_ack), .cpu_rdata(cpu_read_value),
        .video_req(video_req), .video_addr(video_mem_addr),
        .video_ack(video_ack), .video_rdata(video_read_value),
        .loader_req(loader_req), .loader_addr(loader_addr),
        .loader_wdata(loader_wdata), .loader_ack(loader_ack),
        .rd(sd_rd), .wr(sd_wr), .refresh(sd_refresh), .addr(sd_addr),
        .din(sd_din), .wdm(sd_wdm), .dout(sd_dout),
        .data_ready(sd_data_ready), .busy(sd_busy), .enabled(sdram_enabled)
    );
endmodule
