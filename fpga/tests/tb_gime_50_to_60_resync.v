`timescale 1ns/1ps
module tb_gime_50_to_60_resync;
    reg clk=0,reset_n=0,video_50hz=0,hdmi_active_50hz=0;
    reg hdmi_frame_start=0;
    always #5 clk=~clk;
    gime_native_video dut(
        .clk(clk),.reset_n(reset_n),.video_50hz(video_50hz),
        .bit_plane(1'b1),.hdmi_frame_start(hdmi_frame_start),
        .hdmi_active_50hz(hdmi_active_50hz),
        .active_height(8'd225),.compatibility_mode(1'b0),
        .compatibility_css(1'b0),.compatibility_border_rgb(6'd0),
        .pixel_rgb(6'd0),.hs_n(),.fs_n(),.hborder_irq_n(),
        .hblank(),.vblank(),.red(),.green(),.blue(),
        .compatibility_sample(),.compatibility_sample_css(),
        .compatibility_sample_y(),.compatibility_sample_byte(),
        .compatibility_border_sample(),.compatibility_border_right(),
        .compatibility_border_y(),.compatibility_border_sample_rgb(),
        .debug_raster_y());

    task frame_pulse;
        begin
            @(negedge clk); hdmi_frame_start=1;
            @(negedge clk); hdmi_frame_start=0;
            repeat(5) @(negedge clk);
        end
    endtask

    initial begin
        repeat(4) @(negedge clk); reset_n=1;
        // A cold 60 Hz frame must not be moved by the HDMI marker.
        @(negedge clk); dut.y=9'd100; dut.x=10'd100;
        frame_pulse();
        if(dut.y!==9'd100 || dut.standard_60_resync_pending)
            $fatal(1,"cold 60 Hz raster was changed");
        if(!dut.standard_60_phase_valid ||
           dut.standard_60_phase_y!==9'd100 ||
           dut.standard_60_phase_x!==10'd100)
            $fatal(1,"cold HDMI/GIME phase was not retained");

        @(negedge clk); video_50hz=1; hdmi_active_50hz=1;
        repeat(5) @(negedge clk);
        dut.y=9'd300; dut.x=10'd453;
        video_50hz=0;
        repeat(5) @(negedge clk);
        if(!dut.standard_60_resync_pending)
            $fatal(1,"50-to-60 request was not latched");
        frame_pulse();
        if(!dut.standard_60_resync_pending || dut.y==9'd0)
            $fatal(1,"resynchronized before HDMI left 50 Hz");

        hdmi_active_50hz=0;
        repeat(5) @(negedge clk);
        frame_pulse();
        if(dut.y!==9'd100 || dut.x!==10'd100 ||
           dut.standard_60_resync_pending)
            $fatal(1,"native raster did not restore the cold 60 Hz phase");

        @(negedge clk); dut.y=9'd100; dut.x=10'd100;
        frame_pulse();
        if(dut.y!==9'd100)
            $fatal(1,"one-shot realignment repeated");
        $display("tb_gime_50_to_60_resync PASS");
        $finish;
    end
endmodule
