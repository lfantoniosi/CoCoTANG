// Standalone CPU-side data-bus probe image; the 6809 stays in reset.
module top_coco3_data_test #(
    parameter integer BYTE_HOLD_CYCLES=27008, // ~1 ms at 27 MHz; multiple of 16
    parameter integer STARTUP_CYCLES=27008,
    parameter integer STROBE_CYCLES=13500000, // 0.5 s per S code
    parameter integer BUTTON_CYCLES=270000, // 10 ms debounce
    parameter integer ENABLE_HDMI=1
) (
    input clkin,input s1,input s2,input [7:0] mp,output [1:0] msel,
    inout [7:0] cpu_data,output irq_n_in,output firq_n_in,output audio_out,
    output reset_drive,output e_out,output q_out,output hs_n,output fs_n,
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
    wire [7:0] test_data,data_readback,mp_live;
    wire [23:0] mux_banks;
    wire [15:0] cpu_address;
    wire paused,drive_data,ready;
    cpu_bus_probe_engine #(.BYTE_HOLD_CYCLES(BYTE_HOLD_CYCLES),
        .STARTUP_CYCLES(STARTUP_CYCLES),.STROBE_CYCLES(STROBE_CYCLES),
        .BUTTON_CYCLES(BUTTON_CYCLES)) probe(
        .clkin(clkin),.s1(s1),.s2(s2),.mp(mp),.cpu_data(cpu_data),
        .msel(msel),.reset_drive(reset_drive),.e_out(e_out),.q_out(q_out),
        .sam_s(sam_s),.irq_n(irq_n_in),.firq_n(firq_n_in),.hs_n(hs_n),.fs_n(fs_n),
        .test_data(test_data),.data_readback(data_readback),.mp_live(mp_live),
        .mux_banks(mux_banks),.cpu_address(cpu_address),
        .paused(paused),.drive_data(drive_data),.ready(ready));

    // HDMI uses the same phase-related PLL / CLKDIV path as the normal core.
    generate if (ENABLE_HDMI!=0) begin:display_enabled
        wire clk108,clk108p,clk270,clk135,pixel_clk,video_reset_n,locked;
        coco_clocks clocks(.clkin(clkin),.button_reset(1'b0),.clk108(clk108),
            .clk108p(clk108p),.clk270(clk270),.clk135(clk135),.clk27(pixel_clk),
            .board_reset_n(video_reset_n),.clocks_locked(locked));
        cpu_bus_probe_hdmi display(.pixel_clk(pixel_clk),.serial_clk(clk135),
            .reset(!video_reset_n),.test_data(test_data),.data_readback(data_readback),
            .mux_banks(mux_banks),.cpu_address(cpu_address),.mp_live(mp_live),
            .extras({s2,s1,mspi_miso,sd_cmd,sd_dat0,sd_dat1,sd_dat2,sd_dat3}),
            .outputs({msel,ready,drive_data,paused,irq_n_in,firq_n_in,hs_n,fs_n,sam_s}),
            .tmds_clk_p(tmds_clk_p),.tmds_clk_n(tmds_clk_n),
            .tmds_data_p(tmds_data_p),.tmds_data_n(tmds_data_n));
    end else begin:display_disabled
        assign {tmds_clk_p,tmds_clk_n,tmds_data_p,tmds_data_n}=8'd0;
    end endgenerate
    assign audio_out=1'b0;
    assign y_out=1'b0;
    assign pb_out=1'b0;
    assign cvbs_out=1'b0;
    assign mspi_sclk=1'b0;
    assign mspi_cs=1'b1;
    assign mspi_mosi=1'b0;
    assign sd_sclk=1'b0;
    assign {sd_cmd,sd_dat0,sd_dat1,sd_dat2,sd_dat3}=5'bzzzzz;
    assign O_sdram_clk=1'b0;
    assign O_sdram_cke=1'b0;
    assign O_sdram_cs_n=1'b1;
    assign O_sdram_cas_n=1'b1;
    assign O_sdram_ras_n=1'b1;
    assign O_sdram_wen_n=1'b1;
    assign IO_sdram_dq=32'hzzzzzzzz;
    assign O_sdram_addr=0;
    assign O_sdram_ba=0;
    assign O_sdram_dqm=4'hf;
endmodule

// No ROM, SDRAM, or running CPU is needed to exercise the carrier pins.
module cpu_bus_probe_engine #(
    parameter integer BYTE_HOLD_CYCLES=27008,
    parameter integer STARTUP_CYCLES=27008,
    parameter integer STROBE_CYCLES=13500000,
    parameter integer BUTTON_CYCLES=270000
)(
    input clkin,input s1,input s2,input [7:0] mp,inout [7:0] cpu_data,
    output [1:0] msel,output reset_drive,output e_out,output q_out,
    output [2:0] sam_s,output irq_n,output firq_n,output hs_n,output fs_n,
    output reg [7:0] test_data,output reg [7:0] data_readback,
    output [7:0] mp_live,output reg [23:0] mux_banks,
    output [15:0] cpu_address,output reg paused,
    output drive_data,output reg ready
);
    initial begin
        test_data=0;data_readback=0;mux_banks=0;paused=0;ready=0;
    end
    // Pin 42 high asserts physical /RESET through the NPN transistor.
    assign reset_drive=1'b1;
    reg [3:0] phase=0;
    always @(posedge clkin) phase<=phase+1'b1;
    assign e_out=phase[3];
    assign q_out=phase[3]^phase[2]; // Q leads E; 1.6875 MHz

    wire step_press,pause_press;
    probe_button #(.CYCLES(BUTTON_CYCLES)) step_button(
        .clk(clkin),.pin(s1),.press(step_press));
    probe_button #(.CYCLES(BUTTON_CYCLES)) pause_button(
        .clk(clkin),.pin(s2),.press(pause_press));
    reg [31:0] startup_count=0,byte_count=0,strobe_count=0;
    reg [2:0] output_phase=0;
    // Commit user actions with E low, so changing the S decode does not
    // interrupt an enabled external transfer in the middle of its E phase.
    reg step_pending=0,pause_pending=0;
    always @(posedge clkin) begin
        if (step_press) step_pending<=1;
        if (pause_press) pause_pending<=1;
        if (phase==0 && pause_pending) begin
            paused<=!paused;pause_pending<=0;
        end
        if (!ready) begin
            if (startup_count==STARTUP_CYCLES-1) ready<=1;
            else startup_count<=startup_count+1'b1;
        end else if (phase==0 && step_pending) begin
            step_pending<=0;byte_count<=0;strobe_count<=0;
            test_data<=paused ? test_data+1'b1 : 8'd0;
            output_phase<=paused ? output_phase+1'b1 : 3'd0;
        end else if (!paused) begin
            if (byte_count==BYTE_HOLD_CYCLES-1) begin
                byte_count<=0;test_data<=test_data+1'b1;
            end else byte_count<=byte_count+1'b1;
            if (strobe_count==STROBE_CYCLES-1) begin
                strobe_count<=0;output_phase<=output_phase+1'b1;
            end else strobe_count<=strobe_count+1'b1;
        end
    end
    assign sam_s=output_phase;
    assign irq_n=~output_phase[0];
    assign firq_n=~output_phase[1];
    assign hs_n=~output_phase[2];
    assign fs_n=~(output_phase[0]^output_phase[1]);

    // Continuously inspect all three mux banks, with 16 raw clocks (~593 ns)
    // per bank. Two synchronizer stages settle well before each sample.
    reg [7:0] mp_meta=0,mp_sync=0,data_meta=0,data_sync=0;
    reg [1:0] bank=0;
    reg [3:0] settle=0;
    reg [7:0] address_low=0,address_high=0;
    reg controls_valid=0;
    always @(posedge clkin) begin
        mp_meta<=mp;mp_sync<=mp_meta;
        data_meta<=cpu_data;data_sync<=data_meta;
        settle<=settle+1'b1;
        if (&settle) begin
            case (bank)
                0:begin address_low<=mp_sync;bank<=1;end
                1:begin address_high<=mp_sync;bank<=2;end
                default:begin
                    mux_banks<={mp_sync,address_high,address_low};
                    controls_valid<=1;bank<=0;
                end
            endcase
        end
        if (phase==14) data_readback<=data_sync;
    end
    assign msel=bank;
    assign mp_live=mp_sync;
    assign cpu_address={mux_banks[8],mux_banks[9],mux_banks[10],
                        mux_banks[15:11],mux_banks[7:0]};
    // S=0/1/2 enables FPGA memory reads. S=3/6/7 disables /DATAEN;
    // S=4/5 selects PIA reads, which reverse DATADIR: release FPGA data.
    // Require physical /RESET low and R/W high in the control bank first.
    // MP0 may gate R/W directly only while the control bank is selected.
    assign drive_data=ready && controls_valid && !mux_banks[17] &&
        mux_banks[16] && sam_s<=2 && (bank!=2 || mp[0]);
    assign cpu_data=drive_data ? test_data : 8'hzz;
endmodule

module probe_button #(parameter integer CYCLES=270000)(
    input clk,input pin,output reg press
);
    initial press=0;
    reg meta=0,sync=0,stable=0;
    reg [31:0] count=0;
    always @(posedge clk) begin
        meta<=pin;sync<=meta;press<=0;
        if (sync==stable) count<=0;
        else if (count==CYCLES-1) begin
            stable<=sync;count<=0;press<=sync;
        end else count<=count+1'b1;
    end
endmodule
