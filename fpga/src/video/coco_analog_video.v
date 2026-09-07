module coco_analog_video #(
    // 0: Y/Pb/Pr component outputs.
    // 1: Y=luma, Pb=chroma (S-Video), Pr=CVBS.
    parameter integer OUTPUT_MODE = 1
) (
    input clk270, input reset_n,
    input [7:0] red, input [7:0] green, input [7:0] blue,
    input hblank, input vblank, input hs_n,
    output y_out, output pb_out, output pr_out
);
    localparam [31:0] COLOR_STEP = 32'd56940847;
    reg [31:0] color_phase = 32'd0;

    reg [9:0] y_red = 10'd0;
    reg [9:0] y_green = 10'd0;
    reg [9:0] y_blue = 10'd0;
    reg [7:0] red_d = 8'd0;
    reg [7:0] blue_d = 8'd0;
    reg [7:0] red_d2 = 8'd0;
    reg [7:0] blue_d2 = 8'd0;
    reg sync_d = 1'b1, hblank_d = 1'b1, vblank_d = 1'b1;
    reg [7:0] luma = 8'd0;
    // An 8-bit channel difference is -255..255, exactly nine signed bits.
    // Keeping this at nine avoids an unnecessary tenth carry stage at 270 MHz.
    reg signed [8:0] pb_delta = 9'sd0;
    reg signed [8:0] pr_delta = 9'sd0;
    reg sync_d2 = 1'b1, hblank_d2 = 1'b1, vblank_d2 = 1'b1;
    reg [7:0] component_y = 8'd0;
    reg [7:0] component_pb = 8'd128;
    reg [7:0] component_pr = 8'd128;
    reg signed [10:0] chroma = 11'sd0;
    reg signed [8:0] chroma_magnitude = 9'sd0;
    reg chroma_negative = 1'b0;
    reg sync_d3 = 1'b1;
    reg [7:0] svideo_chroma = 8'd128;
    reg [7:0] composite = 8'd0;
    reg signed [11:0] composite_work = 12'sd0;
    reg sync_d4 = 1'b1;
    wire [9:0] luma_sum = y_red + y_green + y_blue;

    function [7:0] clamp_chroma;
        input signed [10:0] value;
        begin
            if (value < 0) clamp_chroma = 8'd0;
            else if (value > 255) clamp_chroma = 8'd255;
            else clamp_chroma = value[7:0];
        end
    endfunction

    always @(posedge clk270 or negedge reset_n) begin
        if (!reset_n) begin
            color_phase <= 32'd0;
            y_red <= 10'd0; y_green <= 10'd0; y_blue <= 10'd0;
            red_d <= 8'd0; blue_d <= 8'd0; red_d2 <= 8'd0; blue_d2 <= 8'd0;
            sync_d <= 1'b1; hblank_d <= 1'b1; vblank_d <= 1'b1;
            luma <= 8'd0; pb_delta <= 9'sd0; pr_delta <= 9'sd0;
            sync_d2 <= 1'b1; hblank_d2 <= 1'b1; vblank_d2 <= 1'b1;
            component_y <= 8'd0; component_pb <= 8'd128; component_pr <= 8'd128;
            chroma <= 11'sd0; chroma_magnitude <= 9'sd0;
            chroma_negative <= 1'b0; svideo_chroma <= 8'd128; sync_d3 <= 1'b1;
            composite_work <= 12'sd0; sync_d4 <= 1'b1;
            composite <= 8'd0;
        end else begin
            color_phase <= color_phase + COLOR_STEP;

            // 0.3125 R + 0.625 G + 0.0625 B. The coefficients sum to one
            // and keep each 270 MHz pipeline stage to a pair of small adders.
            y_red <= (red >> 2) + (red >> 4);
            y_green <= (green >> 1) + (green >> 3);
            y_blue <= blue >> 4;
            red_d <= red; blue_d <= blue;
            sync_d <= hs_n; hblank_d <= hblank; vblank_d <= vblank;

            luma <= luma_sum[7:0];
            red_d2 <= red_d; blue_d2 <= blue_d;
            pb_delta <= $signed({1'b0,blue_d2}) - $signed({1'b0,luma});
            pr_delta <= $signed({1'b0,red_d2}) - $signed({1'b0,luma});
            sync_d2 <= sync_d; hblank_d2 <= hblank_d; vblank_d2 <= vblank_d;

            if (!sync_d2) component_y <= 8'd0;
            else if (hblank_d2 || vblank_d2) component_y <= 8'd64;
            else component_y <= 8'd64 + {1'b0,luma[7:1]};
            if (hblank_d2 || vblank_d2) begin
                component_pb <= 8'd128;
                component_pr <= 8'd128;
            end else begin
                component_pb <= clamp_chroma(11'sd128 + (pb_delta >>> 1));
                component_pr <= clamp_chroma(11'sd128 + (pr_delta >>> 1));
            end
            // Quadrature carrier: select the axis and sign in separate
            // stages to keep the 270 MHz paths short.
            chroma_magnitude <= color_phase[30] ? (pr_delta >>> 2) :
                                                        (pb_delta >>> 2);
            chroma_negative <= color_phase[31];
            chroma <= chroma_negative ? -chroma_magnitude : chroma_magnitude;
            if (hblank_d2 || vblank_d2)
                svideo_chroma <= 8'd128;
            else
                svideo_chroma <= clamp_chroma(11'sd128 + chroma);
            sync_d3 <= sync_d2;

            composite_work <= $signed({1'b0,component_y}) + chroma;
            sync_d4 <= sync_d3;
            if (!sync_d4) composite <= 8'd0;
            else if (composite_work < 0) composite <= 8'd0;
            else if (composite_work > 255) composite <= 8'd255;
            else composite <= composite_work[7:0];
        end
    end

    wire [7:0] y_sample;
    wire [7:0] pb_sample;
    wire [7:0] pr_sample;
    generate
        if (OUTPUT_MODE == 0) begin : component_outputs
            assign y_sample = component_y;
            assign pb_sample = component_pb;
            assign pr_sample = component_pr;
        end else begin : svideo_composite_outputs
            assign y_sample = component_y;
            assign pb_sample = svideo_chroma;
            assign pr_sample = composite;
        end
    endgenerate

    sigma_delta_dac y_dac(.clk(clk270),.reset_n(reset_n),.sample(y_sample),.bit_out(y_out));
    sigma_delta_dac pb_dac(.clk(clk270),.reset_n(reset_n),.sample(pb_sample),.bit_out(pb_out));
    sigma_delta_dac pr_dac(.clk(clk270),.reset_n(reset_n),.sample(pr_sample),.bit_out(pr_out));
endmodule
