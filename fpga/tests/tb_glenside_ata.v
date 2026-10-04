`timescale 1ns/1ps
module tb_glenside_ata;
    reg clk=0,reset_n=0,cpu_enable=1,e_fall=0,cpu_rw_n=1;
    reg [15:0] cpu_addr=16'h0000;
    reg [7:0] cpu_wdata=0;
    wire [7:0] cpu_rdata;
    wire cpu_data_oe;
    wire sd_init,sd_read_start,sd_write_start;
    wire [31:0] sd_sector;
    reg sd_busy=0,sd_done=0,sd_error=0,sd_data_valid=0;
    reg [8:0] sd_data_addr=0;
    reg [7:0] sd_data_in=0;
    wire [7:0] sd_data_out;
    integer i;
    reg [7:0] value;
    reg slow_reset_n=0;
    wire [7:0] slow_status;

    always #5 clk=~clk;

    glenside_ata #(.INIT_TIMEOUT_CYCLES(1000)) dut(
        .clk(clk),.reset_n(reset_n),.cpu_enable(cpu_enable),.e_fall(e_fall),
        .cpu_addr(cpu_addr),.cpu_rw_n(cpu_rw_n),.cpu_wdata(cpu_wdata),
        .cpu_rdata(cpu_rdata),.cpu_data_oe(cpu_data_oe),
        .sd_init(sd_init),.sd_read_start(sd_read_start),
        .sd_write_start(sd_write_start),.sd_sector(sd_sector),
        .sd_busy(sd_busy),.sd_done(sd_done),.sd_error(sd_error),
        .sd_data_valid(sd_data_valid),.sd_data_addr(sd_data_addr),
        .sd_data_in(sd_data_in),.sd_data_out(sd_data_out),
        .capacity_sectors(32'h01234567));

    // Exercise the prescaled hardware path as well as the short, exact
    // cycle-by-cycle timeout used by the primary DUT.
    glenside_ata #(.INIT_TIMEOUT_CYCLES(108000)) slow_timeout_dut(
        .clk(clk),.reset_n(slow_reset_n),.cpu_enable(1'b1),.e_fall(1'b0),
        .cpu_addr(16'hff57),.cpu_rw_n(1'b1),.cpu_wdata(8'd0),
        .cpu_rdata(slow_status),.cpu_data_oe(),
        .sd_init(),.sd_read_start(),.sd_write_start(),.sd_sector(),
        .sd_busy(1'b0),.sd_done(1'b0),.sd_error(1'b0),
        .sd_data_valid(1'b0),.sd_data_addr(9'd0),.sd_data_in(8'd0),
        .sd_data_out(),.capacity_sectors(32'd0));

    task fail;
        input [8*96-1:0] message;
        begin $display("FAIL: %0s",message); $finish; end
    endtask

    task write_reg;
        input [3:0] regno;
        input [7:0] data;
        begin
            @(negedge clk); cpu_addr=16'hff50+regno; cpu_rw_n=0;
            cpu_wdata=data; e_fall=1;
            @(negedge clk); e_fall=0; cpu_rw_n=1;
        end
    endtask

    task read_reg;
        input [3:0] regno;
        output [7:0] data;
        begin
            @(negedge clk); cpu_addr=16'hff50+regno; cpu_rw_n=1; e_fall=1;
            #1 data=cpu_rdata;
            @(negedge clk); e_fall=0;
        end
    endtask

    task finish_sd_operation;
        begin
            @(negedge clk); sd_busy=1;
            repeat(3) @(posedge clk);
            @(negedge clk); sd_done=1; sd_busy=0;
            @(posedge clk);
            @(negedge clk); sd_done=0;
        end
    endtask

    initial begin
        repeat(3) @(posedge clk);
        reset_n=1;
        wait(sd_init);
        @(negedge clk); sd_busy=1;
        repeat(4) @(posedge clk);
        @(negedge clk); sd_busy=0;
        repeat(3) @(posedge clk);

        cpu_addr=16'hfe50; #1;
        if(cpu_data_oe) fail("adapter selected outside configured FF50 page");
        cpu_addr=16'hff5f; #1;
        if(!cpu_data_oe) fail("adapter did not own configured 16-byte page");
        read_reg(4'h7,value);
        if(value!==8'h50) fail("ready status after SD initialization");

        // HDB-DOS HDINIT requires EXECUTE DEVICE DIAGNOSTIC to finish ready
        // and return diagnostic code $01 in the error register.
        write_reg(4'h7,8'h90);
        repeat(3) @(posedge clk);
        read_reg(4'h7,value);
        if(value!==8'h50) fail("EXECUTE DIAGNOSTIC ready status");
        read_reg(4'h1,value);
        if(value!==8'h01) fail("EXECUTE DIAGNOSTIC device-0 pass code");

        // Private buffer diagnostic fills the existing sector DPB without
        // involving the SD reader.  Every byte must equal its byte offset.
        write_reg(4'h7,8'he2);
        repeat(260) @(posedge clk);
        read_reg(4'h7,value);
        if(value!==8'h58) fail("BUFFER TEST did not assert DRQ");
        for(i=0;i<256;i=i+1) begin
            read_reg(4'h0,value);
            if(value!==((i*2)&255)) begin
                $display("BUFFER TEST word %0d low expected %02x got %02x",i,(i*2)&255,value);
                fail("BUFFER TEST low byte");
            end
            read_reg(4'h8,value);
            if(value!==((i*2+1)&255)) begin
                $display("BUFFER TEST word %0d high expected %02x got %02x",i,(i*2+1)&255,value);
                fail("BUFFER TEST high byte");
            end
        end

        // LBA28 read, one sector.
        write_reg(4'h2,8'h01);
        write_reg(4'h3,8'h67);
        write_reg(4'h4,8'h45);
        write_reg(4'h5,8'h23);
        write_reg(4'h6,8'he1);
        write_reg(4'h7,8'h20);
        wait(sd_read_start);
        if(sd_sector!==32'h01234567) fail("READ SECTORS LBA assembly");
        @(negedge clk); sd_busy=1;
        for(i=0;i<512;i=i+1) begin
            @(negedge clk);
            sd_data_valid=1; sd_data_addr=i; sd_data_in=i[7:0]^8'ha5;
        end
        @(negedge clk); sd_data_valid=0; sd_busy=0; sd_done=1;
        @(posedge clk); @(negedge clk); sd_done=0;
        repeat(2) @(posedge clk);
        read_reg(4'h7,value);
        if(value!==8'h58) fail("READ did not assert DRQ");
        read_reg(4'h0,value);
        if(value!==8'ha5) fail("Glenside data register low byte order");
        read_reg(4'h8,value);
        if(value!==8'ha4) fail("Glenside read latch high byte order");
        for(i=1;i<256;i=i+1) begin
            read_reg(4'h0,value);
            read_reg(4'h8,value);
        end
        read_reg(4'h7,value);
        if(value!==8'h50) fail("READ did not clear DRQ after 512 bytes");

        // One-sector write.  High byte must be written to FF58 first.
        write_reg(4'h2,8'h01);
        write_reg(4'h3,8'h89);
        write_reg(4'h4,8'h67);
        write_reg(4'h5,8'h45);
        write_reg(4'h6,8'he3);
        write_reg(4'h7,8'h30);
        for(i=0;i<256;i=i+1) begin
            write_reg(4'h8,(i*2+1)^8'h3c);
            write_reg(4'h0,(i*2)^8'h3c);
        end
        wait(sd_write_start);
        if(sd_sector!==32'h03456789) fail("WRITE SECTORS LBA assembly");
        sd_data_addr=9'd0; @(posedge clk); #1;
        if(sd_data_out!==8'h3c) fail("write buffer low byte");
        sd_data_addr=9'd1; @(posedge clk); #1;
        if(sd_data_out!==8'h3d) fail("write buffer latched high byte");
        finish_sd_operation();
        repeat(2) @(posedge clk);
        read_reg(4'h7,value);
        if(value!==8'h50) fail("WRITE completion status");

        write_reg(4'h7,8'hec);
        repeat(520) @(posedge clk);
        read_reg(4'h7,value);
        if(value!==8'h58) fail("IDENTIFY did not assert DRQ");
        read_reg(4'h0,value);
        if(value!==8'h40) fail("IDENTIFY word 0 low byte");
        read_reg(4'h8,value);
        if(value!==8'h00) fail("IDENTIFY word 0 high byte");

        // With no SD busy transition, the one-tick prescaled timeout must
        // retain BSY until the interval elapses, then expose ATA ERR.
        @(negedge clk); slow_reset_n=1;
        repeat(107900) @(posedge clk);
        #1;
        if(slow_status!==8'h80) fail("prescaled init timeout ended early");
        repeat(200) @(posedge clk);
        #1;
        if(slow_status!==8'h51) fail("prescaled init timeout did not report ERR");

        $display("PASS: Glenside ATA task-file, latch ordering, LBA read/write, IDENTIFY and prescaled timeout");
        $finish;
    end
endmodule
