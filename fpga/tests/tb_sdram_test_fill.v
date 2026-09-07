`timescale 1ns/1ps
module tb_sdram_test_fill;
    reg clk = 1'b0;
    reg reset_n = 1'b0;
    reg start = 1'b0;
    reg mem_ack = 1'b0;
    wire done, mem_req;
    wire [22:0] mem_addr;
    wire [7:0] mem_wdata;
    integer writes = 0;
    integer errors = 0;

    sdram_test_fill dut(.clk(clk),.reset_n(reset_n),.start(start),.done(done),
        .mem_req(mem_req),.mem_addr(mem_addr),.mem_wdata(mem_wdata),.mem_ack(mem_ack));
    always #5 clk = !clk;

    always @(posedge clk) begin
        mem_ack <= mem_req && !mem_ack;
        if (mem_ack) begin
            if (mem_addr != writes || mem_wdata != writes[7:0])
                errors = errors + 1;
            writes = writes + 1;
        end
    end

    initial begin
        repeat (3) @(negedge clk);
        reset_n = 1'b1;
        start = 1'b1;
        wait(done);
        @(negedge clk);
        if (writes != 65536) errors = errors + 1;
        if (errors == 0) $display("tb_sdram_test_fill PASS");
        else $display("tb_sdram_test_fill FAIL: writes=%0d errors=%0d",writes,errors);
        $finish;
    end
endmodule
