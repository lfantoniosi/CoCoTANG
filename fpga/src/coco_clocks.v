module coco_clocks (
    input clkin,
    input button_reset,
    output clk108,
    output clk108p,
    output clk270,
    output clk135,
    output reg board_reset_n,
    output clocks_locked
);
    reg [7:0] power_count = 8'd0;
    reg pll_reset = 1'b1;
    always @(posedge clkin) begin
        if (button_reset) begin
            power_count <= 8'd0;
            pll_reset <= 1'b1;
        end else if (!(&power_count)) begin
            power_count <= power_count + 1'b1;
        end else begin
            pll_reset <= 1'b0;
        end
    end

    wire sdram_lock;
    wire video_lock;
    CLK108 sdram_pll (
        .clkout(clk108), .lock(sdram_lock), .clkoutp(clk108p),
        .reset(pll_reset), .clkin(clkin)
    );
    CLK270 video_pll (
        .clkout(clk270), .lock(video_lock), .clkoutd(clk135),
        .reset(pll_reset), .clkin(clkin)
    );

    reg [9:0] lock_count = 10'd0;
    always @(posedge clk108 or posedge pll_reset) begin
        if (pll_reset) begin
            lock_count <= 10'd0;
            board_reset_n <= 1'b0;
        end else if (!(sdram_lock && video_lock)) begin
            lock_count <= 10'd0;
            board_reset_n <= 1'b0;
        end else if (!(&lock_count)) begin
            lock_count <= lock_count + 1'b1;
            board_reset_n <= 1'b0;
        end else begin
            board_reset_n <= 1'b1;
        end
    end
    assign clocks_locked = sdram_lock && video_lock;
endmodule
