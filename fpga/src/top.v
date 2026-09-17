// CoCo 2 top for the physical MC6809E and motherboard PIAs.  The FPGA
// implements SAM timing, SDRAM/ROM service, MC6847-compatible video, HDMI and
// CVBS.  The external MP/MSEL circuitry presents CPU address and control.
module top #(
    parameter integer RESET_HOLD_CYCLES = 10800000,
    parameter integer LOG_DEPTH = 4096,
    //parameter [15:0] LOG_START_ADDRESS = 16'hA199, //16'hA056,
    parameter [15:0] LOG_START_ADDRESS = 16'h8002, //16'hA056,
    parameter [15:0] LOG_WRITE_START_ADDRESS = 16'h0000,
    parameter [15:0] LOG_WRITE_END_ADDRESS = 16'h0000,
    // Set to 1 to synthesize the CPU bus logger and HDMI overlay.  At 0 the
    // overlay instance is not elaborated and synthesis removes the complete
    // unobserved logger cone, keeping it out of CPU/SDRAM placement entirely.
    parameter integer ENABLE_BUS_LOGGER = 0,
    parameter integer DEBUG_OVERLAY = 0,
    parameter integer ENABLE_ARTIFACT_COLOR = 1,
    parameter integer ANALOG_VIDEO_MODE = 1
) (
    input clkin,
    input s1,
    input s2,
    input [7:0] mp,
    output [1:0] msel,
    inout [7:0] cpu_data,
    output irq_n_in,
    output firq_n_in,
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
    // These pins feed NPN transistor bases, not FPGA interrupt inputs.  Keep
    // them low to release the motherboard's active-low IRQ and FIRQ nets.
    assign irq_n_in = 1'b0;
    assign firq_n_in = 1'b0;

    localparam integer LOG_ADDR_WIDTH = 12;
    localparam integer LOG_COUNT_WIDTH = 13;
    localparam integer LOG_PAGE_WIDTH = 6;
    localparam integer ENTRIES_PER_PAGE = 116;
    localparam [LOG_PAGE_WIDTH-1:0] LAST_PAGE =
        (LOG_DEPTH-1)/ENTRIES_PER_PAGE;

    wire clk108,clk108p,clk270,clk135,clk27,board_reset_n,clocks_locked;
    coco_clocks clocks (
        .clkin(clkin), .button_reset(s1), .clk108(clk108), .clk108p(clk108p),
        .clk270(clk270), .clk135(clk135), .clk27(clk27),
        .board_reset_n(board_reset_n),
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
    wire sam_master_tick;
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
        .master_tick(sam_master_tick),
        .video_mode(sam_video_mode), .video_offset(sam_video_offset),
        .page(unused_page), .rate(unused_rate),
        .memory_size(unused_memory_size), .all_ram(unused_all_ram)
    );

    assign sam_s = internal_s;
    // Existing displacer acquisition hardware.  Nothing from the CoCo
    // motherboard is required or interpreted by this top.
    // Q is generated in the clk108 domain.  Pass it through a conventional
    // two-flop synchronizer before edge detection in clk135; sampling Q with
    // one clk135 flop made the scan launch phase placement-dependent.
    reg q_scan_meta = 1'b0;
    reg q_scan_sync = 1'b0;
    reg q_scan_delay = 1'b0;
    always @(posedge clk135 or negedge board_reset_n) begin
        if (!board_reset_n) begin
            q_scan_meta<=1'b0;
            q_scan_sync<=1'b0;
            q_scan_delay<=1'b0;
        end else begin
            q_scan_meta<=q_out;
            q_scan_sync<=q_scan_meta;
            q_scan_delay<=q_scan_sync;
        end
    end
    wire bus_scan_start=q_scan_sync && !q_scan_delay;
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
    wire filtered_mux_reset_n;
    input_filter #(.WIDTH(1)) mux_reset_filter (
        .clk(clk108), .reset_n(board_reset_n),
        .in(mux_reset_n), .out(filtered_mux_reset_n)
    );
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
    wire [7:0] cpu_data_in;
    // These two buses are pad-side only. Gowin IOLOGIC outputs cannot also
    // feed fabric logic; diagnostics use fpga_read_data/fpga_data_oe as the
    // matching fabric-side expected value and cpu_data_in as pin readback.
    wire [7:0] cpu_pin_data;
    wire [7:0] cpu_pin_oen;
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
            cpu_write_data<=cpu_data_in;
    end
    // cpu_memory_wait is diagnostic only.  It must never feed the SAM clock
    // generator: the memory path has to prefetch/cache early enough to meet
    // the fixed 6809 bus cycle.
    // IRQ/FIRQ cannot be observed through their one-way base-drive pins.
    // KEYINT/SERNT are the interrupt-source states visible through the mux.
    wire pia_interrupts_idle=mux_keyint_n && mux_sernt_n;

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

    // Keep HDMI continuously standards-compliant from board reset. Release
    // the VDG only on a clean HDMI frame boundary, then pace it from an exact
    // 35/264 divider without altering the proven physical-CPU SAM clock.
    wire hdmi_vdg_start;
    reg hdmi_frame_meta=1'b0,hdmi_frame_sync=1'b0,hdmi_frame_delay=1'b0;
    reg vdg_release=1'b0;
    reg [8:0] vdg_accumulator=9'd0;
    reg vdg_master_tick=1'b0;
    wire [9:0] vdg_sum={1'b0,vdg_accumulator}+10'd35;
    wire [9:0] vdg_wrapped_sum=vdg_sum-10'd264;
    always @(posedge clk108 or negedge board_reset_n) begin
        if (!board_reset_n) begin
            hdmi_frame_meta<=1'b0;
            hdmi_frame_sync<=1'b0;
            hdmi_frame_delay<=1'b0;
            vdg_release<=1'b0;
            vdg_accumulator<=9'd0;
            vdg_master_tick<=1'b0;
        end else begin
            hdmi_frame_meta<=hdmi_vdg_start;
            hdmi_frame_sync<=hdmi_frame_meta;
            hdmi_frame_delay<=hdmi_frame_sync;
            if (!cpu_started)
                vdg_release<=1'b0;
            else if (hdmi_frame_sync && !hdmi_frame_delay)
                vdg_release<=1'b1;
            if (!vdg_release) begin
                vdg_accumulator<=9'd0;
                vdg_master_tick<=1'b0;
            end else if (vdg_sum >= 10'd264) begin
                vdg_accumulator<=vdg_wrapped_sum[8:0];
                vdg_master_tick<=1'b1;
            end else begin
                vdg_accumulator<=vdg_sum[8:0];
                vdg_master_tick<=1'b0;
            end
        end
    end
    wire vdg_reset_n=board_reset_n && vdg_release;

    wire [7:0] fpga_read_data;
    wire fpga_data_oe;
    wire [15:0] vdg_memory_addr;
    wire [7:0] video_memory_data;
    wire video_memory_valid;
    wire vdg_row_prefetch;
    coco_memory memory (
        .clk(clk108), .reset_n(sdram_reset_n), .loader_start(loader_start),
        .cpu_access_enable(cpu_bus_active), .cpu_bus_valid(bus_snapshot_valid),
        .e(e_out), .q(q_out), .e_fall(e_fall),
        .cpu_addr(address), .cpu_rw_n(rw_n),
        .sam_s(internal_s), .cpu_wdata(cpu_write_data),
        .cpu_rdata(fpga_read_data), .cpu_data_oe(fpga_data_oe),
        .cpu_wait(cpu_memory_wait),
        .video_enable(vdg_reset_n),
        .video_addr({7'd0,vdg_memory_addr}),
        .video_hs_n(hs_n), .video_row_prefetch(vdg_row_prefetch),
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
    // Register data and tristate control in each physical CPU-data I/O cell.
    // Fabric registers were still independently routed to the eight pins, so
    // a placement change could skew one transition (observed as $27 -> $A7).
    // ODDR with D0=D1 acts as an SDR output register; Q1 is the matching
    // active-high OEN register for the adjacent IOBUF.
    genvar cpu_data_bit;
    generate
        for (cpu_data_bit=0;cpu_data_bit<8;cpu_data_bit=cpu_data_bit+1) begin : cpu_data_iologic
            ODDR cpu_output_register (
                .Q0(cpu_pin_data[cpu_data_bit]),
                .Q1(cpu_pin_oen[cpu_data_bit]),
                .D0(fpga_read_data[cpu_data_bit]),
                .D1(fpga_read_data[cpu_data_bit]),
                .TX(!fpga_data_oe),
                .CLK(clk108)
            );
            defparam cpu_output_register.INIT=1'b1;
            defparam cpu_output_register.TXCLK_POL=1'b0;
            IOBUF cpu_data_buffer (
                .O(cpu_data_in[cpu_data_bit]),
                .IO(cpu_data[cpu_data_bit]),
                .I(cpu_pin_data[cpu_data_bit]),
                .OEN(cpu_pin_oen[cpu_data_bit])
            );
        end
    endgenerate

    // Restore the MC6847 around the proven physical-CPU path. PIA1 port-B
    // writes at $FF22/$FF23 are shadowed inside coco_vdg for A/G, INT/EXT,
    // and CSS. HS and FS return to their motherboard PIA input pins.
    wire [7:0] vdg_red,vdg_green,vdg_blue;
    wire [5:0] vdg_native_rgb;
    wire [5:0] vdg_border_rgb;
    wire vdg_hblank,vdg_vblank;
    wire [7:0] unused_vdg_cvbs;
    // Keep the asynchronous, mux-sampled RESET node out of the VDG reset path
    // for the same reason. cpu_release is synchronous to clk108.
    coco_vdg #(
        .SCAN_DOUBLED_OUTPUT(1),
        .ENABLE_ARTIFACT_COLOR(ENABLE_ARTIFACT_COLOR)
    ) vdg (
        .clk(clk108), .reset_n(vdg_reset_n), .bus_reset_n(board_reset_n),
        .sam_tick(vdg_master_tick),
        .e_fall(e_fall), .cpu_rw_n(rw_n), .cpu_addr(address),
        .cpu_data(cpu_write_data), .sam_video_mode(sam_video_mode),
        .debug_an_g(1'b0), .debug_css(1'b0),
        .sam_video_offset(sam_video_offset),
        .memory_data(video_memory_data), .memory_addr(vdg_memory_addr),
        .hs_n(hs_n), .fs_n(fs_n), .red(vdg_red), .green(vdg_green),
        .blue(vdg_blue), .border_rgb(vdg_border_rgb),
        .hblank(vdg_hblank), .vblank(vdg_vblank),
        .row_prefetch(vdg_row_prefetch),
        .cvbs(unused_vdg_cvbs), .native_rgb(vdg_native_rgb),
        .pixel_capture(), .capture_addr(), .capture_rgb()
    );

    // Begin with the first active CPU bus cycle, regardless of its address.
    // The first READ from LOG_START_ADDRESS rewinds the log and arms a second
    // trigger.  The first subsequent RAM write in the inclusive
    // LOG_WRITE_START_ADDRESS..LOG_WRITE_END_ADDRESS range rewinds the log a
    // second time, recording that write as entry 000.  A 0000 read address
    // disables both stages; setting both write-range endpoints to 0000
    // disables only the second stage. Bus data is sampled at E falling, when
    // the 6809 consumes read data or completes a write. Consecutive cycles at
    // the same address share one row.
    reg log_we=1'b0;
    reg [LOG_ADDR_WIDTH-1:0] log_addr=0;
    reg [39:0] log_data=0;
    reg [LOG_COUNT_WIDTH-1:0] log_count=0;
    reg [24:0] last_observation=0;
    reg observation_valid=1'b0;
    reg log_rebased=1'b0;
    reg log_write_rebased=1'b0;
    reg log_rebase_pulse=1'b0;

    // e_fall is registered by coco_sam on the same clk108 edge that lowers
    // the physical E output. Other synchronous blocks observe that pulse one
    // clk108 edge later. Preserve the bus state on every edge so that, when
    // e_fall is observed, the logger uses the state that existed immediately
    // before E physically fell -- not data that arrived up to 9.26 ns late.
    reg [15:0] cpu_sample_address=16'hffff;
    reg [7:0] cpu_sample_data=8'hff;
    reg [7:0] cpu_sample_expected=8'hff;
    reg [2:0] cpu_sample_s=3'd7;
    reg cpu_sample_rw_n=1'b1;
    reg cpu_sample_oe=1'b0;
    reg cpu_sample_wait=1'b1;
    reg q_sample_previous=1'b0;
    reg q_read_window_seen=1'b0;
    reg q_read_window_met=1'b0;
    reg [15:0] q_read_window_address=16'hffff;
    // Pipeline the configurable trigger comparison.  This keeps its 16-bit
    // comparator out of the log-address update path, whose placement used to
    // change substantially with each LOG_START_ADDRESS value.
    reg log_trigger_match=1'b0;
    reg log_write_trigger_match=1'b0;
    always @(posedge clk108 or negedge board_reset_n) begin
        if (!board_reset_n) begin
            cpu_sample_address<=16'hffff;
            cpu_sample_data<=8'hff;
            cpu_sample_expected<=8'hff;
            cpu_sample_s<=3'd7;
            cpu_sample_rw_n<=1'b1;
            cpu_sample_oe<=1'b0;
            cpu_sample_wait<=1'b1;
            q_sample_previous<=1'b0;
            q_read_window_seen<=1'b0;
            q_read_window_met<=1'b0;
            q_read_window_address<=16'hffff;
            log_trigger_match<=1'b0;
            log_write_trigger_match<=1'b0;
        end else begin
            cpu_sample_address<=address;
            cpu_sample_data<=cpu_data_in;
            cpu_sample_expected<=fpga_read_data;
            cpu_sample_s<=internal_s;
            cpu_sample_rw_n<=rw_n;
            cpu_sample_oe<=fpga_data_oe;
            cpu_sample_wait<=cpu_memory_wait;
            q_sample_previous<=q_out;
            log_trigger_match<=cpu_sample_rw_n &&
                               cpu_sample_address == LOG_START_ADDRESS &&
                               LOG_START_ADDRESS != 16'h0000;
            log_write_trigger_match<=!cpu_sample_rw_n &&
                cpu_sample_s == 3'd0 &&
                (LOG_WRITE_START_ADDRESS != 16'h0000 ||
                 LOG_WRITE_END_ADDRESS != 16'h0000) &&
                cpu_sample_address >= LOG_WRITE_START_ADDRESS &&
                cpu_sample_address <= LOG_WRITE_END_ADDRESS;

            // q_out changes just after a clk108 edge. Detect its falling edge
            // on the following clock, about 9.26 ns after physical Q falls.
            // Requiring the byte here reserves almost the complete final
            // Q-low/E-high quadrant as CPU read-data setup margin.
            if (!q_sample_previous && q_out) begin
                q_read_window_seen<=1'b0;
                q_read_window_met<=1'b0;
            end else if (q_sample_previous && !q_out) begin
                q_read_window_seen<=rw_n && internal_s <= 3'd2;
                q_read_window_address<=address;
                q_read_window_met<=rw_n && internal_s <= 3'd2 &&
                                   fpga_data_oe && !cpu_memory_wait &&
                                   cpu_data_in == fpga_read_data;
            end
        end
    end

    // Per-entry CPU-facing SDRAM deadline status. A read passes only if its
    // exact tagged response is on the physical bus just after Q falls and is
    // still correct at the E-falling sampling edge. Writes pass when their
    // byte is captured at E falling; physical SDRAM retirement is later.
    wire logged_sdram_cycle=(cpu_sample_rw_n && cpu_sample_s <= 3'd2) ||
                            (!cpu_sample_rw_n && cpu_sample_s == 3'd0);
    wire e_read_window_met=cpu_sample_oe && !cpu_sample_wait &&
                           cpu_sample_data == cpu_sample_expected;
    wire q_window_for_sample=q_read_window_seen && q_read_window_met &&
                             q_read_window_address == cpu_sample_address;
    // Timing code stored in log bits [1:0]:
    //   00 = not SDRAM, 01 = missed E, 10 = valid by E only/write at E,
    //   11 = read valid from the Q-falling checkpoint through E falling.
    wire [1:0] memory_timing_status=!logged_sdram_cycle ? 2'b00 :
        !cpu_sample_rw_n ? 2'b10 :
        !e_read_window_met ? 2'b01 :
        q_window_for_sample ? 2'b11 : 2'b10;
    wire [24:0] observation={cpu_sample_rw_n,cpu_sample_address,
                             cpu_sample_data};
    always @(posedge clk108 or negedge board_reset_n) begin
        if (!board_reset_n) begin
            log_we<=1'b0;
            log_addr<=0;
            log_data<=0;
            log_count<=0;
            last_observation<=0;
            observation_valid<=1'b0;
            log_rebased<=1'b0;
            log_write_rebased<=1'b0;
            log_rebase_pulse<=1'b0;
        end else begin
            log_we<=1'b0;
            log_rebase_pulse<=1'b0;
            // Clear the capture when RESET is observed through the atomic bus
            // snapshot.  Keep this synchronous: the motherboard RESET node
            // has a slow/noisy edge and must not reset unrelated FPGA state.
            if (!cpu_release || !filtered_mux_reset_n) begin
                log_addr<=0;
                log_data<=0;
                log_count<=0;
                last_observation<=0;
                observation_valid<=1'b0;
                log_rebased<=1'b0;
                log_write_rebased<=1'b0;
            end else if (!log_rebased && e_fall && log_trigger_match) begin
                // Include the trigger cycle itself as the first new entry.
                log_we<=1'b1;
                log_addr<=0;
                log_data<={1'b1,cpu_sample_rw_n,cpu_sample_s,cpu_sample_oe,
                           cpu_sample_address,cpu_sample_data,cpu_sample_expected,
                           memory_timing_status};
                log_count<=1;
                last_observation<=observation;
                observation_valid<=1'b1;
                log_rebased<=1'b1;
                log_rebase_pulse<=1'b1;
            end else if (log_rebased && !log_write_rebased && e_fall &&
                         log_write_trigger_match) begin
                // Include the range-matching RAM write as the first entry in
                // the final capture, then permanently disarm this stage.
                log_we<=1'b1;
                log_addr<=0;
                log_data<={1'b1,cpu_sample_rw_n,cpu_sample_s,cpu_sample_oe,
                           cpu_sample_address,cpu_sample_data,cpu_sample_expected,
                           memory_timing_status};
                log_count<=1;
                last_observation<=observation;
                observation_valid<=1'b1;
                log_write_rebased<=1'b1;
                log_rebase_pulse<=1'b1;
            end else if (e_fall &&
                         ((observation_valid &&
                           observation == last_observation) ||
                          log_count < LOG_DEPTH)) begin
                log_we<=1'b1;
                log_data<={1'b1,cpu_sample_rw_n,cpu_sample_s,cpu_sample_oe,
                           cpu_sample_address,cpu_sample_data,cpu_sample_expected,
                           memory_timing_status};
                // Collapse only a truly repeated bus observation.  A 6809
                // read-modify-write instruction performs consecutive read
                // and write cycles at the same address; those must remain as
                // separate rows so PIA transactions can be diagnosed.
                if (observation_valid && observation == last_observation) begin
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

    coco_hdmi #(
        .LOG_ADDR_WIDTH(LOG_ADDR_WIDTH), .LOG_COUNT_WIDTH(LOG_COUNT_WIDTH),
        .LOG_PAGE_WIDTH(LOG_PAGE_WIDTH), .LOG_DEPTH(LOG_DEPTH),
        .ENABLE_DEBUG_OVERLAY(ENABLE_BUS_LOGGER)
    ) hdmi_output (
        .pixel_clk(clk27), .serial_clk(clk135), .reset(!board_reset_n),
        .vdg_clk(clk108), .vdg_pixel_tick(vdg_master_tick),
        .debug_clk(clk108), .log_we(log_we), .log_addr(log_addr),
        .log_data(log_data), .log_count(log_count), .log_page(log_page),
        .debug_status({clocks_locked,filtered_mux_reset_n,mux_halt_n,
                       pia_interrupts_idle,bus_ready_sync}),
        .overlay_enable(overlay_visible), .vdg_red(vdg_red),
        .vdg_green(vdg_green), .vdg_blue(vdg_blue),
        .vdg_hblank(vdg_hblank), .vdg_vblank(vdg_vblank),
        .tmds_clk_p(tmds_clk_p), .tmds_clk_n(tmds_clk_n),
        .tmds_data_p(tmds_data_p), .tmds_data_n(tmds_data_n),
        .vdg_start(hdmi_vdg_start)
    );

    wire [9:0] unused_cvbs_source_x;
    wire [7:0] unused_cvbs_source_y,unused_cvbs_prefetch_y;
    wire unused_cvbs_source_valid,unused_cvbs_prefetch_valid;
    wire analog_luma,analog_chroma,analog_cvbs;
    wire [15:0] unused_cvbs_framebuffer_addr;
    coco_cvbs_ntsc #(.STREAMING_INPUT(1)) analog_encoder (
        .clk135(clk135), .clk270(clk270), .reset_n(vdg_reset_n),
        .high_resolution(1'b0), .framebuffer_data(vdg_native_rgb),
        .border_rgb(vdg_border_rgb), .active_height(8'd192),
        .framebuffer_addr(unused_cvbs_framebuffer_addr),
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
    wire unused_inputs=audio_in ^ mux_slenb_n ^ mux_cart_n ^
                       mux_nmi_n ^
                       video_memory_valid ^ vdg_hblank ^ vdg_vblank ^
                       ^vdg_red ^ ^vdg_green ^ ^vdg_blue;
endmodule
