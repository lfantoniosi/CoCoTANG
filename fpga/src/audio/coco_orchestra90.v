// Orchestra-90 DACs only: no ROM, readback, CART signalling or bus drive.
// Observe completed CPU writes, just like the PIA1 audio shadow.
module coco_orchestra90 #(
    parameter integer ENABLED=1
) (
    input clk,input reset_n,input e_fall,input cpu_rw_n,
    input [15:0] cpu_addr,input [7:0] cpu_data,
    input [15:0] mono_pcm,
    output [15:0] left_pcm,output [15:0] right_pcm,
    output [15:0] mono_mix_pcm
);
    generate if(ENABLED)begin: enabled
        reg [7:0] left_dac=8'h80,right_dac=8'h80;
        always @(posedge clk or negedge reset_n)begin
            if(!reset_n)begin
                left_dac<=8'h80;
                right_dac<=8'h80;
            end else if(e_fall && !cpu_rw_n)begin
                if(cpu_addr==16'hff7a)left_dac<=cpu_data;
                if(cpu_addr==16'hff7b)right_dac<=cpu_data;
            end
        end
        // Offset-binary 8-bit DAC -> signed PCM at half gain, matching
        // MAME's stereo route. Preserve the existing mono gain and saturate
        // each sum rather than wrapping when both sources are loud.
        wire signed [15:0] left_sample={~left_dac[7],left_dac[6:0],8'b0};
        wire signed [15:0] right_sample={~right_dac[7],right_dac[6:0],8'b0};
        wire signed [16:0] left_sum=$signed({mono_pcm[15],mono_pcm})+
                                      ($signed({left_sample[15],left_sample})>>>1);
        wire signed [16:0] right_sum=$signed({mono_pcm[15],mono_pcm})+
                                       ($signed({right_sample[15],right_sample})>>>1);
        // Mono downmix of the two half-gain stereo contributions. Add
        // before clipping so opposite channels still cancel at high levels.
        wire signed [16:0] mono_sum=$signed({mono_pcm[15],mono_pcm})+
                                      ($signed({left_sample[15],left_sample})>>>2)+
                                      ($signed({right_sample[15],right_sample})>>>2);
        function [15:0] saturate;
            input signed [16:0] value;
            begin
                if(value>17'sd32767)saturate=16'h7fff;
                else if(value < -17'sd32768)saturate=16'h8000;
                else saturate=value[15:0];
            end
        endfunction
        assign left_pcm=saturate(left_sum);
        assign right_pcm=saturate(right_sum);
        assign mono_mix_pcm=saturate(mono_sum);
    end else begin: disabled
        assign left_pcm=mono_pcm;
        assign right_pcm=mono_pcm;
        assign mono_mix_pcm=mono_pcm;
    end endgenerate
endmodule
