`timescale 1ns/1ps
module tb_gime_mode_debug;
    reg clk = 1'b0;
    reg reset_n = 1'b0;
    reg button = 1'b0;
    wire bit_plane;
    wire [2:0] hres;
    wire [1:0] cres;
    wire [1:0] lpf;
    wire [2:0] lpr;
    integer errors = 0;
    integer index;

    gime_mode_debug #(.STABLE_CYCLES(1)) dut (
        .clk(clk), .reset_n(reset_n), .button(button),
        .bit_plane(bit_plane), .hres(hres), .cres(cres), .lpf(lpf),
        .lines_per_row_code(lpr)
    );
    always #5 clk = ~clk;

    task click;
        begin
            button = 1'b1;
            repeat (5) @(posedge clk);
            button = 1'b0;
            repeat (5) @(posedge clk);
        end
    endtask

    task check_mode;
        input integer expected_index;
        begin
            #1;
            if (dut.selection != expected_index) begin
                $display("selection %0d, expected %0d",dut.selection,expected_index);
                errors = errors + 1;
            end
            if (expected_index < 24 && lpf != 2'b00) errors = errors + 1;
            if (expected_index >= 24 && expected_index < 48 && lpf != 2'b01) errors = errors + 1;
            if (expected_index >= 48 && lpf != 2'b11) errors = errors + 1;
        end
    endtask

    initial begin
        repeat (3) @(posedge clk);
        reset_n = 1'b1;
        check_mode(0);
        if (bit_plane || hres != 0 || cres != 0 || lpr != 3'b011) errors = errors + 1;
        for (index=1; index<72; index=index+1) begin
            click();
            check_mode(index);
            if (index == 23 && (!bit_plane || hres != 7 || cres != 2)) errors = errors + 1;
            if (index == 24 && (bit_plane || hres != 0 || cres != 0)) errors = errors + 1;
            if (index == 48 && lpf != 3) errors = errors + 1;
        end
        click();
        check_mode(0);
        if (errors == 0) $display("tb_gime_mode_debug PASS");
        else $display("tb_gime_mode_debug FAIL: %0d",errors);
        $finish;
    end
endmodule
