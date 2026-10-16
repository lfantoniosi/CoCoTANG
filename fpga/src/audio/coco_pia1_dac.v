// Minimal shadow of PIA1 port A and port B control for the CoCo six-bit DAC.
// The motherboard PIA remains the bus-visible device; this block only observes
// CPU writes so the FPGA can reproduce the otherwise-unavailable PA7..PA2 DAC
// and CB2 sound-enable state.
module coco_pia1_dac (
    input clk,
    input reset_n,
    input e_fall,
    input cpu_rw_n,
    input [15:0] cpu_addr,
    input [7:0] cpu_data,
    output [5:0] dac_level,
    output sound_enable,
    output [7:0] pwm_sample,
    output [15:0] pcm_sample,
    output reg audio_clk
);
    reg [7:0] port_a_data = 8'h00;
    reg [7:0] port_a_ddr = 8'h00;
    reg [7:0] control_a = 8'h00;
    reg [7:0] control_b = 8'h00;
    reg [7:0] mux_control_a = 8'h00, mux_control_b = 8'h00;

    // 108 MHz / (2 * 1125) = 48 kHz.  The HDMI packet engine samples PCM on
    // each rising edge of this clock.
    reg [10:0] audio_divider = 11'd0;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            port_a_data <= 8'h00;
            port_a_ddr <= 8'h00;
            control_a <= 8'h00;
            control_b <= 8'h00;
            mux_control_a <= 8'h00;
            mux_control_b <= 8'h00;
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
                if (cpu_addr == 16'hff01)
                    mux_control_a <= cpu_data;
                else if (cpu_addr == 16'hff03)
                    mux_control_b <= cpu_data;
                else if (cpu_addr == 16'hff21)
                    control_a <= cpu_data;
                else if (cpu_addr == 16'hff23)
                    control_b <= cpu_data;
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

    // PIA1 CB2 is the CoCo analog sound-enable line.  Joystick reads use the
    // same DAC as a comparator reference with CB2 low, so forwarding every DAC
    // write would turn joystick movement into loud noise.  The CoCo programs
    // CRB to manual-output mode ($34=low, $3c=high) for this signal.
    assign sound_enable = control_b[5] && control_b[4] && control_b[3];
    // PIA0 CA2/CB2 select the analogue source. The SSC manual selects
    // cartridge input with $FF01=$34, $FF03=$3f. CB2 at PIA1 still enables
    // sound, but the six-bit DAC must not contribute in that mux position.
    wire dac_selected = (mux_control_a[5:3] != 3'b111) &&
                        (mux_control_b[5:3] != 3'b111);
    assign pwm_sample = (sound_enable && dac_selected) ?
                        {port_a_pins[7:2], 2'b00} : 8'h80;

    // Convert the CoCo's unsigned six-bit DAC to signed 16-bit PCM.  DAC 32
    // is digital zero, while DAC 0/63 become -32768/+31744 respectively.
    assign pcm_sample = sound_enable && dac_selected
                      ? {~port_a_pins[7], port_a_pins[6:2], 10'b0}
                      : 16'h0000;
endmodule
