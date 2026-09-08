// One write port plus two logical read clients. The physical BSRAM read port
// runs at 135 MHz; HDMI and CVBS addresses change at 27 and 13.5 MHz, so only
// changed addresses need to be fetched and there is ample arbitration margin.
module coco_framebuffer (
    input             write_clk,
    input             write_en,
    input      [15:0] write_addr,
    input       [5:0] write_data,
    input             read_clk,
    input      [15:0] hdmi_addr,
    output reg  [5:0] hdmi_data,
    input      [15:0] cvbs_addr,
    output reg  [5:0] cvbs_data
);
    // Explicit 32K banks avoid Gowin spilling the non-power-of-two tail into
    // flip-flops. Only 0..57599 are exposed; the unused high-bank tail is an
    // intentional BSRAM-for-logic trade which still fits comfortably.
    reg [5:0] memory_low [0:32767];
    reg [5:0] memory_high [0:32767];
    always @(posedge write_clk) begin
        if (write_en && write_addr < 16'd57600) begin
            if (write_addr[15])
                memory_high[write_addr[14:0]] <= write_data;
            else
                memory_low[write_addr[14:0]] <= write_data;
        end
    end

    reg [15:0] hdmi_addr_meta = 16'hffff;
    reg [15:0] hdmi_addr_sync = 16'hffff;
    reg [15:0] read_address = 16'd0;
    reg [5:0] low_data = 6'd0;
    reg [5:0] high_data = 6'd0;
    reg destination_0 = 1'b0, destination_1 = 1'b0;
    reg bank_0 = 1'b0, bank_1 = 1'b0;
    reg valid_0 = 1'b0, valid_1 = 1'b0;
    reg select_hdmi = 1'b0;

    // Keep each bank's read process in the canonical SDP-RAM form expected by
    // the Gowin inference engine. The arbiter only changes read_address.
    always @(posedge read_clk) begin
        low_data <= memory_low[read_address[14:0]];
        high_data <= memory_high[read_address[14:0]];
    end

    always @(posedge read_clk) begin
        hdmi_addr_meta <= hdmi_addr;
        hdmi_addr_sync <= hdmi_addr_meta;
        destination_1 <= destination_0;
        bank_1 <= bank_0;
        valid_1 <= valid_0;
        select_hdmi <= !select_hdmi;
        destination_0 <= select_hdmi;
        bank_0 <= select_hdmi ? hdmi_addr_sync[15] : cvbs_addr[15];
        read_address <= select_hdmi ? hdmi_addr_sync : cvbs_addr;
        valid_0 <= 1'b1;

        if (valid_1) begin
            if (destination_1)
                hdmi_data <= bank_1 ? high_data : low_data;
            else
                cvbs_data <= bank_1 ? high_data : low_data;
        end

    end
endmodule
