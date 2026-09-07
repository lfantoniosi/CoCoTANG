module video_mode_debug #(
    // 10 ms at the 108 MHz system clock.  Tests can override this value.
    parameter integer STABLE_CYCLES = 1080000
) (
    input            clk,
    input            reset_n,
    input            button,
    output           an_g,
    output           css,
    output     [2:0] gm
);
    localparam integer COUNTER_WIDTH =
        (STABLE_CYCLES <= 1) ? 1 : $clog2(STABLE_CYCLES);

    reg button_meta = 1'b0;
    reg button_sync = 1'b0;
    reg button_state = 1'b0;
    reg [COUNTER_WIDTH-1:0] stable_count = {COUNTER_WIDTH{1'b0}};
    reg [4:0] selection = 5'd0;

    // Walk only the distinct MC6847 mode combinations:
    //   0..1  : alphanumeric, CSS 0/1 (GM is irrelevant)
    //   2..9  : graphics, CSS 0, GM 000..111
    //   10..17: graphics, CSS 1, GM 000..111
    assign an_g = selection >= 5'd2;
    assign css = (selection == 5'd1) || (selection >= 5'd10);
    // Both eight-mode graphics banks begin where selection[2:0] is 3'd2.
    assign gm = (selection < 5'd2) ? 3'b000 : selection[2:0] - 3'd2;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            button_meta <= 1'b0;
            button_sync <= 1'b0;
            button_state <= 1'b0;
            stable_count <= {COUNTER_WIDTH{1'b0}};
            selection <= 5'd0;
        end else begin
            button_meta <= button;
            button_sync <= button_meta;

            if (button_sync == button_state) begin
                stable_count <= {COUNTER_WIDTH{1'b0}};
            end else if (STABLE_CYCLES <= 1 ||
                         stable_count == STABLE_CYCLES - 1) begin
                button_state <= button_sync;
                stable_count <= {COUNTER_WIDTH{1'b0}};
                // Increment on the press edge only and wrap after the last
                // distinct graphics/color-set combination.
                if (button_sync) begin
                    if (selection == 5'd17)
                        selection <= 5'd0;
                    else
                        selection <= selection + 1'b1;
                end
            end else begin
                stable_count <= stable_count + 1'b1;
            end
        end
    end
endmodule
