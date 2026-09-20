// CoCo 3 top for the physical MC6809E motherboard.  GIME CPU/MMU/video
// behavior is implemented in FPGA; video is rendered into output-specific
// double-buffered scanlines, never a full framebuffer.
module top_coco3 #(
    parameter integer RESET_HOLD_CYCLES=10800000,
    parameter integer LOG_DEPTH=4096,
    parameter [15:0] LOG_START_ADDRESS=16'hC0D1,
    //parameter [15:0] LOG_START_ADDRESS=16'hA0CB,
    parameter [15:0] LOG_WRITE_START_ADDRESS=16'h0000,
    parameter [15:0] LOG_WRITE_END_ADDRESS=16'h000,
    parameter integer LOG_REBASE_EVERY_MATCH=1,
    parameter integer ENABLE_BUS_LOGGER=1,
    parameter integer DEBUG_OVERLAY=0,
    parameter integer ANALOG_VIDEO_MODE=1
) (
    input clkin,input s1,input s2,input [7:0] mp,output [1:0] msel,
    inout [7:0] cpu_data,output irq_n_in,output firq_n_in,input audio_in,
    output halt_drive,output e_out,output q_out,output hs_n,output fs_n,
    output [2:0] sam_s,output y_out,output pb_out,
    output tmds_clk_p,output tmds_clk_n,
    output [2:0] tmds_data_p,output [2:0] tmds_data_n,
    output mspi_sclk,output mspi_cs,output mspi_mosi,input mspi_miso,
    output O_sdram_clk,output O_sdram_cke,output O_sdram_cs_n,
    output O_sdram_cas_n,output O_sdram_ras_n,output O_sdram_wen_n,
    inout [31:0] IO_sdram_dq,output [10:0] O_sdram_addr,
    output [1:0] O_sdram_ba,output [3:0] O_sdram_dqm
);
    localparam integer LOG_ADDR_WIDTH=12,LOG_COUNT_WIDTH=13,LOG_PAGE_WIDTH=6;
    localparam integer ENTRIES_PER_PAGE=116;
    localparam [LOG_PAGE_WIDTH-1:0] LAST_PAGE=(LOG_DEPTH-1)/ENTRIES_PER_PAGE;

    wire clk108,clk108p,clk270,clk135,clk27,board_reset_n,clocks_locked;
    coco_clocks clocks(.clkin(clkin),.button_reset(s1),.clk108(clk108),
        .clk108p(clk108p),.clk270(clk270),.clk135(clk135),.clk27(clk27),
        .board_reset_n(board_reset_n),.clocks_locked(clocks_locked));

    reg cpu_release=0;
    wire [15:0] address;
    wire rw_n;
    wire e_core,q_core,e_rise,e_fall;
    wire mux_reset_n,mux_slenb_n,mux_sernt_n,mux_cart_n,mux_keyint_n;
    wire mux_halt_n,mux_nmi_n,bus_address_ready_async,bus_snapshot_ready_async;

    // Capture the asynchronous motherboard mux inputs in the physical input
    // IOLOGIC.  Run the capture and scanner at 135 MHz: five settling clocks
    // retain the proven ~44 ns per switched bank, while doubling the internal
    // IDDR-Q-to-snapshot timing budget compared with the former 270 MHz path.
    // Q0 is the rising-edge sample; Q1 remains available for implementation.
    wire [7:0] mp_iob,mp_iob_falling;
    genvar mp_bit;
    generate for(mp_bit=0;mp_bit<8;mp_bit=mp_bit+1) begin:mp_input_iologic
      IDDR mp_input_register(.Q0(mp_iob[mp_bit]),
          .Q1(mp_iob_falling[mp_bit]),.D(mp[mp_bit]),.CLK(clk135));
      defparam mp_input_register.Q0_INIT=1'b1;
      defparam mp_input_register.Q1_INIT=1'b1;
    end endgenerate

    // At 1.79 MHz the Q-to-E quadrant is about 140 ns.  The first bank is
    // already selected and captured at scan start; the remaining two banks
    // consume about 89 ns at 135 MHz and complete before E rises.
    reg q_scan_meta=0,q_scan_sync=0,q_scan_delay=0,bus_scan_start=0;
    always @(posedge clk135 or negedge board_reset_n) begin
        if (!board_reset_n) begin
            q_scan_meta<=0; q_scan_sync<=0; q_scan_delay<=0;
            bus_scan_start<=0;
        end else begin
            q_scan_meta<=q_core; q_scan_sync<=q_scan_meta;
            q_scan_delay<=q_scan_sync;
            // Register the edge pulse before it fans into the mux scanner.
            // One 135 MHz clock is well inside the Q-to-E acquisition budget.
            bus_scan_start<=q_scan_sync && !q_scan_delay;
        end
    end
    coco_bus_mux #(.SETTLE_CYCLES(5)) bus_mux(.clk(clk135),.reset_n(board_reset_n),
        .scan_start(bus_scan_start),.mp(mp_iob),.msel(msel),.addr(address),
        .rw_n(rw_n),.cpu_reset_n(mux_reset_n),.slenb_n(mux_slenb_n),
        .sernt_n(mux_sernt_n),.cart_n(mux_cart_n),
        .keyint_n(mux_keyint_n),.halt_n(mux_halt_n),.nmi_n(mux_nmi_n),
        .address_ready(bus_address_ready_async),
        .snapshot_valid(bus_snapshot_ready_async));
    reg bus_ready_meta=0,bus_ready_sync=0,bus_ready_delay=0;
    always @(posedge clk108 or negedge board_reset_n) begin
        if (!board_reset_n) begin
            bus_ready_meta<=0; bus_ready_sync<=0; bus_ready_delay<=0;
        end else begin
            bus_ready_meta<=bus_snapshot_ready_async;
            bus_ready_sync<=bus_ready_meta; bus_ready_delay<=bus_ready_sync;
        end
    end
    wire bus_snapshot_valid=bus_ready_sync && !bus_ready_delay;
    reg address_ready_meta=0,address_ready_sync=0,address_ready_delay=0;
    always @(posedge clk108 or negedge board_reset_n) begin
        if (!board_reset_n) begin
            address_ready_meta<=0; address_ready_sync<=0; address_ready_delay<=0;
        end else begin
            address_ready_meta<=bus_address_ready_async;
            address_ready_sync<=address_ready_meta;
            address_ready_delay<=address_ready_sync;
        end
    end
    wire bus_address_valid=address_ready_sync && !address_ready_delay;
    wire filtered_mux_reset_n;
    input_filter #(.WIDTH(1)) mux_reset_filter(.clk(clk108),
        .reset_n(board_reset_n),.in(mux_reset_n),.out(filtered_mux_reset_n));

    wire cpu_mem_read,cpu_mem_write,cpu_mem_is_rom;
    wire [22:0] cpu_mem_addr;
    wire [7:0] core_rdata;
    wire core_data_oe,gime_irq,gime_firq;
    wire [7:0] active_height;
    wire compatibility_video;
    wire [5:0] border_rgb,hdmi_pixel_data,cvbs_pixel_data;
    wire [7:0] native_red,native_green,native_blue;
    wire native_hblank,native_vblank;
    wire video_memory_request,video_memory_valid;
    wire [22:0] video_memory_addr;
    wire [31:0] video_memory_data32;
    wire [9:0] hdmi_source_x;
    wire [7:0] hdmi_source_y;
    wire hdmi_source_valid;
    wire [7:0] hdmi_prefetch_y;
    wire hdmi_prefetch_valid;
    wire [9:0] cvbs_source_x_raw;
    wire [7:0] cvbs_source_y_raw,cvbs_prefetch_y_raw;
    wire cvbs_source_valid_raw,cvbs_prefetch_valid_raw;
    reg [9:0] cvbs_source_x=0;
    reg [7:0] cvbs_source_y=0,cvbs_prefetch_y=0;
    reg cvbs_source_valid=0,cvbs_prefetch_valid=0;
    reg [7:0] cpu_write_data=8'hff;
    wire [7:0] cpu_data_in;

    // KEYINT and SERNT are inverted by the motherboard interface before they
    // reach the multiplexed FPGA inputs. Normalize both here so the GIME
    // block sees their documented active-low interrupt sense.
    wire gime_keyint_n=!mux_keyint_n;
    wire gime_serint_n=!mux_sernt_n;

    coco3 machine(.clk(clk108),.reset_n(board_reset_n),
        .cpu_reset_n(cpu_release),.s2(1'b0),.cpu_addr(address),
        .cpu_rw_n(rw_n),.cpu_data(cpu_write_data),
        .serint_n(gime_serint_n),.keyint_n(gime_keyint_n),.cart_n(mux_cart_n),
        .irq_assert(gime_irq),.firq_assert(gime_firq),.sam_s(sam_s),
        .e(e_core),.q(q_core),.e_pin(e_out),.q_pin(q_out),
        .e_rise(e_rise),.e_fall(e_fall),
        .cpu_mem_read(cpu_mem_read),.cpu_mem_write(cpu_mem_write),
        .cpu_mem_is_rom(cpu_mem_is_rom),.cpu_mem_addr(cpu_mem_addr),
        .core_rdata(core_rdata),.core_data_oe(core_data_oe),
        .video_memory_data(video_memory_data32[7:0]),
        .video_memory_data32(video_memory_data32),
        .video_memory_valid(video_memory_valid),
        .video_memory_request(video_memory_request),
        .video_memory_addr(video_memory_addr),.active_height(active_height),
        .compatibility_video(compatibility_video),
        .hs_n(hs_n),.fs_n(fs_n),.red(native_red),.green(native_green),
        .blue(native_blue),.border_rgb(border_rgb),
        .hblank(native_hblank),.vblank(native_vblank),
        .framebuffer_write(),.framebuffer_write_addr(),
        .framebuffer_write_data(),
        .hdmi_read_clk(clk27),.hdmi_source_x(hdmi_source_x),
        .hdmi_source_y(hdmi_source_y),.hdmi_source_valid(hdmi_source_valid),
        .hdmi_prefetch_y(hdmi_prefetch_y),
        .hdmi_prefetch_valid(hdmi_prefetch_valid),
        .hdmi_pixel_data(hdmi_pixel_data),.cvbs_read_clk(clk135),
        .cvbs_source_x(cvbs_source_x),.cvbs_source_y(cvbs_source_y),
        .cvbs_source_valid(cvbs_source_valid),
        .cvbs_prefetch_y(cvbs_prefetch_y),
        .cvbs_prefetch_valid(cvbs_prefetch_valid),
        .cvbs_pixel_data(cvbs_pixel_data));

    // The board pins drive NPN transistor bases: high asserts the active-low
    // motherboard IRQ/FIRQ nets, low releases them.
    assign irq_n_in=gime_irq;
    assign firq_n_in=gime_firq;

    wire sdram_reset_n,loader_start,system_ready,sdram_enabled,loader_done;
    wire sdram_test_done,sdram_test_pass;
    wire [15:0] sdram_test_error_addr;
    wire [7:0] sdram_test_expected,sdram_test_actual;
    wire rom_verify_done,rom_verify_pass;
    wire [15:0] rom_verify_vector;
    wire flash_vector_done,flash_vector_pass;
    wire [15:0] flash_vector;
    coco_startup startup(.clk(clk108),.board_reset_n(board_reset_n),
        .sdram_enabled(sdram_enabled),.loader_done(loader_done),
        .sdram_reset_n(sdram_reset_n),.loader_start(loader_start),
        .system_ready(system_ready));
    wire sd_rd,sd_wr,sd_refresh,sd_data_ready,sd_busy;
    wire [22:0] sd_addr; wire [15:0] sd_din,sd_dout;
    wire [31:0] sd_dout32; wire [1:0] sd_wdm;
    sdram sdram_controller(.SDRAM_DQ(IO_sdram_dq),.SDRAM_A(O_sdram_addr),
        .SDRAM_BA(O_sdram_ba),.SDRAM_nCS(O_sdram_cs_n),
        .SDRAM_nWE(O_sdram_wen_n),.SDRAM_nRAS(O_sdram_ras_n),
        .SDRAM_nCAS(O_sdram_cas_n),.SDRAM_CLK(O_sdram_clk),
        .SDRAM_CKE(O_sdram_cke),.SDRAM_DQM(O_sdram_dqm),
        .clk(clk108),.clk_sdram(clk108p),.resetn(sdram_reset_n),
        .rd(sd_rd),.wr(sd_wr),.refresh(sd_refresh),.addr(sd_addr),
        .din(sd_din),.wdm(sd_wdm),.dout(sd_dout),.dout32(sd_dout32),
        .data_ready(sd_data_ready),.busy(sd_busy),.enabled(sdram_enabled));

    localparam integer RESET_HOLD_WIDTH=$clog2(RESET_HOLD_CYCLES+1);
    reg [RESET_HOLD_WIDTH-1:0] reset_hold_count=0;
    reg release_pending=0;
    always @(posedge clk108 or negedge board_reset_n) begin
        if (!board_reset_n) begin
            reset_hold_count<=0; release_pending<=0; cpu_release<=0;
        end else if (!system_ready) begin
            reset_hold_count<=0; release_pending<=0; cpu_release<=0;
        end else if (!cpu_release) begin
            if (reset_hold_count<RESET_HOLD_CYCLES)
                reset_hold_count<=reset_hold_count+1'b1;
            else release_pending<=1;
            if (release_pending && e_fall) cpu_release<=1;
        end
    end
    assign halt_drive=!cpu_release;
    wire cpu_bus_active=cpu_release;
    // Keep the SDRAM read engine alive during the post-loader CPU hold.  A
    // reset 6809 presents FFFE, so this preloads the high reset-vector byte
    // well before HALT is released.  Writes and the physical FPGA data driver
    // remain disabled until cpu_release, preventing any held/reset bus state
    // from modifying memory or contending with the motherboard.
    wire cpu_memory_service=system_ready;
    always @(posedge clk108 or negedge board_reset_n) begin
        if (!board_reset_n) cpu_write_data<=8'hff;
        else if (cpu_bus_active && e_core && !rw_n) cpu_write_data<=cpu_data_in;
    end

    wire [7:0] memory_rdata;
    wire memory_data_oe,cpu_memory_wait;
    coco3_memory memory(.clk(clk108),.reset_n(sdram_reset_n),
        .loader_start(loader_start),.cpu_access_enable(cpu_memory_service),
        .cpu_bus_valid(bus_snapshot_valid),.cpu_address_valid(bus_address_valid),
        .e(e_core),.q(q_core),.e_fall(e_fall),
        .cpu_mem_read(cpu_mem_read),
        .cpu_mem_write(cpu_mem_write && cpu_bus_active),
        .cpu_mem_is_rom(cpu_mem_is_rom),.cpu_mem_addr(cpu_mem_addr),
        .cpu_wdata(cpu_write_data),.cpu_rdata(memory_rdata),
        .cpu_data_oe(memory_data_oe),.cpu_wait(cpu_memory_wait),
        .video_req(video_memory_request),.video_addr(video_memory_addr),
        .video_ack(video_memory_valid),.video_rdata(video_memory_data32),
        .loader_done(loader_done),
        .flash_vector_done(flash_vector_done),
        .flash_vector_pass(flash_vector_pass),.flash_vector(flash_vector),
        .sdram_test_done(sdram_test_done),.sdram_test_pass(sdram_test_pass),
        .sdram_test_error_addr(sdram_test_error_addr),
        .sdram_test_expected(sdram_test_expected),
        .sdram_test_actual(sdram_test_actual),
        .rom_verify_done(rom_verify_done),
        .rom_verify_pass(rom_verify_pass),.rom_verify_vector(rom_verify_vector),
        .mspi_cs(mspi_cs),.mspi_sclk(mspi_sclk),
        .mspi_miso(mspi_miso),.mspi_mosi(mspi_mosi),
        .sdram_enabled(sdram_enabled),.sd_rd(sd_rd),.sd_wr(sd_wr),
        .sd_refresh(sd_refresh),.sd_addr(sd_addr),.sd_din(sd_din),
        .sd_wdm(sd_wdm),.sd_dout(sd_dout),.sd_dout32(sd_dout32),
        .sd_data_ready(sd_data_ready),.sd_busy(sd_busy));
    // GIME register reads are decoded as soon as the address banks settle.
    // Register their value once before the I/O cells so the palette/MMU mux
    // is not on the 108 MHz pad-output path.
    reg [7:0] core_rdata_pipe=8'hff;
    always @(posedge clk108 or negedge board_reset_n) begin
        if (!board_reset_n) core_rdata_pipe<=8'hff;
        else core_rdata_pipe<=core_rdata;
    end
    wire [7:0] fpga_read_data=core_data_oe ? core_rdata_pipe : memory_rdata;
    wire fpga_data_oe=cpu_bus_active && (core_data_oe || memory_data_oe);

    wire [7:0] cpu_pin_data,cpu_pin_oen;
    genvar cpu_data_bit;
    generate for(cpu_data_bit=0;cpu_data_bit<8;cpu_data_bit=cpu_data_bit+1)
      begin:cpu_data_iologic
        ODDR cpu_output_register(.Q0(cpu_pin_data[cpu_data_bit]),
            .Q1(cpu_pin_oen[cpu_data_bit]),.D0(fpga_read_data[cpu_data_bit]),
            .D1(fpga_read_data[cpu_data_bit]),.TX(!fpga_data_oe),.CLK(clk108));
        defparam cpu_output_register.INIT=1'b1;
        defparam cpu_output_register.TXCLK_POL=1'b0;
        IOBUF cpu_data_buffer(.O(cpu_data_in[cpu_data_bit]),
            .IO(cpu_data[cpu_data_bit]),.I(cpu_pin_data[cpu_data_bit]),
            .OEN(cpu_pin_oen[cpu_data_bit]));
      end endgenerate

    // Same 40-bit memory logger and page/overlay controls as the CoCo 2 top.
    wire log_we,rebase_pulse;
    wire [LOG_ADDR_WIDTH-1:0] log_addr;
    wire [39:0] log_data;
    wire [LOG_COUNT_WIDTH-1:0] log_count;
    generate if (ENABLE_BUS_LOGGER!=0) begin:logger_enabled
      cpu_bus_logger #(.LOG_ADDR_WIDTH(LOG_ADDR_WIDTH),
        .LOG_COUNT_WIDTH(LOG_COUNT_WIDTH),.LOG_DEPTH(LOG_DEPTH),
        .LOG_START_ADDRESS(LOG_START_ADDRESS),
        .LOG_WRITE_START_ADDRESS(LOG_WRITE_START_ADDRESS),
        .LOG_WRITE_END_ADDRESS(LOG_WRITE_END_ADDRESS),
        .LOG_REBASE_EVERY_MATCH(LOG_REBASE_EVERY_MATCH)) logger(
        .clk(clk108),.reset_n(board_reset_n),.capture_enable(cpu_release),
        .bus_reset_n(filtered_mux_reset_n),.e_fall(e_fall),.q(q_core),
        .rw_n(rw_n),.address(address),.cpu_data(cpu_data_in),
        .expected_data(fpga_read_data),.s(sam_s),.data_oe(fpga_data_oe),
        .memory_wait(cpu_memory_wait),.log_we(log_we),.log_addr(log_addr),
        .log_data(log_data),.log_count(log_count),.rebase_pulse(rebase_pulse));
    end else begin:logger_disabled
      assign log_we=0; assign log_addr=0; assign log_data=0;
      assign log_count=0; assign rebase_pulse=0;
    end endgenerate

    reg s2_meta=0,s2_sync=0,s2_state=0;
    reg [20:0] s2_stable_count=0; reg [26:0] s2_hold_count=0;
    reg s2_long_handled=0; reg overlay_visible=(DEBUG_OVERLAY!=0);
    reg [LOG_PAGE_WIDTH-1:0] log_page=0;
    always @(posedge clk108 or negedge board_reset_n) begin
      if(!board_reset_n) begin
        s2_meta<=0;s2_sync<=0;s2_state<=0;s2_stable_count<=0;
        s2_hold_count<=0;s2_long_handled<=0;
        overlay_visible<=(DEBUG_OVERLAY!=0);log_page<=0;
      end else begin
        s2_meta<=s2;s2_sync<=s2_meta;
        if(rebase_pulse) log_page<=0;
        if(s2_sync==s2_state) begin
          s2_stable_count<=0;
          if(s2_state && !s2_long_handled) begin
            if(s2_hold_count==27'd107999999) begin
              overlay_visible<=!overlay_visible;s2_long_handled<=1;
            end else s2_hold_count<=s2_hold_count+1'b1;
          end
        end else if(s2_stable_count==21'd1079999) begin
          s2_state<=s2_sync;s2_stable_count<=0;
          if(s2_sync) begin s2_hold_count<=0;s2_long_handled<=0; end
          else begin s2_hold_count<=0;
            if(!s2_long_handled) log_page<=(log_page==LAST_PAGE)?0:log_page+1'b1;
          end
        end else s2_stable_count<=s2_stable_count+1'b1;
      end
    end

    wire interrupt_inputs_idle=gime_serint_n && gime_keyint_n && mux_halt_n;
    coco3_hdmi #(.LOG_ADDR_WIDTH(LOG_ADDR_WIDTH),
        .LOG_COUNT_WIDTH(LOG_COUNT_WIDTH),.LOG_PAGE_WIDTH(LOG_PAGE_WIDTH),
        .LOG_DEPTH(LOG_DEPTH),.ENABLE_DEBUG_OVERLAY(ENABLE_BUS_LOGGER)) hdmi_output(
        .pixel_clk(clk27),.serial_clk(clk135),.reset(!board_reset_n),
        .debug_clk(clk108),.log_we(log_we),.log_addr(log_addr),
        .log_data(log_data),.log_count(log_count),.log_page(log_page),
        .debug_status({clocks_locked,filtered_mux_reset_n,mux_halt_n,
                       interrupt_inputs_idle,bus_ready_sync}),
        // Display asserted levels: KEYINT and SERNT are active-low inputs;
        // IRQ and FIRQ are active-high requests to the output transistors.
        .interrupt_status({!gime_keyint_n,!gime_serint_n,gime_irq,gime_firq}),
        .rom_verify_done(rom_verify_done),.rom_verify_pass(rom_verify_pass),
        .rom_verify_vector(rom_verify_vector),
        .sdram_test_done(sdram_test_done),.sdram_test_pass(sdram_test_pass),
        .sdram_test_error_addr(sdram_test_error_addr),
        .sdram_test_expected(sdram_test_expected),
        .sdram_test_actual(sdram_test_actual),
        .overlay_enable(overlay_visible),.active_height(active_height),
        .compatibility_mode(compatibility_video),
        .border_rgb(border_rgb),.pixel_data(hdmi_pixel_data),
        .source_x(hdmi_source_x),.source_y(hdmi_source_y),
        .source_valid(hdmi_source_valid),.prefetch_y(hdmi_prefetch_y),
        .prefetch_valid(hdmi_prefetch_valid),.tmds_clk_p(tmds_clk_p),
        .tmds_clk_n(tmds_clk_n),.tmds_data_p(tmds_data_p),
        .tmds_data_n(tmds_data_n));

    wire analog_luma,analog_chroma,analog_cvbs;
    wire [15:0] unused_cvbs_framebuffer_addr;
    // Cut the encoder-counter -> line-buffer BSRAM-address path at the
    // clk135 boundary.  There are ten clk135 clocks per CVBS sample, so this
    // one-clock staging still leaves the scanline RAM response comfortably
    // ahead of the sample which consumes it.
    always @(posedge clk135 or negedge cpu_release) begin
        if(!cpu_release) begin
            cvbs_source_x<=0;cvbs_source_y<=0;cvbs_source_valid<=0;
            cvbs_prefetch_y<=0;cvbs_prefetch_valid<=0;
        end else begin
            cvbs_source_x<=cvbs_source_x_raw;
            cvbs_source_y<=cvbs_source_y_raw;
            cvbs_source_valid<=cvbs_source_valid_raw;
            cvbs_prefetch_y<=cvbs_prefetch_y_raw;
            cvbs_prefetch_valid<=cvbs_prefetch_valid_raw;
        end
    end
    coco_cvbs_ntsc #(.STREAMING_INPUT(0)) analog_encoder(
        .clk135(clk135),.clk270(clk270),.reset_n(cpu_release),
        .high_resolution(1'b1),.framebuffer_data(cvbs_pixel_data),
        .border_rgb(border_rgb),.active_height(active_height),
        .framebuffer_addr(unused_cvbs_framebuffer_addr),
        .source_x(cvbs_source_x_raw),.source_y(cvbs_source_y_raw),
        .source_valid(cvbs_source_valid_raw),.prefetch_y(cvbs_prefetch_y_raw),
        .prefetch_valid(cvbs_prefetch_valid_raw),.luma_out(analog_luma),
        .chroma_out(analog_chroma),.cvbs_out(analog_cvbs));
    assign y_out=analog_luma;
    assign pb_out=(ANALOG_VIDEO_MODE==0)?analog_chroma:analog_cvbs;

    wire unused_inputs=audio_in ^ mux_slenb_n ^ mux_nmi_n ^ native_hblank ^
        native_vblank ^ ^native_red ^ ^native_green ^ ^native_blue ^ e_rise;
endmodule
