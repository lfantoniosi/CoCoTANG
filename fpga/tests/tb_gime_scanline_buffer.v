`timescale 1ns/1ps
module tb_gime_scanline_buffer;
    reg clk=0,read_clk=0,reset_n=0;
    reg [95:0] palettes=0;
    reg [31:0] memory_data=32'h1b1b1b1b;
    reg memory_valid=0;
    wire memory_request;
    wire [22:0] memory_addr;
    wire [5:0] pixel_data;
    integer transactions=0;
    integer errors=0;
    integer i;
    reg [1:0] responder_state=0;

    gime_scanline_buffer dut(
        .clk(clk),.reset_n(reset_n),.bit_plane(1'b1),.hres(3'd7),.cres(2'd1),
        .lines_per_row_code(3'd0),.screen_base(19'd0),.horizontal_offset(8'd0),
        .palettes(palettes),.read_clk(read_clk),.read_x(10'd0),
        .display_y(8'd0),.display_valid(1'b0),.prefetch_y(8'd0),
        .prefetch_valid(1'b1),.pixel_data(pixel_data),
        .memory_request(memory_request),.memory_addr(memory_addr),
        .memory_data(memory_data),.memory_valid(memory_valid));

    always #5 clk=~clk;
    always #18.5 read_clk=~read_clk;
    always @(posedge clk) begin
        memory_valid<=0;
        if (memory_request && responder_state==0) begin
            responder_state<=1;
            transactions<=transactions+1;
            if (memory_addr[1:0] != 0) begin
                $display("unaligned request %h",memory_addr); errors=errors+1;
            end
        end else if (responder_state==1) begin
            memory_valid<=1;
            responder_state<=2;
        end else if (responder_state==2 && !memory_request) begin
            responder_state<=0;
        end
    end

    function [5:0] mapped;
        input [5:0] c;
        begin mapped={c[5],c[2],c[4],c[1],c[3],c[0]}; end
    endfunction

    initial begin
        for (i=0;i<16;i=i+1) palettes[i*6 +: 6]=i;
        repeat(4) @(posedge clk); reset_n=1;
        while (!dut.tag0_valid && !dut.tag1_valid) @(posedge clk);
        if (transactions != 40) begin
            $display("transactions %0d expected 40",transactions); errors=errors+1;
        end
        for (i=0;i<640;i=i+1) begin
            if (dut.fill_bank ? dut.line1[i] !== mapped(i[1:0]) :
                                dut.line0[i] !== mapped(i[1:0])) begin
                $display("pixel %0d value %0h",i,dut.fill_bank ? dut.line1[i] : dut.line0[i]);
                errors=errors+1;
            end
        end
        if (errors==0) $display("tb_gime_scanline_buffer PASS");
        else $display("tb_gime_scanline_buffer FAIL: %0d",errors);
        $finish;
    end
endmodule
