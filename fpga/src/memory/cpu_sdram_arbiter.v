// SDRAM arbiter for the standalone physical-HD6309E test top. There are only
// three clients: the live CPU, VDG video fetches, and the one-shot SPI-flash
// ROM loader. CPU always has highest priority so adding video cannot delay a
// request that is ready at the start of an SDRAM transaction.
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
    output reg video_ack,
    output reg [31:0] video_rdata,

    input loader_req,
    input [22:0] loader_addr,
    input [7:0] loader_wdata,
    output reg loader_ack,

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
    reg [15:0] refresh_count = 16'd0;
    wire owner_req = (owner == OWNER_CPU) ? cpu_req :
                     (owner == OWNER_VIDEO) ? video_req : loader_req;
    // Match the real SAM's interleaved DMA. VDG and refresh commands may
    // begin only in the early E-low interval, before Q announces the next
    // CPU address. Once Q rises, no new background transaction can launch.
    wire background_slot = !e && !q;

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
            state <= selected_write ? ACTIVE_WRITE : ACTIVE_READ;
        end
    endtask

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state <= IDLE;
            owner <= OWNER_CPU;
            byte_lane <= 1'b0;
            saw_busy <= 1'b0;
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

            case (state)
                IDLE: if (!busy) begin
                    if (cpu_req)
                        launch(OWNER_CPU,cpu_wr,cpu_addr,cpu_wdata);
                    else if (video_req && background_slot)
                        launch(OWNER_VIDEO,1'b0,video_addr,8'd0);
                    else if (loader_req)
                        launch(OWNER_LOADER,1'b1,loader_addr,loader_wdata);
                    else if (enabled && background_slot &&
                             refresh_count == REFRESH_CYCLES) begin
                        refresh <= 1'b1;
                        refresh_count <= 16'd0;
                        saw_busy <= 1'b0;
                        state <= ACTIVE_REFRESH;
                    end
                end
                ACTIVE_READ: if (data_ready) begin
                    if (owner == OWNER_CPU) begin
                        cpu_rdata <= byte_lane ? dout[15:8] : dout[7:0];
                        cpu_ack <= 1'b1;
                    end else begin
                        video_rdata <= dout32;
                        video_ack <= 1'b1;
                    end
                    state <= WAIT_DROP;
                end
                ACTIVE_WRITE: begin
                    if (busy)
                        saw_busy <= 1'b1;
                    if (saw_busy && !busy) begin
                        if (owner == OWNER_LOADER)
                            loader_ack <= 1'b1;
                        else
                            cpu_ack <= 1'b1;
                        state <= WAIT_DROP;
                    end
                end
                ACTIVE_REFRESH: begin
                    if (busy)
                        saw_busy <= 1'b1;
                    if (saw_busy && !busy)
                        state <= IDLE;
                end
                default: if (!owner_req)
                    state <= IDLE;
            endcase
        end
    end
endmodule
