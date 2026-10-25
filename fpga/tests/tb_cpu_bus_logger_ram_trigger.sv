`timescale 1ns/1ps
module tb_cpu_bus_logger_ram_trigger;
    reg clk=0,reset_n=0,e_fall=0,rw_n=1,ram_read=0;
    reg [15:0] address=0;
    reg [7:0] data=0;
    reg [2:0] s=1;
    wire log_we,rebase_pulse,end_pulse;
    wire [1:0] log_addr,log_base;
    wire [2:0] log_count;
    wire [47:0] log_data;
    always #5 clk=~clk;
    cpu_bus_logger #(.LOG_ADDR_WIDTH(2),.LOG_COUNT_WIDTH(3),.LOG_DEPTH(4),
        .LOG_START_ADDRESS(16'h23bd),.LOG_READS_ONLY(1),.LOG_RAM_TRIGGER_ONLY(1)) dut(
        .clk(clk),.reset_n(reset_n),.capture_enable(1'b1),.capture_clear(1'b0),
        .nmi_event(1'b0),.bus_reset_n(1'b1),.e_fall(e_fall),.q(1'b0),
        .rw_n(rw_n),.address(address),.cpu_data(data),.expected_data(data),.s(s),
        .data_oe(1'b0),.memory_wait(1'b0),.ram_read(ram_read),
        .mmu_task0_page(6'd0),.mmu_task1_page(6'd0),
        .mmu_task(1'b0),.mmu_enabled(1'b0),
        .log_we(log_we),.log_addr(log_addr),.log_data(log_data),
        .log_count(log_count),.log_base(log_base),
        .rebase_pulse(rebase_pulse),.end_pulse(end_pulse));
    task sample(input [15:0] a,input read_cycle,input from_ram,input [7:0] d);
        @(negedge clk);
        address=a;rw_n=read_cycle;ram_read=from_ram;data=d;s=read_cycle ? 1 : 0;
        repeat(3)@(negedge clk);
        e_fall=1;@(negedge clk);e_fall=0;
    endtask
    initial begin
        repeat(3)@(negedge clk);reset_n=1;
        sample(16'h23bd,1,0,8'h86);
        if(log_count!=0 || log_we || rebase_pulse)
            $fatal(1,"ROM read started capture");
        sample(16'h23bd,0,0,8'h86);
        if(log_count!=0 || log_we || rebase_pulse)
            $fatal(1,"ROM-to-RAM copy write started capture");
        sample(16'h23bd,1,1,8'h86);
        if(log_count!=1 || !log_we || !rebase_pulse || log_addr!=0 ||
           log_data[45:30]!=16'h23bd || log_data[29:22]!=8'h86)
            $fatal(1,"RAM read did not start capture inclusively");
        sample(16'h23be,1,0,8'h12);
        if(log_count!=2 || !log_we || rebase_pulse)
            $fatal(1,"ROM access after the trigger was lost");
        sample(16'h23bd,1,0,8'h86);
        if(log_count!=3 || !log_we || rebase_pulse)
            $fatal(1,"later ROM read restarted capture");
        sample(16'h23bd,0,0,8'h55);
        if(log_count!=4 || !log_we || rebase_pulse)
            $fatal(1,"write restarted capture or was lost");
        sample(16'h23bd,1,0,8'h86);
        if(log_count!=4 || log_we || rebase_pulse)
            $fatal(1,"ROM read restarted a full trace");
        sample(16'h23bd,1,1,8'h86);
        if(log_count!=1 || !log_we || !rebase_pulse || log_addr!=0)
            $fatal(1,"RAM read failed to restart a full trace");
        $display("PASS: RAM-only 23BD trigger, ROM-copy rejection, inclusive capture, full-buffer restart");
        $finish;
    end
endmodule
