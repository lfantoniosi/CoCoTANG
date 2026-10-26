`timescale 1ns/1ps
module tb_cvbs_incremental_dots;
 reg clk135=0,clk270=0,reset_n=0,compatibility=0,standard=0;
 always #4 clk135=~clk135;
 always #2 clk270=~clk270;
 wire [9:0] ax,bx,read_address;
 wire [7:0] ay,by,ap,bp;
 wire av,bv,apv,bpv;
 wire al,ac,ao,bl,bc,bo;
 wire [5:0] ad=av?(ax[5:0]^6'h2d):6'd0;
 wire [5:0] bd=bv?(bx[5:0]^6'h2d):6'd0;
 coco_cvbs_ntsc #(.CVBS_FIELD_PHASE_ALIGN(1),.CANONICAL_640_INPUT(1),
  .CVBS_CHROMA_FILTER(1),.CVBS_LUMA_FILTER(1),.CVBS_LUMA_NOTCH(1)) original(
  .clk135(clk135),.clk270(clk270),.reset_n(reset_n),.video_50hz(standard),
  .high_resolution(1'b1),.compatibility_mode(compatibility),.active_height(8'd192),
  .framebuffer_data(ad),.border_rgb(6'd0),.row_border_valid(1'b0),.vertical_border_valid(1'b0),
  .source_x(ax),.source_y(ay),.source_valid(av),.prefetch_y(ap),.prefetch_valid(apv),
  .luma_out(al),.chroma_out(ac),.cvbs_out(ao));
 coco_cvbs_ntsc #(.CVBS_FIELD_PHASE_ALIGN(1),.CVBS_INCREMENTAL_DOTS(1),.CVBS_FAST_PREFETCH(1),
  .CANONICAL_640_INPUT(1),.CVBS_CHROMA_FILTER(1),.CVBS_LUMA_FILTER(1),.CVBS_LUMA_NOTCH(1)) counter(
  .clk135(clk135),.clk270(clk270),.reset_n(reset_n),.video_50hz(standard),
  .high_resolution(1'b1),.compatibility_mode(compatibility),.active_height(8'd192),
  .framebuffer_data(bd),.border_rgb(6'd0),.row_border_valid(1'b0),.vertical_border_valid(1'b0),
  .source_x(bx),.source_read_address(read_address),.source_y(by),.source_valid(bv),.prefetch_y(bp),.prefetch_valid(bpv),
  .luma_out(bl),.chroma_out(bc),.cvbs_out(bo));
 integer std,mode,tick,checked;
 initial begin
  checked=0;
  for(std=0;std<2;std=std+1)
   for(mode=0;mode<3;mode=mode+1)begin
    reset_n=0;standard=std;compatibility=mode==1;
    repeat(4)@(negedge clk135);reset_n=1;
    repeat(10)@(negedge clk135);
    // Skip to picture rows after the standard transition has settled.
    original.v_line=70;counter.v_line=70;
    for(tick=0;tick<18000;tick=tick+1)begin
     @(negedge clk135);
     if(mode==2 && (tick==2500 || tick==4500 || tick==6000))compatibility=~compatibility;
     #1;
     if({ay,av,ap,apv,original.sync_tip}!=={by,bv,bp,bpv,counter.sync_tip})
      $fatal(1,"Counter changed raster identity: std=%0d mode=%0d tick=%0d",std,mode,tick);
     if(av)begin
      checked=checked+1;
      if(read_address!==(bx==639?10'd639:bx+1'b1))$fatal(1,"Wrong precomputed read-ahead address");
      if(ax!==bx)$fatal(1,"Coordinate differs: std=%0d mode=%0d tick=%0d x=%0d/%0d",std,mode,tick,ax,bx);
     end
     if({al,ac,ao}!=={bl,bc,bo})$fatal(1,"Counter changed analog waveform");
    end
   end
  if(checked<20000)$fatal(1,"Too few active coordinates checked");
  $display("CVBS incremental dots PASS: %0d visible coordinates, both standards, both modes, mid-line changes and waveform equivalence",checked);
  $finish;
 end
 initial begin #2000000;$fatal(1,"timeout");end
endmodule
