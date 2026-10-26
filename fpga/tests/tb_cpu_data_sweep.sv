`timescale 1ns/1ps
module tb_cpu_data_sweep;
    reg clkin=0,s1=0,s2=0;
    reg [7:0] controls=8'hd5;
    wire [1:0] msel;
    wire [7:0] mp=msel==0 ? 8'ha5 : msel==1 ? 8'hc3 : controls;
    tri [7:0] cpu_data;
    wire reset_drive,e_out,q_out,irq_n,firq_n,hs_n,fs_n;
    wire [2:0] sam_s;
    wire [7:0] test_data,data_readback,mp_live;
    wire [23:0] mux_banks;
    wire [15:0] cpu_address;
    wire paused,drive_data,ready;
    always #5 clkin=~clkin;
    cpu_bus_probe_engine #(.BYTE_HOLD_CYCLES(32),.STARTUP_CYCLES(64),
        .STROBE_CYCLES(8192),.BUTTON_CYCLES(2)) dut(.*);
    task tick;
        begin @(posedge clkin); #1; end
    endtask
    task button(input integer number);
        begin
            @(negedge clkin);
            if (number==1) s1=1; else s2=1;
            repeat (32) tick();
            @(negedge clkin);
            if (number==1) s1=0; else s2=0;
            repeat (32) tick();
        end
    endtask
    initial begin
        repeat (63) begin
            tick();
            if (cpu_data!==8'hzz) $fatal(1,"Driving before startup settles");
        end
        tick();
        if (mux_banks!==24'hd5c3a5 || cpu_address!==16'hd8a5)
            $fatal(1,"Mux acquisition/address lane mapping wrong: %h %h",mux_banks,cpu_address);
        // Every held sample of a full byte sweep plus wrap.
        for (integer value=0;value<258;value=value+1) begin
            for (integer sample=0;sample<32;sample=sample+1) begin
                if (cpu_data!==(value & 255))
                    $fatal(1,"Data %h, expected %h",cpu_data,value & 255);
                if (reset_drive!==1) $fatal(1,"CPU reset released");
                tick();
            end
        end
        // Walk all S codes, including PIA/cartridge modes that must release.
        while (sam_s!=0) begin
            if (drive_data!==(sam_s<=2)) $fatal(1,"S=%d drive=%b",sam_s,drive_data);
            if (sam_s>=3 && cpu_data!==8'hzz) $fatal(1,"Driving external device read");
            if ({irq_n,firq_n,hs_n,fs_n}!==
                {~sam_s[0],~sam_s[1],~sam_s[2],~(sam_s[0]^sam_s[1])})
                $fatal(1,"Output strobe mapping wrong");
            tick();
        end
        button(2);
        if (!paused) $fatal(1,"Pause did not toggle");
        begin
            reg [7:0] held_data;
            reg [2:0] held_s;
            held_data=test_data;held_s=sam_s;
            repeat (300) tick();
            if (test_data!==held_data || sam_s!==held_s) $fatal(1,"Paused outputs changed");
            button(1);
            if (test_data!==((held_data+1)&255) || sam_s!==((held_s+1)&7))
                $fatal(1,"Single step did not advance data and strobes");
        end
        // Physical R/W must release the bus in the control bank immediately.
        wait (msel==2); #1;controls[0]=0; #1;
        if (cpu_data!==8'hzz) $fatal(1,"Driving against physical write direction");
        repeat (64) tick();
        if (drive_data) $fatal(1,"Cached write direction still drives data");
        controls[0]=1;controls[1]=1;
        repeat (64) tick();
        if (drive_data) $fatal(1,"Driving without physical reset asserted");
        controls[1]=0;
        repeat (64) tick();
        if (!drive_data) $fatal(1,"Reset/read qualification never recovered");
        button(2);
        if (paused) $fatal(1,"Resume did not toggle");
        button(1);
        if (test_data>2 || sam_s!=0) $fatal(1,"Running S1 did not restart sweep");
        $display("PASS: data sweep/wrap, all mux banks, address mapping, strobes, hold/step, R/W/reset gating");
        $finish;
    end
    initial begin #2000000; $fatal(1,"Timeout"); end
endmodule
