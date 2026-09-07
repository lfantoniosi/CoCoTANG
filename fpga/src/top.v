module top #(
 parameter integer ANALOG_VIDEO_MODE = 1
) (
 input clkin,input s1,input s2,input [7:0] mp,output [1:0] msel,
 inout [7:0] cpu_data,input irq_n_in,input firq_n_in,input audio_in,
 output halt_drive,output e_out,output q_out,output hs_n,output fs_n,output [2:0] sam_s,
 output y_out,output pb_out,output pr_out,
 output tmds_clk_p,output tmds_clk_n,output [2:0] tmds_data_p,output [2:0] tmds_data_n,
 output mspi_sclk,output mspi_cs,output mspi_mosi,input mspi_miso,
 output O_sdram_clk,output O_sdram_cke,output O_sdram_cs_n,output O_sdram_cas_n,
 output O_sdram_ras_n,output O_sdram_wen_n,inout [31:0] IO_sdram_dq,
 output [10:0] O_sdram_addr,output [1:0] O_sdram_ba,output [3:0] O_sdram_dqm
);
 wire clk108,clk108p,clk270,clk135,board_reset_n,clocks_locked;
 coco_clocks clocks(.clkin(clkin),.button_reset(s1),.clk108(clk108),.clk108p(clk108p),
  .clk270(clk270),.clk135(clk135),.board_reset_n(board_reset_n),.clocks_locked(clocks_locked));

 wire [15:0] address; wire rw_n,cpu_reset_n,slenb_n,sernt_n,cart_n,keyint_n;
 wire cpu_halt_n,nmi_n,bus_snapshot_valid;
 coco_bus_mux bus_mux(.clk(clk108),.reset_n(board_reset_n),.mp(mp),.msel(msel),
  .addr(address),.rw_n(rw_n),.cpu_reset_n(cpu_reset_n),.slenb_n(slenb_n),
  .sernt_n(sernt_n),.cart_n(cart_n),.keyint_n(keyint_n),.halt_n(cpu_halt_n),
  .nmi_n(nmi_n),.snapshot_valid(bus_snapshot_valid));
 wire [2:0] filtered_interrupts;
 input_filter #(.WIDTH(3)) interrupt_filter(.clk(clk108),.reset_n(board_reset_n),
  .in({irq_n_in,firq_n_in,audio_in}),.out(filtered_interrupts));

 wire e_rise,e_fall; wire [2:0] video_mode; wire [6:0] video_offset;
 wire page,all_ram; wire [1:0] rate,memory_size;
 coco_sam sam(.clk(clk108),.reset_n(board_reset_n && cpu_reset_n),.addr(address),.rw_n(rw_n),
  .s(sam_s),.e(e_out),.q(q_out),.e_rise(e_rise),.e_fall(e_fall),
  .video_mode(video_mode),.video_offset(video_offset),.page(page),.rate(rate),
  .memory_size(memory_size),.all_ram(all_ram));

 wire sdram_reset_n,loader_start,system_ready,sdram_enabled,loader_done;
 coco_startup startup(.clk(clk108),.board_reset_n(board_reset_n),.sdram_enabled(sdram_enabled),
  .loader_done(loader_done),.sdram_reset_n(sdram_reset_n),.loader_start(loader_start),
  .system_ready(system_ready));
 assign halt_drive=!system_ready;

 wire sd_rd,sd_wr,sd_refresh,sd_data_ready,sd_busy; wire [22:0] sd_addr;
 wire [15:0] sd_din,sd_dout; wire [1:0] sd_wdm; wire [31:0] unused_sd_dout32;
 sdram sdram_controller(.SDRAM_DQ(IO_sdram_dq),.SDRAM_A(O_sdram_addr),.SDRAM_BA(O_sdram_ba),
  .SDRAM_nCS(O_sdram_cs_n),.SDRAM_nWE(O_sdram_wen_n),.SDRAM_nRAS(O_sdram_ras_n),
  .SDRAM_nCAS(O_sdram_cas_n),.SDRAM_CLK(O_sdram_clk),.SDRAM_CKE(O_sdram_cke),
  .SDRAM_DQM(O_sdram_dqm),.clk(clk108),.clk_sdram(clk108p),.resetn(sdram_reset_n),
  .rd(sd_rd),.wr(sd_wr),.refresh(sd_refresh),.addr(sd_addr),.din(sd_din),.wdm(sd_wdm),
  .dout(sd_dout),.dout32(unused_sd_dout32),.data_ready(sd_data_ready),.busy(sd_busy),
  .enabled(sdram_enabled));

 wire [15:0] video_memory_addr; wire [7:0] video_memory_data,cpu_read_data; wire cpu_data_oe;
 coco_memory memory(.clk(clk108),.reset_n(sdram_reset_n),.loader_start(loader_start),
  .e(e_out),.e_rise(e_rise),.e_fall(e_fall),.cpu_addr(address),.cpu_wdata(cpu_data),
  .cpu_rw_n(rw_n),.cpu_select(sam_s),.cpu_rdata(cpu_read_data),.cpu_data_oe(cpu_data_oe),
  .video_addr(video_memory_addr),.video_data(video_memory_data),.loader_done(loader_done),
  .mspi_cs(mspi_cs),.mspi_sclk(mspi_sclk),.mspi_miso(mspi_miso),.mspi_mosi(mspi_mosi),
  .sdram_enabled(sdram_enabled),.sd_rd(sd_rd),.sd_wr(sd_wr),.sd_refresh(sd_refresh),
  .sd_addr(sd_addr),.sd_din(sd_din),.sd_wdm(sd_wdm),.sd_dout(sd_dout),
  .sd_data_ready(sd_data_ready),.sd_busy(sd_busy));
 assign cpu_data=cpu_data_oe?cpu_read_data:8'bz;

 wire [7:0] vdg_red,vdg_green,vdg_blue,vdg_cvbs; wire vdg_hblank,vdg_vblank;
 wire framebuffer_write; wire [15:0] framebuffer_write_addr; wire [5:0] framebuffer_write_data;
 coco_vdg vdg(.clk(clk108),.reset_n(board_reset_n && cpu_reset_n),.e_fall(e_fall),
  .cpu_rw_n(rw_n),.cpu_addr(address),.cpu_data(cpu_data),.sam_video_mode(video_mode),
  .sam_video_offset(video_offset),.memory_data(video_memory_data),.memory_addr(video_memory_addr),
  .hs_n(hs_n),.fs_n(fs_n),.red(vdg_red),.green(vdg_green),.blue(vdg_blue),
  .hblank(vdg_hblank),.vblank(vdg_vblank),.cvbs(vdg_cvbs),.pixel_capture(framebuffer_write),
  .capture_addr(framebuffer_write_addr),.capture_rgb(framebuffer_write_data));
 wire [15:0] framebuffer_read_addr; wire [5:0] framebuffer_read_data;
 coco_framebuffer framebuffer(.write_clk(clk108),.write_en(framebuffer_write),
  .write_addr(framebuffer_write_addr),.write_data(framebuffer_write_data),.read_clk(clkin),
  .read_addr(framebuffer_read_addr),.read_data(framebuffer_read_data));
 coco_hdmi hdmi_output(.pixel_clk(clkin),.serial_clk(clk135),.reset(!board_reset_n),
  .framebuffer_data(framebuffer_read_data),.framebuffer_addr(framebuffer_read_addr),
  .tmds_clk_p(tmds_clk_p),.tmds_clk_n(tmds_clk_n),.tmds_data_p(tmds_data_p),
  .tmds_data_n(tmds_data_n));
 generate
  if (ANALOG_VIDEO_MODE == 0) begin : component_video
   coco_analog_video #(.OUTPUT_MODE(0)) analog_output(
    .clk270(clk270),.reset_n(board_reset_n),
    .red(vdg_red),.green(vdg_green),.blue(vdg_blue),.hblank(vdg_hblank),
    .vblank(vdg_vblank),.hs_n(hs_n),.y_out(y_out),.pb_out(pb_out),.pr_out(pr_out));
  end else begin : ntsc_video
   wire [15:0] cvbs_framebuffer_addr;
   wire [5:0] cvbs_framebuffer_data;
   coco_framebuffer cvbs_framebuffer(.write_clk(clk108),.write_en(framebuffer_write),
    .write_addr(framebuffer_write_addr),.write_data(framebuffer_write_data),.read_clk(clk135),
    .read_addr(cvbs_framebuffer_addr),.read_data(cvbs_framebuffer_data));
   coco_cvbs_ntsc encoder(.clk135(clk135),.clk270(clk270),.reset_n(board_reset_n),
    .framebuffer_data(cvbs_framebuffer_data),.framebuffer_addr(cvbs_framebuffer_addr),
    .luma_out(y_out),.chroma_out(pb_out),.cvbs_out(pr_out));
  end
 endgenerate
endmodule
