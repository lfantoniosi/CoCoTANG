`timescale 1ns/1ps
module tb_coco3_video_mux;
    reg clk=0,reset_n=0,cpu_reset_n=0;
    always #5 clk=!clk;

    reg video_memory_valid=0;
    reg [15:0] cpu_addr=16'hffff;
    reg cpu_rw_n=1;
    reg [7:0] cpu_data=8'hff;
    wire video_memory_request;
    wire [22:0] video_memory_addr;
    reg [9:0] hdmi_source_x=0;
    reg [7:0] hdmi_source_y=0;
    reg hdmi_source_valid=0;
    wire [5:0] hdmi_pixel_data;
    integer errors=0;
    integer delay_count;
    reg [22:0] held_addr;

    coco3 dut(
        .clk(clk),.reset_n(reset_n),.cpu_reset_n(cpu_reset_n),.s2(1'b0),
        .cpu_addr(cpu_addr),.cpu_rw_n(cpu_rw_n),.cpu_data(cpu_data),
        .serint_n(1'b1),.keyint_n(1'b1),.cart_n(1'b1),
        .irq_assert(),.firq_assert(),.sam_s(),.e(),.q(),.e_rise(),.e_fall(),
        .cpu_mem_read(),.cpu_mem_write(),.cpu_mem_is_rom(),.cpu_mem_addr(),
        .core_rdata(),.core_data_oe(),
        .video_memory_data(8'h00),.video_memory_data32(32'h00000000),
        .video_memory_valid(video_memory_valid),
        .video_memory_request(video_memory_request),
        .video_memory_addr(video_memory_addr),.active_height(),
        .compatibility_video(),
        .hs_n(),.fs_n(),.red(),.green(),.blue(),.border_rgb(),
        .hblank(),.vblank(),.framebuffer_write(),.framebuffer_write_addr(),
        .framebuffer_write_data(),
        .hdmi_read_clk(clk),.hdmi_source_x(hdmi_source_x),
        .hdmi_source_y(hdmi_source_y),.hdmi_source_valid(hdmi_source_valid),
        .hdmi_prefetch_y(8'd1),.hdmi_prefetch_valid(1'b0),
        .hdmi_pixel_data(hdmi_pixel_data),
        .cvbs_read_clk(clk),.cvbs_source_x(10'd0),.cvbs_source_y(8'd0),
        .cvbs_source_valid(1'b0),.cvbs_prefetch_y(8'd0),
        .cvbs_prefetch_valid(1'b0),.cvbs_pixel_data()
    );

    initial begin
        repeat(4) @(posedge clk);
        reset_n=1; cpu_reset_n=1; hdmi_source_valid=1;
        wait(video_memory_request);
        held_addr=video_memory_addr;
        // An interleaved SDRAM slot may arrive many clocks after selection.
        // The mux must retain both request and address until acknowledge.
        for(delay_count=0;delay_count<12;delay_count=delay_count+1) begin
            @(posedge clk); #1;
            if(!video_memory_request || video_memory_addr!=held_addr)
                errors=errors+1;
        end
        video_memory_valid=1;
        @(posedge clk); #1;
        video_memory_valid=0;
        @(posedge clk); #1;
        if(video_memory_request) errors=errors+1;

        // Enter the ROM's CoCo-compatible startup mode.  Native LPR=000 is
        // one raster per row, but compatible alpha text must retain the
        // MC6847 twelve-raster character cell.
        cpu_addr=16'hff90; cpu_data=8'hc0; cpu_rw_n=0;
        repeat(100) @(posedge clk);
        cpu_rw_n=1;
        repeat(3) @(posedge clk); #1;
        if(!dut.compatibility_mode ||
           dut.effective_lines_per_row_code!=3'b111 ||
           dut.effective_bit_plane!=1'b0 || dut.effective_hres!=3'b000)
            errors=errors+1;
        if(errors==0) $display("tb_coco3_video_mux PASS");
        else $display("tb_coco3_video_mux FAIL: %0d",errors);
        $finish;
    end
endmodule
