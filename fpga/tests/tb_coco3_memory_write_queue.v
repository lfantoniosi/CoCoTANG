`timescale 1ns/1ps

// Exercise the real memory front end and arbiter with a deliberately slow
// SDRAM response. A speculative read must not displace committed CPU writes.
module tb_coco3_memory_write_queue;
    reg clk=0, reset_n=0;
    reg cpu_address_valid=0, cpu_bus_valid=0, e_fall=0;
    reg cpu_mem_read=0, cpu_mem_write=0, cpu_mem_is_rom=0;
    reg [15:0] cpu_logical_addr=0;
    reg [22:0] cpu_mem_addr=0;
    reg [7:0] cpu_wdata=0;
    reg sd_busy=0, sd_data_ready=0;
    wire sd_rd, sd_wr, sd_refresh;
    wire [22:0] sd_addr;
    wire [15:0] sd_din;
    wire [1:0] sd_wdm;
    wire [7:0] cpu_rdata;
    wire cpu_data_oe, cpu_wait;
    integer delay_count=-1;
    integer write_count=0, read_count=0;
    integer reads_before_io;
    integer response_delay=30, stress_phase=0, stress_index;

    always #5 clk=~clk;

    coco3_memory dut(
        .clk(clk),.reset_n(reset_n),.loader_start(1'b0),
        .cpu_access_enable(1'b1),.cpu_bus_valid(cpu_bus_valid),
        .cpu_address_valid(cpu_address_valid),.e(1'b1),.q(1'b1),
        .e_fall(e_fall),.cpu_mem_read(cpu_mem_read),
        .cpu_mem_write(cpu_mem_write),.cpu_mem_is_rom(cpu_mem_is_rom),
        .cpu_logical_addr(cpu_logical_addr),
        .cpu_mem_addr(cpu_mem_addr),.cpu_wdata(cpu_wdata),
        .cpu_rdata(cpu_rdata),.cpu_data_oe(cpu_data_oe),.cpu_wait(cpu_wait),
        .video_req(1'b0),.video_addr(23'd0),.video_ack(),.video_rdata(),
        .loader_done(),.flash_vector_done(),.flash_vector_pass(),
        .flash_vector(),.sdram_test_done(),.sdram_test_pass(),
        .sdram_test_error_addr(),.sdram_test_expected(),
        .sdram_test_actual(),.rom_verify_done(),.rom_verify_pass(),
        .rom_verify_vector(),.mspi_cs(),.mspi_sclk(),.mspi_miso(1'b1),
        .mspi_mosi(),.sdram_enabled(1'b1),.sd_rd(sd_rd),.sd_wr(sd_wr),
        .sd_refresh(sd_refresh),.sd_addr(sd_addr),.sd_din(sd_din),
        .sd_wdm(sd_wdm),.sd_dout(16'h5aa5),.sd_dout32(32'h5aa55aa5),
        .sd_data_ready(sd_data_ready),.sd_busy(sd_busy));

    // SDRAM's command pulse is registered. Hold the first speculative read
    // long enough for two later CPU cycles to queue behind it.
    always @(negedge clk) begin
        if (reset_n && (sd_rd || sd_wr)) begin
            if (delay_count>=0)
                $fatal(1,"overlapping SDRAM commands");
            delay_count=response_delay;
            sd_busy=1;
            if (sd_rd) read_count=read_count+1;
            if (sd_wr) begin
                if (stress_phase==2) begin
                    if (sd_addr!==23'h001000 ||
                        sd_din!==16'haaaa || sd_wdm!==2'b10)
                        $fatal(1,"readback test write changed");
                end else if (stress_phase) begin
                    if (sd_addr!==(23'h4000+(write_count>>1)) ||
                        sd_din!=={2{8'h80+write_count[7:0]}} ||
                        sd_wdm!==(write_count[0] ? 2'b01 : 2'b10))
                        $fatal(1,"stress write %0d changed: %h %h %b",
                               write_count,sd_addr,sd_din,sd_wdm);
                end else case (write_count)
                    0: if (sd_addr!==23'h003f91 ||
                           sd_din!==16'h3636 || sd_wdm!==2'b10)
                           $fatal(1,"first committed write changed: %h %h %b",
                                  sd_addr,sd_din,sd_wdm);
                    1: if (sd_addr!==23'h003f92 ||
                           sd_din!==16'h5a5a || sd_wdm!==2'b01)
                           $fatal(1,"second committed write changed: %h %h %b",
                                  sd_addr,sd_din,sd_wdm);
                    default: $fatal(1,"unexpected third SDRAM write");
                endcase
                write_count=write_count+1;
            end
        end else if (delay_count>=0) begin
            if (delay_count==1) begin
                sd_data_ready=1;
                delay_count=0;
            end else if (delay_count==0) begin
                sd_data_ready=0;
                sd_busy=0;
                delay_count=-1;
            end else delay_count=delay_count-1;
        end
    end

    task bus_cycle;
        input [22:0] addr;
        input rd, wr, rom;
        input [7:0] data;
        input early_address;
        begin
            @(negedge clk);
            cpu_mem_addr=addr;
            cpu_logical_addr=(addr==23'h000090) ? 16'hff90 :
                             addr[15:0];
            cpu_mem_read=rd;
            cpu_mem_write=wr;
            cpu_mem_is_rom=rom;
            cpu_wdata=data;
            repeat (2) @(negedge clk);
            cpu_address_valid=early_address;
            @(negedge clk);
            cpu_address_valid=0;
            cpu_bus_valid=1;
            @(negedge clk);
            cpu_bus_valid=0;
            repeat (2) @(negedge clk);
            e_fall=1;
            @(negedge clk);
            e_fall=0;
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        reset_n=1;
        bus_cycle(23'h000100,1,0,0,8'h00,1);
        if (read_count==0 || !sd_busy)
            $fatal(1,"speculative read did not occupy SDRAM");
        bus_cycle(23'h007f22,0,1,0,8'h36,1);
        bus_cycle(23'h007f25,0,1,0,8'h5a,1);
        // These next cycles used to replace a shared pending entry. Neither
        // the external I/O nor the internal ROM cycle may erase RAM writes.
        bus_cycle(23'h000090,0,0,0,8'h00,1);
        bus_cycle(23'h007fef,1,0,1,8'h00,0);
        repeat (220) @(negedge clk);
        if (write_count!==2)
            $fatal(1,"committed writes lost: %0d observed",write_count);
        reads_before_io=read_count;
        bus_cycle(23'h000090,0,0,0,8'h00,1);
        repeat (80) @(negedge clk);
        if (read_count!=reads_before_io)
            $fatal(1,"I/O cycle launched an unnecessary SDRAM read");
        // Hold one read across nine CPU write cycles. This exceeds the old
        // shared pending slot and verifies that the write FIFO actually
        // retains a burst while SDRAM is busy.
        @(negedge clk); reset_n=0; sd_busy=0; sd_data_ready=0;
        delay_count=-1; write_count=0; read_count=0;
        response_delay=150; stress_phase=1;
        repeat (3) @(negedge clk);
        reset_n=1;
        bus_cycle(23'h001000,1,0,0,8'h00,1);
        for (stress_index=0; stress_index<9; stress_index=stress_index+1)
            bus_cycle(23'h008000+stress_index,0,1,0,
                      8'h80+stress_index[7:0],1);
        if (dut.write_count<9)
            $fatal(1,"nine committed writes were not queued");
        repeat (1800) @(negedge clk);
        if (write_count!==9)
            $fatal(1,"stress writes lost: %0d observed",write_count);
        // The speculative read started for a write cycle returns the old
        // value. It must not become a valid response after that write commits.
        @(negedge clk); reset_n=0; sd_busy=0; sd_data_ready=0;
        delay_count=-1; write_count=0; read_count=0;
        response_delay=70; stress_phase=2;
        repeat (3) @(negedge clk);
        reset_n=1;
        bus_cycle(23'h002000,0,1,0,8'haa,1);
        if (!dut.read_invalidated)
            $fatal(1,"write did not invalidate its speculative read");
        repeat (100) @(negedge clk);
        if (dut.response_valid)
            $fatal(1,"stale speculative read became a CPU response");
        $display("tb_coco3_memory_write_queue PASS");
        $finish;
    end
endmodule
