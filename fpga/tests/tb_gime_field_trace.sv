`timescale 1ns/1ps
module tb_gime_field_trace;
    logic debug_clk=0,pixel_clk=0;
    always #5 debug_clk=~debug_clk;
    always #7 pixel_clk=~pixel_clk;
    logic arm=0,sample=0;
    logic [8:0] sample_y=0;
    logic [9:0] display_y=0;
    logic [2:0] page=0;
    logic [200:0] sample_data=0;
    wire [23:0] rgb;
    integer y,errors=0;

    hdmi_debug_overlay #(.GIME_TRACE_MODE(1),.EXTENDED_HEADER(2)) dut(
        .pixel_clk(pixel_clk),.x(10'd0),.y(display_y),.enable(1'b1),
        .debug_clk(debug_clk),.gime_trace_arm(arm),
        .gime_trace_page(page),.gime_trace_sample(sample),
        .gime_trace_y(sample_y),.gime_trace_data(sample_data),
        .debug_data(320'd0),.log_we(1'b0),.log_addr(9'd0),
        .log_data(48'd0),.log_count(9'd0),.log_base(9'd0),
        .log_page(2'd0),.debug_status(5'd0),
        .interrupt_status(4'd0),.gime_register_debug(80'd0),
        .mmu_register_debug(96'd0),.rom_verify_done(1'b0),
        .rom_verify_pass(1'b0),.rom_verify_vector(16'd0),
        .sdram_test_done(1'b0),.sdram_test_pass(1'b0),
        .sdram_test_error_addr(19'd0),.sdram_test_expected(8'd0),
        .sdram_test_actual(8'd0),.rgb_in(24'd0),.rgb_out(rgb));

    task write_line(input integer line,input [7:0] vmode,
                    input [22:0] cache_start);
        reg [127:0] regs;
        begin
            regs=128'd0;
            regs[63:56]=vmode; // FF98, byte eight of FF90..FF9F.
            @(negedge debug_clk);
            sample_y=line[8:0];
            sample_data={regs,cache_start,19'(cache_start),
                         8'(line),8'(line),8'(line),4'd0,2'd2,1'b1};
            sample=1;
            @(negedge debug_clk);sample=0;
        end
    endtask

    initial begin
        // A synthetic line26 BOINK field. Page boundaries are 57 rows.
        for(y=0;y<263;y=y+1)
            write_line(y,y>=27&&y<122?8'h80:8'h87,
                       y<27?21'h0c040:
                       y<122?21'h0c040+(y-26)*21'h0a0:21'h0fba0);
        write_line(0,8'h55,21'h12345); // frame wrap freezes old capture
        if(dut.gime_count!==9'd263 || dut.gime_capturing!==0)begin
            $display("field did not freeze: count=%0d active=%b",
                     dut.gime_count,dut.gime_capturing);errors=errors+1;
        end
        if(dut.gime_field_memory[26][136:129]!==8'h87 ||
           dut.gime_field_memory[27][136:129]!==8'h80 ||
           dut.gime_field_memory[27][72:50]!==21'h0c0e0 ||
           dut.gime_field_memory[122][72:50]!==21'h0fba0)begin
            $display("line26 BOINK trace bytes/addresses differ");errors=errors+1;
        end
        page=3'd4;
        display_y=10'd24;
        repeat(3)@(posedge pixel_clk);
        if(dut.gime_trace_index!==9'd228)begin
            $display("page four did not begin at line 228");errors=errors+1;
        end
        @(negedge debug_clk);arm=1;
        @(negedge debug_clk);arm=0;
        write_line(0,8'h80,23'h700440);
        if(dut.gime_count!==9'd1 ||
           dut.gime_field_memory[0][72:50]!==23'h700440)begin
            $display("S2 rearm did not start next field");errors=errors+1;
        end
        for(y=1;y<313;y=y+1)
            write_line(y,8'h80,21'h00440+y*21'h0a0);
        write_line(0,8'h87,21'h12345);
        if(dut.gime_count!==9'd313 ||
           dut.gime_field_memory[312][136:129]!==8'h80 ||
           dut.gime_field_memory[312][72:50]!==21'h0c740)begin
            $display("313-line field did not freeze at line 312");errors=errors+1;
        end
        page=3'd5;
        repeat(3)@(posedge pixel_clk);
        if(dut.gime_trace_index!==9'd285)begin
            $display("page five did not begin at line 285");errors=errors+1;
        end
        if(errors) $fatal(1,"tb_gime_field_trace FAIL: %0d",errors);
        $display("tb_gime_field_trace PASS");
        $finish;
    end
endmodule
