`timescale 1ns/1ps
module tb_component_dac_phase;
    reg clk135=0,clk270=0,reset_n=0,line_start=0;
    reg [6:0] pb_level=64,pr_level=64;
    reg [6:0] y_level=68;
    wire [2:0] y,pb,pr;
    integer count,code,pb_ones,pr_ones,width;
    reg compare_counts=0;
    reg unlocked_pb=0,unlocked_pr=0;
    integer locked_pb_total=0,locked_pr_total=0;
    integer unlocked_pb_total=0,unlocked_pr_total=0;
    always #4 clk135=~clk135;
    always #2 clk270=~clk270;
    genvar c;
    generate for(c=0;c<3;c=c+1) begin: encoders
        coco_cvbs_ntsc #(.LUMA_SCANLINE_PHASE_ALTERNATION(1),
            .COMPONENT_DAC_PHASE_STAGGER(c!=0)) dut(
            .clk135(clk135),.clk270(clk270),.reset_n(reset_n),
            .video_50hz(1'b0),.high_resolution(1'b1),
            .compatibility_mode(1'b0),.framebuffer_data(6'd0),
            .border_rgb(6'd0),.row_border_rgb(6'd0),
            .row_right_border_rgb(6'd0),.row_border_valid(1'b0),
            .vertical_left_border_rgb(6'd0),.vertical_right_border_rgb(6'd0),
            .vertical_border_valid(1'b0),.active_height(8'd192),
            .luma_out(y[c]),.component_pb_out(pb[c]),.component_pr_out(pr[c]));
        initial begin
            force dut.dac_line_start=line_start;
            force dut.luma_level_135=y_level;
        end
        if(c==2) initial begin
            // Reference stays grey while the moving object crosses channel 1.
            force dut.component_pb_level_135=7'd64;
            force dut.component_pr_level_135=7'd64;
        end else initial begin
            force dut.component_pb_level_135=pb_level;
            force dut.component_pr_level_135=pr_level;
        end
    end endgenerate

    always @(negedge clk270) if(reset_n && y[0]!==y[1])
        $fatal(1,"Pb/Pr phase staggering changed Y waveform");

    // Compare total emitted pulses with the ordinary sigma carry, including
    // all colour/neutral transitions. The phase lock must not build up a DC
    // error over the moving-object sequence; an endpoint may differ by one.
    always @(posedge clk270) begin
        unlocked_pb<=encoders[1].dut.component_pb_sigma[7];
        unlocked_pr<=encoders[1].dut.component_pr_sigma[7];
    end
    always @(negedge clk270) if(compare_counts) begin
        locked_pb_total=locked_pb_total+pb[1];
        locked_pr_total=locked_pr_total+pr[1];
        unlocked_pb_total=unlocked_pb_total+unlocked_pb;
        unlocked_pr_total=unlocked_pr_total+unlocked_pr;
    end

    initial begin
        repeat(3) @(negedge clk270);
        reset_n=1;
        for(count=0;count<3;count=count+1) begin
            line_start=1;
            @(posedge clk270); #1;
            if(encoders[1].dut.component_pb_sigma !== 8'd42 ||
               encoders[1].dut.component_pr_sigma !== 8'd85)
                $fatal(1,"Component phases differ from RGB seeds");
            @(negedge clk270); line_start=0;
            repeat(8) @(negedge clk270);
            repeat(256) begin
                @(negedge clk270);
                if(pb[0]!==pr[0]) $fatal(1,"Expected coincident legacy grey outputs");
                if(pb[1]===pr[1]) $fatal(1,"Staggered neutral Pb/Pr should be complementary");
            end
        end
        // One 13.5-MHz pixel spans 20 DAC clocks. Sweep all widths modulo
        // the accumulator period, including the blue/white edges of BOINK.
        compare_counts=1;
        for(width=1;width<=64;width=width+1) begin
            pb_level=127; pr_level=55; y_level=46;
            repeat(width*20) @(negedge clk270);
            pb_level=64; pr_level=64; y_level=126;
            repeat(20) @(negedge clk270);
            y_level=68;
            repeat(8) @(negedge clk270);
            repeat(128) begin
                @(negedge clk270);
                if(pb[1]!==pb[2] || pr[1]!==pr[2])
                    $fatal(1,"Grey DAC phase retains blue history after %0d pixels",width);
                if(pb[1]===pr[1])
                    $fatal(1,"Neutral Pb/Pr became in phase after blue");
            end
        end
        compare_counts=0;
        if(locked_pb_total-unlocked_pb_total>1 ||
           unlocked_pb_total-locked_pb_total>1 ||
           locked_pr_total-unlocked_pr_total>1 ||
           unlocked_pr_total-locked_pr_total>1)
            $fatal(1,"Neutral locking accumulated a DC error: Pb=%0d Pr=%0d",
                   locked_pb_total-unlocked_pb_total,locked_pr_total-unlocked_pr_total);
        for(code=0;code<128;code=code+1) begin
            // Offset Pr so each midpoint detector is also exercised while
            // the other channel requests a non-neutral level.
            pb_level=code; pr_level=(code+63)%128;
            repeat(8) @(negedge clk270);
            pb_ones=0; pr_ones=0;
            repeat(256) begin
                @(negedge clk270);
                pb_ones=pb_ones+pb[1]; pr_ones=pr_ones+pr[1];
            end
            if(pb_ones!=pb_level*2 || pr_ones!=pr_level*2)
                $fatal(1,"Staggering changed colour levels %0d/%0d: Pb=%0d Pr=%0d",pb_level,pr_level,pb_ones,pr_ones);
        end
        $display("Component neutral phase independent of preceding blue/white, all DAC levels preserved, Y waveform unchanged PASS");
        $finish;
    end
endmodule
