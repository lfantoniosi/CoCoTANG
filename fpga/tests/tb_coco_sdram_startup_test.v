`timescale 1ns/1ps
module tb_coco_sdram_startup_test;
    reg clk=0,reset_n=0,start=0,mem_ack=0;
    reg [7:0] mem_rdata=0;
    wire mem_req,mem_wr,done,passed,failed;
    wire [22:0] mem_addr;
    wire [7:0] mem_wdata;
    wire [18:0] error_addr;
    wire [7:0] error_expected,error_actual;
    reg [7:0] memory [0:524287];
    integer errors=0,transactions=0;

    coco_sdram_startup_test dut(
        .clk(clk),.reset_n(reset_n),.start(start),.mem_req(mem_req),
        .mem_wr(mem_wr),.mem_addr(mem_addr),.mem_wdata(mem_wdata),
        .mem_rdata(mem_rdata),.mem_ack(mem_ack),.done(done),
        .passed(passed),.failed(failed),.error_addr(error_addr),
        .error_expected(error_expected),.error_actual(error_actual));
    always #5 clk=!clk;

    always @(posedge clk) begin
        mem_ack <= mem_req && !mem_ack;
        if (mem_req && !mem_ack) begin
            transactions <= transactions+1;
            if (mem_wr) memory[mem_addr[18:0]] <= mem_wdata;
            else mem_rdata <= memory[mem_addr[18:0]];
        end
    end

    initial begin
        repeat(3) @(negedge clk);
        reset_n=1; start=1;
        wait(done); @(negedge clk);
        if (!passed || failed || transactions != 1048576) errors=errors+1;
        if (errors==0) $display("tb_coco_sdram_startup_test PASS");
        else $display("tb_coco_sdram_startup_test FAIL errors=%0d tx=%0d",errors,transactions);
        $finish;
    end
endmodule
