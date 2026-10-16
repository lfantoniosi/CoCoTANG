`timescale 1ns/1ps
module tb_coco_ssc_tts;
    reg clk=0,reset_n=0,abort=0,byte_valid=0,allophone_ready=0;
    always #5 clk=~clk;
    reg [7:0] byte_data=0;
    wire host_ready,busy,allophone_valid,allophone_last;
    wire [5:0] allophone;
    coco_ssc_tts dut(.*);
    reg [7:0] input_data[0:65535],expected_data[0:65535];
    string input_path,expected_path;
    integer count,in_bytes,out_bytes,in_pos=0,out_pos=0,phrase,length,expected_length;
    integer i,emitted,cycles;
    reg [15:0] random_bits=16'hd00d;
    task send_byte(input [7:0] value);
        begin
            while(!host_ready) @(negedge clk);
            byte_valid=1;byte_data=value;
            @(negedge clk);byte_valid=0;
            @(negedge clk);
        end
    endtask
    initial begin
        if(!$value$plusargs("INPUT=%s",input_path) || !$value$plusargs("EXPECTED=%s",expected_path) ||
           !$value$plusargs("PHRASES=%d",count) || !$value$plusargs("IN_BYTES=%d",in_bytes) ||
           !$value$plusargs("OUT_BYTES=%d",out_bytes)) $fatal(1,"missing vectors");
        $readmemh(input_path,input_data,0,in_bytes-1);
        $readmemh(expected_path,expected_data,0,out_bytes-1);
        repeat(4) @(negedge clk);reset_n=1;
        for(phrase=0;phrase<count;phrase=phrase+1) begin
            length={input_data[in_pos],input_data[in_pos+1]};in_pos=in_pos+2;
            expected_length={expected_data[out_pos],expected_data[out_pos+1]};out_pos=out_pos+2;
            for(i=0;i<length;i=i+1) send_byte(input_data[in_pos+i]);
            in_pos=in_pos+length;
            send_byte(13);
            emitted=0;cycles=0;
            while(busy && cycles<500000) begin
                random_bits={random_bits[14:0],random_bits[15]^random_bits[13]^random_bits[12]^random_bits[10]};
                allophone_ready=random_bits[0];
                // Sample the stable transaction before the next positive edge.
                #1;
                if(allophone_valid && allophone_ready) begin
                    if(emitted>=expected_length || allophone!==expected_data[out_pos+emitted][5:0])
                        $fatal(1,"phrase %d allophone %d got %d expected %d state=%d cursor=%d",
                            phrase,emitted,allophone,expected_data[out_pos+emitted],dut.state,dut.cursor);
                    if(allophone_last!==(emitted==expected_length-1)) $fatal(1,"last flag wrong");
                    emitted=emitted+1;
                end
                @(negedge clk);cycles=cycles+1;
            end
            if(busy || emitted!=expected_length)
                $fatal(1,"phrase %d timeout/length: %d of %d pc=%d cursor=%d",phrase,emitted,expected_length,dut.pc,dut.cursor);
            allophone_ready=0;out_pos=out_pos+expected_length;
        end
        // Aborting a pending phrase must release BUSY and discard the text.
        send_byte("H");send_byte("I");send_byte(13);
        repeat(20) @(negedge clk);abort=1;
        @(negedge clk);abort=0;
        if(busy || !host_ready || allophone_valid) $fatal(1,"abort did not clear translator");
        $display("PASS: SSC English translator matches regex reference for %0d phrases, with backpressure and abort",count);
        $finish;
    end
endmodule
