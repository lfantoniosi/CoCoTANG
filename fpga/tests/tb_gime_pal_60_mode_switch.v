`timescale 1ns/1ps
module tb_gime_pal_60_mode_switch;
    reg clk=0, reset_n=0, video_50hz=0, bit_plane=0;
    reg hdmi_frame_start=0;
    reg [7:0] active_height=8'd192;
    integer errors=0;
    always #5 clk=~clk;

    gime_native_video #(.PAL_MACHINE(1)) dut (
        .clk(clk), .reset_n(reset_n), .video_50hz(video_50hz),
        .bit_plane(bit_plane), .hdmi_frame_start(hdmi_frame_start),
        .hdmi_active_50hz(1'b0),
        .active_height(active_height),
        .compatibility_mode(1'b0), .compatibility_css(1'b0),
        .compatibility_border_rgb(6'd0), .pixel_rgb(6'd0),
        .hs_n(), .fs_n(), .hborder_irq_n(), .hblank(), .vblank(),
        .debug_raster_y(), .compatibility_sample(),
        .compatibility_sample_css(), .compatibility_sample_y(),
        .compatibility_sample_byte(), .compatibility_border_sample(),
        .compatibility_border_right(), .compatibility_border_y(),
        .compatibility_border_sample_rgb(), .red(), .green(), .blue()
    );

    task advance_dot;
        begin
            @(negedge clk);
            while (!dut.raster_tick) @(negedge clk);
            @(posedge clk); #1;
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        reset_n=1;
        @(negedge clk);
        // Switch from PAL text to bitmap after the NTSC-style line end.
        dut.x=10'd910;
        dut.y=9'd42;
        bit_plane=1;
        advance_dot();
        if (dut.x!==0 || dut.y!==43) begin
            $display("bitmap entry missed line wrap x=%0d y=%0d",dut.x,dut.y);
            errors=errors+1;
        end
        // The reverse transition still finishes a complete PAL text line.
        @(negedge clk);
        dut.x=10'd910;
        dut.y=9'd43;
        bit_plane=0;
        advance_dot();
        if (dut.x!==911 || dut.y!==43) begin
            $display("text entry shortened line x=%0d y=%0d",dut.x,dut.y);
            errors=errors+1;
        end
        advance_dot();
        if (dut.x!==0 || dut.y!==44) begin
            $display("text line missed wrap x=%0d y=%0d",dut.x,dut.y);
            errors=errors+1;
        end
        // Bitmap fields must align to HDMI even when text left the native
        // raster at an arbitrary phase.
        @(negedge clk);
        dut.x=10'd700;
        dut.y=9'd100;
        bit_plane=1;
        hdmi_frame_start=1;
        repeat (4) @(negedge clk);
        hdmi_frame_start=0;
        repeat (2) @(negedge clk);
        if (dut.y!==9'd18 || dut.x>10'd2 || dut.native_top!==9'd43 ||
            dut.pal_60_line_phase!==2'd1) begin
            $display("bitmap frame did not align x=%0d y=%0d",
                     dut.x,dut.y);
            errors=errors+1;
        end
        @(negedge clk);
        dut.x=10'd700;
        dut.y=9'd100;
        hdmi_frame_start=1;
        repeat (4) @(negedge clk);
        hdmi_frame_start=0;
        repeat (2) @(negedge clk);
        if (dut.y!==9'd18 || dut.x>10'd2) begin
            $display("later HDMI frame did not restart raster");
            errors=errors+1;
        end
        active_height=8'd225;
        #1;
        if(dut.native_top!==9'd26 || dut.y!==9'd18)begin
            $display("225-line native picture begins at wrong GIME scanline");
            errors=errors+1;
        end
        if (errors) $display("tb_gime_pal_60_mode_switch FAIL: %0d",errors);
        else $display("tb_gime_pal_60_mode_switch PASS");
        $finish;
    end
endmodule
