// Physical-CPU CoCo 2 memory service. RAM occupies SDRAM byte addresses
// 000000-00ffff and the 16 KiB flash-backed ROM starts at 080000. Separate
// an aligned four-byte cache line feeds the VDG. The CPU retains the proven
// byte-read path while the video arbitration is validated in hardware.
module cpu_test_memory #(
    parameter integer ROM_BYTES = 16384
) (
    input clk,
    input reset_n,
    input loader_start,
    input cpu_access_enable,
    input cpu_bus_valid,
    input e,
    input q,
    input e_fall,
    input [15:0] cpu_addr,
    input cpu_rw_n,
    input [2:0] sam_s,
    input [7:0] cpu_wdata,
    output [7:0] cpu_rdata,
    output cpu_data_oe,
    output cpu_wait,
    input [22:0] video_addr,
    output reg [7:0] video_data,
    output reg video_data_valid,
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
    input [31:0] sd_dout32,
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
    // A new CPU cycle can arrive while the arbiter is still retiring the
    // previous SDRAM request (especially when video is active).  Keep that
    // transaction here instead of silently dropping it.
    reg pending_valid = 1'b0;
    reg pending_wr = 1'b0;
    reg [22:0] pending_addr = 23'd0;
    reg [7:0] pending_wdata = 8'd0;
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
            pending_valid <= 1'b0;
            pending_wr <= 1'b0;
            pending_addr <= 23'd0;
            pending_wdata <= 8'd0;
            read_hold <= 3'd0;
        end else if (!cpu_access_enable) begin
            cpu_req <= 1'b0;
            response_valid <= 1'b0;
            pending_valid <= 1'b0;
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

            // Move a queued transaction into the SDRAM request slot as soon
            // as it becomes free.  Keeping pending_valid asserted until this
            // edge also keeps Q/E stopped continuously between transactions.
            if (pending_valid && !cpu_req) begin
                cpu_wr <= pending_wr;
                request_addr <= pending_addr;
                request_wdata <= pending_wdata;
                cpu_req <= 1'b1;
                pending_valid <= 1'b0;
            end

            // The atomic mux snapshot arrives during Q high. Queue every
            // memory read, even if the previous SDRAM transaction is active.
            if (cpu_bus_valid) begin
                response_valid <= 1'b0;
                if (cpu_mem_read) begin
                    pending_wr <= 1'b0;
                    pending_addr <= selected_addr;
                    pending_wdata <= 8'd0;
                    pending_valid <= 1'b1;
                end
            end

            // The HD6309E write byte is stable at E falling. RAM is the only
            // writable SAM selection in this test top.
            if (e_fall) begin
                if (cpu_mem_read && response_valid &&
                    response_addr == selected_addr)
                    read_hold <= 3'd4;
                if (cpu_mem_write) begin
                    pending_wr <= 1'b1;
                    pending_addr <= selected_addr;
                    pending_wdata <= cpu_wdata;
                    pending_valid <= 1'b1;
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
    // Keep the pre-E hold continuous from snapshot through queued/active SDRAM
    // service. This prevents an old ACK from releasing E while the current
    // cycle's read is still waiting to launch.
    assign cpu_wait = cpu_access_enable &&
                      (cpu_req || pending_valid ||
                       (cpu_bus_valid && cpu_mem_read));

    // The MC6847 address advances independently of the CPU. Fetch one
    // aligned 32-bit SDRAM word whenever it enters a new group of four bytes;
    // the VDG consumes the selected byte until the next word arrives.
    reg video_req = 1'b0;
    reg [22:0] video_request_addr = 23'd0;
    reg [22:0] video_response_word = 23'h7fffff;
    reg [31:0] video_data_reg = 32'd0;
    reg video_cache_valid = 1'b0;
    wire video_ack;
    wire [31:0] video_read_value;
    wire video_word_matches = video_cache_valid &&
                              video_response_word[22:2] == video_addr[22:2];
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            video_req <= 1'b0;
            video_request_addr <= 23'd0;
            video_response_word <= 23'h7fffff;
            video_data_reg <= 32'd0;
            video_data <= 8'h00;
            video_cache_valid <= 1'b0;
            video_data_valid <= 1'b0;
        end else if (!cpu_access_enable) begin
            video_req <= 1'b0;
            video_response_word <= 23'h7fffff;
            video_cache_valid <= 1'b0;
            video_data <= 8'h00;
            video_data_valid <= 1'b0;
        end else begin
            video_data_valid <= 1'b0;
            // Register the selected cache byte. The MC6847 advances at the
            // much slower SAM rate, leaving several clk cycles before it uses
            // this value and breaking a long VDG-address-to-pixel path.
            if (!video_word_matches)
                video_data <= 8'h00;
            else begin
                case (video_addr[1:0])
                    2'd0: video_data <= video_data_reg[7:0];
                    2'd1: video_data <= video_data_reg[15:8];
                    2'd2: video_data <= video_data_reg[23:16];
                    default: video_data <= video_data_reg[31:24];
                endcase
            end
            if (video_ack) begin
                video_req <= 1'b0;
                video_response_word <= video_request_addr;
                video_data_reg <= video_read_value;
                video_cache_valid <= 1'b1;
                video_data_valid <= 1'b1;
            end
            // Start video work immediately after the CPU sampling edge. This
            // keeps VDG traffic out of the CPU's Q-to-E read-data window.
            if (e_fall && !video_req && !video_word_matches) begin
                video_request_addr <= {video_addr[22:2],2'b00};
                video_req <= 1'b1;
            end
            if ((cpu_req && cpu_wr && video_cache_valid &&
                 video_response_word[22:2] == request_addr[22:2]) ||
                (e_fall && cpu_mem_write && video_cache_valid &&
                 video_response_word[22:2] == selected_addr[22:2]))
                video_cache_valid <= 1'b0;
        end
    end
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
        .clk(clk), .reset_n(reset_n), .e(e), .q(q),
        .cpu_req(cpu_req), .cpu_wr(cpu_wr), .cpu_addr(request_addr),
        .cpu_wdata(request_wdata), .cpu_ack(cpu_ack), .cpu_rdata(cpu_read_value),
        .video_req(video_req), .video_addr(video_request_addr),
        .video_ack(video_ack), .video_rdata(video_read_value),
        .loader_req(loader_req), .loader_addr(loader_addr),
        .loader_wdata(loader_wdata), .loader_ack(loader_ack),
        .rd(sd_rd), .wr(sd_wr), .refresh(sd_refresh), .addr(sd_addr),
        .din(sd_din), .wdm(sd_wdm), .dout(sd_dout), .dout32(sd_dout32),
        .data_ready(sd_data_ready), .busy(sd_busy), .enabled(sdram_enabled)
    );
endmodule
