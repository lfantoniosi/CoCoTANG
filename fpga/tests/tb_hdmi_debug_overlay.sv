`timescale 1ns/1ps
module tb_hdmi_debug_overlay;
    logic [9:0] x=0,y=0;
    logic enable=1;
    logic [319:0] debug_data=320'd0;
    logic pixel_clk=0,debug_clk=0,log_we=0;
    logic [8:0] log_addr=0,log_count=0;
    logic [1:0] log_page=0;
    logic [39:0] log_data=0;
    logic [23:0] rgb_in=24'h123456;
    logic [23:0] rgb_out;
    integer errors=0;

    hdmi_debug_overlay #(.EXTENDED_HEADER(1)) dut(
        .pixel_clk(pixel_clk),.x(x),.y(y),.enable(enable),
        .debug_data(debug_data),.debug_clk(debug_clk),.log_we(log_we),
        .log_addr(log_addr),.log_data(log_data),.log_count(log_count),
        .log_page(log_page),
        .debug_status(5'b11111),
        .interrupt_status(4'b0000),
        .rom_verify_done(1'b1),.rom_verify_pass(1'b1),
        .rom_verify_vector(16'h8c1b),
        .sdram_test_done(1'b1),.sdram_test_pass(1'b1),
        .sdram_test_error_addr(16'h0000),
        .sdram_test_expected(8'h00),.sdram_test_actual(8'h00),
        .rgb_in(rgb_in),.rgb_out(rgb_out));

    always #5 debug_clk=~debug_clk;
    always #7 pixel_clk=~pixel_clk;

    task check;
        input [9:0] test_x,test_y;
        input [23:0] expected;
        begin
            x=test_x; y=test_y; repeat (2) @(posedge pixel_clk); #1;
            if (rgb_out !== expected) begin
                $display("overlay mismatch at %0d,%0d: got %h expected %h",
                         test_x,test_y,rgb_out,expected);
                errors=errors+1;
            end
        end
    endtask

    initial begin
        check(719,479,24'h001020);   // Overlay covers all 720x480 active pixels.
        check(720,479,24'h123456);   // Immediately right of the active screen.
        check(2,0,24'h40ffff);       // Lit title pixel is cyan.
        log_addr=0;
        log_data={1'b1,1'b1,3'd2,1'b1,16'hfffe,8'ha0,8'ha0,2'b11};
        log_we=1; @(posedge debug_clk); #1; log_we=0; log_count=1;
        repeat (4) @(posedge pixel_clk);
        check(2,16,24'hffffff);      // Entry zero index is rendered.
        check(58,16,24'hffffff);     // First address digit is rendered.
        check(298,16,24'hffffff);    // T:Q: valid by Q fall and E fall.
        log_addr=0;
        log_data={1'b1,1'b1,3'd1,1'b1,16'h8000,8'h45,8'h45,2'b10};
        log_we=1; @(posedge debug_clk); #1; log_we=0;
        repeat (4) @(posedge pixel_clk);
        check(2,16,24'hffb040);      // T:E: late after Q but valid by E.
        log_addr=0;
        log_data={1'b1,1'b1,3'd1,1'b0,16'h8000,8'hff,8'h45,2'b01};
        log_we=1; @(posedge debug_clk); #1; log_we=0;
        repeat (4) @(posedge pixel_clk);
        check(2,16,24'hff4040);      // A T:0 read failure makes the row red.
        log_addr=9'd116;
        log_data={1'b1,1'b1,3'd2,1'b1,16'ha05a,8'h1f,8'h1f,2'b00};
        log_we=1; @(posedge debug_clk); #1; log_we=0; log_count=9'd117;
        repeat (4) @(posedge pixel_clk);
        log_page=2'd1;
        repeat (4) @(posedge pixel_clk);
        check(2,16,24'hffffff);      // Page one starts with local entry 00.
        enable=0;
        check(58,16,24'h123456);     // S2/debug disable path.
        if (errors==0) $display("tb_hdmi_debug_overlay PASS");
        else $display("tb_hdmi_debug_overlay FAIL: %0d",errors);
        $finish;
    end
endmodule
