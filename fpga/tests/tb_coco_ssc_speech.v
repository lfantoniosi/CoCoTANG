`timescale 1ns/1ps
module tb_coco_ssc_speech;
    reg clk=0,reset_n=0;
    always #5 clk=~clk;
    reg cpu_enable=1,e=1,e_fall=0,cpu_rw_n=1,audio_clk=0;
    reg [15:0] cpu_addr=16'hff7e;
    reg [7:0] cpu_wdata=0;
    wire [7:0] cpu_rdata;
    wire cpu_data_oe;
    wire signed [15:0] psg_pcm,speech_pcm;
    coco_ssc_psg #(.ENABLE_SPEECH(1)) dut(.*);
    task put;
        input [7:0] value;
        begin
            while(!cpu_rdata[7]) @(negedge clk);
            cpu_rw_n=0;cpu_wdata=value;e_fall=1;
            @(negedge clk);e_fall=0;cpu_rw_n=1;
            repeat(40) @(negedge clk);
        end
    endtask
    integer i,ticks,nonzero,min_pcm,max_pcm;
    reg [7:0] phrase[0:16];
    initial begin
        // Manual phrase: COLOR COMPUTER, using explicit AL2 allophones.
        phrase[0]=8;phrase[1]=15;phrase[2]=45;phrase[3]=51;
        phrase[4]=4;phrase[5]=4;phrase[6]=4;phrase[7]=8;
        phrase[8]=15;phrase[9]=16;phrase[10]=9;phrase[11]=49;
        phrase[12]=31;phrase[13]=13;phrase[14]=51;phrase[15]=4;phrase[16]=255;
        repeat(4) @(negedge clk);reset_n=1;
        ticks=0;
        repeat(67500) begin @(negedge clk);if(dut.speech_enabled.speech.cen) ticks=ticks+1;end
        if(ticks!=1600) $fatal(1,"Speech enable rate: %d",ticks);
        // Keep synthesis untouched, accelerate only its clock enable for simulation.
        force dut.speech_enabled.speech.divider=10'd659;
        repeat(3000) @(negedge clk);
        // KQ1/KQ2 reset pulse and exact BF comparison from Sierra loader.
        cpu_addr=16'hff7d;put(1);put(0);cpu_addr=16'hff7e;#1;
        repeat(512) @(negedge clk);
        if(cpu_rdata!==8'hbf) $fatal(1,"KQ1/KQ2 reset probe expects BF, got %h",cpu_rdata);
        repeat(3000) @(negedge clk);
        // Exact Pitfall II probe: idle -> space -> CR -> some status goes low.
        if((cpu_rdata & 8'he0)!=8'he0) $fatal(1,"not idle after reset");
        put(8'h20);
        put(8'h0d);
        if(cpu_rdata[6]!==0) $fatal(1,"Pitfall II probe sees no speech activity");
        i=0;
        while(!cpu_rdata[6] && i<1000000) begin @(negedge clk);i=i+1;end
        if(!cpu_rdata[6]) $fatal(1,"blank speech never completes");
        // SPEAK2.BAS sends ASCII bytes and CR, with only BUSY polling.
        // Lowercase is deliberate; the pronunciation engine normalizes it.
        put("h");put("i");
        if(cpu_rdata[6]!==1) $fatal(1,"text spoke before carriage return");
        put(13);
        if(cpu_rdata[7]!==0 || cpu_rdata[6]!==0)
            $fatal(1,"ASCII speech did not assert BUSY and speech status");
        nonzero=0;i=0;
        while(!cpu_rdata[6] && i<4000000) begin
            @(negedge clk);i=i+1;
            if(speech_pcm!==0) nonzero=nonzero+1;
        end
        if(!cpu_rdata[6] || !cpu_rdata[7] || nonzero<100)
            $fatal(1,"SPEAK2 ASCII/CR produced no speech or never completed");
        repeat(4) @(negedge clk);
        if(speech_pcm!==0) $fatal(1,"text speech did not silence final pause");
        // A forced 00 command must stop both PSG and text, even while text
        // playback is holding BUSY low. Payload zeroes must keep their meaning.
        put(8'haf);put(8'h08);put(15);put(8'hff);
        if(cpu_rdata[5]!==0) $fatal(1,"PSG did not start before text stop test");
        put("h");put(13);repeat(10000) @(negedge clk);
        cpu_rw_n=0;cpu_wdata=0;e_fall=1;
        @(negedge clk);e_fall=0;cpu_rw_n=1;
        repeat(40) @(negedge clk);
        if((cpu_rdata & 8'he0)!==8'he0 || speech_pcm!==0 || psg_pcm!==0)
            $fatal(1,"00 failed to stop text and PSG while text BUSY");
        put(8'hb0);
        for(i=0;i<17;i=i+1) put(phrase[i]);
        put(8'hf0);
        if(cpu_rdata[6]!==0) $fatal(1,"buffered speech never starts");
        nonzero=0;min_pcm=32767;max_pcm=-32768;i=0;
        while(!cpu_rdata[6] && i<12000000) begin
            @(negedge clk);i=i+1;
            if(speech_pcm!==0) nonzero=nonzero+1;
            if(speech_pcm<min_pcm) min_pcm=speech_pcm;
            if(speech_pcm>max_pcm) max_pcm=speech_pcm;
        end
        if(!cpu_rdata[6]) $fatal(1,"buffered speech stuck state=%d",dut.speech_enabled.speech.state);
        if(nonzero<100 || min_pcm>=0 || max_pcm<=0)
            $fatal(1,"speech PCM invalid: samples %d range %d..%d",nonzero,min_pcm,max_pcm);
        repeat(4) @(negedge clk);
        if(speech_pcm!==0) $fatal(1,"speech leaves nonzero idle output");
        put(8'hf0);repeat(10000) @(negedge clk);put(8'hc7);
        if(cpu_rdata[6]!==1 || speech_pcm!==0) $fatal(1,"speech abort failed");
        put(8'hf0);repeat(1000) @(negedge clk);
        cpu_addr=16'hff7d;put(1);put(0);cpu_addr=16'hff7e;#1;
        if(cpu_rdata!==8'hbf || speech_pcm!==0) $fatal(1,"software reset startup failed");
        repeat(3000) @(negedge clk);
        if(cpu_rdata!==8'hff) $fatal(1,"software reset never returns idle");
        $display("PASS: SSC speech clock, KQ1/KQ2 reset probe, Pitfall II probe, ASCII/CR and buffered phrase PCM, completion, abort and reset (%d..%d)",min_pcm,max_pcm);
        $finish;
    end
    initial begin #500000000;$fatal(1,"timeout");end
endmodule
