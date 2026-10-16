// English text to AL2 allophones using the public NRL letter-to-sound rules.
// A serial matcher keeps the rule tables and input text in block RAM. Repeat
// operators backtrack, so adjacent classes such as # : retain regex semantics.
module coco_ssc_tts (
    input clk,input reset_n,input abort,
    input byte_valid,input [7:0] byte_data,
    output host_ready,output reg busy=0,
    output [5:0] allophone,output allophone_valid,output allophone_last,
    input allophone_ready
);
    (* syn_ramstyle = "distributed_ram" *) reg [7:0] text [0:511];
    initial text[0]=8'h20;
    reg [9:0] write_pos=1,text_limit=1,cursor=1,match_pos=1,match_end=1;
    reg [15:0] normalize_bytes=0;
    reg [1:0] normalize_count=0,last_kind=0;
    reg [7:0] text_data=0;
    reg text_in_range=0,text_at_end=0;
    reg [12:0] pc=0,next_rule=0;
    wire [7:0] opcode_raw;
    reg [7:0] opcode=0;
    reg opcode_zero=1,opcode_end=0,opcode_repeat=0;
    wire [12:0] first_rule;
    reg [7:0] character=8'h20;
    wire [7:0] character_raw=text_in_range ? text_data :
        text_at_end ? 8'h20 : 8'h00;
    coco_ssc_tts_rom rules(.clk(clk),.address(pc),.data(opcode_raw),
        .letter(character),.first_rule(first_rule));
    always @(posedge clk) begin
        text_data<=text[match_pos[8:0]];
        text_in_range<=match_pos<text_limit;
        text_at_end<=match_pos==text_limit;
    end

    localparam START=0,LOOKUP=1,HEADER_LO=2,HEADER_HI=3,
        MATCH=4,BACKTRACK=5,OUTPUT=6,FINAL=7;
    localparam LITERAL=0,LEFT=1,RIGHT=2;
    reg [2:0] state=START;
    reg [1:0] phase=LITERAL;
    reg [1:0] wait_read=3;
    reg matched=0,retry_matched=0;
    reg [12:0] first_rule_held=0;
    reg [2:0] depth=0;
    // At most four repeat operators occur in a context in this rule set.
    reg [12:0] retry_pc [0:3];
    reg [9:0] retry_pos [0:3];
    reg retry_vowel [0:3];
    wire [9:0] advanced=phase==LEFT ? match_pos-1'b1 : match_pos+1'b1;
    wire [7:0] upper=(byte_data>=8'h61 && byte_data<=8'h7a) ?
        byte_data-8'd32 : byte_data;
    function [1:0] kind;
        input [7:0] value;
        begin
            if(value==8'h20 || value==8'h09) kind=0;
            else if(value>=8'h41 && value<=8'h5a) kind=1;
            else kind=2;
        end
    endfunction
    function class_matches;
        input [7:0] token,value;
        begin
            case(token)
                128,132: case(value)
                    "A","E","I","O","U","Y": class_matches=1;
                    default: class_matches=0;
                endcase
                129,133: case(value)
                    "B","C","D","F","G","H","J","K","L","M","N",
                    "P","Q","R","S","T","V","W","X","Z": class_matches=1;
                    default: class_matches=0;
                endcase
                130: case(value)
                    "B","D","V","G","J","L","M","N","R","W","Z": class_matches=1;
                    default: class_matches=0;
                endcase
                131: class_matches=value=="E" || value=="I" || value=="Y";
                default: class_matches=token==value && value!=0;
            endcase
        end
    endfunction
    // Synchronous RAM read, registered ROM output, classification, then the FSM.
    // Keep bounds checks and rule classes off the state-update critical path.
    always @(posedge clk) begin
        character<=character_raw;
        opcode<=opcode_raw;
        opcode_zero<=opcode_raw==0;
        opcode_end<=opcode_raw==255;
        opcode_repeat<=opcode_raw==132 || opcode_raw==133;
        matched<=class_matches(opcode,character);
        retry_matched<=class_matches(retry_vowel[depth-1'b1] ? 8'd128 : 8'd129,character);
        first_rule_held<=first_rule;
    end
    assign host_ready=!busy && normalize_count==0;
    assign allophone_valid=busy && ((state==OUTPUT && !wait_read && !opcode_end) || state==FINAL);
    assign allophone=state==FINAL ? 6'd4 : opcode[5:0];
    assign allophone_last=state==FINAL;

    task reject_rule;
        begin
            depth<=0;match_pos<=cursor;wait_read<=3;
            if(next_rule!=0) begin pc<=next_rule;state<=HEADER_LO;end
            else begin cursor<=cursor+1'b1;match_pos<=cursor+1'b1;state<=LOOKUP;end
        end
    endtask
    task mismatch;
        begin
            if(depth!=0) begin
                match_pos<=retry_pos[depth-1'b1];state<=BACKTRACK;wait_read<=3;
            end else reject_rule;
        end
    endtask

    always @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            write_pos<=1;text_limit<=1;cursor<=1;match_pos<=1;match_end<=1;
            normalize_bytes<=0;normalize_count<=0;last_kind<=0;
            pc<=0;next_rule<=0;busy<=0;state<=START;phase<=LITERAL;
            wait_read<=3;depth<=0;
        end else if(abort) begin
            write_pos<=1;normalize_count<=0;last_kind<=0;
            busy<=0;state<=START;wait_read<=3;depth<=0;
        end else begin
            // Normalize exactly as the NRL frontend: uppercase, spaces around
            // non-letter groups, and collapse whitespace. Reserve index zero
            // as the implicit left word boundary and the last cell for padding.
            if(normalize_count!=0) begin
                if(write_pos<511) begin
                    text[write_pos[8:0]]<=normalize_bytes[7:0];
                    write_pos<=write_pos+1'b1;
                    last_kind<=kind(normalize_bytes[7:0]);
                end
                normalize_bytes<={8'd0,normalize_bytes[15:8]};
                normalize_count<=normalize_count-1'b1;
            end
            if(byte_valid && host_ready) begin
                if(byte_data==13) begin
                    busy<=1;state<=START;
                    if(last_kind!=0 && write_pos<511) begin
                        normalize_bytes<=16'h0020;normalize_count<=1;
                    end
                end else if((byte_data>=32 && byte_data<127) || byte_data==9) begin
                    if(kind(upper)==0) begin
                        if(last_kind!=0) begin
                            normalize_bytes<=16'h0020;normalize_count<=1;
                        end
                    end else if(last_kind!=0 && kind(upper)!=last_kind) begin
                        normalize_bytes<={upper,8'h20};normalize_count<=2;
                    end else begin normalize_bytes<={8'd0,upper};normalize_count<=1;end
                end
            end
            if(busy) begin
                if(state==START) begin
                    if(normalize_count==0) begin
                        text_limit<=write_pos;cursor<=1;match_pos<=1;
                        state<=LOOKUP;wait_read<=3;
                    end
                end else if(wait_read!=0) wait_read<=wait_read-1'b1;
                else case(state)
                    LOOKUP: begin
                        if(cursor>=text_limit) state<=FINAL;
                        else if(first_rule_held==0) begin
                            cursor<=cursor+1'b1;match_pos<=cursor+1'b1;wait_read<=3;
                        end else begin pc<=first_rule_held;state<=HEADER_LO;wait_read<=3;end
                    end
                    HEADER_LO: begin next_rule[7:0]<=opcode;pc<=pc+1'b1;state<=HEADER_HI;wait_read<=3;end
                    HEADER_HI: begin
                        next_rule[12:8]<=opcode[4:0];pc<=pc+1'b1;
                        phase<=LITERAL;depth<=0;state<=MATCH;wait_read<=3;
                    end
                    MATCH: begin
                        if(opcode_zero) begin
                            pc<=pc+1'b1;depth<=0;wait_read<=3;
                            case(phase)
                                LITERAL: begin match_end<=match_pos;match_pos<=cursor-1'b1;phase<=LEFT;end
                                LEFT: begin match_pos<=match_end;phase<=RIGHT;end
                                RIGHT: state<=OUTPUT;
                                default: ;
                            endcase
                        end else if(phase!=LITERAL && opcode_repeat) begin
                            if(depth<4) begin
                                retry_pc[depth[1:0]]<=pc+1'b1;
                                retry_pos[depth[1:0]]<=match_pos;
                                retry_vowel[depth[1:0]]<=opcode==132;
                                depth<=depth+1'b1;pc<=pc+1'b1;wait_read<=3;
                            end else reject_rule;
                        end else if(matched) begin
                            match_pos<=advanced;pc<=pc+1'b1;wait_read<=3;
                        end else mismatch;
                    end
                    BACKTRACK: begin
                        if(retry_matched) begin
                            retry_pos[depth-1'b1]<=advanced;
                            match_pos<=advanced;pc<=retry_pc[depth-1'b1];
                            state<=MATCH;wait_read<=3;
                        end else if(depth>1) begin
                            depth<=depth-1'b1;match_pos<=retry_pos[depth-2'd2];wait_read<=3;
                        end else reject_rule;
                    end
                    OUTPUT: begin
                        if(opcode_end) begin
                            cursor<=match_end;match_pos<=match_end;state<=LOOKUP;wait_read<=3;
                        end else if(allophone_ready) begin pc<=pc+1'b1;wait_read<=3;end
                    end
                    FINAL: if(allophone_ready) begin
                        busy<=0;write_pos<=1;last_kind<=0;state<=START;
                    end
                    default: state<=START;
                endcase
            end
        end
    end
endmodule
