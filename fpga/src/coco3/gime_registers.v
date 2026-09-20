module gime_registers (
    input clk, input reset_n, input e, input e_fall,
    input [15:0] cpu_addr, input cpu_rw_n, input [7:0] cpu_data,
    input serint_n, input keyint_n, input cart_n,
    input hs_n, input fs_n,
    output reg [7:0] core_rdata, output core_data_oe,
    output irq_assert, output firq_assert, output reg fast_mode,
    output reg [2:0] sam_s,
    output cpu_mem_read, output cpu_mem_write, output cpu_mem_is_rom,
    output [22:0] cpu_mem_addr,
    output reg [7:0] vmode, output reg [7:0] vres,
    output reg [5:0] border_color,
    output reg [3:0] vertical_scroll,
    output reg [15:0] video_offset,
    output reg [7:0] horizontal_offset,
    output compatibility_mode,
    output reg [6:0] sam_video_offset,
    output [95:0] palettes
);
    reg [7:0] init0, init1;
    reg [5:0] irq_enable, firq_enable;
    reg [5:0] irq_pending, firq_pending;
    reg [11:0] timer_reload, timer_count;
    reg [12:0] timer_divider;
    reg prior_serint_n, prior_keyint_n, prior_cart_n;
    reg prior_hs_n, prior_fs_n;
    reg [5:0] palette [0:15];
    reg [5:0] mmu [0:15];
    reg ram_mode;
    integer i;

    wire gime_selected = cpu_addr >= 16'hff90 && cpu_addr <= 16'hffbf;
    wire io_selected = cpu_addr >= 16'hff00 && cpu_addr < 16'hffe0;
    wire vector_selected = cpu_addr >= 16'hffe0;
    // The hardware-vector page is always supplied by the internal ROM,
    // including while TY selects all-RAM mode.  Keeping vector_selected
    // outside the ram_mode qualification is essential: IRQ entry commonly
    // occurs after Extended BASIC has enabled all-RAM, and otherwise FFF8/9
    // are incorrectly translated through the RAM/MMU path.
    wire rom_window = vector_selected ||
                      (!ram_mode && cpu_addr >= 16'h8000 && !io_selected);
    wire [1:0] rom_map = init0[1:0];
    // INIT0.MC1:MC0: 0x is 16K internal plus 16K external, 10 is
    // 32K internal, and 11 is 32K external except for vectors.  The FPGA
    // contains the complete internal 32K image; external portions must
    // release the data bus for the cartridge/motherboard path.
    wire external_rom_selected = rom_window && !vector_selected &&
        ((!rom_map[1] && cpu_addr >= 16'hc000) || rom_map == 2'b11);
    wire rom_selected = rom_window && !external_rom_selected;
    wire [3:0] mmu_index = {init1[0],cpu_addr[15:13]};
    wire mmu_enabled = !init0[7] && init0[6];
    wire [18:0] compatibility_ram_address =
        19'h70000 + {3'd0,cpu_addr};
    wire [18:0] ram_address = mmu_enabled ?
                              {mmu[mmu_index],cpu_addr[12:0]} :
                              compatibility_ram_address;

    assign cpu_mem_read = cpu_rw_n && !gime_selected &&
                          (!io_selected || vector_selected) &&
                          !external_rom_selected;
    assign cpu_mem_write = !cpu_rw_n && !io_selected && !rom_window;
    assign cpu_mem_is_rom = rom_selected;
    assign cpu_mem_addr = rom_selected ?
                          {8'd0,cpu_addr[14:0]} : {4'd0,ram_address};
    assign core_data_oe = e && cpu_rw_n && gime_selected;
    assign irq_assert = init0[5] && |irq_pending;
    assign firq_assert = init0[4] && |firq_pending;
    assign compatibility_mode = init0[7];

    genvar p;
    generate
        for (p=0;p<16;p=p+1) begin : flatten_palette
            assign palettes[p*6 +: 6] = palette[p];
        end
    endgenerate

    always @(*) begin
        // S1/S2 physically enable the motherboard EXTROM/ROM devices.  All
        // FPGA-owned RAM, internal CoCo 3 ROM, vectors and GIME registers use
        // S0 so those legacy ROMs cannot contend with the FPGA data driver.
        // Only an external-ROM mapping is released to the cartridge select.
        if (gime_selected || cpu_mem_read || cpu_mem_write || rom_selected)
            sam_s = 3'd0;
        else if (external_rom_selected)
            sam_s = 3'd3;
        else if (cpu_addr < 16'hff20)
            sam_s = 3'd4;
        else if (cpu_addr < 16'hff40)
            sam_s = 3'd5;
        else if (cpu_addr < 16'hff60)
            sam_s = 3'd6;
        else if (cpu_addr < 16'hffe0)
            sam_s = 3'd7;
        else
            sam_s = 3'd2;

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
            timer_divider <= 13'd0;
            prior_serint_n <= 1'b1;
            prior_keyint_n <= 1'b1;
            prior_cart_n <= 1'b1;
            prior_hs_n <= 1'b1;
            prior_fs_n <= 1'b1;
            fast_mode <= 1'b1;
            vmode <= 8'h00;
            vres <= 8'h00;
            border_color <= 6'd0;
            vertical_scroll <= 4'd0;
            video_offset <= 16'd0;
            horizontal_offset <= 8'd0;
            sam_video_offset <= 7'd0;
            ram_mode <= 1'b0;
            for (i=0;i<16;i=i+1) mmu[i] <= 6'h38 + i[5:0];
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

            // INIT1.TINS selects approximately 279 ns or 63.5 us timer ticks.
            if (timer_reload != 0) begin
                if ((init1[5] && timer_divider == 13'd29) ||
                    (!init1[5] && timer_divider == 13'd6857)) begin
                    timer_divider <= 13'd0;
                    if (timer_count <= 12'd1) begin
                        timer_count <= timer_reload;
                        irq_pending[5] <= irq_enable[5];
                        firq_pending[5] <= firq_enable[5];
                    end else timer_count <= timer_count - 1'b1;
                end else timer_divider <= timer_divider + 1'b1;
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
                if (cpu_addr == 16'hffd8) fast_mode <= 1'b0;
                if (cpu_addr == 16'hffd9) fast_mode <= 1'b1;
                // Legacy SAM controls retained by the GIME. Each paired
                // address clears/sets one display-offset bit. TY selects
                // ROM-overlay versus all-RAM mapping.  The CoCo 3 GIME
                // ignores the legacy SAM P1 strobes at FFD4/FFD5; Extended
                // BASIC writes FFD5 during startup and expects no remapping.
                if (cpu_addr >= 16'hffc6 && cpu_addr <= 16'hffd3)
                    sam_video_offset[(cpu_addr-16'hffc6)>>1] <= cpu_addr[0];
                if (cpu_addr == 16'hffde) ram_mode <= 1'b0;
                if (cpu_addr == 16'hffdf) ram_mode <= 1'b1;
                if (gime_selected) begin
                    case (cpu_addr)
                        16'hff90: init0 <= cpu_data;
                        16'hff91: init1 <= cpu_data;
                        16'hff92: begin irq_enable <= cpu_data[5:0]; irq_pending <= 6'd0; end
                        16'hff93: begin firq_enable <= cpu_data[5:0]; firq_pending <= 6'd0; end
                        16'hff94: begin
                            timer_reload[11:8] <= cpu_data[3:0];
                            timer_count <= {cpu_data[3:0],timer_reload[7:0]};
                        end
                        16'hff95: begin
                            timer_reload[7:0] <= cpu_data;
                            timer_count <= {timer_reload[11:8],cpu_data};
                        end
                        16'hff98: vmode <= cpu_data;
                        16'hff99: vres <= cpu_data;
                        16'hff9a: border_color <= cpu_data[5:0];
                        16'hff9c: vertical_scroll <= cpu_data[3:0];
                        16'hff9d: video_offset[15:8] <= cpu_data;
                        16'hff9e: video_offset[7:0] <= cpu_data;
                        16'hff9f: horizontal_offset <= cpu_data;
                        default: begin
                            if (cpu_addr >= 16'hffa0 && cpu_addr <= 16'hffaf)
                                mmu[cpu_addr[3:0]] <= cpu_data[5:0];
                            else if (cpu_addr >= 16'hffb0 && cpu_addr <= 16'hffbf)
                                palette[cpu_addr[3:0]] <= cpu_data[5:0];
                        end
                    endcase
                end
            end
        end
    end
endmodule
