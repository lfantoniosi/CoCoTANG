// Standalone physical-MC6809E bring-up top for the existing Tang displacer.
// This deliberately contains no PIA, VDG, framebuffer, CVBS, debug program,
// RAM fill, or motherboard-side client.  The external MP/MSEL circuitry is
// retained only because it is how the displacer presents CPU address/control.
module top_cpu_test #(
    parameter integer RESET_HOLD_CYCLES = 10800000,
    parameter integer LOG_DEPTH = 4096
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
    wire [2:0] unused_video_mode;
    wire [6:0] unused_video_offset;
    wire unused_page,unused_all_ram;
    wire [1:0] unused_rate,unused_memory_size;
    reg cpu_release = 1'b0;
    wire [15:0] address;
    wire rw_n;
    coco_sam sam (
        .clk(clk108), .reset_n(board_reset_n), .register_reset_n(cpu_release),
        .addr(address), .rw_n(rw_n), .s(internal_s),
        .e(e_out), .q(q_out), .e_rise(e_rise), .e_fall(e_fall),
        .video_mode(unused_video_mode), .video_offset(unused_video_offset),
        .page(unused_page), .rate(unused_rate),
        .memory_size(unused_memory_size), .all_ram(unused_all_ram)
    );

    assign sam_s = internal_s;

    // Existing displacer acquisition hardware.  Nothing from the CoCo
    // motherboard is required or interpreted by this top.
    reg q_scan_delay = 1'b0;
    always @(posedge clk270 or negedge board_reset_n) begin
        if (!board_reset_n)
            q_scan_delay<=1'b0;
        else
            q_scan_delay<=q_out;
    end
    wire bus_scan_start=q_out && !q_scan_delay;
    wire mux_reset_n,mux_slenb_n,mux_sernt_n,mux_cart_n,mux_keyint_n;
    wire mux_halt_n,mux_nmi_n,bus_snapshot_ready_async;
    coco_bus_mux bus_mux (
        .clk(clk270), .reset_n(board_reset_n), .scan_start(bus_scan_start),
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
    wire [31:0] unused_sd_dout32;
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
        .dout32(unused_sd_dout32), .data_ready(sd_data_ready),
        .busy(sd_busy), .enabled(sdram_enabled)
    );

    // ROM loading already holds reset for a substantial interval.  Add a
    // deterministic 100 ms default afterward and release only on E falling.
    reg [31:0] reset_hold_count = 32'd0;
    reg release_pending = 1'b0;
    always @(posedge clk108 or negedge board_reset_n) begin
        if (!board_reset_n) begin
            reset_hold_count<=32'd0;
            release_pending<=1'b0;
            cpu_release<=1'b0;
        end else if (!system_ready) begin
            reset_hold_count<=32'd0;
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
    cpu_test_memory memory (
        .clk(clk108), .reset_n(sdram_reset_n), .loader_start(loader_start),
        .cpu_access_enable(cpu_release), .cpu_bus_valid(bus_snapshot_valid),
        .e_fall(e_fall), .cpu_addr(address), .cpu_rw_n(rw_n),
        .sam_s(internal_s), .cpu_wdata(cpu_data),
        .cpu_rdata(fpga_read_data), .cpu_data_oe(fpga_data_oe),
        .loader_done(loader_done),
        .mspi_cs(mspi_cs), .mspi_sclk(mspi_sclk),
        .mspi_miso(mspi_miso), .mspi_mosi(mspi_mosi),
        .sdram_enabled(sdram_enabled), .sd_rd(sd_rd), .sd_wr(sd_wr),
        .sd_refresh(sd_refresh), .sd_addr(sd_addr), .sd_din(sd_din),
        .sd_wdm(sd_wdm), .sd_dout(sd_dout),
        .sd_data_ready(sd_data_ready), .sd_busy(sd_busy)
    );
    assign cpu_data=fpga_data_oe ? fpga_read_data : 8'bz;

    // Capture every observable {address,R/W,data} change after RESET release.
    // Address/control come from an atomic mux snapshot; data is observed on
    // the physical CPU-side bus so both CPU writes and FPGA reads are visible.
    reg log_we=1'b0;
    reg [LOG_ADDR_WIDTH-1:0] log_addr=0;
    reg [39:0] log_data=0;
    reg [LOG_COUNT_WIDTH-1:0] log_count=0;
    reg [24:0] last_observation=0;
    reg observation_valid=1'b0;
    reg bus_seen=1'b0;
    wire [24:0] observation={rw_n,address,cpu_data};
    always @(posedge clk108 or negedge board_reset_n) begin
        if (!board_reset_n) begin
            log_we<=1'b0;
            log_addr<=0;
            log_data<=0;
            log_count<=0;
            last_observation<=0;
            observation_valid<=1'b0;
            bus_seen<=1'b0;
        end else begin
            log_we<=1'b0;
            if (bus_snapshot_valid)
                bus_seen<=1'b1;
            if (!cpu_release) begin
                observation_valid<=1'b0;
            end else if (bus_seen && log_count < LOG_DEPTH &&
                         (!observation_valid || observation != last_observation)) begin
                log_we<=1'b1;
                log_addr<=log_count[LOG_ADDR_WIDTH-1:0];
                log_data<={1'b1,rw_n,internal_s,fpga_data_oe,address,
                           cpu_data,fpga_read_data,q_out,e_out};
                log_count<=log_count+1'b1;
                last_observation<=observation;
                observation_valid<=1'b1;
            end
        end
    end

    // One debounced S2 press advances one 116-entry page.  After the last
    // physical log page it wraps directly to page zero.
    reg s2_meta=1'b0,s2_sync=1'b0,s2_state=1'b0;
    reg [20:0] s2_stable_count=0;
    reg [LOG_PAGE_WIDTH-1:0] log_page=0;
    always @(posedge clk108 or negedge board_reset_n) begin
        if (!board_reset_n) begin
            s2_meta<=1'b0;
            s2_sync<=1'b0;
            s2_state<=1'b0;
            s2_stable_count<=0;
            log_page<=0;
        end else begin
            s2_meta<=s2;
            s2_sync<=s2_meta;
            if (s2_sync == s2_state)
                s2_stable_count<=0;
            else if (s2_stable_count == 21'd1079999) begin
                s2_state<=s2_sync;
                s2_stable_count<=0;
                if (s2_sync)
                    log_page <= (log_page == LAST_PAGE) ?
                                {LOG_PAGE_WIDTH{1'b0}} : log_page+1'b1;
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
        .debug_status({clocks_locked,cpu_release,mux_reset_n,
                       bus_snapshot_ready_async,bus_ready_sync}),
        .tmds_clk_p(tmds_clk_p), .tmds_clk_n(tmds_clk_n),
        .tmds_data_p(tmds_data_p), .tmds_data_n(tmds_data_n)
    );

    // Constrained legacy outputs are intentionally inactive in this top.
    assign hs_n=1'b1;
    assign fs_n=1'b1;
    assign y_out=1'b0;
    assign pb_out=1'b0;
    wire unused_inputs=irq_n_in ^ firq_n_in ^ audio_in ^ mux_slenb_n ^
                       mux_sernt_n ^ mux_cart_n ^ mux_keyint_n ^
                       mux_halt_n ^ mux_nmi_n;
endmodule
