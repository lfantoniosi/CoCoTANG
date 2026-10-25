`timescale 1ns/1ps
module tb_hdmi_debug_overlay #(
    parameter integer LOG_ADDR_WIDTH=9,LOG_COUNT_WIDTH=9,
    parameter integer LOG_PAGE_WIDTH=2,LOG_DEPTH=512
);
    logic [9:0] x=0,y=0;
    logic enable=1;
    logic [319:0] debug_data=320'd0;
    logic pixel_clk=0,debug_clk=0,log_we=0;
    logic [LOG_ADDR_WIDTH-1:0] log_addr=0;
    logic [LOG_COUNT_WIDTH-1:0] log_count=0;
    logic [LOG_PAGE_WIDTH-1:0] log_page=0;
    logic [47:0] log_data=0;
    logic [23:0] rgb_in=24'h123456;
    logic [23:0] rgb_out;
    integer errors=0;
    integer test_count,test_page,expected_start;

    hdmi_debug_overlay #(.EXTENDED_HEADER(2),.LOG_ADDR_WIDTH(LOG_ADDR_WIDTH),
        .LOG_COUNT_WIDTH(LOG_COUNT_WIDTH),.LOG_PAGE_WIDTH(LOG_PAGE_WIDTH),
        .LOG_DEPTH(LOG_DEPTH)) dut(
        .pixel_clk(pixel_clk),.x(x),.y(y),.enable(enable),
        .debug_data(debug_data),.debug_clk(debug_clk),.log_we(log_we),
        .log_addr(log_addr),.log_data(log_data),.log_count(log_count),
        .log_base({LOG_ADDR_WIDTH{1'b0}}),
        .log_page(log_page),
        .debug_status(5'b11111),
        .interrupt_status(4'b0000),
        .gime_register_debug(80'hc0011808300000000000),
        .mmu_register_debug(96'h3f3e3d3c3b3a39383f3e3d3c),
        .rom_verify_done(1'b1),.rom_verify_pass(1'b1),
        .rom_verify_vector(16'h8c1b),
        .sdram_test_done(1'b1),.sdram_test_pass(1'b1),
        .sdram_test_error_addr(19'h00000),
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
        log_data={1'b1,1'b1,16'hfffe,8'ha0,8'ha0,
                  1'b1,1'b0,6'h12,6'h2a};
        log_we=1; @(negedge debug_clk); @(posedge debug_clk); #1;
        log_we=0; log_count=1;
        repeat (4) @(posedge pixel_clk);
        check(2,8,24'h40ffff);       // Fixed GIME row is rendered in cyan.
        check(2,24,24'hffffff);      // Entry zero index is rendered.
        check(74,24,24'hffffff);     // First address digit is rendered.
        check(194,24,24'hffffff);    // First MMU-page digit is rendered.
        log_addr=0;
        log_data={1'b1,1'b0,16'h8000,8'h45,8'h45,
                  1'b1,1'b1,6'h01,6'h02};
        log_we=1; @(negedge debug_clk); @(posedge debug_clk); #1; log_we=0;
        repeat (4) @(posedge pixel_clk);
        check(2,24,24'hffff40);      // Writes are highlighted yellow.
        log_addr=0;
        log_data={1'b1,1'b1,16'h8000,8'hff,8'h45,
                  1'b0,1'b0,6'h03,6'h04};
        log_we=1; @(negedge debug_clk); @(posedge debug_clk); #1; log_we=0;
        repeat (4) @(posedge pixel_clk);
        check(2,24,24'hffffff);      // Reads remain white.
        // With 115 entries, the tail page displays entries 1 through 114.
        log_addr=1;
        log_data={1'b1,1'b1,16'ha05a,8'h1f,8'h1f,
                  1'b1,1'b1,6'h05,6'h06};
        log_we=1; @(negedge debug_clk); @(posedge debug_clk); #1;
        log_we=0; log_count=115;
        repeat (4) @(posedge pixel_clk);
        log_page=1;
        repeat (4) @(posedge pixel_clk);
        check(2,24,24'hffffff);      // Page one starts with local entry 00.
        enable=0;
        check(58,16,24'h123456);     // S2/debug disable path.
        // Exhaustively compare page bounds with the original tail-page
        // division, including every boundary and the full capture count.
        for(test_count=0;test_count<=LOG_DEPTH &&
            test_count<2**LOG_COUNT_WIDTH;test_count=test_count+1)begin
            log_count=test_count;
            repeat(4)@(posedge pixel_clk);
            for(test_page=0;test_page<2**LOG_PAGE_WIDTH;test_page=test_page+1)begin
                log_page=test_page;#1;
                expected_start=(test_count>114 && test_page==(test_count-1)/114) ?
                    test_count-114 : test_page*114;
                if(dut.page_start_index!==expected_start)
                    $fatal(1,"Page address changed for count=%0d page=%0d",test_count,test_page);
            end
        end
        if (errors==0) $display("tb_hdmi_debug_overlay PASS");
        else $fatal(1,"tb_hdmi_debug_overlay FAIL: %0d",errors);
        $finish;
    end
endmodule
