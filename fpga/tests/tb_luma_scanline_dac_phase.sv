`timescale 1ns/1ps

module tb_luma_scanline_dac_phase;
    reg clk135=0, clk270=0, reset_n=0;
    always #4 clk135=~clk135;
    always #2 clk270=~clk270;
    reg [6:0] level=40;
    wire [2:0] pins, phases;
    wire [7:0] sigma[0:2];
    integer value, channel, ones[0:2];
    reg [2:0] first_period[0:63];
    genvar c;
    generate for(c=0;c<3;c=c+1) begin: encoders
        // RGB green reference, component Y, and the existing S-Video Y path.
        coco_cvbs_ntsc #(.RGB_SOG_OUTPUT(c==0),
            .LUMA_DAC_EVEN_LEVELS(1),
            .RGB_SCANLINE_PHASE_ALTERNATION(c==0),
            .LUMA_SCANLINE_PHASE_ALTERNATION(c==1),
            .CVBS_SVIDEO_SCANLINE_PHASE_ALTERNATION(c==2)) dut(
            .clk135(clk135),.clk270(clk270),.reset_n(reset_n),
            .video_50hz(1'b0),.high_resolution(1'b1),
            .compatibility_mode(1'b0),.framebuffer_data(6'd0),
            .border_rgb(6'd0),.row_border_rgb(6'd0),
            .row_right_border_rgb(6'd0),.row_border_valid(1'b0),
            .vertical_left_border_rgb(6'd0),
            .vertical_right_border_rgb(6'd0),
            .vertical_border_valid(1'b0),.active_height(8'd192),
            .luma_out(pins[c]));
        initial force dut.luma_level=level;
        assign sigma[c]=dut.luma_sigma;
        assign phases[c]=dut.dac_line_phase;
    end endgenerate

    // Exercise real sync detection, rather than forcing the seed event.
    task sync_line(input [7:0] expected_seed);
        begin
            @(negedge clk270); level=40;
            repeat(8) @(negedge clk270);
            level=0;
            wait(encoders[0].dut.dac_line_start);
            @(posedge clk270); #1;
            for(channel=0;channel<3;channel=channel+1)
                if(sigma[channel]!==expected_seed)
                    $fatal(1,"Y DAC channel %0d seed=%0d expected=%0d",
                           channel,sigma[channel],expected_seed);
            repeat(8) @(negedge clk270);
            if(phases!=={3{phases[0]}})
                $fatal(1,"Y scanline phase differs from RGB green");
        end
    endtask

    always @(negedge clk270) if(reset_n && pins!=={3{pins[0]}})
        $fatal(1,"Component/S-Video Y pulse pattern differs from RGB green");

    initial begin
        #1000000;
        $fatal(1,"Y DAC test timed out waiting for sync");
    end

    initial begin
        repeat(3) @(negedge clk270);
        reset_n=1;
        sync_line(0);
        sync_line(64);
        sync_line(0);
        // Include every seven-bit level, not just the four RGB green levels.
        for(value=0;value<128;value=value+1) begin
            level=value;
            repeat(8) @(negedge clk270);
            for(channel=0;channel<3;channel=channel+1) ones[channel]=0;
            for(integer sample=0;sample<256;sample=sample+1) begin
                @(negedge clk270);
                if(sample<64) first_period[sample]=pins;
                else if(pins!==first_period[sample%64])
                    $fatal(1,"Y DAC pattern exceeds RGB's 64-clock period at level %0d",value);
                for(channel=0;channel<3;channel=channel+1)
                    ones[channel]=ones[channel]+pins[channel];
            end
            for(channel=0;channel<3;channel=channel+1)
                if(ones[channel]!=2*(value & 126))
                    $fatal(1,"Y DAC density: channel=%0d level=%0d ones=%0d",
                           channel,value,ones[channel]);
        end
        $display("Component/S-Video Y matches RGB green phase, even-code density and 64-clock period at all 128 input levels PASS");
        $finish;
    end
endmodule
