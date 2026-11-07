`timescale 1ns/1ps
module tb_cvbs_chroma_rounding;
 coco_cvbs_ntsc dut(.clk135(1'b0),.clk270(1'b0),.reset_n(1'b0));
 // Independent reference: negate at the original eleven-bit precision,
 // then perform the arithmetic shift and six-bit assignment.
 function automatic signed [5:0] reference_chroma(
  input signed [10:0] x,y,sum,difference,input [2:0] phase);
  reg signed [10:0] mix;
  begin
   case(phase)
    0:mix=y;1:mix=sum;2:mix=x;3:mix=difference;
    4:mix=-y;5:mix=-sum;6:mix=-x;7:mix=-difference;
   endcase
   reference_chroma=mix>>>6;
  end
 endfunction
 integer value,phase,flip,count=0;
 reg signed [10:0] x,y,sum,difference;
 reg signed [5:0] expected,actual;
 initial begin
  for(value=-1024;value<1024;value=value+1)begin
   x=value;y=value+151;sum=value+593;difference=value-317;
   for(phase=0;phase<8;phase=phase+1)begin
    expected=reference_chroma(x,y,sum,difference,3'(phase));
    actual=dut.rgb_chroma(x,y,sum,difference,3'(phase));
    if(actual!==expected)$fatal(1,"CVBS chroma mismatch value=%0d phase=%0d got=%0d expected=%0d",value,phase,actual,expected);
    count=count+1;
    for(flip=0;flip<2;flip=flip+1)begin
     expected=reference_chroma(x,x,x,x,3'(phase));
     if(flip)expected=~expected+6'(!( |x[5:0]));
     actual=dut.cvbs_phase_chroma(x,1'(phase>>2),1'(flip));
     if(actual!==expected)$fatal(1,"CVBS field rounding mismatch value=%0d phase=%0d flip=%0d got=%0d expected=%0d",value,phase,flip,actual,expected);
     count=count+1;
    end
   end
  end
  $display("CVBS chroma rounding PASS: %0d exhaustive signed axis/phase cases",count);
  $finish;
 end
endmodule
