`timescale 1ns/1ps
// Compare the minimal encoder with the unchanged shared implementation.
// Removing the CVBS filters may change composite picture levels only;
// S-Video waveforms and raster/cache request identity must stay identical.
module tb_cvbs_minimal #(parameter REFERENCE_FILTERS=1);
 reg clk135=0,clk270=0,reset_n=0,standard=0,compatibility=0;
 reg [7:0] height=192;
 reg [5:0] color=0;
 always #4 clk135=~clk135;
 always #2 clk270=~clk270;
 wire ay,ac,av,by,bc,bv;
 wire [9:0] ax,bx,read_address;
 wire [7:0] arow,brow,ap,bp;
 wire active_a,active_b,pv_a,pv_b;
 coco_cvbs_ntsc_reference #(.CANONICAL_640_INPUT(1),
  .CVBS_CHROMA_FILTER(REFERENCE_FILTERS),.CVBS_LUMA_FILTER(REFERENCE_FILTERS),.CVBS_LUMA_NOTCH(REFERENCE_FILTERS),
  .LUMA_DAC_EVEN_LEVELS(1),.LUMA_SCANLINE_PHASE_ALTERNATION(1),
  .CVBS_SVIDEO_SCANLINE_PHASE_ALTERNATION(1)) original(
  .clk135(clk135),.clk270(clk270),.reset_n(reset_n),.video_50hz(standard),
  .high_resolution(1'b1),.compatibility_mode(compatibility),.active_height(height),
  .framebuffer_data(color),.border_rgb(6'h09),.row_border_valid(1'b0),
  .vertical_border_valid(1'b0),.luma_out(ay),.chroma_out(ac),.cvbs_out(av),
  .source_x(ax),.source_y(arow),.source_valid(active_a),.prefetch_y(ap),.prefetch_valid(pv_a));
 coco_cvbs_ntsc #(.CANONICAL_640_INPUT(1),.CVBS_INCREMENTAL_DOTS(1),
  .CVBS_CHROMA_FILTER(0),.CVBS_LUMA_FILTER(0),.CVBS_LUMA_NOTCH(0),
  .LUMA_DAC_EVEN_LEVELS(1),.LUMA_SCANLINE_PHASE_ALTERNATION(1),
  .CVBS_SVIDEO_SCANLINE_PHASE_ALTERNATION(1)) minimal(
  .clk135(clk135),.clk270(clk270),.reset_n(reset_n),.video_50hz(standard),
  .high_resolution(1'b1),.compatibility_mode(compatibility),.active_height(height),
  .framebuffer_data(color),.border_rgb(6'h09),.row_border_valid(1'b0),
  .vertical_border_valid(1'b0),.luma_out(by),.chroma_out(bc),.cvbs_out(bv),
  .source_x(bx),.source_read_address(read_address),.source_y(brow),
  .source_valid(active_b),.prefetch_y(bp),.prefetch_valid(pv_b));
 integer std,mode,size,tick,checked=0,changed=0;
 reg checking=0;
 always @(negedge clk270)if(checking)begin
  #0.1;
  if({ay,ac}!=={by,bc})$fatal(1,"Minimal CVBS changed S-Video Y/C bits");
  if(av!==bv)begin
   changed=changed+1;
   if(!REFERENCE_FILTERS)$fatal(1,"Lookup encoder changed unfiltered composite bits");
  end
 end
 initial begin
  for(std=0;std<2;std=std+1)
   for(mode=0;mode<2;mode=mode+1)
    for(size=0;size<3;size=size+1)begin
     checking=0;reset_n=0;standard=std;compatibility=mode;
     height=size==0?192:size==1?199:225;
     color=0;repeat(4)@(negedge clk135);reset_n=1;
     repeat(10)@(negedge clk135);
     original.v_line=80;minimal.v_line=80;
     checking=1;
     for(tick=0;tick<17200;tick=tick+1)begin
      @(negedge clk135);color=6'((tick/50)%64);#0.1;
      if({arow,active_a,ap,pv_a,original.sync_tip}!==
         {brow,active_b,bp,pv_b,minimal.sync_tip})
       $fatal(1,"Minimal CVBS changed raster/request identity");
      if(active_a)begin
       checked=checked+1;
       if(ax!==bx)$fatal(1,"Minimal CVBS changed active cache coordinates");
       if(read_address!==(bx==639?10'd639:bx+1'b1))$fatal(1,"Minimal CVBS changed read-ahead coordinate");
      end
     end
    end
  if(checked<100000||(REFERENCE_FILTERS&&changed==0))$fatal(1,"Insufficient waveform coverage");
  $display("Minimal CVBS PASS: %0d coordinates, S-Video bit-identical, NTSC/PAL native/compatibility at 192/199/225 lines; reference filters=%0d",checked,REFERENCE_FILTERS);
  $finish;
 end
 initial begin #3000000;$fatal(1,"timeout");end
endmodule
