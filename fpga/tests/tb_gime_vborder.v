`timescale 1ns/1ps
module tb_gime_vborder;
    reg clk=0,reset_n=0,video_50hz=0,compatibility_mode=0;
    reg [7:0] active_height=192,vmode=8'h80;
    reg [3:0] hres=4'b0111;
    wire fs_n,vborder_irq_n,irq_assert;
    integer vb_count=0,irq_count=0,fs_count=0;
    reg prior_vb=1,prior_irq=0,prior_fs=1;
    always #5 clk=~clk;
    gime_native_video video(
        .clk(clk),.reset_n(reset_n),.video_50hz(video_50hz),
        .bit_plane(1'b1),.hres(hres),.vmode(vmode),
        .hdmi_frame_start(1'b0),.hdmi_active_50hz(video_50hz),
        .active_height(active_height),.compatibility_mode(compatibility_mode),
        .compatibility_css(1'b0),.compatibility_border_rgb(6'd0),
        .pixel_rgb(6'd0),.fs_n(fs_n),.vborder_irq_n(vborder_irq_n));
    // Read/acknowledge FF92 after each IRQ assertion so independently
    // generated requests can be counted. FS is absent from this input.
    gime_registers registers(
        .clk(clk),.reset_n(reset_n),.e(1'b1),.e_fall(irq_assert),
        .cpu_addr(16'hff92),.cpu_rw_n(1'b1),.cpu_data(8'd0),
        .serint_n(1'b1),.keyint_n(1'b1),.cart_n(1'b1),
        .hs_n(1'b1),.fs_n(vborder_irq_n),.irq_assert(irq_assert));
    always @(negedge clk) begin
        if(!reset_n) begin
            prior_vb=1;prior_irq=0;prior_fs=1;
        end else begin
            if(prior_vb&&!vborder_irq_n) begin
                vb_count=vb_count+1;
                if(compatibility_mode) begin
                    if(video.compatibility_y!=video.compatibility_bottom ||
                       video.compatibility_x!=video.vb_irq_position+1)
                        $fatal(1,"Compatibility VBORD position");
                end else if(video.y!=video.native_bottom ||
                            video.x!=video.vb_irq_position+1)
                    $fatal(1,"Native VBORD position");
            end
            if(!prior_irq&&irq_assert) irq_count=irq_count+1;
            if(prior_fs&&!fs_n) begin
                fs_count=fs_count+1;
                if(!vborder_irq_n || irq_assert)
                    $fatal(1,"FS generated a VBORD request");
            end
            prior_vb=vborder_irq_n;prior_irq=irq_assert;prior_fs=fs_n;
        end
    end
    task check_fields;
        input [7:0] height;
        input compat,h50;
        input [3:0] hr;
        input [7:0] mode;
        input integer expected_x;
        integer ticks;
        begin
            @(posedge clk); #1; reset_n=0;
            active_height=height;compatibility_mode=compat;video_50hz=h50;
            hres=hr;vmode=mode;
            repeat(3) @(posedge clk);
            #1;reset_n=1;vb_count=0;irq_count=0;fs_count=0;
            force video.raster_tick=1;
            force video.compatibility_raster_tick=1;
            force registers.init0=8'h20;
            force registers.irq_enable=6'h08;
            if(video.vb_irq_position!=expected_x) $fatal(1,"VBORD dot selection");
            // First field uses reset's 60 Hz terminal; the second latches
            // H50. Both must generate exactly one end-of-picture request.
            ticks=compat ? (h50 ? 262*912+312*912 : 524*912) :
                          (h50 ? 238875+284375 : 477750);
            repeat(ticks) @(posedge clk);
            #1;
            if(vb_count!=2 || irq_count!=2 || fs_count!=2)
                $fatal(1,"height=%0d compat=%0d h50=%0d VB=%0d IRQ=%0d FS=%0d",
                    height,compat,h50,vb_count,irq_count,fs_count);
        end
    endtask
    initial begin
        check_fields(192,0,0,7,8'h80,163);
        check_fields(199,0,0,0,8'h80,221);
        check_fields(225,0,0,1,8'h00,161);
        check_fields(192,0,1,4,8'h80,227);
        check_fields(192,1,0,7,8'h80,221);
        $display("GIME VBORD position, one IRQ per field, independent FS PASS");
        $finish;
    end
endmodule
