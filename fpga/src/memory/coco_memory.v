module coco_memory #(
    parameter integer TEST_FILL = 1,
    parameter integer ROM_BYTES = 16384
) (
    input clk, input reset_n, input loader_start,
    input e, input q, input e_rise, input e_fall, input cpu_access_enable,
    input cpu_bus_valid,
    input [7:0] cpu_wdata,
    input cpu_mem_read, input cpu_mem_write, input cpu_mem_is_rom,
    input [22:0] cpu_mem_addr,
    output [7:0] cpu_rdata, output cpu_data_oe,
    output debug_cpu_req, output debug_cpu_ack,
    input video_read_request, input [22:0] video_addr,
    output [7:0] video_data, output [31:0] video_data32,
    output reg video_data_valid,
    output loader_done,
    output mspi_cs, output mspi_sclk, input mspi_miso, output mspi_mosi,
    input sdram_enabled,
    output sd_rd, output sd_wr, output sd_refresh,
    output [22:0] sd_addr, output [15:0] sd_din, output [1:0] sd_wdm,
    input [15:0] sd_dout, input [31:0] sd_dout32,
    input sd_data_ready, input sd_busy
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
    reg [22:0] cpu_response_addr = 23'd0;
    reg cpu_cycle_serviced = 1'b0;
    reg [2:0] cpu_read_hold = 3'd0;

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
            cpu_response_addr <= 23'd0;
            cpu_cycle_serviced <= 1'b0;
            cpu_read_hold <= 3'd0;
        end else begin
            if (!cpu_access_enable) begin
                cpu_req <= 1'b0;
                cpu_wr <= 1'b0;
                cpu_data_valid <= 1'b0;
                cpu_cycle_serviced <= 1'b0;
                cpu_read_hold <= 3'd0;
            end else begin
                if (cpu_read_hold != 3'd0)
                    cpu_read_hold <= cpu_read_hold - 1'b1;
                if (cpu_ack) begin
                    cpu_req <= 1'b0;
                    // Retain a late read response.  The output address check
                    // below permits it on a repeated CPU cycle but prevents
                    // stale data from being driven for a different address.
                    if (!cpu_wr) begin
                        cpu_rdata_reg <= cpu_read_value;
                        cpu_response_addr <= cpu_sdram_addr;
                        cpu_data_valid <= 1'b1;
                    end
                end
                if (e_fall) begin
                    // The 6809 samples read data at E falling.  Retain the
                    // driven byte for about 37 ns afterward instead of
                    // removing it on the sampling edge with zero hold time.
                    if (cpu_mem_read && cpu_data_valid &&
                        selected_read_addr == cpu_response_addr)
                        cpu_read_hold <= 3'd4;
                    cpu_cycle_serviced <= 1'b0;
                    if (cpu_mem_write && !cpu_req) begin
                        cpu_wr <= 1'b1;
                        cpu_sdram_addr <= RAM_BASE + cpu_mem_addr;
                        cpu_mem_wdata <= cpu_wdata;
                        cpu_req <= 1'b1;
                        cpu_cycle_serviced <= 1'b1;
                    end
                // Launch from the newly synchronized atomic bus snapshot.
                end else if (cpu_bus_valid && cpu_mem_read &&
                             !cpu_req && !cpu_cycle_serviced) begin
                    cpu_wr <= 1'b0;
                    cpu_sdram_addr <= selected_read_addr;
                    cpu_req <= 1'b1;
                    cpu_cycle_serviced <= 1'b1;
                end
            end
        end
    end
    assign cpu_rdata = cpu_rdata_reg;
    assign cpu_data_oe = (e && cpu_mem_read && cpu_data_valid &&
                          (selected_read_addr == cpu_response_addr)) ||
                         (cpu_read_hold != 3'd0);
    assign debug_cpu_req = cpu_req;
    assign debug_cpu_ack = cpu_ack;

    reg video_req = 1'b0;
    reg [22:0] video_mem_addr = 23'd0;
    reg [22:0] last_video_addr = 23'h7fffff;
    reg [31:0] video_data_reg = 32'd0;
    reg [1:0] video_byte_lane = 2'd0;
    wire video_ack;
    wire [31:0] video_read_value;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            video_req <= 1'b0;
            video_mem_addr <= 23'd0;
            last_video_addr <= 23'h7fffff;
            video_data_reg <= 32'd0;
            video_byte_lane <= 2'd0;
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
                video_byte_lane <= video_addr[1:0];
                video_req <= 1'b1;
            end
        end
    end
    assign video_data32 = video_data_reg;
    assign video_data = video_byte_lane == 2'd0 ? video_data_reg[7:0] :
                        video_byte_lane == 2'd1 ? video_data_reg[15:8] :
                        video_byte_lane == 2'd2 ? video_data_reg[23:16] :
                                                  video_data_reg[31:24];

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
        .din(sd_din), .wdm(sd_wdm), .dout(sd_dout), .dout32(sd_dout32),
        .data_ready(sd_data_ready), .busy(sd_busy), .enabled(sdram_enabled)
    );
endmodule
