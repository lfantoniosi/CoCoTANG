`timescale 1ns/1ps
module tb_gime_native_video #(
    parameter integer PAL_MACHINE=0
);
    reg clk=0,reset_n=0,video_50hz=0;
    wire hs_n,fs_n,hborder_irq_n,hblank,vblank;
    wire compatibility_sample;
    integer errors=0;
    integer raster_ticks=0;
    integer frames=0;
    reg saw_hborder_at_830=0;

    always #5 clk=!clk;

    gime_native_video #(.PAL_MACHINE(PAL_MACHINE)) dut(
        .clk(clk),.reset_n(reset_n),.video_50hz(video_50hz),
        .active_height(8'd192),.compatibility_mode(1'b0),
        .compatibility_css(1'b0),
        .pixel_rgb(6'd0),.hs_n(hs_n),.fs_n(fs_n),
        .compatibility_sample(compatibility_sample),
        .hborder_irq_n(hborder_irq_n),
        .hblank(hblank),.vblank(vblank),.red(),.green(),.blue());

    always @(posedge clk) begin
        if(reset_n&&compatibility_sample)begin
            $display("native hires emitted a VDG CSS sample");errors=errors+1;
        end
        if (reset_n && dut.raster_tick) begin
            raster_ticks=raster_ticks+1;
            // Sequential outputs reflect the preceding dot here.
            if (!hborder_irq_n && dut.x==10'd831)
                saw_hborder_at_830=1;
            if (dut.y==dut.frame_last_line && dut.x==dut.half_line_dot) begin
                frames=frames+1;
                if ((!video_50hz && raster_ticks!=(PAL_MACHINE ? 239400 : 238875)) ||
                    (video_50hz && raster_ticks!=(PAL_MACHINE ? 285000 : 284375))) begin
                    $display("native frame %0d h50=%0d was %0d dots",
                             frames,video_50hz,raster_ticks);
                    errors=errors+1;
                end
                raster_ticks=0;
                if (frames==1) begin
                    video_50hz=1'b1;
                end else if (frames==2) begin
                    if (!saw_hborder_at_830) begin
                        $display("HBORD interrupt did not assert at dot 830");
                        errors=errors+1;
                    end
                    if (errors==0) $display("tb_gime_native_video PASS");
                    else $display("tb_gime_native_video FAIL: %0d",errors);
                    $finish;
                end
            end
            if (dut.y==dut.frame_last_line && dut.x>dut.half_line_dot) begin
                $display("native half-line overran at x=%0d",dut.x);
                errors=errors+1;
            end
        end
    end

    initial begin
        repeat(3) @(posedge clk);
        reset_n=1;
        #1;
        if (PAL_MACHINE && dut.RASTER_STEP!=32'd566697074) begin
            $display("PAL cache raster is not locked to 576p");
            errors=errors+1;
        end
        if (dut.top!=9'd25) begin
            $display("192-line body top was %0d, expected 25",dut.top);
            errors=errors+1;
        end
        force dut.active_height=8'd225; #1;
        if (dut.top!=9'd8) begin
            $display("225-line body top was %0d, expected 8",dut.top);
            errors=errors+1;
        end
        release dut.active_height;
        video_50hz=1'b1; #1;
        if (dut.top!=9'd48 || dut.frame_last_line!=9'd312) begin
            $display("50Hz geometry top=%0d last=%0d",dut.top,
                     dut.frame_last_line);
            errors=errors+1;
        end
        video_50hz=1'b0;
        // One 262.5-line and one 312.5-line frame.
        repeat(4300000) @(posedge clk);
        $display("tb_gime_native_video timeout");
        $finish;
    end
endmodule
