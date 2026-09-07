`timescale 1ns/1ps

module tb_video_mode_debug;
    reg clk = 1'b0;
    reg reset_n = 1'b0;
    reg button = 1'b0;
    wire an_g;
    wire css;
    wire [2:0] gm;

    always #5 clk = !clk;

    video_mode_debug #(.STABLE_CYCLES(4)) dut (
        .clk(clk), .reset_n(reset_n), .button(button),
        .an_g(an_g), .css(css), .gm(gm)
    );

    task settle;
        input value;
        begin
            button = value;
            repeat (8) @(posedge clk);
        end
    endtask

    integer i;
    task check_selection;
        input integer number;
        reg expected_an_g;
        reg expected_css;
        reg [2:0] expected_gm;
        begin
            expected_an_g = number >= 2;
            expected_css = (number == 1) || (number >= 10);
            if (number < 2) expected_gm = 3'b000;
            else if (number < 10) expected_gm = number - 2;
            else expected_gm = number - 10;
            if ({an_g,css,gm} !== {expected_an_g,expected_css,expected_gm})
                $fatal(1, "selection %0d produced A/G=%b CSS=%b GM=%03b",
                       number, an_g, css, gm);
        end
    endtask

    initial begin
        repeat (2) @(posedge clk);
        reset_n = 1'b1;
        repeat (2) @(posedge clk);
        check_selection(0);

        // A short bounce must not register as a press.
        button = 1'b1;
        @(posedge clk);
        button = 1'b0;
        repeat (6) @(posedge clk);
        check_selection(0);

        for (i = 1; i <= 18; i = i + 1) begin
            settle(1'b1);
            check_selection(i == 18 ? 0 : i);
            // Holding the button must not repeat.
            repeat (8) @(posedge clk);
            check_selection(i == 18 ? 0 : i);
            settle(1'b0);
        end

        $display("tb_video_mode_debug PASS");
        $finish;
    end
endmodule
