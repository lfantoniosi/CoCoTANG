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

    // The mux publishes its atomic snapshot several clk cycles before
    // cpu_bus_valid crosses into this domain.  Pipeline the decoded result so
    // the transaction-launch edge does not contain the complete SAM decode,
    // ROM mapping and address mux path.  cycle_* then remains immutable for
    // the entire external CPU cycle.
    reg [22:0] selected_addr_pipe = 23'd0;
    reg pipe_mem_read = 1'b0;
    reg pipe_mem_write = 1'b0;
    reg [22:0] cycle_addr = 23'd0;
    reg cycle_mem_read = 1'b0;
    reg cycle_mem_write = 1'b0;

    reg cpu_req = 1'b0;
    reg cpu_wr = 1'b0;
    reg [22:0] request_addr = 23'd0;
    reg [7:0] request_wdata = 8'd0;
    wire cpu_ack;
    wire [7:0] cpu_read_value;
    reg [7:0] response_data = 8'hff;
    reg [22:0] response_addr = 23'h7fffff;
    reg response_valid = 1'b0;
    // A response that is already resident (or is arriving on this clk edge)
    // can satisfy another CPU cycle at the same address without dropping the
    // data bus and issuing a duplicate SDRAM transaction.
    wire snapshot_response_ready = pipe_mem_read &&
        ((response_valid && response_addr == selected_addr_pipe) ||
         (cpu_ack && !cpu_wr && request_addr == selected_addr_pipe));
    // selected_addr still describes the preceding bus cycle until the mux
    // finishes its Q-high scan.  Never let a matching stale response release
    // the SAM wait before that current-cycle snapshot has arrived.
    reg cycle_snapshot_seen = 1'b0;
    wire current_read_ready = cycle_snapshot_seen && cycle_mem_read &&
                              response_valid && response_addr == cycle_addr;
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
            selected_addr_pipe <= 23'd0;
            pipe_mem_read <= 1'b0;
            pipe_mem_write <= 1'b0;
            cycle_addr <= 23'd0;
            cycle_mem_read <= 1'b0;
            cycle_mem_write <= 1'b0;
            cycle_snapshot_seen <= 1'b0;
            pending_valid <= 1'b0;
            pending_wr <= 1'b0;
            pending_addr <= 23'd0;
            pending_wdata <= 8'd0;
            read_hold <= 3'd0;
        end else if (!cpu_access_enable) begin
            cpu_req <= 1'b0;
            response_valid <= 1'b0;
            cycle_mem_read <= 1'b0;
            cycle_mem_write <= 1'b0;
            cycle_snapshot_seen <= 1'b0;
            pending_valid <= 1'b0;
            read_hold <= 3'd0;
        end else begin
            selected_addr_pipe <= selected_addr;
            pipe_mem_read <= cpu_mem_read;
            pipe_mem_write <= cpu_mem_write;

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

            // The atomic mux snapshot arrives during Q high. Reuse a matching
            // resident byte; otherwise queue the new memory transaction.
            if (cpu_bus_valid) begin
                cycle_snapshot_seen <= 1'b1;
                cycle_addr <= selected_addr_pipe;
                cycle_mem_read <= pipe_mem_read;
                cycle_mem_write <= pipe_mem_write;
                if (pipe_mem_read) begin
                    if (snapshot_response_ready) begin
                        // Preserve the byte across repeated reads such as the
                        // reset-time FFFE cycles.  This gives the CPU the full
                        // Q-to-E data setup window instead of a narrow pulse
                        // at E falling.
                        response_valid <= 1'b1;
                        if (pending_valid && !pending_wr &&
                            pending_addr == selected_addr_pipe)
                            pending_valid <= 1'b0;
                    end else begin
                        response_valid <= 1'b0;
                        pending_wr <= 1'b0;
                        pending_addr <= selected_addr_pipe;
                        pending_wdata <= 8'd0;
                        pending_valid <= 1'b1;
                    end
                end else begin
                    response_valid <= 1'b0;
                end
            end

            // Once this cycle's address has been captured, recreate a missing
            // transaction if necessary.  Gating recovery with snapshot_seen
            // is essential: before then selected_addr is the previous cycle,
            // and a quick stale response can raise E only to be invalidated by
            // the real snapshot shortly before Q falls.
            if (cycle_snapshot_seen && cycle_mem_read && !current_read_ready &&
                !cpu_req && !pending_valid) begin
                pending_wr <= 1'b0;
                pending_addr <= cycle_addr;
                pending_wdata <= 8'd0;
                pending_valid <= 1'b1;
            end

            // The HD6309E write byte is stable at E falling. RAM is the only
            // writable SAM selection in this test top.
            if (e_fall) begin
                cycle_snapshot_seen <= 1'b0;
                if (cycle_mem_read && response_valid &&
                    response_addr == cycle_addr)
                    read_hold <= 3'd4;
                if (cycle_mem_write) begin
                    pending_wr <= 1'b1;
                    pending_addr <= cycle_addr;
                    pending_wdata <= cpu_wdata;
                    pending_valid <= 1'b1;
                end
            end

        end
    end

    assign cpu_rdata = response_data;
    // Once a tagged byte has arrived, keep it on the physical bus for as long
    // as the live captured address continues to request that byte.  Do not
    // gate OE with cycle_snapshot_seen: that flag is deliberately cleared at
    // every E falling edge, and doing so reduced repeated reads (notably the
    // reset-time FFFE cycles) to narrow data pulses instead of a stable level.
    // The response tag prevents a byte from leaking into a different cycle;
    // read_hold supplies the required hold time while the address changes.
    assign cpu_data_oe = cpu_access_enable &&
                         ((cpu_mem_read && response_valid &&
                           response_addr == selected_addr) ||
                          read_hold != 0);
    // Never raise E for a memory read until the byte for this exact captured
    // address is on the CPU bus. The recovery launcher above prevents this
    // strict condition from deadlocking on a missed reset-vector request.
    assign cpu_wait = cpu_access_enable && cycle_mem_read &&
                      !current_read_ready;

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
                (e_fall && cycle_mem_write && video_cache_valid &&
                 video_response_word[22:2] == cycle_addr[22:2]))
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
