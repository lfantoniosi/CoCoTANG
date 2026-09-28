`timescale 1ns/1ps
module tb_hdmi_video_standard;
    logic clk=0;
    logic reset=1;
    logic video_50hz=0;
    logic [9:0] x,y;
    logic [9:0] tmds[2:0];
    logic [15:0] audio[1:0];
    integer errors=0;

    always #5 clk=!clk;
    initial begin audio[0]=0;audio[1]=0;end

    hdmi #(.VIDEO_ID_CODE(2),.DYNAMIC_480_576(1),.DVI_OUTPUT(1'b1),
           .VIDEO_REFRESH_RATE(59.94),.AUDIO_RATE(48000),
           .AUDIO_BIT_WIDTH(16)) dut(
        .clk_pixel_x5(clk),.clk_pixel(clk),.clk_audio(clk),
        .video_50hz(video_50hz),.reset(reset),.rgb(24'd0),
        .audio_sample_word(audio),.cx(x),.cy(y),.frame_width(),
        .frame_height(),.screen_width(),.screen_height(),
           .tmds_internal(tmds));


    initial begin
        repeat(2)@(posedge clk);reset=0;#1;
        if(dut.frame_width!=858||dut.frame_height!=525||
           dut.screen_height!=480)begin
            $display("initial HDMI geometry %0d x %0d/%0d",
                     dut.frame_width,dut.screen_height,dut.frame_height);
            errors=errors+1;
        end
        video_50hz=1'b1;
        force dut.cx=10'd857;force dut.cy=10'd524;
        @(posedge clk);#1;release dut.cx;release dut.cy;
        #1;
        if(dut.frame_width!=864||dut.frame_height!=625||
           dut.screen_height!=576||dut.hsync_pulse_start!=12||
           dut.hsync_pulse_size!=64)begin
            $display("50Hz HDMI geometry %0d x %0d/%0d",
                     dut.frame_width,dut.screen_height,dut.frame_height);
            errors=errors+1;
        end
        video_50hz=1'b0;
        force dut.cx=10'd863;force dut.cy=10'd624;
        @(posedge clk);#1;release dut.cx;release dut.cy;
        #1;
        if(dut.active_video_50hz!==1'b0||dut.frame_width!=858||
           dut.frame_height!=525||dut.screen_height!=480)begin
            $display("50-to-60 HDMI geometry stuck at %0d x %0d/%0d",
                     dut.frame_width,dut.screen_height,dut.frame_height);
            errors=errors+1;
        end
        if(errors==0)$display("tb_hdmi_video_standard PASS");
        else $display("tb_hdmi_video_standard FAIL: %0d",errors);
        $finish;
    end
endmodule
