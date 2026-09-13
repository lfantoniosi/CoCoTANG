// Standalone physical-MC6809E bring-up top for the existing Tang displacer.
// This deliberately contains no PIA, VDG, framebuffer, CVBS, debug program,
// RAM fill, or motherboard-side client.  The external MP/MSEL circuitry is
// retained only because it is how the displacer presents CPU address/control.
module top_cpu_test #(
    parameter integer RESET_HOLD_CYCLES = 10800000,
    parameter integer LOG_DEPTH = 4096,
    parameter [15:0] LOG_START_ADDRESS = 16'h0000,
    parameter integer DEBUG_OVERLAY = 0,
    parameter integer ANALOG_VIDEO_MODE = 1
) (
    input clkin,
    input s1,
    input s2,
    input [7:0] mp,
    output [1:0] msel,
    inout [7:0] cpu_data,
    input irq_n_in,
    input firq_n_in,
    input audio_in,
    output halt_drive,
    output e_out,
    output q_out,
    output hs_n,
    output fs_n,
    output [2:0] sam_s,
    output y_out,
    output pb_out,
    output tmds_clk_p,
    output tmds_clk_n,
    output [2:0] tmds_data_p,
    output [2:0] tmds_data_n,
    output mspi_sclk,
    output mspi_cs,
    output mspi_mosi,
    input mspi_miso,
    output O_sdram_clk,
    output O_sdram_cke,
    output O_sdram_cs_n,
    output O_sdram_cas_n,
    output O_sdram_ras_n,
    output O_sdram_wen_n,
    inout [31:0] IO_sdram_dq,
    output [10:0] O_sdram_addr,
    output [1:0] O_sdram_ba,
    output [3:0] O_sdram_dqm
);
    localparam integer LOG_ADDR_WIDTH = 12;
    localparam integer LOG_COUNT_WIDTH = 13;
    localparam integer LOG_PAGE_WIDTH = 6;
    localparam integer ENTRIES_PER_PAGE = 116;
    localparam [LOG_PAGE_WIDTH-1:0] LAST_PAGE =
        (LOG_DEPTH-1)/ENTRIES_PER_PAGE;

    wire clk108,clk108p,clk270,clk135,board_reset_n,clocks_locked;
    coco_clocks clocks (
        .clkin(clkin), .button_reset(s1), .clk108(clk108), .clk108p(clk108p),
        .clk270(clk270), .clk135(clk135), .board_reset_n(board_reset_n),
        .clocks_locked(clocks_locked)
    );

    // E and Q run as soon as the PLL/reset domain is ready.  The SAM register
    // bank remains reset until the physical CPU is released much later.
    wire e_rise,e_fall;
    wire [2:0] internal_s;
    wire [2:0] sam_video_mode;
    wire [6:0] sam_video_offset;
    wire unused_page,unused_all_ram;
    wire [1:0] unused_rate,unused_memory_size;
    reg cpu_release = 1'b0;
    wire cpu_memory_wait;
    wire [15:0] address;
    wire rw_n;
    coco_sam sam (
        .clk(clk108), .reset_n(board_reset_n), .register_reset_n(cpu_release),
        // An external 6809E has no READY input.  E and Q are its master
        // clocks and must run continuously; SDRAM latency may never be turned
        // into a stopped-clock "wait state".
        .memory_wait(1'b0),
        .addr(address), .rw_n(rw_n), .s(internal_s),
        .e(e_out), .q(q_out), .e_rise(e_rise), .e_fall(e_fall),
        .video_mode(sam_video_mode), .video_offset(sam_video_offset),
        .page(unused_page), .rate(unused_rate),
        .memory_size(unused_memory_size), .all_ram(unused_all_ram)
    );

    assign sam_s = internal_s;

    // Existing displacer acquisition hardware.  Nothing from the CoCo
    // motherboard is required or interpreted by this top.
    reg q_scan_delay = 1'b0;
    always @(posedge clk135 or negedge board_reset_n) begin
        if (!board_reset_n)
            q_scan_delay<=1'b0;
        else
            q_scan_delay<=q_out;
    end
    wire bus_scan_start=q_out && !q_scan_delay;
    wire mux_reset_n,mux_slenb_n,mux_sernt_n,mux_cart_n,mux_keyint_n;
    wire mux_halt_n,mux_nmi_n,bus_snapshot_ready_async;
    coco_bus_mux bus_mux (
        .clk(clk135), .reset_n(board_reset_n), .scan_start(bus_scan_start),
        .mp(mp), .msel(msel), .addr(address), .rw_n(rw_n),
        .cpu_reset_n(mux_reset_n), .slenb_n(mux_slenb_n),
        .sernt_n(mux_sernt_n), .cart_n(mux_cart_n),
        .keyint_n(mux_keyint_n), .halt_n(mux_halt_n), .nmi_n(mux_nmi_n),
        .snapshot_valid(bus_snapshot_ready_async)
    );
    reg bus_ready_meta=1'b0,bus_ready_sync=1'b0,bus_ready_delay=1'b0;
    always @(posedge clk108 or negedge board_reset_n) begin
        if (!board_reset_n) begin
            bus_ready_meta<=1'b0;
            bus_ready_sync<=1'b0;
            bus_ready_delay<=1'b0;
        end else begin
            bus_ready_meta<=bus_snapshot_ready_async;
            bus_ready_sync<=bus_ready_meta;
            bus_ready_delay<=bus_ready_sync;
        end
    end
    wire bus_snapshot_valid=bus_ready_sync && !bus_ready_delay;
    // The motherboard RESET node has a slow RC rise and can cross the digital
    // threshold many times.  It must not gate the synchronous memory state:
    // doing so can park SAM at Q-high/E-low on one RESET sample and prevent
    // the next mux scan needed for recovery.  Begin servicing the reset-vector
    // address as soon as our open-collector RESET driver releases it.  The CPU
    // continues holding FFFE during the RC rise, giving SDRAM time to prefetch
    // and present the vector byte before the CPU recognizes RESET high.
    wire cpu_bus_active=cpu_release;
    // Before the CPU recognizes the slow external RESET rise it repeatedly
    // presents FFFE.  Allow those cycles to prefetch the high vector byte, but
    // never stop Q/E during that interval: stopping Q would also stop the mux
    // scanner.  FFFF is the first proof that the CPU has entered its real
    // reset-vector sequence; normal SDRAM clock stretching is safe afterward.
    reg cpu_started=1'b0;
    always @(posedge clk108 or negedge board_reset_n) begin
        if (!board_reset_n)
            cpu_started<=1'b0;
        else if (!cpu_release)
            cpu_started<=1'b0;
        else if (bus_snapshot_valid && address == 16'hffff)
            cpu_started<=1'b1;
    end
    // A 6309 write byte is valid during E high and may be released immediately
    // after E falls. Keep the latest full-clock sample from that window so RAM,
    // PIA shadowing and diagnostics do not depend on FPGA/input-buffer skew at
    // the exact external falling edge.
    reg [7:0] cpu_write_data=8'hff;
    always @(posedge clk108 or negedge board_reset_n) begin
        if (!board_reset_n)
            cpu_write_data<=8'hff;
        else if (cpu_bus_active && e_out && !rw_n)
            cpu_write_data<=cpu_data;
    end
    // cpu_memory_wait is diagnostic only.  It must never feed the SAM clock
    // generator: the memory path has to prefetch/cache early enough to meet
    // the fixed 6809 bus cycle.
    wire [2:0] filtered_pia_inputs;
    input_filter #(.WIDTH(3)) pia_input_filter (
        .clk(clk108), .reset_n(board_reset_n),
        .in({irq_n_in,firq_n_in,audio_in}), .out(filtered_pia_inputs)
    );
    wire pia_interrupts_idle=filtered_pia_inputs[2] &&
                             filtered_pia_inputs[1] &&
                             mux_keyint_n && mux_sernt_n;

    wire sdram_reset_n,loader_start,system_ready,sdram_enabled,loader_done;
    coco_startup startup (
        .clk(clk108), .board_reset_n(board_reset_n),
        .sdram_enabled(sdram_enabled), .loader_done(loader_done),
        .sdram_reset_n(sdram_reset_n), .loader_start(loader_start),
        .system_ready(system_ready)
    );

    wire sd_rd,sd_wr,sd_refresh,sd_data_ready,sd_busy;
    wire [22:0] sd_addr;
    wire [15:0] sd_din,sd_dout;
    wire [31:0] sd_dout32;
    wire [1:0] sd_wdm;
    sdram sdram_controller (
        .SDRAM_DQ(IO_sdram_dq), .SDRAM_A(O_sdram_addr),
        .SDRAM_BA(O_sdram_ba), .SDRAM_nCS(O_sdram_cs_n),
        .SDRAM_nWE(O_sdram_wen_n), .SDRAM_nRAS(O_sdram_ras_n),
        .SDRAM_nCAS(O_sdram_cas_n), .SDRAM_CLK(O_sdram_clk),
        .SDRAM_CKE(O_sdram_cke), .SDRAM_DQM(O_sdram_dqm),
        .clk(clk108), .clk_sdram(clk108p), .resetn(sdram_reset_n),
        .rd(sd_rd), .wr(sd_wr), .refresh(sd_refresh), .addr(sd_addr),
        .din(sd_din), .wdm(sd_wdm), .dout(sd_dout),
        .dout32(sd_dout32), .data_ready(sd_data_ready),
        .busy(sd_busy), .enabled(sdram_enabled)
    );

    // ROM loading already holds reset for a substantial interval.  Add a
    // deterministic 100 ms default afterward and release only on E falling.
    localparam integer RESET_HOLD_WIDTH = $clog2(RESET_HOLD_CYCLES + 1);
    reg [RESET_HOLD_WIDTH-1:0] reset_hold_count = 0;
    reg release_pending = 1'b0;
    always @(posedge clk108 or negedge board_reset_n) begin
        if (!board_reset_n) begin
            reset_hold_count<=0;
            release_pending<=1'b0;
            cpu_release<=1'b0;
        end else if (!system_ready) begin
            reset_hold_count<=0;
            release_pending<=1'b0;
            cpu_release<=1'b0;
        end else if (!cpu_release) begin
            if (reset_hold_count < RESET_HOLD_CYCLES)
                reset_hold_count<=reset_hold_count+1'b1;
            else
                release_pending<=1'b1;
            if (release_pending && e_fall)
                cpu_release<=1'b1;
        end
    end
    // Q2 on the displacer is the inverting open-collector RESET driver.
    assign halt_drive=!cpu_release;

    wire [7:0] fpga_read_data;
    wire fpga_data_oe;
    wire [15:0] vdg_memory_addr;
    wire [7:0] video_memory_data;
    wire video_memory_valid;
    cpu_test_memory memory (
        .clk(clk108), .reset_n(sdram_reset_n), .loader_start(loader_start),
        .cpu_access_enable(cpu_bus_active), .cpu_bus_valid(bus_snapshot_valid),
        .e(e_out), .q(q_out), .e_fall(e_fall),
        .cpu_addr(address), .cpu_rw_n(rw_n),
        .sam_s(internal_s), .cpu_wdata(cpu_write_data),
        .cpu_rdata(fpga_read_data), .cpu_data_oe(fpga_data_oe),
        .cpu_wait(cpu_memory_wait),
        .video_addr({7'd0,vdg_memory_addr}),
        .video_data(video_memory_data),
        .video_data_valid(video_memory_valid),
        .loader_done(loader_done),
        .mspi_cs(mspi_cs), .mspi_sclk(mspi_sclk),
        .mspi_miso(mspi_miso), .mspi_mosi(mspi_mosi),
        .sdram_enabled(sdram_enabled), .sd_rd(sd_rd), .sd_wr(sd_wr),
        .sd_refresh(sd_refresh), .sd_addr(sd_addr), .sd_din(sd_din),
        .sd_wdm(sd_wdm), .sd_dout(sd_dout), .sd_dout32(sd_dout32),
        .sd_data_ready(sd_data_ready), .sd_busy(sd_busy)
    );
    assign cpu_data=fpga_data_oe ? fpga_read_data : 8'bz;

    // Restore the MC6847 around the proven physical-CPU path. PIA1 port-B
    // writes at $FF22/$FF23 are shadowed inside coco_vdg for A/G, INT/EXT,
    // and CSS. HS and FS return to their motherboard PIA input pins.
    wire [7:0] vdg_red,vdg_green,vdg_blue;
    wire [5:0] vdg_border_rgb;
    wire vdg_hblank,vdg_vblank;
    wire [7:0] unused_vdg_cvbs;
    wire framebuffer_write;
    wire [15:0] framebuffer_write_addr;
    wire [5:0] framebuffer_write_data;
    // Keep the asynchronous, mux-sampled RESET node out of the VDG reset path
    // for the same reason. cpu_release is synchronous to clk108.
    wire vdg_reset_n=board_reset_n && cpu_started;
    coco_vdg vdg (
        .clk(clk108), .reset_n(vdg_reset_n),
        .e_fall(e_fall), .cpu_rw_n(rw_n), .cpu_addr(address),
        .cpu_data(cpu_write_data), .sam_video_mode(sam_video_mode),
        .debug_an_g(1'b0), .debug_css(1'b0),
        .sam_video_offset(sam_video_offset),
        .memory_data(video_memory_data), .memory_addr(vdg_memory_addr),
        .hs_n(hs_n), .fs_n(fs_n), .red(vdg_red), .green(vdg_green),
        .blue(vdg_blue), .border_rgb(vdg_border_rgb),
        .hblank(vdg_hblank), .vblank(vdg_vblank),
        .cvbs(unused_vdg_cvbs), .pixel_capture(framebuffer_write),
        .capture_addr(framebuffer_write_addr),
        .capture_rgb(framebuffer_write_data)
    );

    wire [15:0] hdmi_framebuffer_addr,cvbs_framebuffer_addr;
    wire [5:0] hdmi_framebuffer_data,cvbs_framebuffer_data;
    coco_framebuffer framebuffer (
        .write_clk(clk108), .write_en(framebuffer_write),
        .write_addr(framebuffer_write_addr), .write_data(framebuffer_write_data),
        .read_clk(clk135), .hdmi_addr(hdmi_framebuffer_addr),
        .hdmi_data(hdmi_framebuffer_data), .cvbs_addr(cvbs_framebuffer_addr),
        .cvbs_data(cvbs_framebuffer_data)
    );

    // Begin with the first active CPU bus cycle, regardless of its address.
    // The first occurrence of LOG_START_ADDRESS rewinds the log and records
    // that cycle as entry 000. Bus data is sampled at E falling, when the 6809
    // consumes read data or completes a write. Consecutive cycles at the same
    // address share one row.
    reg log_we=1'b0;
    reg [LOG_ADDR_WIDTH-1:0] log_addr=0;
    reg [39:0] log_data=0;
    reg [LOG_COUNT_WIDTH-1:0] log_count=0;
    reg [24:0] last_observation=0;
    reg observation_valid=1'b0;
    reg log_rebased=1'b0;
    reg log_rebase_pulse=1'b0;
    wire [7:0] sampled_cpu_data=rw_n ? cpu_data : cpu_write_data;
    wire [24:0] observation={rw_n,address,sampled_cpu_data};
    always @(posedge clk108 or negedge board_reset_n) begin
        if (!board_reset_n) begin
            log_we<=1'b0;
            log_addr<=0;
            log_data<=0;
            log_count<=0;
            last_observation<=0;
            observation_valid<=1'b0;
            log_rebased<=1'b0;
            log_rebase_pulse<=1'b0;
        end else begin
            log_we<=1'b0;
            log_rebase_pulse<=1'b0;
            if (!cpu_release) begin
                observation_valid<=1'b0;
                log_rebased<=1'b0;
            end else if (!log_rebased && e_fall &&
                         address == LOG_START_ADDRESS && LOG_START_ADDRESS != 16'h0000) begin
                // Include the trigger cycle itself as the first new entry.
                log_we<=1'b1;
                log_addr<=0;
                log_data<={1'b1,rw_n,internal_s,fpga_data_oe,address,
                           sampled_cpu_data,fpga_read_data,q_out,e_out};
                log_count<=1;
                last_observation<=observation;
                observation_valid<=1'b1;
                log_rebased<=1'b1;
                log_rebase_pulse<=1'b1;
            end else if (e_fall &&
                         ((observation_valid &&
                           address == last_observation[23:8]) ||
                          log_count < LOG_DEPTH)) begin
                log_we<=1'b1;
                log_data<={1'b1,rw_n,internal_s,fpga_data_oe,address,
                           sampled_cpu_data,fpga_read_data,q_out,e_out};
                if (observation_valid && address == last_observation[23:8]) begin
                    // Preserve the row number but refresh it with the latest
                    // data and control values observed at this address.
                    log_addr<=log_count[LOG_ADDR_WIDTH-1:0]-1'b1;
                end else begin
                    log_addr<=log_count[LOG_ADDR_WIDTH-1:0];
                    log_count<=log_count+1'b1;
                end
                last_observation<=observation;
                observation_valid<=1'b1;
            end
        end
    end

    // A short debounced S2 press advances one 116-entry log page. Holding S2
    // for one second toggles the overlay, which starts hidden so VDG video is
    // visible immediately after configuration.
    reg s2_meta=1'b0,s2_sync=1'b0,s2_state=1'b0;
    reg [20:0] s2_stable_count=0;
    reg [26:0] s2_hold_count=0;
    reg s2_long_handled=1'b0;
    reg overlay_visible=(DEBUG_OVERLAY != 0);
    reg [LOG_PAGE_WIDTH-1:0] log_page=0;
    always @(posedge clk108 or negedge board_reset_n) begin
        if (!board_reset_n) begin
            s2_meta<=1'b0;
            s2_sync<=1'b0;
            s2_state<=1'b0;
            s2_stable_count<=0;
            s2_hold_count<=0;
            s2_long_handled<=1'b0;
            overlay_visible<=(DEBUG_OVERLAY != 0);
            log_page<=0;
        end else begin
            s2_meta<=s2;
            s2_sync<=s2_meta;
            if (log_rebase_pulse) begin
                // Always expose entry 000 after the trigger rewinds the log.
                log_page<=0;
            end
            if (s2_sync == s2_state) begin
                s2_stable_count<=0;
                if (s2_state && !s2_long_handled) begin
                    if (s2_hold_count == 27'd107999999) begin
                        overlay_visible<=!overlay_visible;
                        s2_long_handled<=1'b1;
                    end else
                        s2_hold_count<=s2_hold_count+1'b1;
                end
            end else if (s2_stable_count == 21'd1079999) begin
                s2_state<=s2_sync;
                s2_stable_count<=0;
                if (s2_sync) begin
                    s2_hold_count<=0;
                    s2_long_handled<=1'b0;
                end else begin
                    s2_hold_count<=0;
                    if (!s2_long_handled)
                        log_page <= (log_page == LAST_PAGE) ?
                                    {LOG_PAGE_WIDTH{1'b0}} : log_page+1'b1;
                end
            end else
                s2_stable_count<=s2_stable_count+1'b1;
        end
    end

    cpu_test_hdmi #(
        .LOG_ADDR_WIDTH(LOG_ADDR_WIDTH), .LOG_COUNT_WIDTH(LOG_COUNT_WIDTH),
        .LOG_PAGE_WIDTH(LOG_PAGE_WIDTH), .LOG_DEPTH(LOG_DEPTH)
    ) hdmi_output (
        .pixel_clk(clkin), .serial_clk(clk135), .reset(!board_reset_n),
        .debug_clk(clk108), .log_we(log_we), .log_addr(log_addr),
        .log_data(log_data), .log_count(log_count), .log_page(log_page),
        .debug_status({clocks_locked,mux_reset_n,mux_halt_n,
                       pia_interrupts_idle,bus_ready_sync}),
        .overlay_enable(overlay_visible),
        .framebuffer_data(hdmi_framebuffer_data),
        .border_rgb(vdg_border_rgb),
        .framebuffer_addr(hdmi_framebuffer_addr),
        .tmds_clk_p(tmds_clk_p), .tmds_clk_n(tmds_clk_n),
        .tmds_data_p(tmds_data_p), .tmds_data_n(tmds_data_n)
    );

    wire [9:0] unused_cvbs_source_x;
    wire [7:0] unused_cvbs_source_y,unused_cvbs_prefetch_y;
    wire unused_cvbs_source_valid,unused_cvbs_prefetch_valid;
    wire analog_luma,analog_chroma,analog_cvbs;
    coco_cvbs_ntsc analog_encoder (
        .clk135(clk135), .clk270(clk270), .reset_n(board_reset_n),
        .high_resolution(1'b0), .framebuffer_data(cvbs_framebuffer_data),
        .border_rgb(vdg_border_rgb), .active_height(8'd192),
        .framebuffer_addr(cvbs_framebuffer_addr),
        .source_x(unused_cvbs_source_x), .source_y(unused_cvbs_source_y),
        .source_valid(unused_cvbs_source_valid),
        .prefetch_y(unused_cvbs_prefetch_y),
        .prefetch_valid(unused_cvbs_prefetch_valid),
        .luma_out(analog_luma), .chroma_out(analog_chroma),
        .cvbs_out(analog_cvbs)
    );
    assign y_out=analog_luma;
    assign pb_out=(ANALOG_VIDEO_MODE == 0) ? analog_chroma : analog_cvbs;

    // These motherboard-owned signals reach the physical CPU directly. They
    // are observed here for diagnostics, but must never qualify FPGA memory.
    wire unused_inputs=filtered_pia_inputs[0] ^ mux_slenb_n ^ mux_cart_n ^
                       mux_nmi_n ^
                       video_memory_valid ^ vdg_hblank ^ vdg_vblank ^
                       ^vdg_red ^ ^vdg_green ^ ^vdg_blue;
endmodule
