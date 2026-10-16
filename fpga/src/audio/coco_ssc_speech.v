// Command-level SSC speech controller with NRL English pronunciation rules.
// It supports the ASCII/CR host interface and buffered AL2 allophones.
// Speech256 runs with a synchronous 2.56-MHz
// enable, so audio, command RAM and the host all share clk108.
module coco_ssc_speech (
    input clk,input reset_n,input soft_reset,
    input command_valid,input [7:0] command_data,
    output reg loading=0,output active,output host_ready,
    output reg signed [15:0] pcm=0
);
    // Separate the shared SSC command/ready decoder from the speech FSM.
    // A CPU byte is separated by many 108-MHz clocks, so this extra stage
    // preserves the host handshake while shortening its large fanout path.
    reg command_pending=0;
    reg [7:0] command_byte=0;
    reg command_aborts_text=0;
    always @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin command_pending<=0;command_byte<=0;command_aborts_text<=0;end
        else if(soft_reset) command_pending<=0;
        else begin
            command_pending<=command_valid;
            if(command_valid) begin
                command_byte<=command_data;
                command_aborts_text<=command_data==0 || command_data==8'hc7 ||
                    (command_data[7:5]==3'b111 && !command_data[3]);
            end
        end
    end
    (* syn_ramstyle = "distributed_ram" *) reg [7:0] buffer [0:511];
    integer i;
    initial for(i=0;i<512;i=i+1) buffer[i]=8'hff;
    reg [8:0] load_pos=0,play_pos=0;
    reg load_chain=0,play_chain=0;
    reg [7:0] fetched=8'hff;
    reg [2:0] state=0;
    localparam IDLE=0,FETCH=1,DECODE=2,SEND=3,WAIT_LOW=4,WAIT_HIGH=5,DRAIN=6,TEXT_WAIT=7;
    reg last_allophone=0,text_playing=0;
    reg [2:0] reset_count=7;
    wire tts_host_ready,tts_busy,tts_valid,tts_last;
    wire [5:0] tts_allophone;
    wire tts_take=state==TEXT_WAIT && tts_valid && reset_count==0;
    // Predecode alongside command_byte without changing command latency.
    wire text_abort=soft_reset || (command_pending && !loading && command_aborts_text);
    assign host_ready=tts_host_ready && !text_playing;
    coco_ssc_tts translator(.clk(clk),.reset_n(reset_n),.abort(text_abort),
        .byte_valid(command_pending && !loading && command_byte<128 && command_byte!=0),
        .byte_data(command_byte),.host_ready(tts_host_ready),.busy(tts_busy),
        .allophone(tts_allophone),.allophone_valid(tts_valid),
        .allophone_last(tts_last),.allophone_ready(tts_take));
    reg [5:0] allophone=0;
    reg strobe=0;
    wire synth_reset_n=reset_n && reset_count==0;
    wire ldq,synth_active;
    wire signed [15:0] sample;
    wire sample_stb;
    // KQ1/KQ2's SSC-enabled Sierra loader expects BF shortly after reset.
    // Retain a short speech-startup window (1 ms); this is a compatibility
    // interval, not cycle-accurate TMS7040/SP0256 reset timing.
    reg [11:0] startup=12'd2560;
    reg [9:0] divider=0;
    wire cen=divider>=10'd659;
    assign active=state!=IDLE || startup!=0;
    SPEECH256_TOP synth(.clk(clk),.cen(cen),.rst_an(synth_reset_n),
        .active(synth_active),.ldq(ldq),.data_in(allophone),.data_stb(strobe),.pwm_out(),
        .sample_out(sample),.sample_stb(sample_stb));
    // Scale the filter samples to PCM and saturate loud phonemes. The
    // shared SSC mixer boosts both speech and PSG by 1.5x.
    wire signed [20:0] amplified=$signed(sample)*21'sd32;
    always @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            loading<=0;load_pos<=0;play_pos<=0;
            load_chain<=0;play_chain<=0;fetched<=8'hff;
            state<=IDLE;last_allophone<=0;text_playing<=0;
            allophone<=0;strobe<=0;reset_count<=7;divider<=0;pcm<=0;startup<=2560;
        end else begin
            if(cen && startup!=0) startup<=startup-1'b1;
            if(cen) divider<=divider-10'd659;
            else divider<=divider+10'd16;
            if(reset_count!=0) reset_count<=reset_count-1'b1;
            if(!active || !synth_reset_n) pcm<=0;
            else if(cen && sample_stb) begin
                if(amplified>21'sd32767) pcm<=16'sh7fff;
                else if(amplified< -21'sd32768) pcm<=16'sh8000;
                else pcm<=amplified[15:0];
            end
            case(state)
                FETCH: begin fetched<=buffer[play_pos];state<=DECODE;end
                DECODE: begin
                    if(fetched==8'hff) state<=DRAIN;
                    else begin
                        allophone<=fetched[5:0];
                        last_allophone<=play_pos[5:0]==63 &&
                            (!play_chain || play_pos[8:6]==7);
                        play_pos<=play_pos+1'b1;
                        state<=SEND;
                    end
                end
                SEND: if(cen && ldq) begin strobe<=1;state<=WAIT_LOW;end
                WAIT_LOW: if(cen) begin
                    strobe<=0;
                    if(!ldq) state<=WAIT_HIGH;
                end
                WAIT_HIGH: if(cen && ldq) begin
                    if(last_allophone) state<=DRAIN;
                    else state<=text_playing ? TEXT_WAIT : FETCH;
                end
                DRAIN: if(cen && !synth_active) begin state<=IDLE;text_playing<=0;end
                TEXT_WAIT: if(tts_take) begin
                    allophone<=tts_allophone;last_allophone<=tts_last;state<=SEND;
                end
                default: ;
            endcase
            if(command_pending) begin
                if(loading) begin
                    buffer[load_pos]<=command_byte;
                    if(command_byte==8'hff ||
                        (load_pos[5:0]==63 && (!load_chain || load_pos[8:6]==7)))
                        loading<=0;
                    else load_pos<=load_pos+1'b1;
                end else casez(command_byte)
                    8'b10100???,8'b10110???: begin
                        loading<=1;load_pos<={command_byte[2:0],6'd0};
                        load_chain<=!command_byte[4];
                    end
                    8'b11100???,8'b11110???: begin
                        play_pos<={command_byte[2:0],6'd0};
                        play_chain<=!command_byte[4];state<=FETCH;
                        strobe<=0;reset_count<=7;text_playing<=0;
                    end
                    8'h0d: begin
                        text_playing<=1;state<=TEXT_WAIT;
                        strobe<=0;reset_count<=7;
                    end
                    8'h00,8'hc7: begin
                        state<=IDLE;strobe<=0;reset_count<=7;text_playing<=0;
                    end
                    default: ;
                endcase
            end
            if(soft_reset) begin
                loading<=0;state<=IDLE;strobe<=0;
                reset_count<=7;pcm<=0;text_playing<=0;startup<=2560;
            end
        end
    end
endmodule
