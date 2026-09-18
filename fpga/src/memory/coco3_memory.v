// CoCo 3 physical-CPU memory service.  The GIME supplies the translated
// 19-bit RAM address. The internal 32 KiB ROM is loaded from SPI flash into
// dedicated dual-port BSRAM; CPU RAM and scanline traffic alone share SDRAM
// in alternating CPU and early-E-low background slots.
module coco3_memory #(
    parameter integer ROM_BYTES = 32768
) (
    input clk, input reset_n, input loader_start,
    input cpu_access_enable, input cpu_bus_valid, input cpu_address_valid,
    input e, input q, input e_fall,
    input cpu_mem_read, input cpu_mem_write, input cpu_mem_is_rom,
    input [22:0] cpu_mem_addr, input [7:0] cpu_wdata,
    output [7:0] cpu_rdata, output cpu_data_oe, output cpu_wait,

    input video_req, input [22:0] video_addr,
    output video_ack, output [31:0] video_rdata,
    output loader_done,
    output flash_vector_done, output flash_vector_pass,
    output [15:0] flash_vector,
    output sdram_test_done, output sdram_test_pass,
    output [15:0] sdram_test_error_addr,
    output [7:0] sdram_test_expected, output [7:0] sdram_test_actual,
    output reg rom_verify_done, output reg rom_verify_pass,
    output reg [15:0] rom_verify_vector,

    output mspi_cs, output mspi_sclk, input mspi_miso, output mspi_mosi,
    input sdram_enabled,
    output sd_rd, output sd_wr, output sd_refresh,
    output [22:0] sd_addr, output [15:0] sd_din, output [1:0] sd_wdm,
    input [15:0] sd_dout, input [31:0] sd_dout32,
    input sd_data_ready, input sd_busy
);
    wire [22:0] selected_addr = cpu_mem_addr;

    // Decode/address are available before the atomic mux snapshot pulse.
    // Pipeline them continuously, then freeze one complete transaction for
    // the remainder of the external CPU cycle.
    reg [22:0] selected_addr_pipe=0,cycle_addr=0;
    reg pipe_read=0,pipe_write=0,cycle_read=0,cycle_write=0;
    reg pipe_rom=0,cycle_rom=0;
    reg cycle_snapshot_seen=0;
    reg cpu_req=0,cpu_wr=0;
    reg [22:0] request_addr=0;
    reg [7:0] request_wdata=0;
    wire cpu_ack;
    wire [7:0] cpu_read_value;
    reg [7:0] response_data=8'hff;
    reg [22:0] response_addr=23'h7fffff;
    reg response_valid=0;
    reg pending_valid=0,pending_wr=0;
    reg [22:0] pending_addr=0;
    reg [7:0] pending_wdata=0;
    reg [2:0] read_hold=0;

    wire snapshot_response_ready = pipe_read &&
        ((pipe_rom && rom_read_addr_tag == selected_addr_pipe[14:0]) ||
         (response_valid && response_addr == selected_addr_pipe) ||
         (cpu_ack && !cpu_wr && request_addr == selected_addr_pipe));
    wire current_read_ready = cycle_snapshot_seen && cycle_read &&
        ((cycle_rom && rom_read_addr_tag == cycle_addr[14:0]) ||
         (response_valid && response_addr == cycle_addr));
    wire selected_read_in_flight =
        (cpu_req && !cpu_wr && request_addr == selected_addr_pipe) ||
        (pending_valid && !pending_wr &&
         pending_addr == selected_addr_pipe);

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            selected_addr_pipe<=0; pipe_read<=0; pipe_write<=0;
            cycle_addr<=0; cycle_read<=0; cycle_write<=0;
            pipe_rom<=0; cycle_rom<=0;
            cycle_snapshot_seen<=0; cpu_req<=0; cpu_wr<=0;
            request_addr<=0; request_wdata<=0;
            response_data<=8'hff; response_addr<=23'h7fffff;
            response_valid<=0;
            pending_valid<=0; pending_wr<=0;
            pending_addr<=0; pending_wdata<=0; read_hold<=0;
        end else if (!cpu_access_enable) begin
            cpu_req<=0; response_valid<=0;
            cycle_read<=0; cycle_write<=0;
            cycle_rom<=0;
            cycle_snapshot_seen<=0; pending_valid<=0; read_hold<=0;
        end else begin
            selected_addr_pipe<=selected_addr;
            pipe_read<=cpu_mem_read;
            pipe_write<=cpu_mem_write;
            pipe_rom<=cpu_mem_is_rom;
            if (read_hold != 0) read_hold<=read_hold-1'b1;

            if (cpu_ack) begin
                cpu_req<=0;
                if (!cpu_wr) begin
                    response_data<=cpu_read_value;
                    response_addr<=request_addr;
                    response_valid<=1;
                end
            end
            if (pending_valid && !cpu_req) begin
                cpu_wr<=pending_wr; request_addr<=pending_addr;
                request_wdata<=pending_wdata; cpu_req<=1;
                pending_valid<=0;
            end
            // The high address bank is trustworthy well before the control
            // bank has completed its scan.  Speculatively fetch that byte;
            // reads then have the full remainder of Q-low/Q-high to settle,
            // while writes and I/O cycles merely discard the harmless read.
            if (cpu_address_valid && !pipe_rom &&
                !selected_read_in_flight) begin
                if (!cpu_req) begin
                    cpu_wr<=0; request_addr<=selected_addr_pipe;
                    request_wdata<=0; cpu_req<=1;
                end else begin
                    pending_wr<=0; pending_addr<=selected_addr_pipe;
                    pending_wdata<=0; pending_valid<=1;
                end
            end
            if (cpu_bus_valid) begin
                cycle_snapshot_seen<=1;
                cycle_addr<=selected_addr_pipe;
                cycle_read<=pipe_read; cycle_write<=pipe_write;
                cycle_rom<=pipe_rom;
                if (pipe_read) begin
                    if (pipe_rom) begin
                        // Internal ROM is already available from BSRAM; leave
                        // any unrelated SDRAM response alone.
                    end else if (snapshot_response_ready) begin
                        response_valid<=1;
                        if (pending_valid && !pending_wr &&
                            pending_addr == selected_addr_pipe)
                            pending_valid<=0;
                    end else if (!selected_read_in_flight) begin
                        response_valid<=0; pending_wr<=0;
                        pending_addr<=selected_addr_pipe;
                        pending_wdata<=0; pending_valid<=1;
                    end else response_valid<=0;
                end else response_valid<=0;
            end
            if (cycle_snapshot_seen && cycle_read && !cycle_rom &&
                !current_read_ready &&
                !cpu_req && !pending_valid) begin
                pending_wr<=0; pending_addr<=cycle_addr;
                pending_wdata<=0; pending_valid<=1;
            end
            if (e_fall) begin
                cycle_snapshot_seen<=0;
                if (cycle_read && ((cycle_rom &&
                    rom_read_addr_tag==cycle_addr[14:0]) ||
                    (response_valid && response_addr==cycle_addr)))
                    read_hold<=3'd4;
                if (cycle_write) begin
                    pending_wr<=1; pending_addr<=cycle_addr;
                    pending_wdata<=cpu_wdata; pending_valid<=1;
                end
            end
        end
    end

    // Keep ROM data tied to its synchronous BSRAM address tag instead of
    // freezing an untagged sample at the mux snapshot. This is important for
    // interrupt vectors, whose reads immediately follow a burst of stack
    // writes to unrelated RAM addresses.
    assign cpu_rdata=cycle_rom ? rom_read_data : response_data;
    // Once the control-bank snapshot arrives, drive the CPU bus from the
    // frozen transaction tag.  Re-decoding the live address through the GIME
    // ROM/MMU mapping here put INIT0 and the complete translated-address
    // comparator on the physical DQ output-enable path.  current_read_ready
    // is equivalent for the active cycle and is entirely register based.
    assign cpu_data_oe=cpu_access_enable &&
                       (current_read_ready || read_hold!=0);
    assign cpu_wait=cpu_access_enable && cycle_read && !current_read_ready;

    // A fast CoCo 3 cycle still has a complete E-low/Q-low quadrant.  Open a
    // bounded eight-clock window at its leading edge for one 32-bit scanline
    // fetch or refresh, matching the real GIME's interleaved DMA behavior.
    reg [3:0] video_slot_count=0,refresh_slot_count=0;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            video_slot_count<=0; refresh_slot_count<=0;
        end else begin
            if (e_fall) begin
                video_slot_count<=4'd8;
                refresh_slot_count<=4'd8;
            end else begin
                if (video_slot_count!=0) video_slot_count<=video_slot_count-1'b1;
                if (refresh_slot_count!=0) refresh_slot_count<=refresh_slot_count-1'b1;
            end
        end
    end

    wire test_req,test_wr,test_ack,test_failed;
    wire [22:0] test_addr;
    wire [7:0] test_wdata;
    wire loader_ack;
    wire [7:0] loader_rdata;
    coco_sdram_startup_test startup_test(
        .clk(clk),.reset_n(reset_n),.start(loader_start),
        .mem_req(test_req),.mem_wr(test_wr),.mem_addr(test_addr),
        .mem_wdata(test_wdata),.mem_rdata(loader_rdata),.mem_ack(test_ack),
        .done(sdram_test_done),.passed(sdram_test_pass),.failed(test_failed),
        .error_addr(sdram_test_error_addr),
        .error_expected(sdram_test_expected),.error_actual(sdram_test_actual));

    wire flash_loader_req,flash_loader_ack,raw_loader_done;
    wire flash_tail_valid;
    wire [15:0] flash_tail_vector;
    wire [22:0] flash_loader_addr;
    wire [7:0] flash_loader_wdata;
    coco_flash_loader #(.SDRAM_ADDRESS(23'd0),.BYTE_COUNT(ROM_BYTES)) loader(
        .clk(clk),.reset_n(reset_n),.start(sdram_test_pass),.done(raw_loader_done),
        .tail_vector_valid(flash_tail_valid),.tail_vector(flash_tail_vector),
        .mem_req(flash_loader_req),.mem_addr(flash_loader_addr),
        .mem_wdata(flash_loader_wdata),.mem_ack(flash_loader_ack),
        .mspi_cs(mspi_cs),.mspi_sclk(mspi_sclk),
        .mspi_miso(mspi_miso),.mspi_mosi(mspi_mosi));
    assign flash_vector_done=flash_tail_valid;
    assign flash_vector=flash_tail_vector;
    assign flash_vector_pass=flash_tail_valid && flash_tail_vector==16'h8c1b;

    // Dedicated internal CoCo 3 ROM. Port A is written once by the SPI flash
    // loader; port B continuously follows the CPU ROM address after startup.
    // During verification, port B is temporarily directed at FFFE/FFFF.
    (* syn_ramstyle = "block_ram" *) reg [7:0] rom_memory [0:ROM_BYTES-1];
    reg [7:0] rom_read_data=8'hff;
    reg [14:0] rom_read_addr_tag=15'h7fff;
    reg [14:0] verify_rom_addr=15'd0;
    wire [14:0] rom_read_addr =
        (raw_loader_done && !rom_verify_done) ? verify_rom_addr :
                                               cpu_mem_addr[14:0];
    wire rom_loader_write = sdram_test_pass && !raw_loader_done &&
                            flash_loader_req;
    always @(posedge clk) begin
        if (rom_loader_write)
            rom_memory[flash_loader_addr[14:0]] <= flash_loader_wdata;
        rom_read_data <= rom_memory[rom_read_addr];
        rom_read_addr_tag <= rom_read_addr;
    end
    // The loader holds mem_req until it sees mem_ack. The BSRAM write occurs
    // on the same rising edge at which this combinational acknowledge is
    // observed, so every flash byte produces exactly one write.
    assign flash_loader_ack=rom_loader_write;

    // Read the reset vector back from BSRAM before releasing the CPU. Two
    // prime states account for the synchronous BSRAM read-port latency.
    localparam VERIFY_WAIT=3'd0,VERIFY_HIGH_PRIME=3'd1,
               VERIFY_HIGH_CAPTURE=3'd2,VERIFY_LOW_PRIME=3'd3,
               VERIFY_LOW_CAPTURE=3'd4,VERIFY_DONE=3'd5;
    reg [2:0] verify_state=VERIFY_WAIT;
    reg verify_high_pass=1'b0;
    wire loader_req=!sdram_test_done && test_req;
    wire loader_wr=test_wr;
    wire [22:0] loader_addr=test_addr;
    wire [7:0] loader_wdata=test_wdata;
    assign test_ack=!sdram_test_done && loader_ack;
    assign loader_done=rom_verify_done;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            verify_state<=VERIFY_WAIT; verify_rom_addr<=15'd0;
            verify_high_pass<=1'b0;
            rom_verify_done<=1'b0; rom_verify_pass<=1'b0;
            rom_verify_vector<=16'hffff;
        end else begin
            case (verify_state)
                VERIFY_WAIT: if (raw_loader_done) begin
                    verify_rom_addr<=ROM_BYTES-2;
                    verify_state<=VERIFY_HIGH_PRIME;
                end
                VERIFY_HIGH_PRIME:
                    verify_state<=VERIFY_HIGH_CAPTURE;
                VERIFY_HIGH_CAPTURE: begin
                    rom_verify_vector[15:8]<=rom_read_data;
                    verify_high_pass<=rom_read_data==8'h8c;
                    verify_rom_addr<=ROM_BYTES-1;
                    verify_state<=VERIFY_LOW_PRIME;
                end
                VERIFY_LOW_PRIME:
                    verify_state<=VERIFY_LOW_CAPTURE;
                VERIFY_LOW_CAPTURE: begin
                    rom_verify_vector[7:0]<=rom_read_data;
                    rom_verify_pass<=verify_high_pass && rom_read_data==8'h1b;
                    rom_verify_done<=1'b1;
                    verify_state<=VERIFY_DONE;
                end
                default: begin end
            endcase
        end
    end

    cpu_sdram_arbiter arbiter(
        .clk(clk),.reset_n(reset_n),.e(e),.q(q),
        .cpu_req(cpu_req),.cpu_wr(cpu_wr),.cpu_addr(request_addr),
        .cpu_wdata(request_wdata),.cpu_ack(cpu_ack),.cpu_rdata(cpu_read_value),
        .video_req(video_req),.video_addr(video_addr),
        .video_slot_open(video_slot_count!=0),
        .refresh_slot_open(refresh_slot_count!=0),
        .video_ack(video_ack),.video_rdata(video_rdata),
        .loader_req(loader_req),.loader_wr(loader_wr),.loader_addr(loader_addr),
        .loader_wdata(loader_wdata),.loader_ack(loader_ack),
        .loader_rdata(loader_rdata),
        .rd(sd_rd),.wr(sd_wr),.refresh(sd_refresh),.addr(sd_addr),
        .din(sd_din),.wdm(sd_wdm),.dout(sd_dout),.dout32(sd_dout32),
        .data_ready(sd_data_ready),.busy(sd_busy),.enabled(sdram_enabled));
endmodule
