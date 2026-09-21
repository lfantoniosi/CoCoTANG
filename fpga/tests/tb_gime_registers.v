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
    integer block;
    reg [22:0] expected_address;

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
        // MMUEN resets clear: native logical RAM initially uses the same
        // fixed upper-64K compatibility window.
        cpu_addr=16'h1234;cpu_rw_n=1;#1;
        if(cpu_mem_addr!=23'h071234)begin
            $display("MMU-disabled reset mapping got %h",cpu_mem_addr);errors=errors+1;end
        // Both tasks reset to the CoCo-compatible upper 64K mapping.  Verify
        // every 8K block, including the final byte at physical $7ffff.
        write_reg(16'hff90,8'h40);
        write_reg(16'hffdf,8'h00);
        for (block=0;block<8;block=block+1) begin
            cpu_addr={block[2:0],13'h0123};cpu_rw_n=1;#1;
            expected_address=23'h070000+block*23'h002000+23'h000123;
            if(cpu_mem_addr!=expected_address)begin
                $display("task 0 reset block %0d got %h expected %h",
                         block,cpu_mem_addr,expected_address);errors=errors+1;end
        end
        write_reg(16'hff91,8'h01);
        for (block=0;block<8;block=block+1) begin
            cpu_addr={block[2:0],13'h0123};cpu_rw_n=1;#1;
            expected_address=23'h070000+block*23'h002000+23'h000123;
            if(cpu_mem_addr!=expected_address)begin
                $display("task 1 reset block %0d got %h expected %h",
                         block,cpu_mem_addr,expected_address);errors=errors+1;end
        end
        cpu_addr=16'hdfff;cpu_rw_n=1;#1;
        if(cpu_mem_addr!=23'h07dfff)begin
            $display("task 1 upper RAM boundary got %h",cpu_mem_addr);errors=errors+1;end
        write_reg(16'hffde,8'h00);
        write_reg(16'hff91,8'h00);

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

        // Exercise all task registers with distinct pages and confirm that
        // reads and writes use the same translated physical address.
        for(block=0;block<8;block=block+1)begin
            write_reg(16'hffa0+block,8'h08+block);
            write_reg(16'hffa8+block,8'h20+block);
            cpu_addr=16'hffa0+block;cpu_rw_n=1;e=1;#1;
            if(core_rdata!={2'b00,6'h08+block})begin
                $display("task 0 register %0d read back %h",block,core_rdata);
                errors=errors+1;end
            cpu_addr=16'hffa8+block;#1;
            if(core_rdata!={2'b00,6'h20+block})begin
                $display("task 1 register %0d read back %h",block,core_rdata);
                errors=errors+1;end
            e=0;
        end
        write_reg(16'hffdf,8'h00);
        for(block=0;block<8;block=block+1)begin
            cpu_addr={block[2:0],13'h0555};cpu_rw_n=1;#1;
            expected_address=(23'h08+block)*23'h2000+23'h555;
            if(!cpu_mem_read||cpu_mem_addr!=expected_address)begin
                $display("task 0 read block %0d got %h expected %h",
                         block,cpu_mem_addr,expected_address);errors=errors+1;end
            cpu_rw_n=0;#1;
            if(!cpu_mem_write||cpu_mem_addr!=expected_address)begin
                $display("task 0 write block %0d got %h expected %h",
                         block,cpu_mem_addr,expected_address);errors=errors+1;end
        end
        write_reg(16'hff91,8'h01);
        for(block=0;block<8;block=block+1)begin
            cpu_addr={block[2:0],13'h0555};cpu_rw_n=1;#1;
            expected_address=(23'h20+block)*23'h2000+23'h555;
            if(!cpu_mem_read||cpu_mem_addr!=expected_address)begin
                $display("task 1 read block %0d got %h expected %h",
                         block,cpu_mem_addr,expected_address);errors=errors+1;end
            cpu_rw_n=0;#1;
            if(!cpu_mem_write||cpu_mem_addr!=expected_address)begin
                $display("task 1 write block %0d got %h expected %h",
                         block,cpu_mem_addr,expected_address);errors=errors+1;end
        end
        cpu_rw_n=1;

        // INIT0.MC3 fixes $FE00-$FEFF at physical $7FE00-$7FEFF.  With MC3
        // clear the same logical address follows block 7 of the active task;
        // with it set, task selection must no longer affect reads or writes.
        write_reg(16'hff91,8'h00);
        write_reg(16'hff90,8'h40);
        cpu_addr=16'hfea5;cpu_rw_n=1;#1;
        if(!cpu_mem_read||cpu_mem_is_rom||cpu_mem_addr!=23'h01fea5)begin
            $display("task 0 ordinary FE mapping got %h",cpu_mem_addr);
            errors=errors+1;end
        write_reg(16'hff91,8'h01);
        cpu_addr=16'hfea5;cpu_rw_n=1;#1;
        if(!cpu_mem_read||cpu_mem_is_rom||cpu_mem_addr!=23'h04fea5)begin
            $display("task 1 ordinary FE mapping got %h",cpu_mem_addr);
            errors=errors+1;end
        write_reg(16'hff90,8'h48);
        cpu_addr=16'hfea5;cpu_rw_n=1;#1;
        if(!cpu_mem_read||cpu_mem_is_rom||cpu_mem_addr!=23'h07fea5)begin
            $display("MC3 task 1 FE read got %h",cpu_mem_addr);
            errors=errors+1;end
        cpu_rw_n=0;#1;
        if(!cpu_mem_write||cpu_mem_is_rom||cpu_mem_addr!=23'h07fea5)begin
            $display("MC3 task 1 FE write got %h",cpu_mem_addr);
            errors=errors+1;end
        cpu_rw_n=1;
        write_reg(16'hff91,8'h00);
        cpu_addr=16'hfea5;cpu_rw_n=1;#1;
        if(!cpu_mem_read||cpu_mem_is_rom||cpu_mem_addr!=23'h07fea5)begin
            $display("MC3 task 0 FE read got %h",cpu_mem_addr);
            errors=errors+1;end

        // ROM is selected by an MMU page value, not by a fixed logical
        // $8000-$FEFF window. Expansion RAM mapped into logical block 4 must
        // therefore remain readable and writable in RAM/ROM mode.
        write_reg(16'hff91,8'h00);
        write_reg(16'hff90,8'h4a);
        write_reg(16'hffde,8'h00);
        write_reg(16'hffa4,8'h00);
        cpu_addr=16'h8123;cpu_rw_n=1;#1;
        if(!cpu_mem_read||cpu_mem_is_rom||cpu_mem_addr!=23'h000123)begin
            $display("RAM page at logical ROM window decoded incorrectly: %h",
                     cpu_mem_addr);errors=errors+1;end
        cpu_rw_n=0;#1;
        if(!cpu_mem_write||cpu_mem_is_rom||cpu_mem_addr!=23'h000123)
            errors=errors+1;

        // Any $3C-$3F MMU value denotes ROM in RAM/ROM mode. Its low two
        // bits come from the destination logical block; writes still target
        // the translated physical RAM page underneath the read overlay.
        write_reg(16'hffa0,8'h3f);
        cpu_addr=16'h0123;cpu_rw_n=1;#1;
        if(!cpu_mem_read||!cpu_mem_is_rom||cpu_mem_addr!=23'h000123)
            errors=errors+1;
        cpu_rw_n=0;#1;
        if(!cpu_mem_write||cpu_mem_is_rom||cpu_mem_addr!=23'h07e123)
            errors=errors+1;
        cpu_rw_n=1;
        write_reg(16'hffdf,8'h00);

        // Map page $3f into logical block zero so the last physical byte is
        // reachable without the GIME register/vector overlay at logical FFxx.
        write_reg(16'hffa8,8'h3f);
        cpu_addr=16'h1fff;cpu_rw_n=1;#1;
        if(cpu_mem_addr!=23'h07ffff)begin
            $display("512K top boundary got %h",cpu_mem_addr);errors=errors+1;end
        write_reg(16'hffde,8'h00);
        write_reg(16'hff91,8'h00);

        // COCO selects compatibility video but is independent of MMUEN.
        // With MMUEN clear, compatibility mode retains the fixed upper-64K
        // mapping, the SAM display offset, and the ROM/all-RAM toggle.
        write_reg(16'hff90,8'h80);
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

        // The 512K memory checker runs with compatibility video selected and
        // MMU translation enabled.  Page $25 must remain independently
        // addressable in that state; gating MMUEN with COCO used to turn this
        // access into physical $70000 and report 64K/128K duplication.
        write_reg(16'hffa4,8'h25);
        write_reg(16'hff90,8'hc0);
        cpu_addr=16'h8123; cpu_rw_n=1; #1;
        if (!compatibility_mode || !cpu_mem_read || cpu_mem_is_rom ||
            cpu_mem_addr != 23'h04a123) begin
            $display("compatibility-video MMU page 25 got %h",cpu_mem_addr);
            errors=errors+1;
        end
        cpu_rw_n=0; #1;
        if (!cpu_mem_write || cpu_mem_addr != 23'h04a123)
            errors=errors+1;
        cpu_rw_n=1;

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

        // In slow mode the programmable timer is clocked by HS itself.  It
        // must not drift against the HBORD source through a free-running
        // approximation of the line period.
        write_reg(16'hff95,8'h02);
        write_reg(16'hff94,8'h00);
        write_reg(16'hff92,8'h20);
        repeat(100) @(posedge clk);
        if (dut.timer_count!=12'd2 || dut.timer_divider!=13'd0 || irq_assert) begin
            $display("idle slow timer count=%0d divider=%0d irq=%b",
                     dut.timer_count,dut.timer_divider,irq_assert);
            errors=errors+1;
        end
        @(negedge clk); hs_n=0; @(posedge clk); #1;
        hs_n=1; @(posedge clk); #1;
        if (dut.timer_count!=12'd1 || irq_assert) begin
            $display("first HS timer count=%0d irq=%b",dut.timer_count,irq_assert);
            errors=errors+1;
        end
        @(negedge clk); hs_n=0; @(posedge clk); #1;
        hs_n=1; @(posedge clk); #1;
        if (dut.timer_count!=12'd2 || !irq_assert) begin
            $display("second HS timer count=%0d irq=%b",dut.timer_count,irq_assert);
            errors=errors+1;
        end

        if (errors==0) $display("tb_gime_registers PASS");
        else $display("tb_gime_registers FAIL: %0d",errors);
        $finish;
    end
endmodule
