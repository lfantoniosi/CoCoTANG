`timescale 1ns/1ps
module tb_coco_ssc_psg;
    reg clk=0, reset_n=0;
    always #5 clk=~clk;
    reg cpu_enable=0, e=0, e_fall=0, cpu_rw_n=1;
    reg [15:0] cpu_addr=16'hffff;
    reg [7:0] cpu_wdata=0;
    reg audio_clk=0;
    reg [10:0] audio_div=0;
    always @(posedge clk) begin
        if (audio_div==11'd1124) begin
            audio_div<=0;
            audio_clk<=!audio_clk;
        end else audio_div<=audio_div+1'b1;
    end
    wire [7:0] cpu_rdata;
    wire cpu_data_oe;
    wire signed [15:0] psg_pcm,speech_pcm;
    coco_ssc_psg dut(.*);

    task write_ssc;
        input [15:0] addr;
        input [7:0] data;
        begin
            @(negedge clk);
            cpu_enable=1;
            cpu_addr=addr;
            cpu_rw_n=0;
            cpu_wdata=data;
            e=1;
            e_fall=1;
            @(negedge clk);
            e_fall=0;
            cpu_rw_n=1;
            @(negedge clk);
            if (addr==16'hff7e)
                while (dut.busy_count!=0) @(negedge clk);
        end
    endtask

    task check_status;
        input [7:0] mask, expected;
        begin
            @(negedge clk);
            cpu_enable=1;
            cpu_addr=16'hff7e;
            cpu_rw_n=1;
            e=1;
            #1;
            if (!cpu_data_oe || (cpu_rdata & mask)!==expected)
                $fatal(1,"SSC status %02x expected masked %02x",cpu_rdata,expected);
        end
    endtask

    integer i, channel, clock_en_count, tone_edges, divider_edges, mixer_edges;
    integer pcm_min, pcm_max, sound_min, sound_max;
    reg tone_last_high, divider_last_high, mixer_last_high;
    initial begin
        repeat (4) @(negedge clk);
        reset_n=1;
        check_status(8'he0,8'he0);
        cpu_enable=0;
        #1;
        if (cpu_data_oe) $fatal(1,"unselected SSC drove CPU bus");
        cpu_enable=1;cpu_addr=16'hff7a;
        #1;
        if (cpu_data_oe) $fatal(1,"SSC overlaps Orchestra-90 address");

        // Reset and directly program AY channel A at about 3.5 kHz.
        write_ssc(16'hff7d,8'h01);
        write_ssc(16'hff7d,8'h00);
        write_ssc(16'hff7e,8'haf);
        write_ssc(16'hff7e,8'h00);
        write_ssc(16'hff7e,8'h20);
        write_ssc(16'hff7e,8'h01);
        write_ssc(16'hff7e,8'h00);
        write_ssc(16'hff7e,8'h07);
        write_ssc(16'hff7e,8'h3e);
        write_ssc(16'hff7e,8'h08);
        write_ssc(16'hff7e,8'h0f);
        repeat (5) @(negedge clk);
        if (dut.psg.regarray[0]!==8'h20 ||
            dut.psg.regarray[7]!==8'h3e ||
            dut.psg.regarray[8]!==8'h0f)
            $fatal(1,"direct PSG register writes failed");
        check_status(8'he0,8'hc0);

        // JT49's clock-enabled mixer/output pipeline needs several PSG
        // clocks to settle. Sampling its initial X as the previous level
        // makes every later edge comparison X and falsely reports no tone.
        repeat (1024) @(negedge clk);

        // 1 ms of 108 MHz input must yield about 1,790 PSG clock enables.
        clock_en_count=0;
        tone_edges=0;
        divider_edges=0;
        mixer_edges=0;
        tone_last_high=(dut.psg_sound > 10'd100);
        divider_last_high=dut.psg.bitA;
        mixer_last_high=dut.psg.Amix;
        pcm_min=32767;
        pcm_max=-32768;
        sound_min=1023;
        sound_max=0;
        for (i=0;i<108000;i=i+1) begin
            @(posedge clk);
            if (dut.psg_clock_enable) clock_en_count=clock_en_count+1;
            if ((dut.psg_sound > 10'd100) != tone_last_high) begin
                tone_edges=tone_edges+1;
                tone_last_high=(dut.psg_sound > 10'd100);
            end
            if (dut.psg.bitA != divider_last_high) begin
                divider_edges=divider_edges+1;
                divider_last_high=dut.psg.bitA;
            end
            if (dut.psg.Amix != mixer_last_high) begin
                mixer_edges=mixer_edges+1;
                mixer_last_high=dut.psg.Amix;
            end
            if (psg_pcm<pcm_min) pcm_min=psg_pcm;
            if (psg_pcm>pcm_max) pcm_max=psg_pcm;
            if (dut.psg_sound<sound_min) sound_min=dut.psg_sound;
            if (dut.psg_sound>sound_max) sound_max=dut.psg_sound;
        end
        if (clock_en_count<1789 || clock_en_count>1790)
            $fatal(1,"PSG clock rate wrong: %0d enables/ms",clock_en_count);
        if (pcm_min>=0 || pcm_max<=0)
            $fatal(1,"PSG PCM did not oscillate around zero: %0d %0d",
                   pcm_min,pcm_max);
        if (tone_edges<5 || tone_edges>10)
            $fatal(1,"PSG made %0d tone edges, divider %0d, mixer %0d (sound %0d..%0d, PCM %0d..%0d)",
                   tone_edges,divider_edges,mixer_edges,sound_min,sound_max,pcm_min,pcm_max);

        // Exercise the other two voices independently through the same
        // public register protocol, as used by PSGAUTO.BAS on the disk.
        for(channel=1;channel<=2;channel=channel+1) begin
            // Disable the previous voice's volume too: disabling both tone
            // and noise in AY's mixer produces DC rather than silence.
            write_ssc(16'hff7e,7+channel);
            write_ssc(16'hff7e,8'd0);
            write_ssc(16'hff7e,2*channel);
            write_ssc(16'hff7e,8'd32);
            write_ssc(16'hff7e,2*channel+1);
            write_ssc(16'hff7e,8'd0);
            write_ssc(16'hff7e,8'd7);
            write_ssc(16'hff7e,8'h3f ^ (8'd1 << channel));
            write_ssc(16'hff7e,8+channel);
            write_ssc(16'hff7e,8'd15);
            repeat(1024) @(negedge clk);
            tone_edges=0;
            tone_last_high=(dut.psg_sound>100);
            repeat(108000) begin
                @(negedge clk);
                if((dut.psg_sound>100)!=tone_last_high) begin
                    tone_edges=tone_edges+1;
                    tone_last_high=(dut.psg_sound>100);
                end
            end
            if(tone_edges<5 || tone_edges>10)
                $fatal(1,"PSG voice %0d produced %0d tone edges",channel,tone_edges);
        end

        write_ssc(16'hff7e,8'hff); // documented direct-mode terminator
        write_ssc(16'hff7e,8'hcf); // silence
        repeat (5) @(negedge clk);
        check_status(8'he0,8'he0);

        // Buffered register pairs must reach the same JT49 core in order.
        write_ssc(16'hff7e,8'hb8);
        write_ssc(16'hff7e,8'h00);
        write_ssc(16'hff7e,8'hff); // FF is data within a register pair
        write_ssc(16'hff7e,8'h07);
        write_ssc(16'hff7e,8'h3e);
        write_ssc(16'hff7e,8'h08);
        write_ssc(16'hff7e,8'h0f);
        write_ssc(16'hff7e,8'hff);
        write_ssc(16'hff7e,8'hf8);
        repeat (30) @(negedge clk);
        if (dut.psg.regarray[0]!==8'hff ||
            dut.psg.regarray[7]!==8'h3e ||
            dut.psg.regarray[8]!==8'h0f)
            $fatal(1,"buffered PSG register playback failed");

        // The manual's 98/D8 sound-event path is used by many SSC games.
        // Two four-byte tones, the second with zero amplitude, must play
        // sequentially and leave the sound-idle status set.
        write_ssc(16'hff7e,8'h8f);
        write_ssc(16'hff7e,8'h00);
        write_ssc(16'hff7e,8'h98);
        write_ssc(16'hff7e,8'h0f);
        write_ssc(16'hff7e,8'h00);
        write_ssc(16'hff7e,8'h40);
        write_ssc(16'hff7e,8'h01);
        write_ssc(16'hff7e,8'h00);
        write_ssc(16'hff7e,8'h00);
        write_ssc(16'hff7e,8'h00);
        write_ssc(16'hff7e,8'h01);
        write_ssc(16'hff7e,8'hff);
        write_ssc(16'hff7e,8'hd8);
        repeat (70) @(negedge clk);
        if (dut.psg.regarray[0]!==8'h40 ||
            dut.psg.regarray[8]!==8'h0f)
            $fatal(1,"sound event did not program the PSG tone");
        repeat (240000) @(negedge clk);
        if (dut.psg.regarray[8]!==8'h00 || dut.effect_state!==dut.FX_IDLE)
            $fatal(1,"sound event did not finish at silence");
        check_status(8'he0,8'he0);
        $display("tb_coco_ssc_psg PASS");
        $finish;
    end
endmodule
