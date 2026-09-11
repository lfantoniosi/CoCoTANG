module top #(
 parameter integer COCO_MODEL = 2,
 parameter integer ANALOG_VIDEO_MODE = 1,
 parameter integer SDRAM_TEST_FILL = 0,
 parameter integer DEBUG_S2_VIDEO_MODE = 0,
 parameter integer DEBUG_HDMI_OVERLAY = 1,
 parameter integer DEBUG_CPU_BOOT_LOOP = 0,
 parameter integer DEBUG_DATA_BUS_SWEEP = 0
) (
 input clkin,input s1,input s2,input [7:0] mp,output [1:0] msel,
 inout [7:0] cpu_data,input irq_n_in,input firq_n_in,input audio_in,
 output halt_drive,output e_out,output q_out,output hs_n,output fs_n,output [2:0] sam_s,
 output y_out,output pb_out,
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
 wire e_rise,e_fall;
 wire cpu_halt_n,nmi_n,bus_snapshot_ready_async;
 // Q leads E on the 6809E and its address is guaranteed valid at Q rising.
 // Launch the mux scan there to maximize read-data setup before E falls.
 reg q_scan_delay=1'b0;
 always @(posedge clk270 or negedge board_reset_n) begin
  if (!board_reset_n) q_scan_delay<=1'b0;
  else q_scan_delay<=q_out;
 end
 wire bus_scan_start=q_out && !q_scan_delay;
 coco_bus_mux bus_mux(.clk(clk270),.reset_n(board_reset_n),.mp(mp),.msel(msel),
  .scan_start(bus_scan_start),
  .addr(address),.rw_n(rw_n),.cpu_reset_n(cpu_reset_n),.slenb_n(slenb_n),
  .sernt_n(sernt_n),.cart_n(cart_n),.keyint_n(keyint_n),.halt_n(cpu_halt_n),
  .nmi_n(nmi_n),.snapshot_valid(bus_snapshot_ready_async));
 reg bus_ready_meta=1'b0,bus_ready_sync=1'b0,bus_ready_delay=1'b0;
 always @(posedge clk108 or negedge board_reset_n) begin
  if (!board_reset_n) begin
   bus_ready_meta<=1'b0; bus_ready_sync<=1'b0; bus_ready_delay<=1'b0;
  end else begin
   bus_ready_meta<=bus_snapshot_ready_async;
   bus_ready_sync<=bus_ready_meta;
   bus_ready_delay<=bus_ready_sync;
  end
 end
 wire bus_snapshot_valid=bus_ready_sync && !bus_ready_delay;
 wire [2:0] filtered_interrupts;
 input_filter #(.WIDTH(3)) interrupt_filter(.clk(clk108),.reset_n(board_reset_n),
  .in({irq_n_in,firq_n_in,audio_in}),.out(filtered_interrupts));

 wire sdram_reset_n,loader_start,system_ready,sdram_enabled,loader_done;
 coco_startup startup(.clk(clk108),.board_reset_n(board_reset_n),.sdram_enabled(sdram_enabled),
  .loader_done(loader_done),.sdram_reset_n(sdram_reset_n),.loader_start(loader_start),
  .system_ready(system_ready));
 // Q2 has been rewired to the CPU RESET input on the prototype.  Release it
 // only at E falling so reset recovery gets a complete E-low/Q setup interval
 // before the 6809E begins fetching its vector.
 reg cpu_release=1'b0;
 always @(posedge clk108 or negedge board_reset_n) begin
  if (!board_reset_n)
   cpu_release<=1'b0;
  else if (e_fall && system_ready)
   cpu_release<=1'b1;
 end
 assign halt_drive=!cpu_release;

 wire sd_rd,sd_wr,sd_refresh,sd_data_ready,sd_busy; wire [22:0] sd_addr;
 wire [15:0] sd_din,sd_dout; wire [1:0] sd_wdm; wire [31:0] sd_dout32;
 sdram sdram_controller(.SDRAM_DQ(IO_sdram_dq),.SDRAM_A(O_sdram_addr),.SDRAM_BA(O_sdram_ba),
  .SDRAM_nCS(O_sdram_cs_n),.SDRAM_nWE(O_sdram_wen_n),.SDRAM_nRAS(O_sdram_ras_n),
  .SDRAM_nCAS(O_sdram_cas_n),.SDRAM_CLK(O_sdram_clk),.SDRAM_CKE(O_sdram_cke),
  .SDRAM_DQM(O_sdram_dqm),.clk(clk108),.clk_sdram(clk108p),.resetn(sdram_reset_n),
  .rd(sd_rd),.wr(sd_wr),.refresh(sd_refresh),.addr(sd_addr),.din(sd_din),.wdm(sd_wdm),
  .dout(sd_dout),.dout32(sd_dout32),.data_ready(sd_data_ready),.busy(sd_busy),
  .enabled(sdram_enabled));

 wire cpu_mem_read,cpu_mem_write,cpu_mem_is_rom;
 wire cpu_access_enable=system_ready && cpu_reset_n && cpu_halt_n;
 wire memory_cpu_read=cpu_access_enable && cpu_mem_read;
 wire memory_cpu_write=cpu_access_enable && cpu_mem_write;
 wire [22:0] cpu_mem_addr,video_memory_addr;
 wire [7:0] video_memory_data,cpu_read_data,core_read_data;
 wire [31:0] video_memory_data32;
 wire cpu_data_oe,core_data_oe,video_memory_valid,video_memory_request;
 wire debug_cpu_req,debug_cpu_ack;
 coco_memory #(.TEST_FILL(SDRAM_TEST_FILL),
  .ROM_BYTES(COCO_MODEL == 3 ? 32768 : 16384)) memory(
  .clk(clk108),.reset_n(sdram_reset_n),.loader_start(loader_start),
  .cpu_access_enable(cpu_access_enable),
  .cpu_bus_valid(bus_snapshot_valid),
  .e(e_out),.q(q_out),.e_rise(e_rise),.e_fall(e_fall),.cpu_wdata(cpu_data),
  .cpu_mem_read(cpu_mem_read),.cpu_mem_write(cpu_mem_write),
  .cpu_mem_is_rom(cpu_mem_is_rom),.cpu_mem_addr(cpu_mem_addr),
  .cpu_rdata(cpu_read_data),.cpu_data_oe(cpu_data_oe),
  .debug_cpu_req(debug_cpu_req),.debug_cpu_ack(debug_cpu_ack),
  .video_read_request(video_memory_request),
  .video_addr(video_memory_addr),.video_data(video_memory_data),
  .video_data32(video_memory_data32),
  .video_data_valid(video_memory_valid),.loader_done(loader_done),
  .mspi_cs(mspi_cs),.mspi_sclk(mspi_sclk),.mspi_miso(mspi_miso),.mspi_mosi(mspi_mosi),
  .sdram_enabled(sdram_enabled),.sd_rd(sd_rd),.sd_wr(sd_wr),.sd_refresh(sd_refresh),
  .sd_addr(sd_addr),.sd_din(sd_din),.sd_wdm(sd_wdm),.sd_dout(sd_dout),
  .sd_dout32(sd_dout32),
  .sd_data_ready(sd_data_ready),.sd_busy(sd_busy));
 // Temporary CPU-interface diagnostics. Mode 1 is the minimal two-byte
 // "BRA -2" delivery test.  A CPU that
 // sees both bytes can only alternate fetches at $E000 and $E001.  Mode 2
 // exercises immediate/indexed/extended addressing and writes.  Mode 3 is
 // an extended-indirect jump test: JMP [$E010], where $E010 contains $E040.
 // A CPU that receives every byte must read E000-E003, then the pointer at
 // E010-E011, and finally execute the BRA -2 loop at E040-E041.
 // Keep the diagnostic program in the physical ROM window: the prototype's
 // U12 data-buffer enable is qualified by the board ROM/EXTROM decode, so an
 // internally asserted FPGA OE at $0000 does not put data on the CPU bus.
 // The reset-vector bytes must not be qualified by cpu_access_enable.  That
 // term contains RESET/HALT sampled through the same external mux and becomes
 // valid too late for the first FFFE access after reset release.  Driving 00
 // at FFFE/FFFF while reset is still asserted is harmless.
 wire debug_boot_vector_oe=(DEBUG_CPU_BOOT_LOOP != 0) && rw_n &&
                           (address == 16'hfffe || address == 16'hffff);
 wire debug_boot_program_address=
      ((DEBUG_CPU_BOOT_LOOP == 1) &&
       (address >= 16'he000 && address <= 16'he001)) ||
      ((DEBUG_CPU_BOOT_LOOP == 2) &&
       (address >= 16'he000 && address <= 16'he013)) ||
      ((DEBUG_CPU_BOOT_LOOP == 3) &&
       ((address >= 16'he000 && address <= 16'he003) ||
        (address >= 16'he010 && address <= 16'he011) ||
        (address >= 16'he040 && address <= 16'he041)));
 wire debug_boot_program_oe=(DEBUG_CPU_BOOT_LOOP != 0) &&
                            cpu_access_enable && rw_n &&
                            debug_boot_program_address;
 wire debug_boot_address_oe=debug_boot_vector_oe || debug_boot_program_oe;
 reg [7:0] debug_boot_data;
 always @(*) begin
  // 6809 vectors are big endian: FFFE=$E0, FFFF=$00 -> reset PC=$E000.
  debug_boot_data=8'h00;
  if (address == 16'hfffe) begin
   debug_boot_data=8'he0;
  end else if (address == 16'hffff) begin
   debug_boot_data=8'h00;
  end else if (DEBUG_CPU_BOOT_LOOP == 1) begin
   if (address == 16'he000) debug_boot_data=8'h20;      // BRA -2
   else if (address == 16'he001) debug_boot_data=8'hfe;
  end else if (DEBUG_CPU_BOOT_LOOP == 2) begin
   case (address)
    16'he000: debug_boot_data=8'h8e; // LDX #$FF20
    16'he001: debug_boot_data=8'hff;
    16'he002: debug_boot_data=8'h20;
    16'he003: debug_boot_data=8'h6f; // CLR -3,X -> $FF1D
    16'he004: debug_boot_data=8'h1d;
    16'he005: debug_boot_data=8'h6f; // CLR -1,X -> $FF1F
    16'he006: debug_boot_data=8'h1f;
    16'he007: debug_boot_data=8'h86; // LDA #$96
    16'he008: debug_boot_data=8'h96;
    16'he009: debug_boot_data=8'hb7; // STA $1234
    16'he00a: debug_boot_data=8'h12;
    16'he00b: debug_boot_data=8'h34;
    16'he00c: debug_boot_data=8'h86; // LDA #$69
    16'he00d: debug_boot_data=8'h69;
    16'he00e: debug_boot_data=8'hb7; // STA $5678
    16'he00f: debug_boot_data=8'h56;
    16'he010: debug_boot_data=8'h78;
    16'he011: debug_boot_data=8'h7e; // JMP $E000
    16'he012: debug_boot_data=8'he0;
    16'he013: debug_boot_data=8'h00;
    default: debug_boot_data=8'h00;
   endcase
  end else if (DEBUG_CPU_BOOT_LOOP == 3) begin
   case (address)
    16'he000: debug_boot_data=8'h6e; // JMP [$E010]
    16'he001: debug_boot_data=8'h9f; // indexed-indirect extended postbyte
    16'he002: debug_boot_data=8'he0;
    16'he003: debug_boot_data=8'h10;
    16'he010: debug_boot_data=8'he0; // indirect destination = $E040
    16'he011: debug_boot_data=8'h40;
    16'he040: debug_boot_data=8'h20; // BRA -2: stay visibly at $E040
    16'he041: debug_boot_data=8'hfe;
    default: debug_boot_data=8'h00;
   endcase
  end
 end
 wire debug_boot_data_oe=debug_boot_address_oe;
 // The diagnostic ROM must override the normal core/SDRAM ROM at the same
 // addresses; otherwise both OEs assert and the old priority silently feeds
 // the loaded ROM byte instead of debug_boot_data.
 // CPU-socket/transceiver isolation test.  With the CPU removed and the
 // motherboard R/W signal tied high, U12 points from its FPGA A side toward
 // its CPU B side.  Once normal startup has released reset, present every
 // possible byte for 4 ms and repeat continuously.  The deliberately slow
 // sweep permits all eight CPU data pins to be checked with an 8-channel
 // analyzer at only 20 kHz; no E/Q probe is required.  S=000 is forced below
 // so the motherboard asserts /MRD and enables U12.
 reg [7:0] debug_sweep_data=8'h00;
 reg debug_sweep_active=1'b0;
 reg [18:0] debug_sweep_hold_count=19'd0;
 always @(posedge clk108 or negedge board_reset_n) begin
  if (!board_reset_n) begin
   debug_sweep_data<=8'h00;
   debug_sweep_active<=1'b0;
   debug_sweep_hold_count<=19'd0;
  end else if (DEBUG_DATA_BUS_SWEEP != 0) begin
   if (!debug_sweep_active) begin
    if (cpu_release && e_fall) begin
     debug_sweep_data<=8'h00;
     debug_sweep_active<=1'b1;
     debug_sweep_hold_count<=19'd0;
    end
   end else if (debug_sweep_hold_count == 19'd431999) begin
    debug_sweep_hold_count<=19'd0;
    debug_sweep_data<=debug_sweep_data+1'b1;
   end else begin
    debug_sweep_hold_count<=debug_sweep_hold_count+1'b1;
   end
  end
 end
 wire [7:0] fpga_read_data=debug_sweep_active ? debug_sweep_data :
                           debug_boot_data_oe ? debug_boot_data :
                           core_data_oe ? core_read_data : cpu_read_data;
 wire fpga_data_oe=debug_sweep_active || core_data_oe ||
                   debug_boot_data_oe || cpu_data_oe;
 assign cpu_data=fpga_data_oe ? fpga_read_data : 8'bz;

 wire [7:0] vdg_red,vdg_green,vdg_blue; wire vdg_hblank,vdg_vblank;
 wire [5:0] vdg_border_rgb;
 wire [7:0] video_active_height;
 wire framebuffer_write; wire [15:0] framebuffer_write_addr; wire [5:0] framebuffer_write_data;
 wire [15:0] framebuffer_read_addr,cvbs_framebuffer_addr;
 wire [5:0] framebuffer_read_data,cvbs_framebuffer_data;
 wire [9:0] hdmi_source_x,cvbs_source_x;
 wire [7:0] hdmi_source_y,cvbs_source_y,hdmi_prefetch_y,cvbs_prefetch_y;
 wire hdmi_source_valid,cvbs_source_valid,hdmi_prefetch_valid,cvbs_prefetch_valid;
 wire [5:0] machine_hdmi_pixel,machine_cvbs_pixel;
 wire [2:0] machine_sam_s;
 // The external 74LS138 decodes 000 as the /MRD selection.  That directly
 // enables U12 pin 19 in the sweep fixture, independent of the absent CPU's
 // floating address bus.
 assign sam_s=(DEBUG_DATA_BUS_SWEEP != 0) ? 3'b000 : machine_sam_s;
 generate
  if (COCO_MODEL == 2) begin : coco2_machine
   coco2 #(.DEBUG_S2_VIDEO_MODE(DEBUG_S2_VIDEO_MODE),
           .DEBUG_CPU_SLOW((DEBUG_CPU_BOOT_LOOP != 0) ||
                           (DEBUG_DATA_BUS_SWEEP != 0))) machine(
    .clk(clk108),.reset_n(board_reset_n),.cpu_reset_n(cpu_reset_n),.s2(1'b0),
    .cpu_addr(address),.cpu_rw_n(rw_n),.cpu_data(cpu_data),
    .sam_s(machine_sam_s),.e(e_out),.q(q_out),.e_rise(e_rise),.e_fall(e_fall),
    .cpu_mem_read(cpu_mem_read),.cpu_mem_write(cpu_mem_write),
    .cpu_mem_is_rom(cpu_mem_is_rom),.cpu_mem_addr(cpu_mem_addr),
    .core_rdata(core_read_data),.core_data_oe(core_data_oe),
    .video_memory_data(video_memory_data),.video_memory_valid(video_memory_valid),
    .video_memory_request(video_memory_request),
    .video_memory_addr(video_memory_addr),.active_height(video_active_height),
    .hs_n(hs_n),.fs_n(fs_n),.red(vdg_red),.green(vdg_green),.blue(vdg_blue),
    .border_rgb(vdg_border_rgb),.hblank(vdg_hblank),.vblank(vdg_vblank),
    .framebuffer_write(framebuffer_write),
    .framebuffer_write_addr(framebuffer_write_addr),
    .framebuffer_write_data(framebuffer_write_data));
   assign machine_hdmi_pixel=framebuffer_read_data;
   assign machine_cvbs_pixel=cvbs_framebuffer_data;
  end else if (COCO_MODEL == 3) begin : coco3_machine
   coco3 #(.DEBUG_S2_VIDEO_MODE(DEBUG_S2_VIDEO_MODE)) machine(
    .clk(clk108),.reset_n(board_reset_n),.cpu_reset_n(cpu_reset_n),.s2(1'b0),
    .cpu_addr(address),.cpu_rw_n(rw_n),.cpu_data(cpu_data),
    .sam_s(machine_sam_s),.e(e_out),.q(q_out),.e_rise(e_rise),.e_fall(e_fall),
    .cpu_mem_read(cpu_mem_read),.cpu_mem_write(cpu_mem_write),
    .cpu_mem_is_rom(cpu_mem_is_rom),.cpu_mem_addr(cpu_mem_addr),
    .core_rdata(core_read_data),.core_data_oe(core_data_oe),
    .video_memory_data(video_memory_data),.video_memory_data32(video_memory_data32),
    .video_memory_valid(video_memory_valid),
    .video_memory_request(video_memory_request),
    .video_memory_addr(video_memory_addr),.active_height(video_active_height),
    .hs_n(hs_n),.fs_n(fs_n),.red(vdg_red),.green(vdg_green),.blue(vdg_blue),
    .border_rgb(vdg_border_rgb),.hblank(vdg_hblank),.vblank(vdg_vblank),
    .framebuffer_write(framebuffer_write),
    .framebuffer_write_addr(framebuffer_write_addr),
    .framebuffer_write_data(framebuffer_write_data),
    .hdmi_read_clk(clkin),.hdmi_source_x(hdmi_source_x),.hdmi_source_y(hdmi_source_y),
    .hdmi_source_valid(hdmi_source_valid),.hdmi_prefetch_y(hdmi_prefetch_y),
    .hdmi_prefetch_valid(hdmi_prefetch_valid),.hdmi_pixel_data(machine_hdmi_pixel),
    .cvbs_read_clk(clk135),.cvbs_source_x(cvbs_source_x),.cvbs_source_y(cvbs_source_y),
    .cvbs_source_valid(cvbs_source_valid),.cvbs_prefetch_y(cvbs_prefetch_y),
    .cvbs_prefetch_valid(cvbs_prefetch_valid),.cvbs_pixel_data(machine_cvbs_pixel));
  end else begin : unsupported_machine
   assign machine_sam_s = 3'd7;
   assign e_out = 1'b0;
   assign q_out = 1'b0;
   assign e_rise = 1'b0;
   assign e_fall = 1'b0;
   assign cpu_mem_read = 1'b0;
   assign cpu_mem_write = 1'b0;
   assign cpu_mem_is_rom = 1'b0;
   assign cpu_mem_addr = 23'd0;
   assign core_read_data = 8'hff;
   assign core_data_oe = 1'b0;
   assign video_memory_request = 1'b0;
   assign video_memory_addr = 23'd0;
   assign video_active_height = 8'd192;
   assign hs_n = 1'b1;
   assign fs_n = 1'b1;
   assign vdg_red = 8'd0;
   assign vdg_green = 8'd0;
   assign vdg_blue = 8'd0;
   assign vdg_border_rgb = 6'd0;
   assign vdg_hblank = 1'b1;
   assign vdg_vblank = 1'b1;
   assign framebuffer_write = 1'b0;
   assign framebuffer_write_addr = 16'd0;
   assign framebuffer_write_data = 6'd0;
   assign machine_hdmi_pixel=6'd0;
   assign machine_cvbs_pixel=6'd0;
  end
 endgenerate
 generate
  if (COCO_MODEL == 2) begin : coco2_frame_store
   coco_framebuffer framebuffer(.write_clk(clk108),.write_en(framebuffer_write),
    .write_addr(framebuffer_write_addr),.write_data(framebuffer_write_data),.read_clk(clk135),
    .hdmi_addr(framebuffer_read_addr),.hdmi_data(framebuffer_read_data),
    .cvbs_addr(cvbs_framebuffer_addr),.cvbs_data(cvbs_framebuffer_data));
  end else begin : no_frame_store
   assign framebuffer_read_data=6'd0;
   assign cvbs_framebuffer_data=6'd0;
  end
 endgenerate
 reg [15:0] debug_last_address=16'd0;
 reg [7:0] debug_last_data=8'd0;
 reg [15:0] debug_scan_count=16'd0,debug_cycle_count=16'd0;
 reg [15:0] debug_sdram_count=16'd0,debug_read_request_count=16'd0;
 reg [15:0] debug_read_ack_count=16'd0,debug_write_count=16'd0;
 reg [24:0] debug_refresh_count=25'd0;
 reg [39:0] debug_last_bus=40'd0;
 // Capture four display pages (4 * 116 cycles) beginning with the first
 // complete post-reset bus snapshot, then freeze the display.  The FPGA input can recognize the slow
 // reset RC edge thousands of CPU cycles before the 6809 does.
 reg debug_log_we=1'b0;
 reg [8:0] debug_log_addr=9'd0;
 reg [39:0] debug_log_data=40'd0;
 reg [8:0] debug_log_count=9'd0;
 reg debug_boot_started=1'b0;
 reg debug_log_frozen=1'b0;
 // A short S2 press selects the next 116-entry page.  A one-second hold
 // toggles overlay visibility and does not also advance the page on release.
 reg s2_meta=1'b0,s2_sync=1'b0,s2_state=1'b0;
 reg [20:0] s2_stable_count=21'd0;
 reg [26:0] s2_hold_count=27'd0;
 reg s2_long_handled=1'b0;
 reg [1:0] debug_log_page=2'd0;
 reg debug_visible=1'b1;
 reg [15:0] debug_cycle_address=16'd0;
 reg [7:0] debug_cycle_din=8'd0,debug_cycle_dout=8'd0;
 reg [2:0] debug_cycle_s=3'd0;
 reg debug_cycle_rw=1'b1,debug_cycle_oe_seen=1'b0;
 reg [319:0] hdmi_debug_data=320'd0;
 always @(posedge clk108 or negedge board_reset_n) begin
  if (!board_reset_n) begin
   debug_last_address<=0; debug_last_data<=0; debug_last_bus<=0;
   debug_scan_count<=0; debug_cycle_count<=0; debug_sdram_count<=0;
   debug_read_request_count<=0; debug_read_ack_count<=0; debug_write_count<=0;
   debug_refresh_count<=0; hdmi_debug_data<=0;
   debug_log_we<=0; debug_log_addr<=0; debug_log_data<=0;
   debug_log_count<=0; debug_boot_started<=1'b0; debug_log_frozen<=1'b0;
   s2_meta<=0; s2_sync<=0; s2_state<=0; s2_stable_count<=0;
   s2_hold_count<=0; s2_long_handled<=1'b0; debug_log_page<=2'd0;
   debug_visible<=1'b1;
   debug_cycle_address<=0; debug_cycle_din<=0; debug_cycle_dout<=0;
   debug_cycle_s<=0; debug_cycle_rw<=1'b1; debug_cycle_oe_seen<=1'b0;
  end else begin
   debug_log_we<=1'b0;
   // Capture only once after FPGA configuration.  Repeated CPU resets used
   // to clear and rewrite the live HDMI log RAM, making the LCD blink badly.
   // If reset returns after capture has begun, preserve that failing boot
   // trace until the FPGA itself is reconfigured or power-cycled.
   if (!cpu_reset_n) begin
    debug_boot_started<=1'b0;
    if (debug_log_count != 0)
     debug_log_frozen<=1'b1;
   end
   s2_meta<=s2;
   s2_sync<=s2_meta;
   if (s2_sync == s2_state) begin
    s2_stable_count<=0;
   end else if (s2_stable_count == 21'd1079999) begin
    s2_state<=s2_sync;
    s2_stable_count<=0;
    if (s2_sync) begin
     s2_hold_count<=0;
     s2_long_handled<=1'b0;
    end else begin
     if (!s2_long_handled)
      debug_log_page<=debug_log_page+1'b1;
     s2_hold_count<=0;
     s2_long_handled<=1'b0;
    end
   end else begin
    s2_stable_count<=s2_stable_count+1'b1;
   end
   if (s2_state && !s2_long_handled) begin
    if (s2_hold_count == 27'd107999999) begin
     debug_visible<=!debug_visible;
     s2_long_handled<=1'b1;
    end else begin
     s2_hold_count<=s2_hold_count+1'b1;
    end
   end
   debug_refresh_count<=debug_refresh_count+1'b1;
   if (bus_snapshot_valid) debug_scan_count<=debug_scan_count+1'b1;
   if (bus_snapshot_valid) begin
    // The Q-triggered mux scan completes before E rises, so replace the
    // provisional fields with this cycle's atomic snapshot.
    debug_cycle_address<=address;
    debug_cycle_rw<=rw_n;
    debug_cycle_s<=sam_s;
   end
   if (sd_data_ready) debug_sdram_count<=debug_sdram_count+1'b1;
   if (e_rise) begin
    debug_cycle_count<=debug_cycle_count+1'b1;
    debug_cycle_address<=address;
    debug_cycle_rw<=rw_n;
    debug_cycle_s<=sam_s;
    debug_cycle_din<=cpu_data;
    debug_cycle_dout<=8'd0;
    debug_cycle_oe_seen<=1'b0;
    if (memory_cpu_read && !debug_cpu_req)
     debug_read_request_count<=debug_read_request_count+1'b1;
   end
   if (e_out) begin
    debug_cycle_din<=cpu_data;
    if (fpga_data_oe) begin
     debug_cycle_dout<=fpga_read_data;
     debug_cycle_oe_seen<=1'b1;
    end
   end
   if (debug_cpu_ack) debug_read_ack_count<=debug_read_ack_count+1'b1;
   if (fpga_data_oe) debug_last_data<=fpga_read_data;
   if (e_fall) begin
    debug_last_address<=debug_cycle_address;
    debug_last_data<=debug_cycle_din;
    debug_last_bus<={mp,msel,board_reset_n,clocks_locked,sd_wr,sd_rd,
                    sd_data_ready,sd_busy,sdram_enabled,loader_done,loader_start,
                    system_ready,fpga_data_oe,cpu_mem_is_rom,memory_cpu_write,
                    memory_cpu_read,filtered_interrupts[0],filtered_interrupts[1],
                    filtered_interrupts[2],nmi_n,cpu_halt_n,keyint_n,cart_n,
                    sernt_n,slenb_n,cpu_reset_n,q_out,e_out,
                    debug_cycle_rw,debug_cycle_s};
    if (memory_cpu_write) debug_write_count<=debug_write_count+1'b1;
    // Arm and write entry zero from the exact same latched E-cycle.  Testing
    // the live scanner output in a separate clock cycle allowed a transient
    // non-FFFF value to arm a later reset-held FFFF record.
    if (!debug_log_frozen && system_ready && cpu_reset_n &&
        (debug_boot_started || debug_cycle_address != 16'hffff) &&
        debug_log_count < 9'd464) begin
     debug_log_we<=1'b1;
     debug_log_addr<=debug_log_count;
     debug_log_data<={1'b1,debug_cycle_rw,debug_cycle_s,
                      debug_cycle_oe_seen,debug_cycle_address,
                      debug_cycle_din,debug_cycle_dout,2'b00};
     debug_log_count<=debug_log_count+1'b1;
     debug_boot_started<=1'b1;
     if (debug_log_count == 9'd463)
      debug_log_frozen<=1'b1;
    end
   end
   if (&debug_refresh_count)
    hdmi_debug_data<={160'd0,
                     debug_write_count,debug_read_ack_count,
                     debug_read_request_count,debug_sdram_count,
                     debug_cycle_count,debug_scan_count,debug_last_bus,
                     debug_last_data,debug_last_address};
  end
 end
 coco_hdmi hdmi_output(.pixel_clk(clkin),.serial_clk(clk135),.reset(!board_reset_n),
  .high_resolution(COCO_MODEL == 3),.framebuffer_data(machine_hdmi_pixel),.border_rgb(vdg_border_rgb),
  .active_height(video_active_height),
  .debug_enable((COCO_MODEL == 2) && (DEBUG_HDMI_OVERLAY != 0) && debug_visible),
  .debug_data(hdmi_debug_data),
  .debug_clk(clk108),.debug_log_we(debug_log_we),
  .debug_log_addr(debug_log_addr),.debug_log_data(debug_log_data),
  .debug_log_count(debug_log_count),.debug_log_page(debug_log_page),
  .debug_status({system_ready,cpu_reset_n,cpu_halt_n,
                 bus_snapshot_ready_async,bus_ready_sync}),
  .framebuffer_addr(framebuffer_read_addr),
  .source_x(hdmi_source_x),.source_y(hdmi_source_y),.source_valid(hdmi_source_valid),
  .prefetch_y(hdmi_prefetch_y),.prefetch_valid(hdmi_prefetch_valid),
  .tmds_clk_p(tmds_clk_p),.tmds_clk_n(tmds_clk_n),.tmds_data_p(tmds_data_p),
  .tmds_data_n(tmds_data_n));
 wire analog_luma,analog_chroma,analog_cvbs;
 coco_cvbs_ntsc encoder(.clk135(clk135),.clk270(clk270),.reset_n(board_reset_n),
  .high_resolution(COCO_MODEL == 3),.framebuffer_data(machine_cvbs_pixel),.border_rgb(vdg_border_rgb),
  .active_height(video_active_height),
  .framebuffer_addr(cvbs_framebuffer_addr),
  .source_x(cvbs_source_x),.source_y(cvbs_source_y),.source_valid(cvbs_source_valid),
  .prefetch_y(cvbs_prefetch_y),.prefetch_valid(cvbs_prefetch_valid),
  .luma_out(analog_luma),.chroma_out(analog_chroma),.cvbs_out(analog_cvbs));
 assign y_out=analog_luma;
 // 0 selects S-Video chroma; the default 1 selects composite video.
 assign pb_out=(ANALOG_VIDEO_MODE == 0)?analog_chroma:analog_cvbs;
endmodule
