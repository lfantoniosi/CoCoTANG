`timescale 1ns/1ps
module tb_coco_ssc_audio;
    reg clk=0,clk270=0,reset_n=0,e=0,e_fall=0,cpu_rw_n=1;
    reg [15:0] cpu_addr=0;
    reg [7:0] cpu_wdata=0;
    always #4.62963 clk=~clk;
    always #1.85185 clk270=~clk270;
    wire audio_clk,cpu_data_oe;
    wire [7:0] cpu_rdata;
    wire signed [15:0] psg_pcm;
    wire [15:0] pia_pcm,base_left,base_right,base_mono;
    wire [15:0] left_pcm,right_pcm,mono_pcm,disabled_left,disabled_right,disabled_mono;
    coco_pia1_dac pia(.clk(clk),.reset_n(reset_n),.e_fall(e_fall),
        .cpu_rw_n(cpu_rw_n),.cpu_addr(cpu_addr),.cpu_data(cpu_wdata),
        .pcm_sample(pia_pcm),.audio_clk(audio_clk));
    coco_ssc_psg ssc(.clk(clk),.reset_n(reset_n),.cpu_enable(1'b1),
        .e(e),.e_fall(e_fall),.cpu_addr(cpu_addr),.cpu_rw_n(cpu_rw_n),
        .cpu_wdata(cpu_wdata),.audio_clk(audio_clk),.cpu_rdata(cpu_rdata),
        .cpu_data_oe(cpu_data_oe),.psg_pcm(psg_pcm));
    coco_orchestra90 orchestra(.clk(clk),.reset_n(reset_n),.e_fall(e_fall),
        .cpu_rw_n(cpu_rw_n),.cpu_addr(cpu_addr),.cpu_data(cpu_wdata),
        .mono_pcm(pia_pcm),.left_pcm(base_left),.right_pcm(base_right),
        .mono_mix_pcm(base_mono));
    coco_psg_mix mix(.clk(clk),.reset_n(reset_n),.base_left(base_left),
        .base_right(base_right),.base_mono(base_mono),.psg_pcm(psg_pcm),
        .left_pcm(left_pcm),.right_pcm(right_pcm),.mono_pcm(mono_pcm));
    coco_psg_mix #(.ENABLED(0)) disabled(.clk(clk),.reset_n(reset_n),
        .base_left(base_left),.base_right(base_right),.base_mono(base_mono),
        .psg_pcm(psg_pcm),.left_pcm(disabled_left),.right_pcm(disabled_right),
        .mono_pcm(disabled_mono));
    reg [7:0] analog_sample=128;
    wire audio_out;
    always @(posedge clk) analog_sample<={~mono_pcm[15],mono_pcm[14:8]};
    sigma_delta_dac dac(.clk(clk270),.reset_n(reset_n),
        .sample(analog_sample),.bit_out(audio_out));
    coco3_hdmi display(.pixel_clk(clk),.serial_clk(clk),.audio_clk(audio_clk),
        .reset(!reset_n),.audio_pcm_left(left_pcm),.audio_pcm_right(right_pcm),
        .video_50hz(1'b0),.bit_plane(1'b1),.active_height(8'd192),
        .compatibility_mode(1'b0),.border_rgb(6'd0),.artifact_mode(2'd0),
        .artifact_video_active(1'b0),.artifact_css(1'b0),.overlay_enable(1'b0),
        .row_border_valid(1'b0),.vertical_border_valid(1'b0),.pixel_data(24'd0));
    wire [23:0] words[3:0][1:0];
    wire [1:0] flags[3:0];
    wire [23:0] header;
    wire [55:0] sub[3:0];
    genvar sample_index;
    generate for(sample_index=0;sample_index<4;sample_index=sample_index+1) begin
        assign words[sample_index][0]={display.audio_samples[0],8'd0};
        assign words[sample_index][1]={display.audio_samples[1],8'd0};
        assign flags[sample_index]=0;
    end endgenerate
    audio_sample_packet packet(.frame_counter(8'd0),.valid_bit(flags),
        .user_data_bit(flags),.audio_sample_word(words),
        .audio_sample_word_present(4'hf),.header(header),.sub(sub));

    task write_bus(input [15:0] addr,input [7:0] value);
        begin
            @(negedge clk);cpu_addr=addr;cpu_rw_n=1;e=1;
            if(addr==16'hff7e) begin
                #1;
                if(!cpu_data_oe) $fatal(1,"SSC status read not enabled");
                while(!cpu_rdata[7]) @(negedge clk);
            end
            @(negedge clk);cpu_wdata=value;cpu_rw_n=0;e_fall=1;
            @(negedge clk);cpu_rw_n=1;e_fall=0;e=0;
        end
    endtask
    task register_write(input [7:0] regnum,input [7:0] value);
        begin write_bus(16'hff7e,regnum);write_bus(16'hff7e,value);end
    endtask
    task check_outputs(input integer l,input integer r,input integer m);
        integer ones,expected;
        begin
            repeat(8) @(negedge clk);
            if(left_pcm!==l[15:0] || right_pcm!==r[15:0] || mono_pcm!==m[15:0])
                $fatal(1,"SSC mix %0d/%0d/%0d expected %0d/%0d/%0d",
                       $signed(left_pcm),$signed(right_pcm),$signed(mono_pcm),l,r,m);
            if(disabled_left!==base_left || disabled_right!==base_right || disabled_mono!==base_mono)
                $fatal(1,"Disabled PSG mix changes base audio");
            if(sub[0][23:0]!=={left_pcm,8'd0} || sub[0][47:24]!=={right_pcm,8'd0})
                $fatal(1,"PSG mix did not reach both HDMI packet channels");
            expected=analog_sample;ones=0;
            repeat(256) begin @(negedge clk270);ones=ones+audio_out;end
            if(ones!=expected) $fatal(1,"Physical audio density %0d expected %0d",ones,expected);
        end
    endtask

    integer i,level,min_level=32767,max_level=-32768;
    initial begin #20000000;$fatal(1,"SSC audio integration timeout");end
    initial begin
        repeat(4) @(negedge clk);reset_n=1;
        // Reproduce the manual's PIA selection with the six-bit DAC at full
        // scale: it must not leak DC into the cartridge audio mix.
        write_bus(16'hff20,252);write_bus(16'hff21,4);write_bus(16'hff20,252);
        write_bus(16'hff7d,1);write_bus(16'hff7d,0);
        write_bus(16'hff01,52);write_bus(16'hff03,63);write_bus(16'hff23,60);
        if(pia_pcm!==0) $fatal(1,"Manual cartridge selection leaves DAC DC in mix");
        write_bus(16'hff7e,175);
        register_write(0,32);register_write(1,0);
        register_write(7,62);register_write(8,15);
        for(i=0;i<100;i=i+1) begin
            @(negedge audio_clk);
            level=$signed(psg_pcm);
            if(level<min_level) min_level=level;
            if(level>max_level) max_level=level;
            check_outputs(level,level,level);
        end
        if(min_level>=0 || max_level<=0) $fatal(1,"No bipolar PSG tone at outputs");
        // Orchestra-90 stays stereo; the physical output gets its mono mix.
        force psg_pcm=16'sd16000;
        write_bus(16'hff7a,255);write_bus(16'hff7b,0);
        check_outputs(32256,-384,15936);
        // Extreme combinations must saturate rather than wrap.
        write_bus(16'hff03,55);write_bus(16'hff20,252);write_bus(16'hff7b,255);
        force psg_pcm=16'sd32767;
        check_outputs(32767,32767,32767);
        write_bus(16'hff20,0);write_bus(16'hff7a,0);write_bus(16'hff7b,0);
        force psg_pcm=-16'sd32768;
        check_outputs(-32768,-32768,-32768);
        release psg_pcm;
        write_bus(16'hff03,63);write_bus(16'hff7a,128);write_bus(16'hff7b,128);
        write_bus(16'hff7e,255);write_bus(16'hff7e,207);
        check_outputs(0,0,0);
        $display("SSC manual setup, PSG+Orchestra HDMI stereo, physical mono, clipping and silence PASS");
        $finish;
    end
endmodule
