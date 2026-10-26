`timescale 1ns/1ps
module reset_hold_case #(parameter integer CYCLES=256)(output reg done=0);
    reg clk=0,reset_n=0,system_ready=0,e_fall=0;
    always #5 clk=~clk;
    wire cpu_release;
    coco_cpu_reset_hold #(.HOLD_CYCLES(CYCLES)) dut(
        .clk(clk),.reset_n(reset_n),.system_ready(system_ready),
        .e_fall(e_fall),.cpu_release(cpu_release));

    // Original startup logic is the reference, including saturation and
    // the extra pending cycle before release on a falling E edge.
    integer reference_count=0;
    reg reference_pending=0,reference_release=0;
    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)begin
            reference_count<=0;reference_pending<=0;reference_release<=0;
        end else if(!system_ready)begin
            reference_count<=0;reference_pending<=0;reference_release<=0;
        end else if(!reference_release)begin
            if(reference_count<CYCLES)reference_count<=reference_count+1;
            else reference_pending<=1;
            if(reference_pending && e_fall)reference_release<=1;
        end
    end
    always @(negedge clk)if(!done)begin
        if(cpu_release!==reference_release || dut.count!==reference_count ||
           dut.release_pending!==reference_pending)
            $fatal(1,"reset hold differs at CYCLES=%0d count=%0d",CYCLES,reference_count);
    end
    integer tick=0;
    always @(negedge clk)begin
        tick=tick+1;
        e_fall=(tick%13==0);
    end
    initial begin
        #2;reset_n=1;
        repeat(3)@(negedge clk);
        #1;system_ready=1;
        // Exercise interrupted startup and asynchronous board reset.
        repeat(270)@(negedge clk);
        #1;system_ready=0;
        repeat(3)@(negedge clk);
        #1;system_ready=1;
        repeat(258)@(negedge clk);
        #2;reset_n=0;
        #2;reset_n=1;
        wait(cpu_release);
        repeat(16)@(negedge clk);
        // Losing readiness after release must assert reset again.
        #1;system_ready=0;
        repeat(3)@(negedge clk);
        #1;
        if(cpu_release!==0 || dut.count!==0)$fatal(1,"reset did not reassert");
        done=1;
    end
endmodule

module tb_cpu_reset_hold;
    wire [7:0] done;
    reset_hold_case #(.CYCLES(0)) c0(done[0]);
    reset_hold_case #(.CYCLES(1)) c1(done[1]);
    reset_hold_case #(.CYCLES(255)) c255(done[2]);
    reset_hold_case #(.CYCLES(256)) c256(done[3]);
    reset_hold_case #(.CYCLES(257)) c257(done[4]);
    reset_hold_case #(.CYCLES(65536)) c65536(done[5]);
    reset_hold_case #(.CYCLES(65537)) c65537(done[6]);
    reset_hold_case #(.CYCLES(10800000)) production(done[7]);
    initial begin
        wait(&done);
        $display("PASS: cycle-exact reset hold, byte carries, interruptions and E-edge release");
        $finish;
    end
    initial begin #110000000;$fatal(1,"timeout");end
endmodule
