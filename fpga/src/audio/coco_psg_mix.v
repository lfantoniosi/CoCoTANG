// Add mono SSC (PSG and speech) at 1.5x gain (+3.5 dB) to HDMI and physical audio.
// Register the existing mix first: do not chain Orchestra-90's saturating
// adders with another adder on the 108-MHz input path.
module coco_psg_mix #(parameter integer ENABLED=1) (
    input clk,input reset_n,
    input [15:0] base_left,input [15:0] base_right,input [15:0] base_mono,
    input signed [15:0] psg_pcm,
    output [15:0] left_pcm,output [15:0] right_pcm,output [15:0] mono_pcm
);
    function [15:0] saturate;
        input signed [17:0] value;
        begin
            if(value[17:15] != {3{value[15]}})
                saturate=value[17] ? 16'h8000 : 16'h7fff;
            else saturate=value[15:0];
        end
    endfunction
    generate if(ENABLED) begin: enabled
        reg signed [15:0] held_left=0,held_right=0,held_mono=0;
        reg signed [16:0] held_psg=0;
        reg [15:0] mixed_left=0,mixed_right=0,mixed_mono=0;
        // Keep the boosted SSC sample wide until the final sum, so an
        // opposing DAC sample can cancel it before saturation.
        wire signed [16:0] input_sample=$signed({psg_pcm[15],psg_pcm});
        wire signed [17:0] ssc_sample=$signed({held_psg[16],held_psg});
        always @(posedge clk or negedge reset_n) begin
            if(!reset_n) begin
                held_left<=0;held_right<=0;held_mono<=0;held_psg<=0;
                mixed_left<=0;mixed_right<=0;mixed_mono<=0;
            end else begin
                held_left<=base_left;held_right<=base_right;
                held_mono<=base_mono;
                held_psg<=input_sample+(input_sample>>>1);
                mixed_left<=saturate($signed({{2{held_left[15]}},held_left})+ssc_sample);
                mixed_right<=saturate($signed({{2{held_right[15]}},held_right})+ssc_sample);
                mixed_mono<=saturate($signed({{2{held_mono[15]}},held_mono})+ssc_sample);
            end
        end
        assign left_pcm=mixed_left;
        assign right_pcm=mixed_right;
        assign mono_pcm=mixed_mono;
    end else begin: disabled
        assign left_pcm=base_left;
        assign right_pcm=base_right;
        assign mono_pcm=base_mono;
    end endgenerate
endmodule
