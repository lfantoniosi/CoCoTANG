// Minimal shadow of PIA1 port A for the CoCo six-bit DAC.  The motherboard
// PIA remains the bus-visible device; this block only observes CPU writes so
// the FPGA can reproduce the otherwise-unavailable PA7..PA2 audio value.
module coco_pia1_dac (
    input clk,
    input reset_n,
    input e_fall,
    input cpu_rw_n,
    input [15:0] cpu_addr,
    input [7:0] cpu_data,
    output [5:0] dac_level,
    output [7:0] pwm_sample,
    output [15:0] pcm_sample,
    output reg audio_clk
);
    reg [7:0] port_a_data = 8'h00;
    reg [7:0] port_a_ddr = 8'h00;
    reg [7:0] control_a = 8'h00;

    // 108 MHz / (2 * 1125) = 48 kHz.  The HDMI packet engine samples PCM on
    // each rising edge of this clock.
    reg [10:0] audio_divider = 11'd0;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            port_a_data <= 8'h00;
            port_a_ddr <= 8'h00;
            control_a <= 8'h00;
            audio_divider <= 11'd0;
            audio_clk <= 1'b0;
        end else begin
            if (audio_divider == 11'd1124) begin
                audio_divider <= 11'd0;
                audio_clk <= !audio_clk;
            end else begin
                audio_divider <= audio_divider + 1'b1;
            end

            if (e_fall && !cpu_rw_n) begin
                if (cpu_addr == 16'hff21)
                    control_a <= cpu_data;
                else if (cpu_addr == 16'hff20) begin
                    if (control_a[2])
                        port_a_data <= cpu_data;
                    else
                        port_a_ddr <= cpu_data;
                end
            end
        end
    end

    wire [7:0] port_a_pins = port_a_data & port_a_ddr;
    assign dac_level = port_a_pins[7:2];
    assign pwm_sample = {port_a_pins[7:2], 2'b00};

    // Convert the CoCo's unsigned six-bit DAC to signed 16-bit PCM.  DAC 32
    // is digital zero, while DAC 0/63 become -32768/+31744 respectively.
    assign pcm_sample = {~port_a_pins[7], port_a_pins[6:2], 10'b0};
endmodule
