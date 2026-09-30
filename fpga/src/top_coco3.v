// CoCo 3 top for the physical MC6809E motherboard.  GIME CPU/MMU/video
// behavior is implemented in FPGA; video is rendered into output-specific
// double-buffered scanlines, never a full framebuffer.
module top_coco3 #(
    parameter integer RESET_HOLD_CYCLES=10800000,
    parameter integer LOG_DEPTH=4092,
    parameter [15:0] LOG_START_ADDRESS=16'h0000,
    parameter [15:0] LOG_WRITE_START_ADDRESS=16'h0000,
    parameter [15:0] LOG_WRITE_END_ADDRESS=16'h0000,
    parameter [7:0] LOG_WRITE_DATA_MASK=8'h00,
    parameter [7:0] LOG_WRITE_DATA_VALUE=8'h00,
    parameter [15:0] LOG_CAPTURE_START_ADDRESS=16'h0000,
    parameter [15:0] LOG_CAPTURE_END_ADDRESS=16'hffff,
    parameter [15:0] LOG_CAPTURE_EXTRA_ADDRESS=16'hffff,
    parameter [15:0] LOG_MARKER_ADDRESS=16'hff9b,
    parameter [7:0] LOG_MARKER_DATA=8'hc7,
    parameter integer LOG_REBASE_EVERY_MATCH=0,
    // Set to 1 only for bus-debug builds.  At the default 0, the generate
    // blocks omit both the capture logger/RAM and the HDMI debug overlay;
    // synthesis then removes the unused S2 capture-control cone as well.
    parameter integer ENABLE_BUS_LOGGER=0,
    parameter integer ENABLE_GIME_TRACE=0,
    parameter integer DEBUG_OVERLAY=0,
    // 0/1: simultaneous S-Video and CVBS; 2: Y/Pb/Pr component;
    // 3: RGB with composite sync on green (Y=G/SoG, Pb=B, Pr=R).
    parameter integer ANALOG_VIDEO_MODE=3,
    // 0=OFF, 1=ON (blue/orange), 2=REVERSE (orange/blue).
    parameter [1:0] INITIAL_ARTIFACT_MODE=2'd1,
    parameter integer DISTO_2MB=1,
    // Glenside task-file occupies IDE_BASE..IDE_BASE+$0f; $FF50 is standard.
    parameter integer ENABLE_GLENSIDE_IDE=1,
    parameter [15:0] IDE_BASE=16'hff50
) (
    input clkin,input s1,input s2,input [7:0] mp,output [1:0] msel,
    inout [7:0] cpu_data,output irq_n_in,output firq_n_in,output audio_out,
    output halt_drive,output e_out,output q_out,output hs_n,output fs_n,
    output [2:0] sam_s,output y_out,output pb_out,output cvbs_out,
    output tmds_clk_p,output tmds_clk_n,
    output [2:0] tmds_data_p,output [2:0] tmds_data_n,
    output mspi_sclk,output mspi_cs,output mspi_mosi,input mspi_miso,
    output sd_sclk,inout sd_cmd,inout sd_dat0,inout sd_dat1,
    inout sd_dat2,inout sd_dat3,
    output O_sdram_clk,output O_sdram_cke,output O_sdram_cs_n,
    output O_sdram_cas_n,output O_sdram_ras_n,output O_sdram_wen_n,
    inout [31:0] IO_sdram_dq,output [10:0] O_sdram_addr,
    output [1:0] O_sdram_ba,output [3:0] O_sdram_dqm
);
    localparam integer LOG_ADDR_WIDTH=13,LOG_COUNT_WIDTH=14,LOG_PAGE_WIDTH=7;
    // Two fixed status rows plus one column-heading row leave 57 trace rows
    // in each half of the 60-row HDMI debugger.
    localparam integer ENTRIES_PER_PAGE=114;
    localparam [LOG_PAGE_WIDTH-1:0] LAST_PAGE=(LOG_DEPTH-1)/ENTRIES_PER_PAGE;

    wire clk108,clk108p,clk270,clk135,clk27,board_reset_n,clocks_locked;
    wire [1:0] artifact_mode;
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
    artifact_mode_control #(.INITIAL_MODE(INITIAL_ARTIFACT_MODE)) artifact_control(.clk(clk108),
        .enable(cpu_release),.reset_n(filtered_mux_reset_n),
        .mode(artifact_mode));
    reg [1:0] artifact_mode_video=INITIAL_ARTIFACT_MODE;
    always @(posedge clk108)
        artifact_mode_video<=artifact_mode;

    wire cpu_mem_read,cpu_mem_write,cpu_mem_is_rom;
    wire [22:0] cpu_mem_addr;
    wire [7:0] core_rdata;
    wire core_data_oe,gime_irq,gime_firq;
    wire [2:0] machine_sam_s;
    wire [7:0] active_height;
    wire video_50hz;
    wire compatibility_video;
    wire artifact_video_active,artifact_css;
    wire [5:0] border_rgb,cvbs_pixel_data,cvbs_border_data;
    wire [5:0] cvbs_right_border_data;
    wire cvbs_border_valid;
    wire [5:0] cvbs_vertical_left_border_data;
    wire [5:0] cvbs_vertical_right_border_data;
    wire cvbs_vertical_border_valid;
    wire [8:0] cvbs_border_raster_y;
    wire [23:0] hdmi_pixel_data;
    wire [5:0] hdmi_left_border_data,hdmi_right_border_data;
    wire hdmi_border_valid;
    wire [5:0] hdmi_vertical_left_border_data,hdmi_vertical_right_border_data;
    wire hdmi_vertical_border_valid,hdmi_frame_start;
    wire [8:0] hdmi_border_raster_y;
    wire [7:0] native_red,native_green,native_blue;
    wire native_hblank,native_vblank;
    wire video_memory_request,video_memory_valid;
    wire [22:0] video_memory_addr;
    wire [31:0] video_memory_data32;
    wire [9:0] hdmi_source_x;
    wire [7:0] hdmi_source_y;
    wire hdmi_source_valid,hdmi_source_picture_active;
    wire hdmi_video_50hz;
    wire [7:0] hdmi_prefetch_y;
    wire hdmi_prefetch_valid;
    wire [9:0] cvbs_source_x_raw;
    wire [7:0] cvbs_source_y_raw,cvbs_prefetch_y_raw;
    wire cvbs_source_valid_raw,cvbs_prefetch_valid_raw;
    reg [9:0] cvbs_source_x=0;
    reg [7:0] cvbs_source_y=0,cvbs_prefetch_y=0;
    reg cvbs_source_valid=0,cvbs_prefetch_valid=0;
    reg [7:0] cpu_write_data=8'hff;
    wire [5:0] pia1_dac_level;
    wire pia1_sound_enable;
    wire [7:0] pia1_pwm_sample;
    wire [15:0] pia1_pcm_sample;
    wire pia1_audio_clk;
    wire pia1_audio_reset_n=board_reset_n && cpu_release && filtered_mux_reset_n;
    coco_pia1_dac pia1_audio_shadow(.clk(clk108),
        .reset_n(pia1_audio_reset_n),.e_fall(e_fall),.cpu_rw_n(rw_n),
        .cpu_addr(address),.cpu_data(cpu_write_data),
        .dac_level(pia1_dac_level),.sound_enable(pia1_sound_enable),
        .pwm_sample(pia1_pwm_sample),
        .pcm_sample(pia1_pcm_sample),.audio_clk(pia1_audio_clk));
    sigma_delta_dac line_audio_dac(.clk(clk270),
        .reset_n(pia1_audio_reset_n),.sample(pia1_pwm_sample),
        .bit_out(audio_out));
    wire [7:0] cpu_data_in;
    wire [31:0] raster_debug;
    wire [5:0] mmu_task0_page_debug,mmu_task1_page_debug;
    wire mmu_task_debug,mmu_enabled_debug;
    wire [79:0] gime_register_debug;
    wire [127:0] gime_trace_registers;
    wire gime_trace_sample,gime_trace_cache_valid;
    wire [8:0] gime_trace_y;
    wire [7:0] gime_trace_active_line,gime_trace_cache_y,
               gime_trace_dma_next_y;
    wire [1:0] gime_trace_phase;
    wire [20:0] gime_trace_cache_start;
    wire [18:0] gime_trace_dma_next_address;
    wire [3:0] gime_trace_dma_line;
    wire [95:0] mmu_register_debug;
    wire native_bit_plane;

    // KEYINT and SERNT are inverted by the motherboard interface before they
    // reach the multiplexed FPGA inputs. Normalize both here so the GIME
    // block sees their documented active-low interrupt sense.
    wire gime_keyint_n=!mux_keyint_n;
    wire gime_serint_n=!mux_sernt_n;

    coco3 #(.DISTO_2MB(DISTO_2MB)) machine(
        .clk(clk108),.reset_n(board_reset_n),
        .cpu_reset_n(cpu_release),
        .s2(1'b0),.artifact_mode(artifact_mode_video),
        .cpu_addr(address),
        .cpu_rw_n(rw_n),.cpu_data(cpu_write_data),
        .serint_n(gime_serint_n),.keyint_n(gime_keyint_n),.cart_n(mux_cart_n),
        .irq_assert(gime_irq),.firq_assert(gime_firq),.sam_s(machine_sam_s),
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
        .video_50hz(video_50hz),.native_bit_plane(native_bit_plane),
        .compatibility_video(compatibility_video),
        .artifact_video_active(artifact_video_active),
        .artifact_css(artifact_css),
        .hs_n(hs_n),.fs_n(fs_n),.red(native_red),.green(native_green),
        .blue(native_blue),.border_rgb(border_rgb),
        .hblank(native_hblank),.vblank(native_vblank),
        .framebuffer_write(),.framebuffer_write_addr(),
        .framebuffer_write_data(),
        .hdmi_read_clk(clk27),.hdmi_source_x(hdmi_source_x),
        .hdmi_source_y(hdmi_source_y),.hdmi_source_valid(hdmi_source_valid),
        .hdmi_source_picture_active(hdmi_source_picture_active),
        .hdmi_prefetch_y(hdmi_prefetch_y),
        .hdmi_prefetch_valid(hdmi_prefetch_valid),
        .hdmi_pixel_data(hdmi_pixel_data),
        .hdmi_left_border_data(hdmi_left_border_data),
        .hdmi_right_border_data(hdmi_right_border_data),
        .hdmi_border_valid(hdmi_border_valid),.cvbs_read_clk(clk135),
        .hdmi_vertical_left_border_data(hdmi_vertical_left_border_data),
        .hdmi_vertical_right_border_data(hdmi_vertical_right_border_data),
        .hdmi_vertical_border_valid(hdmi_vertical_border_valid),
        .hdmi_frame_start(hdmi_frame_start),
        .hdmi_active_50hz(hdmi_video_50hz),
        .hdmi_border_raster_y(hdmi_border_raster_y),
        .cvbs_source_x(cvbs_source_x),.cvbs_source_y(cvbs_source_y),
        .cvbs_source_valid(cvbs_source_valid),
        .cvbs_prefetch_y(cvbs_prefetch_y),
        .cvbs_prefetch_valid(cvbs_prefetch_valid),
        .cvbs_border_raster_y(cvbs_border_raster_y),
        .cvbs_pixel_data(cvbs_pixel_data),.cvbs_border_data(cvbs_border_data),
        .cvbs_right_border_data(cvbs_right_border_data),
        .cvbs_border_valid(cvbs_border_valid),
        .cvbs_vertical_left_border_data(cvbs_vertical_left_border_data),
        .cvbs_vertical_right_border_data(cvbs_vertical_right_border_data),
        .cvbs_vertical_border_valid(cvbs_vertical_border_valid),
        .mmu_task0_page_debug(mmu_task0_page_debug),
        .mmu_task1_page_debug(mmu_task1_page_debug),
        .mmu_task_debug(mmu_task_debug),
        .mmu_enabled_debug(mmu_enabled_debug),
        .gime_register_debug(gime_register_debug),
        .gime_trace_registers(gime_trace_registers),
        .gime_trace_sample(gime_trace_sample),.gime_trace_y(gime_trace_y),
        .gime_trace_active_line(gime_trace_active_line),
        .gime_trace_phase(gime_trace_phase),
        .gime_trace_cache_y(gime_trace_cache_y),
        .gime_trace_cache_valid(gime_trace_cache_valid),
        .gime_trace_cache_start(gime_trace_cache_start),
        .gime_trace_dma_next_address(gime_trace_dma_next_address),
        .gime_trace_dma_next_y(gime_trace_dma_next_y),
        .gime_trace_dma_line(gime_trace_dma_line),
        .mmu_register_debug(mmu_register_debug),
        .raster_debug(raster_debug));

    // The board pins drive NPN transistor bases: high asserts the active-low
    // motherboard IRQ/FIRQ nets, low releases them.
    assign irq_n_in=gime_irq;
    assign firq_n_in=gime_firq;

    wire sdram_reset_n,loader_start,system_ready,sdram_enabled,loader_done;
    wire sdram_test_done,sdram_test_pass;
    wire [18:0] sdram_test_error_addr;
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

    wire ide_live_selected=(ENABLE_GLENSIDE_IDE != 0) &&
        (address[15:4] == IDE_BASE[15:4]);

    // Freeze one complete scanned CPU transaction.  The mux address changes
    // while its banks are being acquired, so a live FF5x comparison is not a
    // valid read/write qualifier.  Hold the snapshot through E falling, just
    // as the memory service holds its transaction tag.
    reg ide_cycle_active=1'b0;
    reg ide_cycle_rw_n=1'b1;
    reg [15:0] ide_address_pipe=16'hffff;
    reg [2:0] sam_s_pipe=3'd0;
    // The integrated adapter owns its I/O page.  Qualify ownership from the
    // completed early address capture, never from the partially scanned live
    // address.  Waiting for the later control snapshot leaves a window where
    // S6 can start selecting an external FF5x cartridge before we take over;
    // that device can then contend with an integrated-IDE read.  The address
    // capture is already atomic and arrives a complete mux bank before E.
    assign sam_s=sam_s_pipe;
    always @(posedge clk108 or negedge board_reset_n) begin
        if (!board_reset_n) begin
            ide_cycle_active<=1'b0;
            ide_cycle_rw_n<=1'b1;
            ide_address_pipe<=16'hffff;
            sam_s_pipe<=3'd0;
        end else begin
            if (bus_address_valid) begin
                ide_address_pipe<=address;
                sam_s_pipe<=ide_live_selected ? 3'd0 : machine_sam_s;
            end
            if (bus_snapshot_valid) begin
                ide_cycle_active<=ide_live_selected;
                ide_cycle_rw_n<=rw_n;
            end else if (e_fall)
                ide_cycle_active<=1'b0;
        end
    end

    wire [7:0] ide_rdata;
    wire ide_raw_data_oe;
    // Match the proven GIME-register bus timing: the external transceiver is
    // selected by S0, while the FPGA drives its side only during E high.
    // The output IOLOGIC retains the value through the physical E-falling
    // sample edge without extending ownership into the following CPU cycle.
    // Retain an IDE read for one 108 MHz clock after E falls.  The physical
    // 6809 samples at that edge; releasing the transceiver on the same FPGA
    // clock gave essentially zero hold time and became phase-sensitive.
    reg ide_read_hold=1'b0;
    reg [7:0] ide_read_latched=8'hff;
    always @(posedge clk108 or negedge board_reset_n) begin
        if (!board_reset_n) begin
            ide_read_hold<=1'b0;
            ide_read_latched<=8'hff;
        end else begin
            if (ide_raw_data_oe && e_core) begin
                ide_read_hold<=1'b1;
                ide_read_latched<=ide_rdata;
            end else if (!e_core && !e_fall)
                ide_read_hold<=1'b0;
        end
    end
    wire ide_data_oe=(ide_raw_data_oe && e_core) ||
                     (ide_read_hold && e_fall);
    generate if (ENABLE_GLENSIDE_IDE != 0) begin:glenside_ide_enabled
      glenside_ide #(.IDE_BASE(IDE_BASE),.CPU_ENABLE_PREDECODED(1)) ide(
        .clk(clk108),.reset_n(board_reset_n),
        .cpu_enable(cpu_bus_active && ide_cycle_active),
        .e_fall(e_fall),.cpu_addr(ide_address_pipe),
        .cpu_rw_n(ide_cycle_rw_n),
        .cpu_wdata(cpu_write_data),.cpu_rdata(ide_rdata),
        .cpu_data_oe(ide_raw_data_oe),.sd_sclk(sd_sclk),.sd_cmd(sd_cmd),
        .sd_dat0(sd_dat0),.sd_dat1(sd_dat1),.sd_dat2(sd_dat2),
        .sd_dat3(sd_dat3));
    end else begin:glenside_ide_disabled
      assign ide_rdata=8'hff;
      assign ide_raw_data_oe=1'b0;
      assign sd_sclk=1'b0;
      assign sd_cmd=1'bz;
      assign sd_dat0=1'bz;
      assign sd_dat1=1'bz;
      assign sd_dat2=1'bz;
      assign sd_dat3=1'bz;
    end endgenerate
    // Register IDE data continuously, exactly like the GIME register read
    // path below.  The synchronous sector RAM has the whole preceding CPU
    // cycle to follow data_pointer, and the register captures the current word
    // before the pointer advances at E falling.
    reg [7:0] ide_rdata_pipe=8'hff;
    always @(posedge clk108 or negedge board_reset_n) begin
        if (!board_reset_n) ide_rdata_pipe<=8'hff;
        else ide_rdata_pipe<=ide_rdata;
    end
    // GIME register reads are decoded as soon as the address banks settle.
    // Register their value once before the I/O cells so the palette/MMU mux
    // is not on the 108 MHz pad-output path.
    reg [7:0] core_rdata_pipe=8'hff;
    always @(posedge clk108 or negedge board_reset_n) begin
        if (!board_reset_n) core_rdata_pipe<=8'hff;
        else core_rdata_pipe<=core_rdata;
    end
    // Memory and ROM reads are also ready many 108-MHz clocks before the
    // 6809 samples at E falling.  Register the final byte here so block-RAM
    // placement and the read-source mux are not on the output-IOLOGIC path.
    reg [7:0] memory_rdata_pipe=8'hff;
    always @(posedge clk108 or negedge board_reset_n) begin
        if (!board_reset_n) memory_rdata_pipe<=8'hff;
        else memory_rdata_pipe<=memory_rdata;
    end
    // Keep IDE data isolated from the continuously changing GIME read bus.
    // ATA data-port reads are back-to-back, so an IDE byte must remain intact
    // until its E phase has completed.
    wire [7:0] fpga_read_data=ide_data_oe ? ide_read_latched :
        (core_data_oe ? core_rdata_pipe : memory_rdata_pipe);
    wire fpga_data_oe=cpu_bus_active &&
        (ide_data_oe || core_data_oe || memory_data_oe);

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

    // Manual 48-bit bus/MMU logger and page/overlay controls.
    wire log_we,rebase_pulse,log_marker_pulse;
    wire [LOG_ADDR_WIDTH-1:0] log_addr,log_base;
    wire [47:0] log_data;
    wire [LOG_COUNT_WIDTH-1:0] log_count;
    reg log_capture_active=0,log_capture_clear=0;
    generate if (ENABLE_BUS_LOGGER!=0) begin:logger_enabled
      cpu_bus_logger #(.LOG_ADDR_WIDTH(LOG_ADDR_WIDTH),
        .LOG_COUNT_WIDTH(LOG_COUNT_WIDTH),.LOG_DEPTH(LOG_DEPTH),
        .LOG_START_ADDRESS(LOG_START_ADDRESS),
        .LOG_WRITE_START_ADDRESS(LOG_WRITE_START_ADDRESS),
        .LOG_WRITE_END_ADDRESS(LOG_WRITE_END_ADDRESS),
        .LOG_WRITE_DATA_MASK(LOG_WRITE_DATA_MASK),
        .LOG_WRITE_DATA_VALUE(LOG_WRITE_DATA_VALUE),
        .LOG_CAPTURE_START_ADDRESS(LOG_CAPTURE_START_ADDRESS),
        .LOG_CAPTURE_END_ADDRESS(LOG_CAPTURE_END_ADDRESS),
        .LOG_CAPTURE_EXTRA_ADDRESS(LOG_CAPTURE_EXTRA_ADDRESS),
        .LOG_MARKER_ADDRESS(LOG_MARKER_ADDRESS),
        .LOG_MARKER_DATA(LOG_MARKER_DATA),
        .LOG_REBASE_EVERY_MATCH(LOG_REBASE_EVERY_MATCH)) logger(
        .clk(clk108),.reset_n(board_reset_n),
        .capture_enable(cpu_release && log_capture_active),
        .capture_clear(log_capture_clear),
        .bus_reset_n(filtered_mux_reset_n),.e_fall(e_fall),.q(q_core),
        .rw_n(rw_n),.address(address),.cpu_data(cpu_data_in),
        .expected_data(fpga_read_data),.s(sam_s),.data_oe(fpga_data_oe),
        .memory_wait(cpu_memory_wait),
        .mmu_task0_page(mmu_task0_page_debug),
        .mmu_task1_page(mmu_task1_page_debug),
        .mmu_task(mmu_task_debug),.mmu_enabled(mmu_enabled_debug),
        .log_we(log_we),.log_addr(log_addr),
        .log_data(log_data),.log_count(log_count),.log_base(log_base),
        .rebase_pulse(rebase_pulse),.marker_pulse(log_marker_pulse));
    end else begin:logger_disabled
      assign log_we=0; assign log_addr=0; assign log_data=0;
      assign log_count=0; assign log_base=0; assign rebase_pulse=0;
      assign log_marker_pulse=0;
    end endgenerate

    reg s2_meta=0,s2_sync=0,s2_state=0;
    reg [20:0] s2_stable_count=0; reg [26:0] s2_hold_count=0;
    reg s2_long_handled=0; reg overlay_visible=(DEBUG_OVERLAY!=0);
    reg [LOG_PAGE_WIDTH-1:0] log_page=0;
    reg [2:0] gime_trace_page=0;
    reg gime_trace_arm=0;
    always @(posedge clk108 or negedge board_reset_n) begin
      if(!board_reset_n) begin
        s2_meta<=0;s2_sync<=0;s2_state<=0;s2_stable_count<=0;
        s2_hold_count<=0;s2_long_handled<=0;
        overlay_visible<=(DEBUG_OVERLAY!=0);log_page<=0;
        gime_trace_page<=0;gime_trace_arm<=0;
        log_capture_active<=0;log_capture_clear<=0;
      end else begin
        log_capture_clear<=0;
        gime_trace_arm<=0;
        if(log_marker_pulse) begin
          // Entry zero is already the marker; retain it and capture the 8191
          // bus observations that follow.
          log_capture_active<=1'b1;
          log_page<=0;
        end else if(log_count>=LOG_DEPTH) log_capture_active<=0;
        s2_meta<=s2;s2_sync<=s2_meta;
        if(s2_sync==s2_state) begin
          s2_stable_count<=0;
          if(s2_state && !s2_long_handled) begin
            if(s2_hold_count==27'd107999999) begin
              overlay_visible<=!overlay_visible;log_page<=0;
              if(ENABLE_GIME_TRACE!=0 && ENABLE_BUS_LOGGER==0 &&
                 !overlay_visible) begin
                gime_trace_page<=0;
                gime_trace_arm<=1;
              end
              s2_long_handled<=1;
            end else s2_hold_count<=s2_hold_count+1'b1;
          end
        end else if(s2_stable_count==21'd1079999) begin
          s2_state<=s2_sync;s2_stable_count<=0;
          if(s2_sync) begin s2_hold_count<=0;s2_long_handled<=0; end
          else begin s2_hold_count<=0;
            if(!s2_long_handled) begin
              if(ENABLE_GIME_TRACE!=0 && ENABLE_BUS_LOGGER==0) begin
                if(gime_trace_page==3'd5)begin
                  gime_trace_page<=0;
                  gime_trace_arm<=1;
                end else gime_trace_page<=gime_trace_page+1'b1;
              end else if(overlay_visible)
                log_page<=(log_page==LAST_PAGE)?0:log_page+1'b1;
              else begin
                log_capture_clear<=1'b1;
                log_capture_active<=1'b1;
                log_page<=0;
              end
            end
          end
        end else s2_stable_count<=s2_stable_count+1'b1;
      end
    end

    wire interrupt_inputs_idle=gime_serint_n && gime_keyint_n && mux_halt_n;
    // While the released CPU has not yet programmed a video mode, reproduce
    // the CoCo 3 reset display as one uniform green field.  Without this mask
    // the cleared SDRAM is decoded as repeated native character-zero glyphs.
    // The ROM's first video action enters compatibility mode.  Latch that
    // existing transition here so reset presentation adds no decode or fanout
    // to the timing-critical GIME/scanline-renderer block.
    reg startup_video_blank=1'b1;
    always @(posedge clk108 or negedge cpu_release) begin
        if(!cpu_release) startup_video_blank<=1'b1;
        else if(compatibility_video) startup_video_blank<=1'b0;
    end
    wire [23:0] visible_hdmi_pixel = startup_video_blank ?
        24'h00ff00 : hdmi_pixel_data;
    wire [5:0] visible_cvbs_pixel = startup_video_blank ?
        6'b001100 : cvbs_pixel_data;
    wire [5:0] visible_border_rgb = startup_video_blank ?
        6'b001100 : border_rgb;
    wire [5:0] visible_cvbs_border = startup_video_blank ?
        6'b001100 : cvbs_border_data;
    wire [5:0] visible_cvbs_right_border = startup_video_blank ?
        6'b001100 : cvbs_right_border_data;
    wire visible_cvbs_border_valid = !startup_video_blank && cvbs_border_valid;
    coco3_hdmi #(.LOG_ADDR_WIDTH(LOG_ADDR_WIDTH),
        .LOG_COUNT_WIDTH(LOG_COUNT_WIDTH),.LOG_PAGE_WIDTH(LOG_PAGE_WIDTH),
        .LOG_DEPTH(LOG_DEPTH),
        .ENABLE_DEBUG_OVERLAY(ENABLE_BUS_LOGGER||ENABLE_GIME_TRACE),
        .GIME_TRACE_MODE(ENABLE_GIME_TRACE!=0&&ENABLE_BUS_LOGGER==0)) hdmi_output(
        .pixel_clk(clk27),.serial_clk(clk135),.reset(!board_reset_n),
        .audio_clk(pia1_audio_clk),.audio_pcm(pia1_pcm_sample),
        .debug_clk(clk108),.log_we(log_we),.log_addr(log_addr),
        .log_base(log_base),
        .log_data(log_data),.log_count(log_count),.log_page(log_page),
        .gime_trace_arm(gime_trace_arm),
        .gime_trace_page(gime_trace_page),
        .gime_trace_sample(gime_trace_sample),
        .gime_trace_y(gime_trace_y),
        .gime_trace_data({gime_trace_registers,gime_trace_cache_start,
            gime_trace_dma_next_address,gime_trace_cache_y,
            gime_trace_dma_next_y,gime_trace_active_line,
            gime_trace_dma_line,gime_trace_phase,gime_trace_cache_valid}),
        .debug_status({clocks_locked,filtered_mux_reset_n,mux_halt_n,
                       interrupt_inputs_idle,bus_ready_sync}),
        // Display asserted levels: KEYINT and SERNT are active-low inputs;
        // IRQ and FIRQ are active-high requests to the output transistors.
        .interrupt_status({!gime_keyint_n,!gime_serint_n,gime_irq,gime_firq}),
        .raster_debug(raster_debug),
        .gime_register_debug(gime_register_debug),
        .mmu_register_debug(mmu_register_debug),
        .rom_verify_done(rom_verify_done),.rom_verify_pass(rom_verify_pass),
        .rom_verify_vector(rom_verify_vector),
        .sdram_test_done(sdram_test_done),.sdram_test_pass(sdram_test_pass),
        .sdram_test_error_addr(sdram_test_error_addr),
        .sdram_test_expected(sdram_test_expected),
        .sdram_test_actual(sdram_test_actual),
        .artifact_mode(artifact_mode),
        .artifact_video_active(artifact_video_active),
        .artifact_css(artifact_css),
        .video_50hz(video_50hz),
        .bit_plane(native_bit_plane),
        .overlay_enable(overlay_visible),.active_height(active_height),
        .compatibility_mode(compatibility_video),
        .border_rgb(visible_border_rgb),
        .row_left_border_rgb(hdmi_left_border_data),
        .row_right_border_rgb(hdmi_right_border_data),
        .row_border_valid(!startup_video_blank&&hdmi_border_valid),
        .vertical_left_border_rgb(hdmi_vertical_left_border_data),
        .vertical_right_border_rgb(hdmi_vertical_right_border_data),
        .vertical_border_valid(compatibility_video&&!startup_video_blank&&
                               hdmi_vertical_border_valid),
        .pixel_data(visible_hdmi_pixel),
        .source_x(hdmi_source_x),.source_y(hdmi_source_y),
        .source_valid(hdmi_source_valid),
        .source_picture_active(hdmi_source_picture_active),
        .source_frame_start(hdmi_frame_start),
        .source_border_raster_y(hdmi_border_raster_y),
        .prefetch_y(hdmi_prefetch_y),
        .prefetch_valid(hdmi_prefetch_valid),
        .active_video_50hz(hdmi_video_50hz),.tmds_clk_p(tmds_clk_p),
        .tmds_clk_n(tmds_clk_n),.tmds_data_p(tmds_data_p),
        .tmds_data_n(tmds_data_n));

    wire analog_luma,analog_chroma,analog_cvbs;
    wire analog_component_pb,analog_component_pr;
    wire [15:0] unused_cvbs_framebuffer_addr;
    // Cut the encoder-counter -> line-buffer BSRAM-address path at the
    // clk135 boundary.  There are ten clk135 clocks per CVBS sample, so this
    // one-clock staging still leaves the scanline RAM response comfortably
    // ahead of the sample which consumes it.
    always @(posedge clk135 or negedge board_reset_n) begin
        if(!board_reset_n) begin
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
    coco_cvbs_ntsc #(.STREAMING_INPUT(0),.CANONICAL_640_INPUT(1),
        .RGB_SOG_OUTPUT(ANALOG_VIDEO_MODE==3)) analog_encoder(
        // Start on the same board reset as HDMI.  cpu_release is aligned to
        // the CoCo bus, not to video, and made the CVBS consumer enter the
        // shared two-line cache at an arbitrary scanline phase.
        .clk135(clk135),.clk270(clk270),.reset_n(board_reset_n),
        .video_50hz(hdmi_video_50hz),
        .high_resolution(1'b1),.compatibility_mode(compatibility_video),
        .framebuffer_data(visible_cvbs_pixel),
        .border_rgb(visible_border_rgb),.row_border_rgb(visible_cvbs_border),
        .row_right_border_rgb(visible_cvbs_right_border),
        .row_border_valid(visible_cvbs_border_valid),
        .vertical_left_border_rgb(cvbs_vertical_left_border_data),
        .vertical_right_border_rgb(cvbs_vertical_right_border_data),
        .vertical_border_valid(compatibility_video&&!startup_video_blank&&
                               cvbs_vertical_border_valid),
        .active_height(active_height),
        .framebuffer_addr(unused_cvbs_framebuffer_addr),
        .source_x(cvbs_source_x_raw),.source_y(cvbs_source_y_raw),
        .source_valid(cvbs_source_valid_raw),.prefetch_y(cvbs_prefetch_y_raw),
        .prefetch_valid(cvbs_prefetch_valid_raw),
        .border_raster_y(cvbs_border_raster_y),.luma_out(analog_luma),
        .chroma_out(analog_chroma),.cvbs_out(analog_cvbs),
        .component_pb_out(analog_component_pb),
        .component_pr_out(analog_component_pr));
    assign y_out=analog_luma;
    assign pb_out=((ANALOG_VIDEO_MODE==2)||(ANALOG_VIDEO_MODE==3)) ?
                  analog_component_pb : analog_chroma;
    assign cvbs_out=((ANALOG_VIDEO_MODE==2)||(ANALOG_VIDEO_MODE==3)) ?
                    analog_component_pr : analog_cvbs;

    wire unused_inputs=mux_slenb_n ^ mux_nmi_n ^ native_hblank ^
        native_vblank ^ ^native_red ^ ^native_green ^ ^native_blue ^ e_rise ^
        ^pia1_dac_level;
endmodule
