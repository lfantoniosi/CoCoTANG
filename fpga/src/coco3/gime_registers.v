module gime_registers (
    input clk, input reset_n, input e, input e_fall,
    input [15:0] cpu_addr, input cpu_rw_n, input [7:0] cpu_data,
    output reg [7:0] core_rdata, output core_data_oe,
    output reg [2:0] sam_s,
    output cpu_mem_read, output cpu_mem_write, output cpu_mem_is_rom,
    output [22:0] cpu_mem_addr,
    output reg [7:0] vmode, output reg [7:0] vres,
    output reg [5:0] border_color,
    output reg [3:0] vertical_scroll,
    output reg [15:0] video_offset,
    output reg [7:0] horizontal_offset,
    output [95:0] palettes
);
    reg [7:0] init0, init1;
    reg [5:0] palette [0:15];
    reg [5:0] mmu [0:15];
    integer i;

    wire gime_selected = cpu_addr >= 16'hff90 && cpu_addr <= 16'hffbf;
    wire io_selected = cpu_addr >= 16'hff00 && cpu_addr < 16'hffe0;
    wire rom_selected = cpu_addr >= 16'h8000 && !io_selected;
    wire [3:0] mmu_index = {init1[0],cpu_addr[15:13]};
    wire [18:0] ram_address = init0[6] ?
                              {mmu[mmu_index],cpu_addr[12:0]} :
                              19'h70000 + {3'd0,cpu_addr};

    assign cpu_mem_read = cpu_rw_n && !gime_selected &&
                          (!io_selected || cpu_addr >= 16'hffe0);
    assign cpu_mem_write = !cpu_rw_n && !io_selected && !rom_selected;
    assign cpu_mem_is_rom = rom_selected;
    assign cpu_mem_addr = rom_selected ?
                          {8'd0,cpu_addr[14:0]} : {4'd0,ram_address};
    assign core_data_oe = e && cpu_rw_n && gime_selected;

    genvar p;
    generate
        for (p=0;p<16;p=p+1) begin : flatten_palette
            assign palettes[p*6 +: 6] = palette[p];
        end
    endgenerate

    always @(*) begin
        if (cpu_addr < 16'h8000 || rom_selected || gime_selected)
            sam_s = 3'd0;
        else if (cpu_addr < 16'hff20)
            sam_s = 3'd4;
        else if (cpu_addr < 16'hff40)
            sam_s = 3'd5;
        else
            sam_s = 3'd7;

        core_rdata = 8'hff;
        case (cpu_addr)
            16'hff90: core_rdata = init0;
            16'hff91: core_rdata = init1;
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
            vmode <= 8'h00;
            vres <= 8'h00;
            border_color <= 6'd0;
            vertical_scroll <= 4'd0;
            video_offset <= 16'd0;
            horizontal_offset <= 8'd0;
            for (i=0;i<16;i=i+1) mmu[i] <= 6'h38 + i[5:0];
            palette[0]<=6'd18; palette[1]<=6'd36; palette[2]<=6'd11; palette[3]<=6'd7;
            palette[4]<=6'd63; palette[5]<=6'd31; palette[6]<=6'd9;  palette[7]<=6'd38;
            palette[8]<=6'd0;  palette[9]<=6'd18; palette[10]<=6'd0; palette[11]<=6'd63;
            palette[12]<=6'd0; palette[13]<=6'd18; palette[14]<=6'd0; palette[15]<=6'd38;
        end else if (e_fall && !cpu_rw_n && gime_selected) begin
            case (cpu_addr)
                16'hff90: init0 <= cpu_data;
                16'hff91: init1 <= cpu_data;
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
endmodule
