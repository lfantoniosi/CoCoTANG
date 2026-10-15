module gime_registers #(
    // External DISTO DAT/video-bank extension.  The stock GIME remains the
    // low six address bits, so disabling this parameter is bit-for-bit the
    // original 512 KiB map.
    parameter integer DISTO_2MB = 0,
    // NoCan3: FF9B[5:4] is captured with each MMU write; FF9B[3:0]
    // selects the video 512 KiB bank. Zero extra bits preserve DISTO.
    parameter integer NOCAN3_8MB = 0
) (
    input clk, input reset_n, input e, input e_fall,
    input [15:0] cpu_addr, input cpu_rw_n, input [7:0] cpu_data,
    input serint_n, input keyint_n, input cart_n,
    // Border-event inputs; physical HS/FS go separately to the PIAs.
    input hs_n, input fs_n,
    output reg [7:0] core_rdata, output core_data_oe,
    output irq_assert, output firq_assert, output wire fast_mode,
    output reg [2:0] sam_s,
    output cpu_mem_read, output cpu_mem_write, output cpu_mem_is_rom,
    output [22:0] cpu_mem_addr,
    output reg [7:0] vmode, output reg [7:0] vres,
    output reg [5:0] border_color,
    output reg [3:0] vertical_scroll,
    output reg [15:0] video_offset,
    output reg [7:0] horizontal_offset,
    output [3:0] video_bank,
    output compatibility_mode,
    output reg [2:0] sam_video_mode,
    output reg [6:0] sam_video_offset,
    output [95:0] palettes,
    output [5:0] mmu_task0_page_debug,
    output [5:0] mmu_task1_page_debug,
    output mmu_task_debug,
    output mmu_enabled_debug,
    output [79:0] gime_register_debug,
    output [127:0] gime_trace_registers,
    output [95:0] mmu_register_debug
);
    reg [7:0] init0, init1;
    reg [5:0] irq_enable, firq_enable;
    reg [5:0] irq_pending, firq_pending;
    reg [11:0] timer_reload;
    reg [12:0] timer_count;
    reg timer_running;
    reg [12:0] timer_divider;
    reg prior_serint_n, prior_keyint_n, prior_cart_n;
    reg prior_hs_n, prior_fs_n;
    reg [5:0] palette [0:15];
    reg [5:0] mmu [0:15];
    reg [3:0] disto_mmu [0:15];
    reg [3:0] disto_video_bank;
    reg [1:0] nocan3_cpu_bank;
    reg ram_mode;
    reg selected_fast_mode;
    reg speed_explicit;
    integer i;

    wire gime_selected = cpu_addr >= 16'hff90 && cpu_addr <= 16'hffbf;
    wire io_selected = cpu_addr >= 16'hff00 && cpu_addr < 16'hffe0;
    wire vector_selected = cpu_addr >= 16'hffe0;
    wire [2:0] cpu_block = cpu_addr[15:13];
    wire [3:0] mmu_index = {init1[0],cpu_block};
    // COCO (bit 7) selects the compatibility video/register personality;
    // it does not disable address translation.  Software such as the CoCo 3
    // memory checker deliberately leaves compatibility video selected while
    // enabling the MMU with bit 6.  Coupling the two bits aliases every MMU
    // page back into the fixed upper 64K and makes a 512K machine appear to
    // contain only 64K/128K.
    wire mmu_enabled = init0[6];
    wire [5:0] selected_mmu_page = mmu[mmu_index];
    // INIT0.MC3 makes $FE00-$FEFF the GIME's constant system page.  It is
    // always physical block $3F, independent of the selected MMU task and
    // block-7 register.  NitrOS-9 relies on this for its direct-page kernel
    // globals while switching tasks.
    wire constant_fe_page = init0[3] && cpu_addr[15:8] == 8'hfe;
    // In MMU RAM/ROM mode, $3C-$3F in any MMU slot select ROM.  The two
    // low page bits are supplied by the destination slot, not by the value
    // written to the MMU register.  Consequently a RAM page such as $00
    // mapped at CPU $8000 must remain RAM; ROM is not a fixed CPU window.
    // Predecode ROM-capable MMU pages on register writes. The cartridge
    // select path needs only this bit; selecting all six page bits and then
    // reducing four of them was the longest 108-MHz pad-control path.
    reg mmu_rom_flag [0:15];
    wire mmu_rom_page = mmu_rom_flag[mmu_index];
    wire legacy_rom_window = !mmu_enabled && cpu_addr >= 16'h8000;
    wire mapped_rom_window = mmu_enabled && mmu_rom_page;
    // The hardware-vector page is always supplied by the internal ROM,
    // including while TY selects all-RAM mode.  Keeping vector_selected
    // outside the ram_mode qualification is essential: IRQ entry commonly
    // occurs after Extended BASIC has enabled all-RAM, and otherwise FFF8/9
    // are incorrectly translated through the RAM/MMU path.
    wire rom_window = vector_selected || (!ram_mode && !io_selected &&
                      !constant_fe_page &&
                      (legacy_rom_window || mapped_rom_window));
    wire [14:0] rom_byte_addr = vector_selected ? cpu_addr[14:0] :
                                mmu_enabled ? {cpu_block[1:0],cpu_addr[12:0]} :
                                              cpu_addr[14:0];
    wire [1:0] rom_map = init0[1:0];
    // TINS=0 selects the horizontal-sync clock, not an unrelated nominal
    // 63.5 us divider.  Sharing the actual HS edge keeps timer-driven raster
    // effects phase-locked to HBORD and to the displayed scan lines.
    wire timer_clock = init1[5] ? (timer_divider == 13'd29) :
                                  (prior_hs_n && !hs_n);
    // INIT0.MC1:MC0: 0x is 16K internal plus 16K external, 10 is
    // 32K internal, and 11 is 32K external except for vectors.  The FPGA
    // contains the complete internal 32K image; external portions must
    // release the data bus for the cartridge/motherboard path.
    wire external_rom_selected = rom_window && !vector_selected &&
        ((!rom_map[1] && rom_byte_addr[14]) || rom_map == 2'b11);
    wire rom_selected = rom_window && !external_rom_selected;
    // The card supplies D7:D6 externally.  It has no GIME MMU-enable input,
    // so those two latched bits remain active over the GIME's fixed $38-$3f
    // compatibility pages when INIT0.MMU is clear.
    wire [3:0] external_page = DISTO_2MB ? disto_mmu[mmu_index] : 4'b0000;
    wire [22:0] compatibility_ram_address =
        {external_page,3'b111,cpu_addr};
    wire [22:0] ram_address = constant_fe_page ?
                              (23'h07fe00 + {15'd0,cpu_addr[7:0]}) :
                              mmu_enabled ?
                              {external_page,mmu[mmu_index],cpu_addr[12:0]} :
                              compatibility_ram_address;

    assign cpu_mem_read = cpu_rw_n && !gime_selected &&
                          (!io_selected || vector_selected) &&
                          !external_rom_selected;
    // ROM is a read overlay. Writes still reach the translated RAM beneath
    // it, which is required by MMU memory probes and shadow-RAM software.
    assign cpu_mem_write = !cpu_rw_n && !io_selected;
    assign cpu_mem_is_rom = cpu_rw_n && rom_selected;
    assign cpu_mem_addr = (cpu_rw_n && rom_selected) ?
                          {8'd0,rom_byte_addr} : ram_address;
    assign core_data_oe = e && cpu_rw_n && gime_selected;
    assign irq_assert = init0[5] && |irq_pending;
    assign firq_assert = init0[4] && |firq_pending;
    assign compatibility_mode = init0[7];
    // Preserve the native CoCo 3 reset speed. Before the first explicit
    // $FFD8/$FFD9 write, compatibility software sees the slow CoCo 2 rate.
    assign fast_mode=selected_fast_mode&&
                     (!compatibility_mode||speed_explicit);
    assign video_bank = DISTO_2MB ? disto_video_bank : 4'b0000;
    assign mmu_task0_page_debug=mmu[{1'b0,cpu_block}];
    assign mmu_task1_page_debug=mmu[{1'b1,cpu_block}];
    assign mmu_task_debug=init1[0];
    assign mmu_enabled_debug=mmu_enabled;
    // Complete live state for the fixed HDMI debugger status row.  Keep the
    // bus byte-oriented so the display side can print the same values a CPU
    // read would see without reconstructing partial registers.
    assign gime_register_debug={init0,init1,vmode,vres,
        {2'b00,border_color},{4'b0000,vertical_scroll},video_offset,
        horizontal_offset,{1'b0,sam_video_offset}};
    // Byte-for-byte FF90..FF9F snapshot for the field logger. Read-only
    // diagnostic fanout; it does not alter GIME register timing.
    assign gime_trace_registers={init0,init1,{2'b00,irq_enable},
        {2'b00,firq_enable},{4'b0000,timer_reload[11:8]},
        timer_reload[7:0],8'h00,8'h00,vmode,vres,
        {2'b00,border_color},{2'b00,nocan3_cpu_bank,disto_video_bank},
        {4'b0000,vertical_scroll},video_offset,horizontal_offset};

    genvar p;
    generate
        for (p=0;p<16;p=p+1) begin : flatten_palette
            assign palettes[p*6 +: 6] = palette[p];
            assign mmu_register_debug[p*6 +: 6] = mmu[p];
        end
    endgenerate

    always @(*) begin
        // S1/S2 physically enable the motherboard EXTROM/ROM devices.  All
        // FPGA-owned RAM, internal CoCo 3 ROM, vectors and GIME registers use
        // S0 so those legacy ROMs cannot contend with the FPGA data driver.
        // Only an external-ROM mapping is released to the cartridge select.
        // S is purely an address-region decode.  Do not feed the RAM/ROM
        // request qualifiers back into this pad path: those qualifiers add
        // the MMU, R/W and I/O decode to an output which only needs to know
        // whether the selected ROM window is external.  Everything below
        // FF00 is FPGA RAM/internal ROM unless that one external-ROM case
        // applies; vectors and GIME registers are FPGA-owned as well.
        if (external_rom_selected)
            sam_s = 3'd3;
        else if (cpu_addr[15:8] != 8'hff)
            sam_s = 3'd0;
        else case (cpu_addr[7:4])
            4'h0,4'h1: sam_s = 3'd4; // PIA0
            4'h2,4'h3: sam_s = 3'd5; // PIA1
            4'h4,4'h5: sam_s = 3'd6; // cartridge control
            4'h6,4'h7,4'h8,
            4'hc,4'hd: sam_s = 3'd7; // spare/cart I/O and SAM strobes
            // $FF90-$FFBF are GIME registers and $FFE0-$FFFF are internal
            // vectors; both are FPGA-owned and therefore use S0.
            default: sam_s = 3'd0;
        endcase

        core_rdata = 8'hff;
        case (cpu_addr)
            16'hff90: core_rdata = init0;
            16'hff91: core_rdata = init1;
            16'hff92: core_rdata = {2'b00,irq_pending};
            16'hff93: core_rdata = {2'b00,firq_pending};
            16'hff94: core_rdata = {4'b0000,timer_reload[11:8]};
            16'hff95: core_rdata = timer_reload[7:0];
            16'hff98: core_rdata = vmode;
            16'hff99: core_rdata = vres;
            16'hff9a: core_rdata = {2'b00,border_color};
            16'hff9c: core_rdata = {4'b0000,vertical_scroll};
            16'hff9d: core_rdata = video_offset[15:8];
            16'hff9e: core_rdata = video_offset[7:0];
            16'hff9f: core_rdata = horizontal_offset;
            default: begin
                if (cpu_addr >= 16'hffa0 && cpu_addr <= 16'hffaf)
                    core_rdata = {2'b00,mmu[cpu_addr[3:0]]};
                else if (cpu_addr >= 16'hffb0 && cpu_addr <= 16'hffbf)
                    core_rdata = {2'b00,palette[cpu_addr[3:0]]};
            end
        endcase
    end

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            init0 <= 8'h00;
            init1 <= 8'h00;
            irq_enable <= 6'd0;
            firq_enable <= 6'd0;
            irq_pending <= 6'd0;
            firq_pending <= 6'd0;
            timer_reload <= 12'd0;
            timer_count <= 12'd0;
            timer_running <= 1'b0;
            timer_divider <= 13'd0;
            prior_serint_n <= 1'b1;
            prior_keyint_n <= 1'b1;
            prior_cart_n <= 1'b1;
            prior_hs_n <= 1'b1;
            prior_fs_n <= 1'b1;
            selected_fast_mode <= 1'b1;
            speed_explicit <= 1'b0;
            vmode <= 8'h00;
            vres <= 8'h00;
            border_color <= 6'd0;
            vertical_scroll <= 4'd0;
            video_offset <= 16'd0;
            horizontal_offset <= 8'd0;
            disto_video_bank <= 4'd0;
            nocan3_cpu_bank <= 2'd0;
            sam_video_mode <= 3'd0;
            sam_video_offset <= 7'd0;
            ram_mode <= 1'b0;
            // Both MMU tasks power up with the logical 64K window on the
            // uppermost 64K of 512K RAM.  Each task owns eight 8K blocks;
            // using i directly here formerly wrapped task 1 to pages 00-07.
            for (i=0;i<16;i=i+1) begin
                mmu[i] <= 6'h38 + {3'b000,i[2:0]};
                mmu_rom_flag[i] <= i[2];
                disto_mmu[i] <= 4'b0000;
            end
            // CoCo3FPGA RGB defaults.  The former values were its composite
            // approximations and produced visibly wrong HDMI/derived-CVBS.
            palette[0]<=6'd18; palette[1]<=6'd54; palette[2]<=6'd9;  palette[3]<=6'd36;
            palette[4]<=6'd63; palette[5]<=6'd27; palette[6]<=6'd45; palette[7]<=6'd38;
            palette[8]<=6'd0;  palette[9]<=6'd18; palette[10]<=6'd0; palette[11]<=6'd63;
            palette[12]<=6'd0; palette[13]<=6'd18; palette[14]<=6'd0; palette[15]<=6'd38;
        end else begin
            prior_serint_n <= serint_n;
            prior_keyint_n <= keyint_n;
            prior_cart_n <= cart_n;
            prior_hs_n <= hs_n;
            prior_fs_n <= fs_n;

            // External and border sources are edge-latched separately for
            // IRQ and FIRQ. Reading the corresponding status register clears
            // only that interrupt class.
            if (prior_serint_n && !serint_n) begin
                irq_pending[2] <= irq_enable[2];
                firq_pending[2] <= firq_enable[2];
            end
            if (prior_keyint_n && !keyint_n) begin
                irq_pending[1] <= irq_enable[1];
                firq_pending[1] <= firq_enable[1];
            end
            if (prior_cart_n && !cart_n) begin
                irq_pending[0] <= irq_enable[0];
                firq_pending[0] <= firq_enable[0];
            end
            if (prior_hs_n && !hs_n) begin
                irq_pending[4] <= irq_enable[4];
                firq_pending[4] <= firq_enable[4];
            end
            if (prior_fs_n && !fs_n) begin
                irq_pending[3] <= irq_enable[3];
                firq_pending[3] <= firq_enable[3];
            end

            // INIT1.TINS selects approximately 279 ns or the HS line clock.
            if (timer_running) begin
                if (init1[5]) begin
                    if (timer_clock) timer_divider <= 13'd0;
                    else timer_divider <= timer_divider + 1'b1;
                end else timer_divider <= 13'd0;
                if (timer_clock) begin
                    if (timer_count <= 12'd1) begin
                        irq_pending[5] <= irq_enable[5];
                        firq_pending[5] <= firq_enable[5];
                        if (timer_reload != 0)
                            // The common 1986 GIME effectively counts the
                            // programmed interval plus two timer clocks.
                            timer_count <= {1'b0,timer_reload} + 13'd2;
                        else begin
                            timer_count <= 12'd0;
                            timer_running <= 1'b0;
                        end
                    end else timer_count <= timer_count - 1'b1;
                end
            end else begin
                timer_divider <= 13'd0;
                timer_count <= 12'd0;
            end

            if (e_fall && cpu_rw_n && cpu_addr == 16'hff92)
                irq_pending <= 6'd0;
            if (e_fall && cpu_rw_n && cpu_addr == 16'hff93)
                firq_pending <= 6'd0;

            if (e_fall && !cpu_rw_n) begin
                // CoCo speed-control POKEs remain available in native mode.
                if (cpu_addr == 16'hffd8) begin
                    selected_fast_mode <= 1'b0;
                    speed_explicit <= 1'b1;
                end
                if (cpu_addr == 16'hffd9) begin
                    selected_fast_mode <= 1'b1;
                    speed_explicit <= 1'b1;
                end
                // Legacy SAM controls retained by the GIME.  V0:V2 still
                // control compatibility-video DMA geometry independently of
                // the MC6847 GM pins on PIA1.  Games such as Mega-Bug use
                // the 128x96 SAM geometry even when the live GM value would
                // otherwise look like a 192-line fetch to a simplified VDG.
                // Each paired address clears/sets one bit. TY selects
                // ROM-overlay versus all-RAM mapping.  The CoCo 3 GIME
                // ignores the legacy SAM P1 strobes at FFD4/FFD5; Extended
                // BASIC writes FFD5 during startup and expects no remapping.
                if (cpu_addr >= 16'hffc0 && cpu_addr <= 16'hffc5)
                    sam_video_mode[(cpu_addr-16'hffc0)>>1] <= cpu_addr[0];
                if (cpu_addr >= 16'hffc6 && cpu_addr <= 16'hffd3)
                    sam_video_offset[(cpu_addr-16'hffc6)>>1] <= cpu_addr[0];
                if (cpu_addr == 16'hffde) ram_mode <= 1'b0;
                if (cpu_addr == 16'hffdf) ram_mode <= 1'b1;
                if (gime_selected) begin
                    case (cpu_addr)
                        16'hff90: init0 <= cpu_data;
                        16'hff91: begin
                            init1 <= cpu_data;
                            // Changing TINS switches the timer's clock
                            // domain. The GIME restarts the countdown from
                            // the programmed reload value on that change.
                            if (init1[5] != cpu_data[5]) begin
                                timer_divider <= 13'd0;
                                timer_running <= (timer_reload != 0);
                                if (timer_reload != 0)
                                    timer_count <= {1'b0,timer_reload} + 13'd2;
                                else
                                    timer_count <= 13'd0;
                            end
                        end
                        16'hff92: begin
                            irq_enable <= cpu_data[5:0];
                            // Disabling a source acknowledges its pending
                            // flag; changing the mask must not discard flags
                            // for sources that remain enabled.
                            irq_pending <= irq_pending & cpu_data[5:0];
                            // A zero timer has no running countdown, but
                            // enabling its IRQ while zero generates an
                            // immediate timer request on GIME hardware.
                            if (timer_reload == 0 && cpu_data[5] && !irq_enable[5])
                                irq_pending[5] <= 1'b1;
                        end
                        16'hff93: begin
                            firq_enable <= cpu_data[5:0];
                            firq_pending <= firq_pending & cpu_data[5:0];
                            if (timer_reload == 0 && cpu_data[5] && !firq_enable[5])
                                firq_pending[5] <= 1'b1;
                        end
                        16'hff94: begin
                            timer_reload[11:8] <= cpu_data[3:0];
                            timer_running <= ({cpu_data[3:0],timer_reload[7:0]} != 0);
                            if ({cpu_data[3:0],timer_reload[7:0]} != 0)
                                timer_count <= {1'b0,cpu_data[3:0],timer_reload[7:0]} + 13'd2;
                            else timer_count <= 13'd0;
                            timer_divider <= 13'd0;
                            // Loading zero stops the countdown, but the
                            // zero terminal event still requests the timer
                            // interrupt when its enable is already active.
                            if (cpu_data[3:0] == 0 && timer_reload[7:0] == 0) begin
                                if (irq_enable[5]) irq_pending[5] <= 1'b1;
                                if (firq_enable[5]) firq_pending[5] <= 1'b1;
                            end
                        end
                        16'hff95: begin
                            timer_reload[7:0] <= cpu_data;
                        end
                        16'hff98: vmode <= cpu_data;
                        16'hff99: vres <= cpu_data;
                        16'hff9a: border_color <= cpu_data[5:0];
                        16'hff9b: if (DISTO_2MB)begin
                            disto_video_bank <= NOCAN3_8MB ? cpu_data[3:0] : {2'b00,cpu_data[1:0]};
                            nocan3_cpu_bank <= NOCAN3_8MB ? cpu_data[5:4] : 2'b00;
                        end
                        16'hff9c: vertical_scroll <= cpu_data[3:0];
                        16'hff9d: video_offset[15:8] <= cpu_data;
                        16'hff9e: video_offset[7:0] <= cpu_data;
                        16'hff9f: horizontal_offset <= cpu_data;
                        default: begin
                            if (cpu_addr >= 16'hffa0 && cpu_addr <= 16'hffaf) begin
                                mmu[cpu_addr[3:0]] <= cpu_data[5:0];
                                mmu_rom_flag[cpu_addr[3:0]] <= &cpu_data[5:2];
                                if (DISTO_2MB)
                                    disto_mmu[cpu_addr[3:0]] <=
                                        {nocan3_cpu_bank,cpu_data[7:6]};
                            end
                            else if (cpu_addr >= 16'hffb0 && cpu_addr <= 16'hffbf)
                                palette[cpu_addr[3:0]] <= cpu_data[5:0];
                        end
                    endcase
                end
            end
        end
    end
endmodule
