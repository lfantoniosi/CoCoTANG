`timescale 1ns/1ps
module tb_gime_video;
    reg clk=0, reset_n=0;
    reg [7:0] memory_data=0;
    reg memory_data_valid=0;
    wire video_read_request;
    wire [22:0] memory_addr;
    wire framebuffer_write;
    wire [15:0] framebuffer_write_addr;
    wire [5:0] framebuffer_write_data;
    wire [7:0] active_height;
    integer writes=0, errors=0, timeout=0;

    gime_video dut(
        .clk(clk),.reset_n(reset_n),.bit_plane(1'b1),.hres(3'b111),
        .cres(2'b10),.lines_per_row_code(3'd0),.lpf(2'b11),
        .screen_base(19'd0),.horizontal_offset(8'd0),
        .palettes({16{6'b111001}}),.border_color(6'b001100),
        .memory_data(memory_data),.memory_data_valid(memory_data_valid),
        .video_read_request(video_read_request),.memory_addr(memory_addr),
        .framebuffer_write(framebuffer_write),
        .framebuffer_write_addr(framebuffer_write_addr),
        .framebuffer_write_data(framebuffer_write_data),.active_height(active_height),
        .hs_n(),.fs_n(),.hblank(),.vblank(),.red(),.green(),.blue(),.border_rgb());
    always #5 clk=~clk;

    always @(posedge clk) begin
        memory_data_valid <= video_read_request;
        if (video_read_request)
            memory_data <= memory_addr[7:0];
        if (framebuffer_write) begin
            if (framebuffer_write_addr != writes[15:0]) begin
                $display("write address %0d, expected %0d",framebuffer_write_addr,writes);
                errors = errors+1;
            end
            writes = writes+1;
        end
    end

    initial begin
        repeat(3) @(posedge clk); reset_n=1;
        while (writes < 57600 && timeout < 1000000) begin
            @(posedge clk); timeout=timeout+1;
        end
        if (active_height != 225 || writes != 57600) errors=errors+1;
        if (errors==0) $display("tb_gime_video PASS");
        else $display("tb_gime_video FAIL: %0d writes=%0d",errors,writes);
        $finish;
    end
endmodule
