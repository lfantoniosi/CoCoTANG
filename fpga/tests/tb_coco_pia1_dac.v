`timescale 1ns/1ps
module tb_coco_pia1_dac;
    reg clk=0,reset_n=0,e_fall=0,cpu_rw_n=1;
    reg [15:0] cpu_addr=0;
    reg [7:0] cpu_data=0;
    wire [5:0] dac_level;
    wire [7:0] pwm_sample;
    wire [15:0] pcm_sample;
    wire audio_clk;

    coco_pia1_dac dut(.clk(clk),.reset_n(reset_n),.e_fall(e_fall),
        .cpu_rw_n(cpu_rw_n),.cpu_addr(cpu_addr),.cpu_data(cpu_data),
        .dac_level(dac_level),.pwm_sample(pwm_sample),
        .pcm_sample(pcm_sample),.audio_clk(audio_clk));
    always #5 clk=!clk;

    task pia_write(input [15:0] addr,input [7:0] data);
        begin
            @(negedge clk); cpu_addr=addr;cpu_data=data;cpu_rw_n=0;e_fall=1;
            @(negedge clk); e_fall=0;cpu_rw_n=1;
        end
    endtask

    task check(input [5:0] level,input [7:0] pwm,input [15:0] pcm);
        begin
            #1;
            if(dac_level!==level || pwm_sample!==pwm || pcm_sample!==pcm) begin
                $display("FAIL level=%h pwm=%h pcm=%h expected=%h/%h/%h",
                    dac_level,pwm_sample,pcm_sample,level,pwm,pcm);
                $fatal;
            end
        end
    endtask

    initial begin
        repeat(2) @(negedge clk); reset_n=1;
        check(6'h00,8'h00,16'h8000);

        // CRA bit 2 clear selects DDRA at FF20.
        pia_write(16'hff20,8'hfc);
        check(6'h00,8'h00,16'h8000);
        pia_write(16'hff21,8'h04);
        pia_write(16'hff20,8'h80);
        check(6'h20,8'h80,16'h0000);
        pia_write(16'hff20,8'hfc);
        check(6'h3f,8'hfc,16'h7c00);

        // DDR masking must affect the reproduced physical pins.
        pia_write(16'hff21,8'h00);
        pia_write(16'hff20,8'h80);
        check(6'h20,8'h80,16'h0000);
        pia_write(16'hff21,8'h04);
        pia_write(16'hff20,8'hfc);
        check(6'h20,8'h80,16'h0000);

        $display("PASS coco_pia1_dac");
        $finish;
    end
endmodule
