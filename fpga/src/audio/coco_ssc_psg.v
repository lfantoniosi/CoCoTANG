// Tandy Speech/Sound Cartridge command interface with optional speech.
// $FF7D resets the interface;
// $FF7E accepts direct AY writes, sound events, and buffered register streams.
module coco_ssc_psg #(parameter integer ENABLE_SPEECH=0,
    parameter integer DECODE_ADDRESS=1) (
    input clk, input reset_n,
    input cpu_enable, input e, input e_fall,
    input [15:0] cpu_addr, input cpu_rw_n, input [7:0] cpu_wdata,
    input audio_clk,
    output [7:0] cpu_rdata, output cpu_data_oe,
    output signed [15:0] speech_pcm,
    output reg signed [15:0] psg_pcm
);
    // The board's parent uses an atomic, already decoded bus snapshot.
    // Standalone instantiations retain exact FF7D/E address checking.
    wire selected = cpu_enable && (!DECODE_ADDRESS ||
        cpu_addr==16'hff7d || cpu_addr==16'hff7e);
    // Capture completed bus writes before the command parser. Address
    // decoding must not feed the entire event/buffer state machine in the
    // same 108-MHz cycle, and data must survive the next CPU transaction.
    reg host_write=0,host_reset_port=0,host_stop=0;
    reg [7:0] host_data=0;
    always @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            host_write<=0;host_reset_port<=0;host_data<=0;host_stop<=0;
        end else begin
            host_write<=selected && !cpu_rw_n && e_fall;
            if(selected && !cpu_rw_n && e_fall) begin
                host_reset_port<=cpu_addr[0];host_data<=cpu_wdata;
                host_stop<=cpu_wdata==0 || cpu_wdata==8'hc7;
            end
        end
    end
    assign cpu_data_oe = selected && cpu_rw_n && e;

    reg [7:0] busy_count = 0;
    wire speech_host_ready;
    wire ready = busy_count == 0 && speech_host_ready;
    reg reset_command = 0;
    reg timer_byte_next = 0;
    reg direct_psg = 0, direct_data_next = 0;
    reg [3:0] direct_register = 0;
    reg [1:0] load_kind = 0; // 0=none, 1=register pairs, 2=sound events
    reg [1:0] load_remaining = 0;
    reg load_consecutive = 0;
    reg [2:0] load_bank = 0;
    reg [5:0] load_offset = 0;
    reg play_stream = 0, play_chain = 0, play_data_next = 0;
    reg play_fetch = 1;
    reg [7:0] play_byte = 8'hff;
    reg [2:0] play_bank = 0;
    reg [5:0] play_offset = 0;
    reg [3:0] play_register = 0;
    (* syn_ramstyle = "distributed_ram" *) reg [7:0] sound_buffer [0:511];
    (* syn_ramstyle = "distributed_ram" *) reg [7:0] effect_buffer [0:511];
    reg [4:0] volume_a = 0, volume_b = 0, volume_c = 0;
    integer i;
    initial for (i = 0; i < 512; i = i + 1) begin
        sound_buffer[i] = 8'hff;
        effect_buffer[i] = 8'hff;
    end

    localparam FX_IDLE=4'd0, FX_HEADER=4'd1, FX_BYTE2=4'd2,
        FX_BYTE3=4'd3, FX_BYTE4=4'd4, FX_WRITE=4'd5,
        FX_GAP=4'd6, FX_WAIT=4'd7, FX_FETCH=4'd8, FX_LATCH=4'd9;
    reg [3:0] effect_state = FX_IDLE;
    reg [3:0] effect_read_target = FX_HEADER;
    reg [7:0] effect_ram_byte = 8'hff;
    reg [7:0] effect_read_byte = 8'hff;
    reg [8:0] effect_pos = 0;
    reg effect_chain = 0, effect_exhausted = 0;
    reg [7:0] effect_header = 0, effect_byte2 = 0,
              effect_byte3 = 0, effect_duration = 0;
    reg [2:0] effect_write_index = 0;
    reg [7:0] effect_wait_duration = 0;
    reg [7:0] effect_wait_base = 0;
    reg [4:0] effect_wait_sub = 0;
    reg [7:0] timer_base = 0;
    reg [7:0] mixer_shadow = 8'hff;
    wire [1:0] effect_channel = effect_header[6:5];
    wire effect_envelope = effect_channel == 2'd3;
    wire effect_noise = effect_header[7] && !effect_envelope;
    wire [7:0] effect_mixer = effect_noise ?
        (mixer_shadow | (8'h01 << effect_channel)) &
        ~(8'h08 << effect_channel) :
        (mixer_shadow & ~(8'h01 << effect_channel)) |
        (8'h08 << effect_channel);
    wire [4:0] effect_volume = effect_noise && effect_byte2[7] ?
        (effect_channel == 0 ? volume_a :
         effect_channel == 1 ? volume_b : volume_c) : effect_header[4:0];
    reg audio_clk_prev = 0;
    wire audio_tick = audio_clk && !audio_clk_prev;

    reg [3:0] psg_addr = 0;
    reg [7:0] psg_data = 0;
    reg psg_write = 0;
    reg [1:0] psg_reset_count = 2;
    wire sound_active = effect_state != FX_IDLE ||
        (volume_a | volume_b | volume_c) != 0;
    wire speech_loading, speech_active;
    // Stop commands may interrupt text playback while its BUSY bit is low.
    // Values inside a register/event/allophone payload retain their data meaning.
    wire stop_command=host_stop &&
        !timer_byte_next && load_kind==0 && !direct_psg && !speech_loading;
    wire accept_host_byte=ready || (busy_count==0 && stop_command);
    wire speech_command = host_write && !host_reset_port && accept_host_byte &&
        !timer_byte_next && load_kind==0 && !direct_psg;
    // Keep reset-port decode out of the speech/TTS state-register fanout.
    // Host bytes are separated by many system clocks.
    reg speech_reset=0;
    always @(posedge clk or negedge reset_n) begin
        if(!reset_n) speech_reset<=0;
        else speech_reset<=reset_command || (host_write && host_reset_port && host_data[0]);
    end
    generate if (ENABLE_SPEECH) begin: speech_enabled
        coco_ssc_speech speech(.clk(clk),.reset_n(reset_n),
            .soft_reset(speech_reset),.command_valid(speech_command),
            .command_data(host_data),.loading(speech_loading),.host_ready(speech_host_ready),
            .active(speech_active),.pcm(speech_pcm));
    end else begin: speech_disabled
        assign speech_host_ready=1;
        assign speech_loading=0;
        assign speech_active=0;
        assign speech_pcm=0;
    end endgenerate
    assign cpu_rdata = cpu_addr[0] ? 8'hff :
        {ready && !host_write, !speech_active, !sound_active, 5'h1f};

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            busy_count <= 0;
            reset_command <= 0;
            timer_byte_next <= 0;
            direct_psg <= 0;
            direct_data_next <= 0;
            direct_register <= 0;
            load_kind <= 0;
            load_remaining <= 0;
            load_consecutive <= 0;
            load_bank <= 0;
            load_offset <= 0;
            play_stream <= 0;
            play_chain <= 0;
            play_data_next <= 0;
            play_fetch <= 1;
            play_byte <= 8'hff;
            play_bank <= 0;
            play_offset <= 0;
            play_register <= 0;
            effect_state <= FX_IDLE;
            effect_read_target <= FX_HEADER;
            effect_read_byte <= 8'hff;
            effect_pos <= 0;
            effect_chain <= 0;
            effect_exhausted <= 0;
            effect_header <= 0;
            effect_byte2 <= 0;
            effect_byte3 <= 0;
            effect_duration <= 0;
            effect_write_index <= 0;
            effect_wait_duration <= 0;
            effect_wait_base <= 0;
            effect_wait_sub <= 0;
            timer_base <= 0;
            mixer_shadow <= 8'hff;
            psg_addr <= 0;
            psg_data <= 0;
            psg_write <= 0;
            psg_reset_count <= 2;
            volume_a <= 0;
            volume_b <= 0;
            volume_c <= 0;
        end else begin
            psg_write <= 0;
            if (busy_count != 0) busy_count <= busy_count - 1'b1;
            if (psg_reset_count != 0)
                psg_reset_count <= psg_reset_count - 1'b1;
            if (psg_write && psg_addr == 4'd7)
                mixer_shadow <= psg_data;
            if (psg_reset_count != 0) begin
                volume_a <= 0;
                volume_b <= 0;
                volume_c <= 0;
            end else if (psg_write) begin
                case (psg_addr)
                    4'd8: volume_a <= psg_data[4:0];
                    4'd9: volume_b <= psg_data[4:0];
                    4'd10: volume_c <= psg_data[4:0];
                    default: ;
                endcase
            end

            if (host_write && host_reset_port) begin
                if (host_data[0]) reset_command <= 1;
                else if (reset_command) begin
                    reset_command <= 0;
                    busy_count <= 0;
                    direct_psg <= 0;
                    direct_data_next <= 0;
                    timer_byte_next <= 0;
                    load_kind <= 0;
                    load_remaining <= 0;
                    play_stream <= 0;
                    effect_state <= FX_IDLE;
                    psg_reset_count <= 2;
                    mixer_shadow <= 8'hff;
                end
            end else if (host_write && !host_reset_port && accept_host_byte) begin
                busy_count <= 8'd32;
                if (speech_loading) begin
                    // Speech module consumes this byte, including its FF terminator.
                end else if (timer_byte_next) begin
                    timer_base <= host_data;
                    timer_byte_next <= 0;
                end else if (load_kind != 0) begin
                    if (load_kind == 1)
                        sound_buffer[{load_bank,load_offset}] <= host_data;
                    else
                        effect_buffer[{load_bank,load_offset}] <= host_data;
                    if (load_remaining == 0 && host_data == 8'hff)
                        load_kind <= 0;
                    else begin
                        if (load_remaining != 0)
                            load_remaining <= load_remaining - 1'b1;
                        else if (load_kind == 1)
                            load_remaining <= 1;
                        else
                            load_remaining <= host_data[7] ? 2 : 3;
                    end
                    if (load_offset == 6'd63 && load_consecutive) begin
                        load_offset <= 0;
                        if (load_bank != 7) load_bank <= load_bank + 1'b1;
                        else load_kind <= 0;
                    end else if (load_offset != 6'd63)
                        load_offset <= load_offset + 1'b1;
                    else
                        load_kind <= 0;
                end else if (direct_psg &&
                             (direct_data_next ||
                              (host_data != 8'haf && host_data != 8'hff))) begin
                    if (!direct_data_next) begin
                        direct_register <= host_data[3:0];
                        direct_data_next <= 1;
                    end else begin
                        psg_addr <= direct_register;
                        psg_data <= host_data;
                        psg_write <= 1;
                        direct_data_next <= 0;
                    end
                end else if (direct_psg && !direct_data_next) begin
                    // The manual ends immediate register mode with FF.
                    direct_psg <= 0;
                end else begin
                    casez (host_data)
                        8'h00: begin
                            psg_reset_count <= 2;
                            play_stream <= 0;
                            effect_state <= FX_IDLE;
                            direct_psg <= 0;
                            mixer_shadow <= 8'hff;
                        end
                        8'h8f: begin // next byte sets the sound timer base
                            timer_byte_next <= 1;
                        end
                        8'haf: begin
                            direct_psg <= !direct_psg;
                            direct_data_next <= 0;
                        end
                        8'hcf: begin
                            psg_reset_count <= 2;
                            play_stream <= 0;
                            effect_state <= FX_IDLE;
                            mixer_shadow <= 8'hff;
                        end
                        8'b10001???: begin // 88-8E: sound event banks
                            if (host_data != 8'h8f) begin
                                load_kind <= 2;
                                load_consecutive <= 1;
                                load_bank <= host_data[2:0];
                                load_offset <= 0;
                                load_remaining <= 0;
                            end
                        end
                        8'b10011???: begin // 98-9F: one sound event bank
                            load_kind <= 2;
                            load_consecutive <= 0;
                            load_bank <= host_data[2:0];
                            load_offset <= 0;
                            load_remaining <= 0;
                        end
                        8'b10111???: begin // B8-BF: load one 64-byte bank
                            load_kind <= 1;
                            load_consecutive <= 0;
                            load_bank <= host_data[2:0];
                            load_offset <= 0;
                            load_remaining <= 0;
                        end
                        8'b10101???: begin // A8-AE: load consecutive banks
                            load_kind <= 1;
                            load_consecutive <= 1;
                            load_bank <= host_data[2:0];
                            load_offset <= 0;
                            load_remaining <= 0;
                        end
                        8'b11001???: begin // C8-CE: consecutive sound banks
                            if (host_data != 8'hcf) begin
                                effect_state <= FX_FETCH;
                                effect_read_target <= FX_HEADER;
                                effect_pos <= {host_data[2:0],6'd0};
                                effect_chain <= 1;
                                effect_exhausted <= 0;
                                play_stream <= 0;
                            end
                        end
                        8'b11011???: begin // D8-DF: one sound bank
                            effect_state <= FX_FETCH;
                            effect_read_target <= FX_HEADER;
                            effect_pos <= {host_data[2:0],6'd0};
                            effect_chain <= 0;
                            effect_exhausted <= 0;
                            play_stream <= 0;
                        end
                        8'b11111???: begin // F8-FF: play one register stream
                            play_stream <= 1;
                            play_chain <= 0;
                            play_bank <= host_data[2:0];
                            play_offset <= 0;
                            play_data_next <= 0;
                            play_fetch <= 1;
                            effect_state <= FX_IDLE;
                        end
                        8'b11101???: begin // E8-EF: play consecutive streams
                            play_stream <= 1;
                            play_chain <= 1;
                            play_bank <= host_data[2:0];
                            play_offset <= 0;
                            play_data_next <= 0;
                            play_fetch <= 1;
                            effect_state <= FX_IDLE;
                        end
                        default: ;
                    endcase
                end
            end

            // Buffered streams contain (register,value) pairs followed by FF.
            // Direct host writes take priority over autonomous playback.
            if (play_stream && !psg_write && !host_write) begin
                if (play_fetch) begin
                    play_byte <= sound_buffer[{play_bank,play_offset}];
                    play_fetch <= 0;
                end else begin
                    play_fetch <= 1;
                    if (play_byte == 8'hff && !play_data_next)
                        play_stream <= 0;
                    else begin
                        if (!play_data_next) begin
                            play_register <= play_byte[3:0];
                            play_data_next <= 1;
                        end else begin
                            psg_addr <= play_register;
                            psg_data <= play_byte;
                            psg_write <= 1;
                            play_data_next <= 0;
                        end
                        if (play_offset == 6'd63 && play_chain && play_bank != 7) begin
                            play_bank <= play_bank + 1'b1;
                            play_offset <= 0;
                        end else if (play_offset == 6'd63)
                            play_stream <= 0;
                        else
                            play_offset <= play_offset + 1'b1;
                    end
                end
            end

            // Play the manual's 3/4-byte sound events. Each event updates AY
            // registers, then holds them for its timer-scaled duration.
            if (effect_state != FX_IDLE && !host_write && !play_stream &&
                !psg_write) begin
                case (effect_state)
                    FX_FETCH: begin
                        effect_ram_byte <= effect_buffer[effect_pos];
                        effect_state <= FX_LATCH;
                    end
                    FX_LATCH: begin
                        // Block RAM's output and bank mux need their own
                        // cycle before header decoding and position updates.
                        effect_read_byte <= effect_ram_byte;
                        effect_state <= effect_read_target;
                    end
                    FX_HEADER: begin
                        if (effect_exhausted ||
                            effect_read_byte == 8'hff)
                            effect_state <= FX_IDLE;
                        else begin
                            effect_header <= effect_read_byte;
                            effect_pos <= effect_pos + 1'b1;
                            if (effect_pos[5:0] == 6'd63 &&
                                (!effect_chain || effect_pos[8:6] == 3'd7))
                                effect_exhausted <= 1;
                            effect_state <= FX_FETCH;
                            effect_read_target <= FX_BYTE2;
                        end
                    end
                    FX_BYTE2: begin
                        effect_byte2 <= effect_read_byte;
                        effect_pos <= effect_pos + 1'b1;
                        if (effect_pos[5:0] == 6'd63 &&
                            (!effect_chain || effect_pos[8:6] == 3'd7))
                            effect_exhausted <= 1;
                        effect_state <= FX_FETCH;
                        effect_read_target <= FX_BYTE3;
                    end
                    FX_BYTE3: begin
                        effect_byte3 <= effect_read_byte;
                        effect_pos <= effect_pos + 1'b1;
                        if (effect_pos[5:0] == 6'd63 &&
                            (!effect_chain || effect_pos[8:6] == 3'd7))
                            effect_exhausted <= 1;
                        if (effect_noise) begin
                            effect_duration <= effect_read_byte;
                            effect_write_index <= 0;
                            effect_state <= FX_WRITE;
                        end else begin
                            effect_state <= FX_FETCH;
                            effect_read_target <= FX_BYTE4;
                        end
                    end
                    FX_BYTE4: begin
                        effect_duration <= effect_read_byte;
                        effect_pos <= effect_pos + 1'b1;
                        if (effect_pos[5:0] == 6'd63 &&
                            (!effect_chain || effect_pos[8:6] == 3'd7))
                            effect_exhausted <= 1;
                        effect_write_index <= 0;
                        effect_state <= FX_WRITE;
                    end
                    FX_WRITE: begin
                        psg_write <= 1;
                        if (effect_envelope) begin
                            case (effect_write_index)
                                0: begin psg_addr <= 11; psg_data <= effect_byte3; end
                                1: begin psg_addr <= 12; psg_data <= effect_byte2; end
                                default: begin
                                    psg_addr <= 13;
                                    psg_data <= {4'b0000,effect_header[3:0]};
                                end
                            endcase
                        end else if (effect_noise) begin
                            case (effect_write_index)
                                0: begin psg_addr <= 7; psg_data <= effect_mixer; end
                                1: begin psg_addr <= 6; psg_data <= effect_byte2 & 8'h1f; end
                                default: begin
                                    psg_addr <= 4'd8 + {2'b00,effect_channel};
                                    psg_data <= {3'b000,effect_volume};
                                end
                            endcase
                        end else begin
                            case (effect_write_index)
                                0: begin psg_addr <= 7; psg_data <= effect_mixer; end
                                1: begin
                                    psg_addr <= {effect_channel,1'b0};
                                    psg_data <= effect_byte3;
                                end
                                2: begin
                                    psg_addr <= {effect_channel,1'b1};
                                    psg_data <= effect_byte2 & 8'h0f;
                                end
                                default: begin
                                    psg_addr <= 4'd8 + {2'b00,effect_channel};
                                    psg_data <= {3'b000,effect_volume};
                                end
                            endcase
                        end
                        if ((effect_noise || effect_envelope) ?
                            effect_write_index == 2 : effect_write_index == 3) begin
                            effect_wait_duration <= effect_duration;
                            effect_wait_base <= timer_base;
                            effect_wait_sub <= 5'd23;
                            effect_state <= FX_WAIT;
                        end else begin
                            effect_write_index <= effect_write_index + 1'b1;
                            effect_state <= FX_GAP;
                        end
                    end
                    FX_GAP: effect_state <= FX_WRITE;
                    FX_WAIT: if (audio_tick) begin
                        if (effect_wait_sub != 0)
                            effect_wait_sub <= effect_wait_sub - 1'b1;
                        else if (effect_wait_base != 0) begin
                            effect_wait_sub <= 5'd23;
                            effect_wait_base <= effect_wait_base - 1'b1;
                        end else if (effect_wait_duration != 0) begin
                            effect_wait_sub <= 5'd23;
                            effect_wait_base <= timer_base;
                            effect_wait_duration <= effect_wait_duration - 1'b1;
                        end else begin
                            effect_state <= FX_FETCH;
                            effect_read_target <= FX_HEADER;
                        end
                    end
                    default: effect_state <= FX_IDLE;
                endcase
            end
        end
    end

    // 108 MHz * 71176039 / 2^32 = 1,789,772.001 Hz average. A clock enable
    // keeps JT49 in the 108 MHz domain; pulse spacing is 60 or 61 clocks.
    // Split the accumulator into two pipelined 16-bit additions. The low
    // carry is applied to the high word one clock later; this changes pulse
    // placement by at most one 108 MHz tick, but keeps the exact mean rate.
    reg [15:0] psg_phase_lo = 0, psg_phase_hi = 0;
    reg psg_low_carry = 0, psg_clock_enable = 0;
    wire [16:0] psg_low_sum = {1'b0,psg_phase_lo} + 17'h00f67;
    wire [16:0] psg_high_sum = {1'b0,psg_phase_hi} +
                               17'h0043e + psg_low_carry;
    always @(posedge clk or negedge reset_n)
        if (!reset_n) begin
            psg_phase_lo <= 0;
            psg_phase_hi <= 0;
            psg_low_carry <= 0;
            psg_clock_enable <= 0;
        end else begin
            psg_phase_lo <= psg_low_sum[15:0];
            psg_phase_hi <= psg_high_sum[15:0];
            psg_low_carry <= psg_low_sum[16];
            psg_clock_enable <= psg_high_sum[16];
        end

    wire [9:0] psg_sound;
    jt49 psg (
        .rst_n(reset_n && psg_reset_count == 0),.clk(clk),
        .clk_en(psg_clock_enable),.addr(psg_addr),
        .cs_n(!psg_write),.wr_n(!psg_write),.din(psg_data),.sel(1'b1),
        .dout(),.sound(psg_sound),.A(),.B(),.C(),.sample(),
        .IOA_in(8'hff),.IOA_out(),.IOA_oe(),
        .IOB_in(8'hff),.IOB_out(),.IOB_oe()
    );

    // AC-couple the PSG for HDMI and PWM at the existing 48 kHz audio rate.
    // The 10-bit unipolar output is scaled by 32 before its moving DC level
    // is removed. Both sinks receive the same signed PCM sample.
    reg signed [25:0] dc_accum = 0;
    wire signed [25:0] psg_level_fixed =
        $signed({1'b0,psg_sound,5'b0,8'b0});
    wire signed [25:0] dc_error = psg_level_fixed - dc_accum;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            audio_clk_prev <= 0;
            dc_accum <= 0;
            psg_pcm <= 0;
        end else begin
            audio_clk_prev <= audio_clk;
            // A controller reset/CF stop must silence both outputs, rather
            // than leaving the previous DC estimate as an audible tail.
            if (psg_reset_count != 0) begin
                dc_accum <= 0;
                psg_pcm <= 0;
            end else if (audio_clk && !audio_clk_prev) begin
                dc_accum <= dc_accum + (dc_error >>> 10);
                psg_pcm <= dc_error >>> 8;
            end
        end
    end
endmodule
