`timescale 1ns/1ps
module tb_coco_pia1_dac;
    reg clk=0,reset_n=0,e_fall=0,cpu_rw_n=1;
    reg [15:0] cpu_addr=0;
    reg [7:0] cpu_data=0;
    wire [5:0] dac_level;
    wire sound_enable;
    wire [7:0] pwm_sample;
    wire [15:0] pcm_sample;
    wire audio_clk;

    coco_pia1_dac dut(.clk(clk),.reset_n(reset_n),.e_fall(e_fall),
        .cpu_rw_n(cpu_rw_n),.cpu_addr(cpu_addr),.cpu_data(cpu_data),
        .dac_level(dac_level),.sound_enable(sound_enable),.pwm_sample(pwm_sample),
        .pcm_sample(pcm_sample),.audio_clk(audio_clk));
    always #5 clk=!clk;

    task pia_write(input [15:0] addr,input [7:0] data);
        begin
            @(negedge clk); cpu_addr=addr;cpu_data=data;cpu_rw_n=0;e_fall=1;
            @(negedge clk); e_fall=0;cpu_rw_n=1;
        end
    endtask

    task check(input [5:0] level,input enabled,input [7:0] pwm,input [15:0] pcm);
        begin
            #1;
            if(dac_level!==level || sound_enable!==enabled ||
               pwm_sample!==pwm || pcm_sample!==pcm) begin
                $display("FAIL level=%h enable=%b pwm=%h pcm=%h expected=%h/%b/%h/%h",
                    dac_level,sound_enable,pwm_sample,pcm_sample,
                    level,enabled,pwm,pcm);
                $fatal;
            end
        end
    endtask

    initial begin
        repeat(2) @(negedge clk); reset_n=1;
        check(6'h00,1'b0,8'h80,16'h0000);

        // CRA bit 2 clear selects DDRA at FF20.
        pia_write(16'hff20,8'hfc);
        check(6'h00,1'b0,8'h80,16'h0000);
        pia_write(16'hff21,8'h04);
        pia_write(16'hff20,8'h80);
        check(6'h20,1'b0,8'h80,16'h0000);
        pia_write(16'hff20,8'hfc);
        check(6'h3f,1'b0,8'h80,16'h0000);

        // CRB $3c drives CB2 high and connects the DAC to the audio path.
        pia_write(16'hff23,8'h3c);
        check(6'h3f,1'b1,8'hfc,16'h7c00);
        pia_write(16'hff20,8'h80);
        check(6'h20,1'b1,8'h80,16'h0000);

        // CRB $34 drives CB2 low.  DAC changes used by joystick polling must
        // remain visible internally while both physical audio outputs mute.
        pia_write(16'hff23,8'h34);
        pia_write(16'hff20,8'hfc);
        check(6'h3f,1'b0,8'h80,16'h0000);

        // DDR masking must affect the reproduced physical pins.
        pia_write(16'hff21,8'h00);
        pia_write(16'hff20,8'h80);
        check(6'h20,1'b0,8'h80,16'h0000);
        pia_write(16'hff21,8'h04);
        pia_write(16'hff20,8'hfc);
        check(6'h20,1'b0,8'h80,16'h0000);

        // CB2 must be configured as a manual output, not merely have bit 3 set.
        pia_write(16'hff23,8'h08);
        check(6'h20,1'b0,8'h80,16'h0000);

        $display("PASS coco_pia1_dac");
        $finish;
    end
endmodule
