// SDRAM arbiter for the standalone physical-HD6309E test top. There are only
// three clients: the live CPU, VDG video fetches, and the one-shot SPI-flash
// ROM loader.  The short early-E-low window is reserved for one interleaved
// video word; CPU has priority everywhere else in the cycle.
module cpu_sdram_arbiter #(
    parameter CLK_HZ = 108000000
) (
    input clk,
    input reset_n,
    input e,
    input q,

    input cpu_req,
    input cpu_wr,
    input [22:0] cpu_addr,
    input [7:0] cpu_wdata,
    output reg cpu_ack,
    output reg [7:0] cpu_rdata,

    input video_req,
    input [22:0] video_addr,
    input video_slot_open,
    input refresh_slot_open,
    output reg video_ack,
    output reg [31:0] video_rdata,

    input loader_req,
    input loader_wr,
    input [22:0] loader_addr,
    input [7:0] loader_wdata,
    output reg loader_ack,
    output reg [7:0] loader_rdata,

    output reg rd,
    output reg wr,
    output reg refresh,
    output reg [22:0] addr,
    output reg [15:0] din,
    output reg [1:0] wdm,
    input [15:0] dout,
    input [31:0] dout32,
    input data_ready,
    input busy,
    input enabled
);
    localparam IDLE=3'd0, ACTIVE_READ=3'd1, ACTIVE_WRITE=3'd2,
               WAIT_DROP=3'd3, ACTIVE_REFRESH=3'd4;
    localparam REFRESH_CYCLES = CLK_HZ / 100000;

    reg [2:0] state = IDLE;
    localparam OWNER_CPU=2'd0, OWNER_VIDEO=2'd1, OWNER_LOADER=2'd2;
    reg [1:0] owner = OWNER_CPU;
    reg byte_lane = 1'b0;
    reg saw_busy = 1'b0;
    reg [7:0] recovery_count = 8'd0;
    reg [15:0] refresh_count = 16'd0;
    wire owner_req = (owner == OWNER_CPU) ? cpu_req :
                     (owner == OWNER_VIDEO) ? video_req : loader_req;
    // Match the real SAM's interleaved DMA. Background commands may begin
    // only at the start of the early E-low interval. Each slot indication is
    // deliberately shorter than the complete E-low/Q-low quadrant so an
    // SDRAM operation can never be launched immediately before Q announces
    // the next CPU address.
    wire video_background_slot = !e && !q && video_slot_open;
    // Refresh must remain available while the VDG is held in reset.  In
    // particular, the ROM sits in SDRAM during the post-load CPU reset hold,
    // so tying refresh eligibility to video_enable loses the boot image
    // before the CPU can fetch its reset vector.
    wire refresh_background_slot = !e && !q && refresh_slot_open;

    task launch;
        input [1:0] selected_owner;
        input selected_write;
        input [22:0] byte_address;
        input [7:0] write_data;
        begin
            owner <= selected_owner;
            byte_lane <= byte_address[0];
            // Convert the CPU byte address into the SDRAM controller's
            // half-word address; the mask selects the byte on writes.
            addr <= {1'b0,byte_address[22:2],byte_address[1]};
            din <= {write_data,write_data};
            wdm <= byte_address[0] ? 2'b01 : 2'b10;
            rd <= !selected_write;
            wr <= selected_write;
            saw_busy <= 1'b0;
            recovery_count <= 8'd0;
            state <= selected_write ? ACTIVE_WRITE : ACTIVE_READ;
        end
    endtask

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state <= IDLE;
            owner <= OWNER_CPU;
            byte_lane <= 1'b0;
            saw_busy <= 1'b0;
            recovery_count <= 8'd0;
            refresh_count <= 16'd0;
            rd <= 1'b0;
            wr <= 1'b0;
            refresh <= 1'b0;
            addr <= 23'd0;
            din <= 16'd0;
            wdm <= 2'b11;
            cpu_ack <= 1'b0;
            video_ack <= 1'b0;
            loader_ack <= 1'b0;
            loader_rdata <= 8'hff;
            cpu_rdata <= 8'hff;
            video_rdata <= 32'd0;
        end else begin
            rd <= 1'b0;
            wr <= 1'b0;
            refresh <= 1'b0;
            cpu_ack <= 1'b0;
            video_ack <= 1'b0;
            loader_ack <= 1'b0;
            if (refresh_count != REFRESH_CYCLES)
                refresh_count <= refresh_count + 1'b1;
            if (state == IDLE)
                recovery_count <= 8'd0;
            else if (recovery_count != 8'hff)
                recovery_count <= recovery_count + 1'b1;

            case (state)
                IDLE: if (!busy) begin
                    // At E-fall the previous CPU transfer is complete and
                    // the next physical address is not required until the
                    // following Q/E phases.  Giving this bounded slot to
                    // video guarantees GIME's forty 32-bit words per 80-col
                    // row even while speculative CPU reads remain queued.
                    if (video_req && video_background_slot)
                        launch(OWNER_VIDEO,1'b0,video_addr,8'd0);
                    else if (enabled && refresh_background_slot &&
                             refresh_count == REFRESH_CYCLES) begin
                        // CPU and loader requests can be continuous.  Once
                        // due, use the next unused early-E-low slot so they
                        // cannot starve SDRAM refresh indefinitely.
                        refresh <= 1'b1;
                        refresh_count <= 16'd0;
                        saw_busy <= 1'b0;
                        state <= ACTIVE_REFRESH;
                    end
                    else if (cpu_req)
                        launch(OWNER_CPU,cpu_wr,cpu_addr,cpu_wdata);
                    else if (loader_req)
                        launch(OWNER_LOADER,loader_wr,loader_addr,loader_wdata);
                end
                ACTIVE_READ: begin
                    if (data_ready) begin
                        if (owner == OWNER_CPU) begin
                            cpu_rdata <= byte_lane ? dout[15:8] : dout[7:0];
                            cpu_ack <= 1'b1;
                        end else if (owner == OWNER_VIDEO) begin
                            video_rdata <= dout32;
                            video_ack <= 1'b1;
                        end else begin
                            loader_rdata <= byte_lane ? dout[15:8] : dout[7:0];
                            loader_ack <= 1'b1;
                        end
                        recovery_count <= 8'd0;
                        state <= WAIT_DROP;
                    end else if (recovery_count == 8'hff) begin
                        // The requester still holds its request, so returning
                        // to IDLE retries the same transaction once the SDRAM
                        // controller is no longer busy.
                        recovery_count <= 8'd0;
                        state <= IDLE;
                    end
                end
                ACTIVE_WRITE: begin
                    if (busy)
                        saw_busy <= 1'b1;
                    if (saw_busy && !busy) begin
                        if (owner == OWNER_LOADER)
                            loader_ack <= 1'b1;
                        else
                            cpu_ack <= 1'b1;
                        recovery_count <= 8'd0;
                        state <= WAIT_DROP;
                    end else if (recovery_count == 8'hff && !busy) begin
                        // Recover if the short busy assertion was not sampled.
                        if (owner == OWNER_LOADER)
                            loader_ack <= 1'b1;
                        else
                            cpu_ack <= 1'b1;
                        recovery_count <= 8'd0;
                        state <= WAIT_DROP;
                    end
                end
                ACTIVE_REFRESH: begin
                    if (busy)
                        saw_busy <= 1'b1;
                    if ((saw_busy || recovery_count == 8'hff) && !busy) begin
                        recovery_count <= 8'd0;
                        state <= IDLE;
                    end
                end
                WAIT_DROP: begin
                    if (!owner_req) begin
                        recovery_count <= 8'd0;
                        state <= IDLE;
                    end else if (recovery_count == 8'hff) begin
                        // ACK is a pulse. Replay it if the client missed the
                        // original pulse and therefore never dropped request.
                        if (owner == OWNER_CPU)
                            cpu_ack <= 1'b1;
                        else if (owner == OWNER_VIDEO)
                            video_ack <= 1'b1;
                        else
                            loader_ack <= 1'b1;
                        recovery_count <= 8'd0;
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
