`timescale 1ns/1ps
module tb_gime_registers;
    reg clk=0, reset_n=0, e=0, e_fall=0, cpu_rw_n=1;
    reg [15:0] cpu_addr=0;
    reg [7:0] cpu_data=0;
    wire [7:0] core_rdata,vmode,vres,horizontal_offset;
    wire core_data_oe,cpu_mem_read,cpu_mem_write,cpu_mem_is_rom;
    wire [22:0] cpu_mem_addr;
    wire [2:0] sam_s;
    wire [5:0] border_color;
    wire [3:0] vertical_scroll;
    wire [15:0] video_offset;
    wire [95:0] palettes;
    integer errors=0;

    gime_registers dut(
        .clk(clk),.reset_n(reset_n),.e(e),.e_fall(e_fall),
        .cpu_addr(cpu_addr),.cpu_rw_n(cpu_rw_n),.cpu_data(cpu_data),
        .core_rdata(core_rdata),.core_data_oe(core_data_oe),.sam_s(sam_s),
        .cpu_mem_read(cpu_mem_read),.cpu_mem_write(cpu_mem_write),
        .cpu_mem_is_rom(cpu_mem_is_rom),.cpu_mem_addr(cpu_mem_addr),
        .vmode(vmode),.vres(vres),.border_color(border_color),
        .vertical_scroll(vertical_scroll),.video_offset(video_offset),
        .horizontal_offset(horizontal_offset),.palettes(palettes));
    always #5 clk=~clk;

    task write_reg;
        input [15:0] address;
        input [7:0] value;
        begin
            cpu_addr=address; cpu_data=value; cpu_rw_n=0; e_fall=1;
            @(posedge clk); #1; e_fall=0; cpu_rw_n=1;
        end
    endtask

    initial begin
        repeat(3) @(posedge clk); reset_n=1; @(posedge clk); #1;
        cpu_addr=16'h1234; cpu_rw_n=1; #1;
        if (!cpu_mem_read || cpu_mem_is_rom || cpu_mem_addr != 23'h071234) errors=errors+1;
        cpu_addr=16'h8000; #1;
        if (!cpu_mem_read || !cpu_mem_is_rom || cpu_mem_addr != 0) errors=errors+1;
        cpu_addr=16'hffef; #1;
        if (!cpu_mem_read || !cpu_mem_is_rom || cpu_mem_addr != 23'h007fef) errors=errors+1;
        cpu_addr=16'hff00; #1;
        if (cpu_mem_read || sam_s != 4) errors=errors+1;

        write_reg(16'hff98,8'h87);
        write_reg(16'hff99,8'h6e);
        write_reg(16'hff9a,8'h2a);
        write_reg(16'hff9d,8'h12);
        write_reg(16'hff9e,8'h34);
        if (vmode!=8'h87 || vres!=8'h6e || border_color!=6'h2a || video_offset!=16'h1234)
            errors=errors+1;
        cpu_addr=16'hff98; cpu_rw_n=1; e=1; #1;
        if (!core_data_oe || core_rdata!=8'h87 || cpu_mem_read) errors=errors+1;
        e=0;

        write_reg(16'hffa0,8'h05);
        write_reg(16'hff90,8'h40);
        cpu_addr=16'h0123; cpu_rw_n=1; #1;
        if (cpu_mem_addr != 23'h00a123) errors=errors+1;

        if (errors==0) $display("tb_gime_registers PASS");
        else $display("tb_gime_registers FAIL: %0d",errors);
        $finish;
    end
endmodule
