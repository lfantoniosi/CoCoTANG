// SDRAM arbiter for the standalone physical-6809 test top.  There are only
// two clients: the live CPU and the one-shot SPI-flash ROM loader.  CPU wins
// whenever both request at once; there is deliberately no video client.
module cpu_sdram_arbiter #(
    parameter CLK_HZ = 108000000
) (
    input clk,
    input reset_n,

    input cpu_req,
    input cpu_wr,
    input [22:0] cpu_addr,
    input [7:0] cpu_wdata,
    output reg cpu_ack,
    output reg [7:0] cpu_rdata,

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
    input data_ready,
    input busy,
    input enabled
);
    localparam IDLE=3'd0, ACTIVE_READ=3'd1, ACTIVE_WRITE=3'd2,
               WAIT_DROP=3'd3, ACTIVE_REFRESH=3'd4;
    localparam REFRESH_CYCLES = CLK_HZ / 100000;

    reg [2:0] state = IDLE;
    reg owner_loader = 1'b0;
    reg byte_lane = 1'b0;
    reg saw_busy = 1'b0;
    reg [15:0] refresh_count = 16'd0;
    wire owner_req = owner_loader ? loader_req : cpu_req;

    task launch;
        input selected_loader;
        input selected_write;
        input [22:0] byte_address;
        input [7:0] write_data;
        begin
            owner_loader <= selected_loader;
            byte_lane <= byte_address[0];
            // The SDRAM controller presents a 16-bit access interface.
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
            owner_loader <= 1'b0;
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
            loader_ack <= 1'b0;
            cpu_rdata <= 8'hff;
        end else begin
            rd <= 1'b0;
            wr <= 1'b0;
            refresh <= 1'b0;
            cpu_ack <= 1'b0;
            loader_ack <= 1'b0;
            if (refresh_count != REFRESH_CYCLES)
                refresh_count <= refresh_count + 1'b1;

            case (state)
                IDLE: if (!busy) begin
                    if (cpu_req)
                        launch(1'b0,cpu_wr,cpu_addr,cpu_wdata);
                    else if (loader_req)
                        launch(1'b1,1'b1,loader_addr,loader_wdata);
                    else if (enabled && refresh_count == REFRESH_CYCLES) begin
                        refresh <= 1'b1;
                        refresh_count <= 16'd0;
                        saw_busy <= 1'b0;
                        state <= ACTIVE_REFRESH;
                    end
                end
                ACTIVE_READ: if (data_ready) begin
                    cpu_rdata <= byte_lane ? dout[15:8] : dout[7:0];
                    cpu_ack <= 1'b1;
                    state <= WAIT_DROP;
                end
                ACTIVE_WRITE: begin
                    if (busy)
                        saw_busy <= 1'b1;
                    if (saw_busy && !busy) begin
                        if (owner_loader)
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
