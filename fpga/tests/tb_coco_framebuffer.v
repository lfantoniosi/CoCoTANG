`timescale 1ns/1ps
module tb_coco_framebuffer;
    reg write_clk=0, read_clk=0, write_en=0;
    reg [15:0] write_addr=0,hdmi_addr=0,cvbs_addr=0;
    reg [5:0] write_data=0;
    wire [5:0] hdmi_data,cvbs_data;
    integer errors=0;
    coco_framebuffer dut(
        .write_clk(write_clk),.write_en(write_en),.write_addr(write_addr),
        .write_data(write_data),.read_clk(read_clk),.hdmi_addr(hdmi_addr),
        .hdmi_data(hdmi_data),.cvbs_addr(cvbs_addr),.cvbs_data(cvbs_data));
    always #5 write_clk=~write_clk;
    always #4 read_clk=~read_clk;

    task write_pixel;
        input [15:0] address;
        input [5:0] data;
        begin
            @(negedge write_clk); write_addr=address; write_data=data; write_en=1;
            @(negedge write_clk); write_en=0;
        end
    endtask

    initial begin
        write_pixel(16'd17,6'h15);
        write_pixel(16'd32770,6'h2a);
        hdmi_addr=16'd17; cvbs_addr=16'd32770;
        repeat(20) @(posedge read_clk);
        if (hdmi_data!=6'h15 || cvbs_data!=6'h2a) errors=errors+1;
        hdmi_addr=16'd32770; cvbs_addr=16'd17;
        repeat(20) @(posedge read_clk);
        if (hdmi_data!=6'h2a || cvbs_data!=6'h15) errors=errors+1;
        if (errors==0) $display("tb_coco_framebuffer PASS");
        else $display("tb_coco_framebuffer FAIL: %0d",errors);
        $finish;
    end
endmodule
