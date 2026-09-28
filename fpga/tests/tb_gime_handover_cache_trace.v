`timescale 1ns/1ps
// Replay the address/LPR schedule in results/line26.txt against the scanline
// renderer, cold and after two 50 Hz cache fields. This drives logical row
// requests, not the physical HDMI/native raster timing; it verifies the
// cache's published row starts and first physical SDRAM reads.
module tb_gime_handover_cache_trace;
 parameter integer PAL_MACHINE=0;
 reg clk=0,hdmi_clk=0,cvbs_clk=0,reset_n=0;
 always #5 clk=~clk;
 always #18.5 hdmi_clk=~hdmi_clk;
 always #3.7 cvbs_clk=~cvbs_clk;
 reg [95:0] palettes=0;
 reg [31:0] memory_data=32'h1b1b1b1b;
 reg memory_valid=0;
 wire memory_request;
 wire [22:0] memory_addr;
 reg [1:0] responder_state=0;
 reg [7:0] hdmi_display_y=0,hdmi_prefetch_y=0;
 reg hdmi_display_valid=0,hdmi_prefetch_valid=0;
 reg hdmi_picture_active=0,hdmi_frame_start=0,hdmi_active_50hz=0;
 // results/line26.txt: VOFF-Y=$0C040, VSC=$F, HOFF=$0B.
 reg [18:0] screen_base=19'h0c040;
 reg [3:0] vertical_scroll=15;
 reg [2:0] lpr=7;
 reg [20:0] cold_addr[0:224],warm_addr[0:224];
 reg [20:0] cold_read_addr[0:31],warm_read_addr[0:31];
 reg [22:0] cold_first_read[0:224],warm_first_read[0:224];
 reg [224:0] first_read_seen=0;
 integer capture_kind=0;
 integer errors=0,row,timeout,j;
 wire [23:0] hdmi_pixel;
 wire [5:0] cvbs_pixel;

 gime_scanline_buffer #(.PAL_MACHINE(PAL_MACHINE)) dut(
  .clk(clk),.reset_n(reset_n),.bit_plane(1'b1),.hres(4'd7),.cres(2'd2),
  .lines_per_row_code(lpr),.vertical_scroll(vertical_scroll),
  .screen_base(screen_base),.video_bank(2'd0),
  .horizontal_offset(8'h0b),.palettes(palettes),.border_rgb(6'd0),
  .compatibility_mode(1'b0),.compatibility_an_g(1'b1),
  .compatibility_gm(3'd0),.compatibility_css(1'b0),
  .compatibility_sam_mode(3'd0),
  .compatibility_raster_write(1'b0),.compatibility_raster_y(8'd0),
  .compatibility_raster_byte(5'd0),.compatibility_raster_css(1'b0),
  .compatibility_border_write(1'b0),.compatibility_border_right(1'b0),
  .compatibility_border_y(9'd0),.compatibility_border_rgb(6'd0),
  .artifact_mode(2'd0),.blink(1'b0),
  .cpu_write_strobe(1'b0),.cpu_write_addr(21'd0),
  .hdmi_read_clk(hdmi_clk),.hdmi_read_x(10'd0),
  .hdmi_display_y(hdmi_display_y),.hdmi_display_valid(hdmi_display_valid),
  .hdmi_prefetch_y(hdmi_prefetch_y),.hdmi_prefetch_valid(hdmi_prefetch_valid),
  .hdmi_picture_active(hdmi_picture_active),.hdmi_pixel_data(hdmi_pixel),
  .hdmi_frame_start(hdmi_frame_start),.hdmi_active_50hz(hdmi_active_50hz),
  .hdmi_border_raster_y(9'd0),
  .cvbs_read_clk(cvbs_clk),.cvbs_read_x(10'd0),
  .cvbs_display_y(8'd0),.cvbs_display_valid(1'b0),
  .cvbs_prefetch_y(8'd0),.cvbs_prefetch_valid(1'b0),
  .cvbs_pixel_data(cvbs_pixel),
  .memory_request(memory_request),.memory_addr(memory_addr),
  .memory_data(memory_data),.memory_valid(memory_valid));

 always @(posedge clk) begin
  memory_valid<=0;
  if(memory_request && !first_read_seen[dut.fill_y])begin
   first_read_seen[dut.fill_y]<=1;
   if(hdmi_active_50hz==0)begin
    if(capture_kind==0)cold_first_read[dut.fill_y]<=memory_addr;
    else if(capture_kind==2)warm_first_read[dut.fill_y]<=memory_addr;
   end
  end
  if(memory_request&&responder_state==0)responder_state<=1;
  else if(responder_state==1)begin memory_valid<=1;responder_state<=2;end
  else if(responder_state==2&&!memory_request)responder_state<=0;
 end

 function [20:0] expected_line26;
  input integer y;
  integer advances;
  begin
   // XRoar line 26 is source row 0. FF98 87>80 at line 27,
   // 80>87 at line 122, and 87>80 again at line 246.
   advances=y<=0?0:y<=95?y:y<=219?95:y-124;
   expected_line26=21'h0c040+advances*21'h000a0;
 end
 endfunction
 function [22:0] expected_first_read;
  input integer y;
  begin
   // HOFF=$0B contributes 22 bytes. SDRAM reads are 32-bit aligned.
   expected_first_read=(expected_line26(y)+21'h00016)&23'h7ffffc;
  end
 endfunction

 function [20:0] cached_start;
  input [7:0] y;
  begin
   if(dut.h_valid0&&dut.h_tag0==y)cached_start=dut.h_start0;
   else if(dut.h_valid1&&dut.h_tag1==y)cached_start=dut.h_start1;
   else cached_start=21'h1fffff;
  end
 endfunction

 function [20:0] selected_read_start;
  begin
   if(!dut.h_read_valid)selected_read_start=21'h1fffff;
   else selected_read_start=dut.h_read_bank?dut.h_start1:dut.h_start0;
  end
 endfunction

 task wait_row;
  input [7:0] y;
  begin
   timeout=0;
   while(cached_start(y)==21'h1fffff&&timeout<12000)begin
    @(negedge clk);timeout=timeout+1;
   end
   if(timeout==12000)begin
    $display("TIMEOUT standard=%0d row=%0d dma_y=%0d dma_addr=%05h state=%0d tags=%0d/%0d",
     hdmi_active_50hz,y,dut.dma_next_y,dut.dma_next_address,dut.state,
     dut.h_tag0,dut.h_tag1);
    errors=errors+1;
   end
  end
 endtask

 task run_frame;
  input bit fifty;
  input integer trace_kind; // 0: cold reference, 1: 50 Hz, 2: returned 60 Hz
  begin
   @(negedge clk);
   hdmi_display_valid=0;hdmi_prefetch_valid=0;hdmi_picture_active=0;
   hdmi_active_50hz=fifty;
   hdmi_frame_start=1;
   lpr=7;
   // Leave a genuinely different 50 Hz VOFF/VSC behind.  Returning to
   // $4040/0 must not accidentally reuse a tag or DMA origin from it.
   vertical_scroll=trace_kind==1?4'd5:4'd15;
   screen_base=trace_kind==1?19'h18080:19'h0c040;
   capture_kind=trace_kind;
   first_read_seen=0;
   repeat(6)@(negedge clk);
   hdmi_frame_start=0;
   // A real field has a long upper border.  Give the synchronized standard
   // and setup capture ample time before requesting source row zero.
   repeat(200)@(negedge clk);
   hdmi_prefetch_y=0;hdmi_prefetch_valid=1;
   wait_row(0);
   for(row=0;row<225;row=row+1)begin
    if(trace_kind==0)cold_addr[row]=cached_start(row[7:0]);
    else if(trace_kind==2)warm_addr[row]=cached_start(row[7:0]);
    if(trace_kind!=1&&(row<=2||row==94||row==95||row==96||
       row==218||row==219||row==220||row==224))
     $display("TRACE %s XRoar-line=%0d row=%0d expected=%05h cache=%05h dma_next=%05h dma_y=%0d",
      trace_kind==0?"cold60":"warm60",row+26,row,
      expected_line26(row),cached_start(row[7:0]),
      dut.dma_next_address,dut.dma_next_y);
    @(negedge clk);
    hdmi_picture_active=1;
    hdmi_display_y=row[7:0];hdmi_display_valid=1;
    hdmi_prefetch_valid=0;
    if(row<32)begin
     // This is the actual bank selected by the HDMI-domain read port, not
     // just the cache tag that the producer published.
     repeat(3)@(posedge hdmi_clk);
     #1;
     if(trace_kind==0)cold_read_addr[row]=selected_read_start();
     else if(trace_kind==2)warm_read_addr[row]=selected_read_start();
     if(trace_kind!=1&&row==16)
      $display("HDMI READ %s source_row=16 bank=%0d valid=%0d SDRAM=%05h",
       trace_kind==0?"cold60":"warm60",dut.h_read_bank,
       dut.h_read_valid,selected_read_start());
    end
    // Exact line26.txt FF98 schedule: writes at dot 71 of XRoar lines
    // 27, 122, 246; the new value governs the next DMA advance.
    if(row==0)lpr=0;
    if(row==95)lpr=7;
    if(row==219)lpr=0;
    repeat(20)@(negedge clk);
    if(row<224)begin
     hdmi_prefetch_y=row[7:0]+1'b1;
     hdmi_prefetch_valid=1;
     wait_row(row[7:0]+1'b1);
    end
   end
   @(negedge clk);
   hdmi_display_valid=0;hdmi_prefetch_valid=0;hdmi_picture_active=0;
   repeat(300)@(negedge clk);
  end
 endtask

 initial begin
  for(j=0;j<16;j=j+1)palettes[j*6+:6]=j;
  repeat(6)@(negedge clk);reset_n=1;
  run_frame(0,0);
  @(negedge clk);reset_n=0;
  repeat(8)@(negedge clk);reset_n=1;
  run_frame(1,1);
  run_frame(1,1);
  $display("HANDOVER 50->60: before frame base=%05h dma=%05h dma_y=%0d tags=%0d/%0d",
   dut.frame_screen_base,dut.dma_next_address,dut.dma_next_y,
   dut.h_tag0,dut.h_tag1);
  run_frame(0,2);
  for(j=0;j<225;j=j+1)begin
   if(j<=2||j==94||j==95||j==96||j==219||j==220||j==224)
    $display("SDRAM line=%0d XRoar-DMA=%05h expected-read=%06h cold-read=%06h warm-read=%06h",
     j+26,expected_line26(j),expected_first_read(j),
     cold_first_read[j],warm_first_read[j]);
   if(cold_addr[j]!==warm_addr[j])begin
    $display("MISMATCH row=%0d cold60=%05h warm60=%05h",j,
     cold_addr[j],warm_addr[j]);errors=errors+1;
   end
   if(cold_addr[j]!==expected_line26(j)||
      warm_addr[j]!==expected_line26(j))begin
    $display("XROAR ADDRESS MISMATCH line=%0d row=%0d expected=%05h cold=%05h warm=%05h",
     j+26,j,expected_line26(j),cold_addr[j],warm_addr[j]);errors=errors+1;
   end
   if(cold_first_read[j]!==warm_first_read[j])begin
    $display("SDRAM READ MISMATCH line=%0d row=%0d cold=%06h warm=%06h",
     j+26,j,cold_first_read[j],warm_first_read[j]);errors=errors+1;
   end
   if(cold_first_read[j]!==expected_first_read(j)||
      warm_first_read[j]!==expected_first_read(j))begin
    $display("SDRAM ADDRESS MISMATCH line=%0d row=%0d expected=%06h cold=%06h warm=%06h",
     j+26,j,expected_first_read(j),cold_first_read[j],warm_first_read[j]);
    errors=errors+1;
   end
  end
  for(j=0;j<32;j=j+1)begin
   if(cold_read_addr[j]!==warm_read_addr[j])begin
    $display("HDMI READ MISMATCH source_row=%0d cold=%05h warm=%05h",
     j,cold_read_addr[j],warm_read_addr[j]);errors=errors+1;
   end
   if(cold_read_addr[j]!==cold_addr[j]||warm_read_addr[j]!==warm_addr[j])begin
    $display("HDMI READ TAG MISMATCH source_row=%0d cold-read=%05h cold-tag=%05h warm-read=%05h warm-tag=%05h",
     j,cold_read_addr[j],cold_addr[j],warm_read_addr[j],warm_addr[j]);
    errors=errors+1;
   end
  end
  if(cold_read_addr[0]!==21'h00c040||
     warm_read_addr[0]!==21'h00c040)begin
   $display("HDMI source row 0 did not resolve to XRoar VOFF-Y $0C040");
   errors=errors+1;
  end
  if(errors==0)$display("tb_gime_handover_cache_trace PASS");
  else $fatal(1,"tb_gime_handover_cache_trace FAIL errors=%0d",errors);
  $finish;
 end
endmodule
