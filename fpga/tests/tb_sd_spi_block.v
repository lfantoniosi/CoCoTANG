`timescale 1ns/1ps
module tb_sd_spi_block;
    reg clk=0, reset_n=0;
    reg init=0, read_start=0, write_start=0;
    reg [31:0] sector=0;
    wire busy, done, error, data_valid;
    wire [8:0] data_addr;
    wire [7:0] data_out;
    wire [31:0] capacity_sectors;
    wire sd_sclk, sd_cs_n, sd_mosi;
    reg sd_miso=1;
    reg [7:0] memory [0:511];
    reg [7:0] received [0:511];
    integer i;

    always #5 clk=~clk;

    sd_spi_block #(.INIT_DIV(2),.DATA_DIV(2),.RESPONSE_TIMEOUT(64)) dut (
        .clk(clk),.reset_n(reset_n),.init(init),
        .read_start(read_start),.write_start(write_start),.sector(sector),
        .busy(busy),.done(done),.error(error),
        .data_valid(data_valid),.data_addr(data_addr),.data_out(data_out),
        .data_in(memory[data_addr]),.capacity_sectors(capacity_sectors),
        .sd_sclk(sd_sclk),.sd_cs_n(sd_cs_n),.sd_mosi(sd_mosi),.sd_miso(sd_miso));

    always @(posedge clk)
        if (data_valid)
            received[data_addr] <= data_out;

    task fail;
        input [8*80-1:0] message;
        begin $display("FAIL: %0s",message); $finish; end
    endtask

    task card_get_byte;
        output [7:0] value;
        integer bitno;
        begin
            for(bitno=7;bitno>=0;bitno=bitno-1) begin
                @(posedge sd_sclk);
                value[bitno]=sd_mosi;
            end
        end
    endtask

    task card_put_byte;
        input [7:0] value;
        integer bitno;
        begin
            for(bitno=7;bitno>=0;bitno=bitno-1) begin
                @(negedge sd_sclk);
                sd_miso=value[bitno];
            end
            // Let the host sample bit zero before the caller starts looking
            // for the next command byte.
            @(posedge sd_sclk);
        end
    endtask

    task expect_command;
        input [5:0] expected_cmd;
        input [31:0] expected_arg;
        reg [7:0] value;
        reg [31:0] actual_arg;
        integer n;
        begin
            card_get_byte(value);
            if (value !== {2'b01,expected_cmd}) begin
                $display("command expected %0d got %02x",expected_cmd,value);
                fail("wrong SPI command");
            end
            actual_arg=0;
            for(n=0;n<4;n=n+1) begin
                card_get_byte(value);
                actual_arg={actual_arg[23:0],value};
            end
            card_get_byte(value); // CRC
            if(actual_arg!==expected_arg) begin
                $display("CMD%0d argument expected %08x got %08x",
                         expected_cmd,expected_arg,actual_arg);
                fail("wrong SPI command argument");
            end
        end
    endtask

    initial begin : card_model
        reg [7:0] value;
        integer n;
        sd_miso=1;
        wait(reset_n);
        wait(!sd_cs_n);
        expect_command(0,32'd0);       card_put_byte(8'h01);
        expect_command(8,32'h000001aa);card_put_byte(8'h01);
        card_put_byte(8'h00); card_put_byte(8'h00);
        card_put_byte(8'h01); card_put_byte(8'haa);
        expect_command(55,32'd0);      card_put_byte(8'h01);
        expect_command(41,32'h40000000);card_put_byte(8'h01);
        expect_command(55,32'd0);      card_put_byte(8'h01);
        expect_command(41,32'h40000000);card_put_byte(8'h00);
        expect_command(58,32'd0);      card_put_byte(8'h00);
        card_put_byte(8'h40); card_put_byte(8'h00);
        card_put_byte(8'h00); card_put_byte(8'h00);

        wait(sd_cs_n); wait(!sd_cs_n);
        expect_command(17,32'd3); card_put_byte(8'h00);
        card_put_byte(8'hff); card_put_byte(8'hfe);
        for(n=0;n<512;n=n+1) card_put_byte(n[7:0]^8'ha5);
        card_put_byte(8'h12); card_put_byte(8'h34);

        wait(sd_cs_n); wait(!sd_cs_n);
        expect_command(24,32'd4); card_put_byte(8'h00);
        card_get_byte(value); // inter-command gap
        card_get_byte(value);
        if(value!==8'hfe) fail("missing single-block write token");
        for(n=0;n<512;n=n+1) begin
            card_get_byte(value);
            if(value!==memory[n]) begin
                $display("write byte %0d expected %02x got %02x",n,memory[n],value);
                fail("write payload mismatch");
            end
        end
        card_get_byte(value); card_get_byte(value); // dummy CRC
        card_put_byte(8'h05);
        card_put_byte(8'h00); card_put_byte(8'h00); card_put_byte(8'hff);
    end

    initial begin : host
        for(i=0;i<512;i=i+1) begin
            memory[i]=i[7:0]^8'h3c;
            received[i]=0;
        end
        repeat(4) @(posedge clk);
        reset_n=1;

        @(negedge clk); init=1;
        @(negedge clk); init=0;
        wait(busy); wait(!busy);
        if(error) fail("SD SPI initialization failed");

        sector=3;
        @(negedge clk); read_start=1;
        @(negedge clk); read_start=0;
        wait(done);
        if(error) fail("CMD17 read failed");
        for(i=0;i<512;i=i+1)
            if(received[i] !== (i[7:0]^8'ha5)) fail("read payload mismatch");

        sector=4;
        @(negedge clk); write_start=1;
        @(negedge clk); write_start=0;
        wait(done);
        if(error) fail("CMD24 write failed");
        $display("PASS: SD SPI initialization, CMD17 read and CMD24 write");
        $finish;
    end

    initial begin
        #10000000;
        fail("SD SPI test timeout");
    end
endmodule
