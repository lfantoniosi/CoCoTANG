`timescale 1ns/1ps
module tb_gime_registers;
    reg clk=0, reset_n=0, e=0, e_fall=0, cpu_rw_n=1;
    reg [15:0] cpu_addr=0;
    reg [7:0] cpu_data=0;
    reg serint_n=1, keyint_n=1, cart_n=1, hs_n=1, fs_n=1;
    wire [7:0] core_rdata,vmode,vres,horizontal_offset;
    wire core_data_oe,cpu_mem_read,cpu_mem_write,cpu_mem_is_rom;
    wire [22:0] cpu_mem_addr;
    wire [2:0] sam_s;
    wire [5:0] border_color;
    wire [3:0] vertical_scroll;
    wire [15:0] video_offset;
    wire [95:0] palettes;
    wire irq_assert,firq_assert,fast_mode;
    wire compatibility_mode;
    wire [6:0] sam_video_offset;
    integer errors=0;

    gime_registers dut(
        .clk(clk),.reset_n(reset_n),.e(e),.e_fall(e_fall),
        .cpu_addr(cpu_addr),.cpu_rw_n(cpu_rw_n),.cpu_data(cpu_data),
        .serint_n(serint_n),.keyint_n(keyint_n),.cart_n(cart_n),
        .hs_n(hs_n),.fs_n(fs_n),.irq_assert(irq_assert),
        .firq_assert(firq_assert),.fast_mode(fast_mode),
        .core_rdata(core_rdata),.core_data_oe(core_data_oe),.sam_s(sam_s),
        .cpu_mem_read(cpu_mem_read),.cpu_mem_write(cpu_mem_write),
        .cpu_mem_is_rom(cpu_mem_is_rom),.cpu_mem_addr(cpu_mem_addr),
        .vmode(vmode),.vres(vres),.border_color(border_color),
        .vertical_scroll(vertical_scroll),.video_offset(video_offset),
        .horizontal_offset(horizontal_offset),.compatibility_mode(compatibility_mode),
        .sam_video_offset(sam_video_offset),.palettes(palettes));
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
        if (!cpu_mem_read || !cpu_mem_is_rom || cpu_mem_addr != 0 || sam_s!=0)
            errors=errors+1;
        cpu_addr=16'ha000; #1;
        if (!cpu_mem_read || !cpu_mem_is_rom || sam_s!=0) errors=errors+1;
        cpu_addr=16'hc03c; #1;
        if (cpu_mem_read || cpu_mem_is_rom || sam_s!=3) errors=errors+1;
        cpu_addr=16'hffef; #1;
        if (!cpu_mem_read || !cpu_mem_is_rom || cpu_mem_addr != 23'h007fef || sam_s!=0)
            errors=errors+1;
        cpu_addr=16'hff00; #1;
        if (cpu_mem_read || sam_s != 4) errors=errors+1;
        cpu_addr=16'hff20; #1; if(sam_s!=5) errors=errors+1;
        cpu_addr=16'hff40; #1; if(sam_s!=6) errors=errors+1;
        cpu_addr=16'hff60; #1; if(sam_s!=7) errors=errors+1;

        // The reset stub selects MC=10 before jumping to C000.  That is the
        // upper half of the FPGA's internal 32K image, not EXTROM/cartridge.
        write_reg(16'hff90,8'h0a);
        cpu_addr=16'hc03c; cpu_rw_n=1; #1;
        if (!cpu_mem_read || !cpu_mem_is_rom || cpu_mem_addr!=23'h00403c || sam_s!=0)
            errors=errors+1;

        // MC=11 releases ordinary ROM addresses externally but always keeps
        // the hardware vectors on the internal image.
        write_reg(16'hff90,8'h03);
        cpu_addr=16'h8000; #1;
        if (cpu_mem_read || cpu_mem_is_rom || sam_s!=3) errors=errors+1;
        cpu_addr=16'hfffe; #1;
        if (!cpu_mem_read || !cpu_mem_is_rom || cpu_mem_addr!=23'h007ffe || sam_s!=0)
            errors=errors+1;

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

        // CoCo-compatible mode disables MMU translation, retains the SAM
        // display offset, and supports the legacy ROM/all-RAM toggle.
        write_reg(16'hff90,8'hc0);
        cpu_addr=16'h0123; #1;
        if (!compatibility_mode || cpu_mem_addr != 23'h070123) errors=errors+1;
        // Legacy SAM P1 is not implemented by the CoCo 3 GIME.  Extended
        // BASIC writes FFD5 during startup and the logical RAM mapping must
        // remain unchanged.
        cpu_addr=16'h4123; #1;
        if (cpu_mem_addr != 23'h074123) errors=errors+1;
        write_reg(16'hffd5,8'h00);
        cpu_addr=16'h4123; #1;
        if (cpu_mem_addr != 23'h074123) errors=errors+1;
        write_reg(16'hffd4,8'h00);
        cpu_addr=16'hc123; #1;
        if (cpu_mem_addr != 23'h07c123) errors=errors+1;
        write_reg(16'hffc9,8'h00);
        if (sam_video_offset != 7'd2) errors=errors+1;
        write_reg(16'hffdf,8'h00);
        cpu_addr=16'h8000; cpu_rw_n=0; #1;
        if (cpu_mem_is_rom || !cpu_mem_write || cpu_mem_addr!=23'h078000 || sam_s!=0)
            errors=errors+1;
        cpu_addr=16'hc03c; cpu_rw_n=1; #1;
        if (cpu_mem_is_rom || !cpu_mem_read || cpu_mem_addr!=23'h07c03c || sam_s!=0)
            errors=errors+1;
        // TY/all-RAM never displaces the internal hardware vectors.
        cpu_addr=16'hfff8; cpu_rw_n=1; #1;
        if (!cpu_mem_read || !cpu_mem_is_rom ||
            cpu_mem_addr!=23'h007ff8 || sam_s!=0)
            errors=errors+1;
        write_reg(16'hffde,8'h00);
        cpu_addr=16'h8000; cpu_rw_n=1; #1;
        if (!cpu_mem_is_rom) errors=errors+1;

        // Native CoCo 3 starts fast and retains the standard speed POKEs.
        if (!fast_mode) errors=errors+1;
        write_reg(16'hffd8,8'h00); if (fast_mode) errors=errors+1;
        write_reg(16'hffd9,8'h00); if (!fast_mode) errors=errors+1;

        // Enable GIME IRQ plus keyboard source, latch its falling edge, then
        // acknowledge it by reading FF92 at E falling.
        write_reg(16'hff92,8'h02);
        write_reg(16'hff90,8'h20);
        keyint_n=0; @(posedge clk); #1;
        if (!irq_assert) errors=errors+1;
        cpu_addr=16'hff92; cpu_rw_n=1; e=1; #1;
        if (core_rdata[1] != 1'b1) errors=errors+1;
        e_fall=1; @(posedge clk); #1; e_fall=0;
        if (irq_assert) errors=errors+1;

        if (errors==0) $display("tb_gime_registers PASS");
        else $display("tb_gime_registers FAIL: %0d",errors);
        $finish;
    end
endmodule
