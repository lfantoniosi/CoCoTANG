// CPU-only CoCo 2 memory service.  RAM occupies SDRAM byte addresses
// 000000-00ffff and the 16 KiB flash-backed ROM cache starts at 080000.
// No VDG, framebuffer, test-fill client, or debug program can arbitrate here.
module cpu_test_memory #(
    parameter integer ROM_BYTES = 16384
) (
    input clk,
    input reset_n,
    input loader_start,
    input cpu_access_enable,
    input cpu_bus_valid,
    input e_fall,
    input [15:0] cpu_addr,
    input cpu_rw_n,
    input [2:0] sam_s,
    input [7:0] cpu_wdata,
    output [7:0] cpu_rdata,
    output cpu_data_oe,
    output loader_done,

    output mspi_cs,
    output mspi_sclk,
    input mspi_miso,
    output mspi_mosi,

    input sdram_enabled,
    output sd_rd,
    output sd_wr,
    output sd_refresh,
    output [22:0] sd_addr,
    output [15:0] sd_din,
    output [1:0] sd_wdm,
    input [15:0] sd_dout,
    input sd_data_ready,
    input sd_busy
);
    localparam [22:0] RAM_BASE = 23'h000000;
    localparam [22:0] ROM_BASE = 23'h080000;

    wire cpu_mem_read = cpu_rw_n && (sam_s <= 3'd2);
    wire cpu_mem_write = !cpu_rw_n && (sam_s == 3'd0);
    wire cpu_mem_is_rom = (sam_s == 3'd1) || (sam_s == 3'd2);
    wire [22:0] logical_addr = (sam_s == 3'd1) ?
                               23'h002000 + {10'd0,cpu_addr[12:0]} :
                               (sam_s == 3'd2) ? {10'd0,cpu_addr[12:0]} :
                                                {7'd0,cpu_addr};
    wire [22:0] selected_addr = cpu_mem_is_rom ?
                                ROM_BASE + logical_addr : RAM_BASE + logical_addr;

    reg cpu_req = 1'b0;
    reg cpu_wr = 1'b0;
    reg [22:0] request_addr = 23'd0;
    reg [7:0] request_wdata = 8'd0;
    wire cpu_ack;
    wire [7:0] cpu_read_value;
    reg [7:0] response_data = 8'hff;
    reg [22:0] response_addr = 23'h7fffff;
    reg response_valid = 1'b0;
    reg cycle_requested = 1'b0;
    reg [2:0] read_hold = 3'd0;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            cpu_req <= 1'b0;
            cpu_wr <= 1'b0;
            request_addr <= 23'd0;
            request_wdata <= 8'd0;
            response_data <= 8'hff;
            response_addr <= 23'h7fffff;
            response_valid <= 1'b0;
            cycle_requested <= 1'b0;
            read_hold <= 3'd0;
        end else if (!cpu_access_enable) begin
            cpu_req <= 1'b0;
            response_valid <= 1'b0;
            cycle_requested <= 1'b0;
            read_hold <= 3'd0;
        end else begin
            if (read_hold != 0)
                read_hold <= read_hold - 1'b1;

            if (cpu_ack) begin
                cpu_req <= 1'b0;
                if (!cpu_wr) begin
                    response_data <= cpu_read_value;
                    response_addr <= request_addr;
                    response_valid <= 1'b1;
                end
            end

            // The atomic mux snapshot arrives during Q high.  Launch the
            // SDRAM read immediately; do not wait for E to rise.
            if (cpu_bus_valid) begin
                cycle_requested <= 1'b0;
                response_valid <= 1'b0;
                if (cpu_mem_read && !cpu_req) begin
                    cpu_wr <= 1'b0;
                    request_addr <= selected_addr;
                    cpu_req <= 1'b1;
                    cycle_requested <= 1'b1;
                end
            end

            // The 6809 write byte is stable at E falling.  RAM is the only
            // writable selection in this stripped test system.
            if (e_fall) begin
                if (cpu_mem_read && response_valid &&
                    response_addr == selected_addr)
                    read_hold <= 3'd4;
                if (cpu_mem_write && !cpu_req && !cycle_requested) begin
                    cpu_wr <= 1'b1;
                    request_addr <= selected_addr;
                    request_wdata <= cpu_wdata;
                    cpu_req <= 1'b1;
                    cycle_requested <= 1'b1;
                end
            end
        end
    end

    assign cpu_rdata = response_data;
    // Drive as soon as SDRAM acknowledges, and retain a short hold interval
    // after E falls.  Address matching prevents a late response from being
    // presented during a different CPU cycle.
    assign cpu_data_oe = cpu_access_enable &&
                         ((cpu_mem_read && response_valid &&
                           response_addr == selected_addr) || read_hold != 0);

    wire loader_req;
    wire loader_ack;
    wire [22:0] loader_addr;
    wire [7:0] loader_wdata;
    coco_flash_loader #(
        .SDRAM_ADDRESS(ROM_BASE), .BYTE_COUNT(ROM_BYTES)
    ) loader (
        .clk(clk), .reset_n(reset_n), .start(loader_start), .done(loader_done),
        .mem_req(loader_req), .mem_addr(loader_addr), .mem_wdata(loader_wdata),
        .mem_ack(loader_ack), .mspi_cs(mspi_cs), .mspi_sclk(mspi_sclk),
        .mspi_miso(mspi_miso), .mspi_mosi(mspi_mosi)
    );

    cpu_sdram_arbiter arbiter (
        .clk(clk), .reset_n(reset_n),
        .cpu_req(cpu_req), .cpu_wr(cpu_wr), .cpu_addr(request_addr),
        .cpu_wdata(request_wdata), .cpu_ack(cpu_ack), .cpu_rdata(cpu_read_value),
        .loader_req(loader_req), .loader_addr(loader_addr),
        .loader_wdata(loader_wdata), .loader_ack(loader_ack),
        .rd(sd_rd), .wr(sd_wr), .refresh(sd_refresh), .addr(sd_addr),
        .din(sd_din), .wdm(sd_wdm), .dout(sd_dout),
        .data_ready(sd_data_ready), .busy(sd_busy), .enabled(sdram_enabled)
    );
endmodule
