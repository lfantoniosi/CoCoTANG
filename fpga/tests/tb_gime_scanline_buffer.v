`timescale 1ns/1ps
module tb_gime_scanline_buffer;
 reg clk=0,hdmi_clk=0,cvbs_clk=0,reset_n=0;
 reg [95:0] palettes=0;reg [31:0] memory_data=32'h1b1b1b1b;
 reg memory_valid=0;wire memory_request;wire [22:0] memory_addr;
 wire [23:0] hdmi_pixel;wire [5:0] cvbs_pixel;
 integer transactions=0,errors=0,i,timeout;
 integer responder_delay=0;reg slow_memory=0;
 reg [1:0] responder_state=0;reg compatibility_mode=0,compatibility_an_g=1;
 reg [2:0] compatibility_gm=0,compatibility_sam_mode=0;
 reg [3:0] hres=7;reg [1:0] cres=1;
 reg bit_plane=1;reg [2:0] lpr=0;reg [3:0] vertical_scroll=0;
 reg [18:0] screen_base=0;
 reg [7:0] horizontal_offset=0;reg cpu_write_strobe=0;reg [18:0] cpu_write_addr=0;
 reg hdmi_prefetch_valid=1,cvbs_prefetch_valid=0;
 reg [7:0] hdmi_prefetch_y=0,cvbs_prefetch_y=0;
 reg hdmi_display_valid=0,hdmi_picture_active=0;reg [7:0] hdmi_display_y=0;

 gime_scanline_buffer dut(
  .clk(clk),.reset_n(reset_n),.bit_plane(bit_plane),.hres(hres),.cres(cres),
  .lines_per_row_code(lpr),.vertical_scroll(vertical_scroll),.screen_base(screen_base),
  .horizontal_offset(horizontal_offset),.palettes(palettes),
  .compatibility_mode(compatibility_mode),.compatibility_an_g(compatibility_an_g),
  .compatibility_gm(compatibility_gm),.compatibility_css(1'b0),
  .compatibility_sam_mode(compatibility_sam_mode),
  .artifact_mode(2'd0),.blink(1'b0),
  .cpu_write_strobe(cpu_write_strobe),.cpu_write_addr(cpu_write_addr),
  .hdmi_read_clk(hdmi_clk),.hdmi_read_x(10'd0),.hdmi_display_y(hdmi_display_y),
  .hdmi_display_valid(hdmi_display_valid),.hdmi_prefetch_y(hdmi_prefetch_y),
  .hdmi_picture_active(hdmi_picture_active),
  .hdmi_prefetch_valid(hdmi_prefetch_valid),.hdmi_pixel_data(hdmi_pixel),
  .cvbs_read_clk(cvbs_clk),.cvbs_read_x(10'd0),.cvbs_display_y(8'd0),
  .cvbs_display_valid(1'b0),.cvbs_prefetch_y(cvbs_prefetch_y),
  .cvbs_prefetch_valid(cvbs_prefetch_valid),.cvbs_pixel_data(cvbs_pixel),
  .memory_request(memory_request),.memory_addr(memory_addr),
  .memory_data(memory_data),.memory_valid(memory_valid));

 always #5 clk=~clk;always #18.5 hdmi_clk=~hdmi_clk;always #3.7 cvbs_clk=~cvbs_clk;
 always @(posedge clk) begin
  memory_valid<=0;
  if(memory_request&&responder_state==0)begin responder_state<=1;transactions<=transactions+1;
   // Seventy-five clocks per word is deliberately slower than the nominal
   // sixty-clock 1.79 MHz interleave cadence, covering SDRAM completion/drop
   // overhead while still requiring an 80-column row to meet its deadline.
   responder_delay<=slow_memory?74:0;
   if(memory_addr[1:0]!=0)begin $display("unaligned request %h",memory_addr);errors=errors+1;end
  end else if(responder_state==1&&responder_delay!=0)responder_delay<=responder_delay-1;
  else if(responder_state==1)begin memory_valid<=1;responder_state<=2;end
  else if(responder_state==2&&!memory_request)responder_state<=0;
 end
 function [5:0] mapped;input [5:0] c;begin mapped={c[5],c[2],c[4],c[1],c[3],c[0]};end endfunction
 task wait_hdmi_line;
  begin timeout=0;while(!dut.h_valid0&&!dut.h_valid1&&timeout<200000)begin @(posedge clk);timeout=timeout+1;end
   if(timeout==200000)begin $display("line fill timeout");errors=errors+1;end
  end
 endtask
 task invalidate_all;
  begin cpu_write_addr=0;cpu_write_strobe=1;@(posedge clk);#1;cpu_write_strobe=0;
   timeout=0;while((dut.h_valid0||dut.h_valid1)&&timeout<20)begin @(posedge clk);timeout=timeout+1;end
  end
 endtask

 initial begin
  for(i=0;i<16;i=i+1)palettes[i*6+:6]=i;
  repeat(4)@(posedge clk);reset_n=1;
  wait_hdmi_line();
  if(transactions!=40)begin $display("160-byte line used %0d transactions",transactions);errors=errors+1;end
  for(i=0;i<640;i=i+1)
   if(dut.c_valid0 ? dut.cvbs_line0[i]!==mapped(i[1:0]) :
                     dut.cvbs_line1[i]!==mapped(i[1:0]))begin
    $display("native pixel %0d wrong",i);errors=errors+1;i=640;end
  // Default native GIME output preserves all 640 canonical dots at RGB888.
  if((dut.h_valid0?dut.hdmi_line0[0]:dut.hdmi_line1[0])!==24'h000000||
     (dut.h_valid0?dut.hdmi_line0[1]:dut.hdmi_line1[1])!==24'h000055||
     (dut.h_valid0?dut.hdmi_line0[2]:dut.hdmi_line1[2])!==24'h005500||
     (dut.h_valid0?dut.hdmi_line0[3]:dut.hdmi_line1[3])!==24'h005555)begin
   $display("HDMI native 640-dot RGB888 path is wrong");errors=errors+1;end
  // Aspect-correct builds use the same cache with full-precision coverage.
  // A 25% black contribution over RGB222 grey must become $808080 rather
  // than rounding back to grey as the old RGB222 filter did.
  if(dut.blend_quarters(24'haaaaaa,24'h000000,2'd1)!==24'h808080)begin
   $display("HDMI RGB888 filter lost fractional coverage");errors=errors+1;end

  invalidate_all();
  if(!(dut.h_dirty0||dut.h_dirty1))begin
   $display("CPU write did not mark visible line dirty");errors=errors+1;end
  if(!(dut.h_valid0||dut.h_valid1))begin
   $display("CPU write blanked a visible line");errors=errors+1;end

  // FF9F.HVEN uses a 1024-byte stride in HRES[3] modes and 256 otherwise.
  horizontal_offset=8'h80;hres=4'd8;@(posedge clk);#1;
  if(dut.live_stride!=11'd1024)begin $display("extended HVEN stride %0d",dut.live_stride);errors=errors+1;end
  hres=4'd7;@(posedge clk);#1;
  if(dut.live_stride!=11'd256)begin $display("standard HVEN stride %0d",dut.live_stride);errors=errors+1;end

  // Official SG4 layout: $92 has yellow in the top-left quadrant. A 256-dot
  // VDG line maps to the canonical 640-dot aperture at exactly 5/2.
  hdmi_prefetch_valid=0;repeat(5)@(posedge clk);
  horizontal_offset=0;compatibility_mode=1;compatibility_an_g=0;bit_plane=0;
  // $98 has only SG4's top-left quadrant enabled.  This distinguishes the
  // real 3/2,1/0 ordering from the formerly inverted vertical ordering.
  compatibility_gm=0;memory_data=32'h98989898;transactions=0;
  repeat(5)@(posedge clk);hdmi_prefetch_valid=1;wait_hdmi_line();
  for(i=0;i<10;i=i+1)
   if(dut.c_valid0 ? dut.cvbs_line0[i]!==mapped(6'd54):
                     dut.cvbs_line1[i]!==mapped(6'd54))begin
    $display("SG4 foreground pixel %0d wrong got %02h expected %02h",i,
     dut.c_valid0?dut.cvbs_line0[i]:dut.cvbs_line1[i],mapped(6'd54));
    errors=errors+1;i=10;end
  if(dut.c_valid0 ? dut.cvbs_line0[10]!==mapped(6'd2):
                    dut.cvbs_line1[10]!==mapped(6'd2))begin
   $display("SG4 top-right quadrant should be background");errors=errors+1;end
  // In the 640-dot configuration compatibility video still occupies the
  // centered 512-dot aperture, but it is point-replicated: each 256-wide VDG
  // pixel appears exactly twice with no 5:4 RGB blend at colour boundaries.
  for(i=0;i<8;i=i+1)
   if((dut.h_valid0&&dut.h_tag0==0 ? dut.hdmi_line0[i] : dut.hdmi_line1[i])
       !==dut.expand_rgb222(mapped(6'd54)))begin
    $display("SG4 HDMI 2x foreground pixel %0d was filtered",i);
    errors=errors+1;i=8;end
  if((dut.h_valid0&&dut.h_tag0==0 ? dut.hdmi_line0[8] : dut.hdmi_line1[8])
      !==dut.expand_rgb222(mapped(6'd2)))begin
   $display("SG4 HDMI exact 2x boundary is wrong");errors=errors+1;end

  // Mega-Bug selects 128x96 SAM addressing.  Compatibility DMA geometry is
  // controlled by SAM V0:V2, independently of the PIA GM decode.  A stale or
  // intentionally different 192-line GM value must therefore still repeat
  // every source row twice, while GM continues to select 32-byte colour
  // packing.
  compatibility_an_g=1;compatibility_gm=6;compatibility_sam_mode=5;#1;
  if(dut.compatibility_lines_per_row(compatibility_sam_mode)!=2||
     dut.compatibility_row_bytes!=32)begin
   $display("128x96 SAM geometry decoded as lpr=%0d stride=%0d",
    dut.compatibility_lines_per_row(compatibility_sam_mode),
    dut.compatibility_row_bytes);errors=errors+1;end

  // Both consumers requesting the same line share the one render/fetch pass.
  hdmi_prefetch_valid=0;cvbs_prefetch_valid=0;repeat(5)@(posedge clk);
  compatibility_mode=0;bit_plane=1;hres=7;cres=1;memory_data=32'h1b1b1b1b;
  transactions=0;repeat(5)@(posedge clk);
  hdmi_prefetch_valid=1;cvbs_prefetch_valid=1;
  timeout=0;while((!dut.h_valid0&&!dut.h_valid1||!dut.c_valid0&&!dut.c_valid1)&&timeout<200000)
   begin @(posedge clk);timeout=timeout+1;end
  if(timeout==200000)begin $display("shared fill timeout");errors=errors+1;end
  if(transactions!=40)begin $display("shared line fetched twice: %0d",transactions);errors=errors+1;end

  // The two output timing domains do not cross clk108 on precisely the same
  // edge.  Requests for the same source row must still coalesce when CVBS is
  // a few renderer clocks behind HDMI, rather than consuming another forty
  // interleaved SDRAM slots.
  hdmi_prefetch_valid=0;cvbs_prefetch_valid=0;repeat(5)@(posedge clk);
  hdmi_prefetch_y=8'd1;cvbs_prefetch_y=8'd1;transactions=0;
  hdmi_prefetch_valid=1;repeat(3)@(posedge clk);cvbs_prefetch_valid=1;
  timeout=0;
  while((!((dut.h_valid0&&dut.h_tag0==1)||(dut.h_valid1&&dut.h_tag1==1))||
          !((dut.c_valid0&&dut.c_tag0==1)||(dut.c_valid1&&dut.c_tag1==1)))&&timeout<200000)
   begin @(posedge clk);timeout=timeout+1;end
  if(timeout==200000)begin $display("staggered shared fill timeout");errors=errors+1;end
  if(transactions!=40)begin
   $display("staggered shared line fetched twice: %0d",transactions);errors=errors+1;end

  // Native 80-column attributed text must finish comfortably inside one
  // logical scanline.  Each character/attribute/font row is cached for its
  // eight pixels instead of being reread for every output dot.
  hdmi_prefetch_valid=0;cvbs_prefetch_valid=0;repeat(5)@(posedge clk);
  compatibility_mode=0;bit_plane=0;hres=7;cres=1;lpr=3;
  hdmi_prefetch_y=8'd0;cvbs_prefetch_y=8'd0;
  memory_data=32'h38413841;transactions=0;slow_memory=1;repeat(5)@(posedge clk);
  hdmi_prefetch_valid=1;cvbs_prefetch_valid=1;timeout=0;
  while((!dut.h_valid0&&!dut.h_valid1||!dut.c_valid0&&!dut.c_valid1)&&timeout<6800)
   begin @(posedge clk);timeout=timeout+1;end
  if(timeout==6800)begin $display("80-column line missed scanline deadline");errors=errors+1;end
  if(transactions!=40)begin $display("80-column line used %0d transactions",transactions);errors=errors+1;end
  else $display("80-column shared line completed in %0d clocks",timeout);
  // Native GIME rows keep their normal MSB-first order in the unfiltered
  // canonical/CVBS copy. Row zero of 'A' is $08, so pixel 3 is background
  // and pixel 4 is foreground.
  if((dut.c_valid0&&dut.c_tag0==0 ? dut.cvbs_line0[3] : dut.cvbs_line1[3])!==mapped(6'd0))begin
   $display("native font bit order wrong: A pixel 3 is not background");errors=errors+1;end
  if((dut.c_valid0&&dut.c_tag0==0 ? dut.cvbs_line0[4] : dut.cvbs_line1[4])!==mapped(6'd15))begin
   $display("native font bit order wrong: A pixel 4 is not foreground");errors=errors+1;end
  slow_memory=0;

  // A timed HRES change belongs to the following raster.  The row already
  // being fetched has captured its old mode and must be allowed to finish;
  // aborting it produces a black first copy of a doubled HDMI scanline.
  hdmi_prefetch_valid=0;cvbs_prefetch_valid=0;hdmi_display_valid=0;
  hres=7;cres=1;bit_plane=1;slow_memory=1;repeat(8)@(posedge clk);
  hdmi_prefetch_y=8'd17;hdmi_prefetch_valid=1;
  timeout=0;while(dut.state!=6&&timeout<200000)begin
   @(posedge clk);timeout=timeout+1;end
  if(timeout==200000)begin
   $display("mode-change fill did not reach WAIT_WORD");errors=errors+1;
  end else begin
   hres=6;
   repeat(8)@(posedge clk);#1;
   if(dut.state==0||!dut.memory_request)begin
    $display("raster mode change aborted active row fill");errors=errors+1;end
   timeout=0;
   while(!((dut.h_valid0&&dut.h_tag0==17)||(dut.h_valid1&&dut.h_tag1==17))&&
         timeout<200000)begin @(posedge clk);timeout=timeout+1;end
   if(timeout==200000)begin
    $display("row did not complete after raster mode change");errors=errors+1;end
  end
  hdmi_prefetch_valid=0;slow_memory=0;hres=7;repeat(8)@(posedge clk);

  // HBORD handlers update the mode for the row after the one already
  // prefetched.  Preserve both the displayed row and that completed prefetch
  // across the write; invalidating the latter gives the renderer only one
  // physical HDMI line to recover and creates a thin black gap.
  hdmi_display_valid=0;hdmi_prefetch_y=8'd18;hdmi_prefetch_valid=1;
  timeout=0;
  while(!((dut.h_valid0&&dut.h_tag0==18)||(dut.h_valid1&&dut.h_tag1==18))&&
        timeout<200000)begin @(posedge clk);timeout=timeout+1;end
  hdmi_prefetch_y=8'd19;
  timeout=0;
  while(!((dut.h_valid0&&dut.h_tag0==19)||(dut.h_valid1&&dut.h_tag1==19))&&
        timeout<200000)begin @(posedge clk);timeout=timeout+1;end
  hdmi_display_y=8'd18;hdmi_display_valid=1;hdmi_picture_active=1;
  repeat(8)@(posedge clk);
  // The mode write occurs in horizontal border, where pixel-valid is low
  // but the logical picture row remains active.
  hdmi_display_valid=0;repeat(8)@(posedge clk);
  hres=6;repeat(8)@(posedge clk);#1;
  if(!((dut.h_valid0&&dut.h_tag0==18)||(dut.h_valid1&&dut.h_tag1==18))||
     !((dut.h_valid0&&dut.h_tag0==19)||(dut.h_valid1&&dut.h_tag1==19)))begin
   $display("raster mode write discarded current/prefetched row");errors=errors+1;
  end
  hdmi_display_valid=0;hdmi_picture_active=0;hdmi_prefetch_valid=0;
  hres=7;repeat(8)@(posedge clk);

  // A phase-separated CVBS request must not displace the HDMI master row.
  // The one render is mirrored into both RAM copies; otherwise two nearby
  // requests continually evict each other and produce alternating black or
  // repeated physical scanlines.
  hdmi_prefetch_valid=0;cvbs_prefetch_valid=0;repeat(5)@(posedge clk);
  hdmi_prefetch_y=8'd2;cvbs_prefetch_y=8'd3;transactions=0;
  repeat(5)@(posedge clk);hdmi_prefetch_valid=1;cvbs_prefetch_valid=1;timeout=0;
  while((!((dut.h_valid0&&dut.h_tag0==2)||(dut.h_valid1&&dut.h_tag1==2))||
          !((dut.c_valid0&&dut.c_tag0==2)||(dut.c_valid1&&dut.c_tag1==2)))&&timeout<6800)
   begin @(posedge clk);timeout=timeout+1;end
  if(timeout==6800)begin $display("master row mirror missed deadline");errors=errors+1;end
  if(transactions!=40)begin
   $display("phase-separated request caused %0d transactions",transactions);errors=errors+1;end
  else $display("master row mirrored in %0d clocks",timeout);

  // Scrolling writes commonly dirty the row which has already been
  // prefetched while the preceding row is being shown twice by HDMI.  Keep
  // that immutable row for this raster pass instead of immediately
  // rewriting a dual-clock line RAM which scanout may begin consuming.
  hdmi_prefetch_valid=0;cvbs_prefetch_valid=0;hdmi_display_valid=0;
  hres=6;repeat(5)@(posedge clk);hres=7;repeat(5)@(posedge clk);
  hdmi_prefetch_y=0;hdmi_prefetch_valid=1;
  timeout=0;while(!((dut.h_valid0&&dut.h_tag0==0)||(dut.h_valid1&&dut.h_tag1==0))&&timeout<200000)
   begin @(posedge clk);timeout=timeout+1;end
  hdmi_prefetch_y=1;
  timeout=0;while(!((dut.h_valid0&&dut.h_tag0==1)||(dut.h_valid1&&dut.h_tag1==1))&&timeout<200000)
   begin @(posedge clk);timeout=timeout+1;end
  begin : dirty_prefetch_defer
   reg row0_bank,row1_bank;
   row0_bank=(dut.h_valid1&&dut.h_tag1==0);
   row1_bank=(dut.h_valid1&&dut.h_tag1==1);
   cpu_write_addr=row1_bank?dut.h_start1:dut.h_start0;
   cpu_write_strobe=1;@(posedge clk);#1;cpu_write_strobe=0;
   hdmi_display_y=0;hdmi_display_valid=1;
   repeat(100)@(posedge clk);
   if(dut.state!=0||dut.h_pending)begin
    $display("dirty prefetched row was rewritten during active raster");errors=errors+1;
   end
   if(row0_bank==row1_bank)begin
    $display("two source rows did not occupy separate banks");errors=errors+1;
   end
  end
  hdmi_display_valid=0;

  // VOFF is transferred into the running video address at vertical blank.
  // A write during the picture must not disturb either cached raster; the
  // upper-border row-zero prefetch is the frame-boundary latch in this core.
  hdmi_prefetch_valid=0;hdmi_display_y=0;hdmi_display_valid=1;
  repeat(5)@(posedge clk);
  begin : raster_offset_change
   reg valid0_before,valid1_before;
   valid0_before=dut.h_valid0;valid1_before=dut.h_valid1;
   screen_base=19'h04000;
   repeat(5)@(posedge clk);#1;
   if(dut.frame_screen_base!=0||dut.h_valid0!=valid0_before||
      dut.h_valid1!=valid1_before)begin
    $display("VOFF changed the active frame before vertical blank");errors=errors+1;
   end
   hdmi_display_valid=0;hdmi_prefetch_y=0;hdmi_prefetch_valid=1;
   repeat(8)@(posedge clk);#1;
   if(dut.frame_screen_base!=19'h04000)begin
    $display("VOFF was not latched in upper border");errors=errors+1;end
   if(dut.last_screen_base!=19'h04000)begin
    $display("latched VOFF did not reach renderer configuration");errors=errors+1;end
  end
  hdmi_prefetch_valid=0;screen_base=0;repeat(5)@(posedge clk);

  // FF9C fine scroll is ignored when native LPR selects one raster per row.
  // HDMI/CVBS border height is outside the logical source-y coordinate and
  // must not be folded into this address calculation either.
  hdmi_prefetch_y=0;vertical_scroll=4'hf;lpr=0;bit_plane=1;
  hres=7;cres=2;horizontal_offset=0;hdmi_prefetch_valid=1;
  timeout=0;
  while(!((dut.h_valid0&&dut.h_tag0==0)||(dut.h_valid1&&dut.h_tag1==0))&&
        timeout<200000)begin @(posedge clk);timeout=timeout+1;end
  if(timeout==200000)begin
   $display("single-line VSC fill timeout");errors=errors+1;
  end else if(dut.h_valid0&&dut.h_tag0==0 ? dut.h_start0!=0 : dut.h_start1!=0)begin
   $display("single-line LPR incorrectly applied VSC=%0d",vertical_scroll);
   errors=errors+1;
  end
  hdmi_prefetch_valid=0;vertical_scroll=0;repeat(5)@(posedge clk);

  // FF9F is sampled per row and must not invalidate a row which is already
  // displayed or prefetched.  The address addition wraps inside the current
  // 256-byte virtual row even when HVEN (bit 7) is clear.
  begin : horizontal_raster_effect
   reg valid0_before,valid1_before;
   valid0_before=dut.h_valid0;valid1_before=dut.h_valid1;
   horizontal_offset=8'h01;repeat(5)@(posedge clk);#1;
   if(dut.h_valid0!=valid0_before||dut.h_valid1!=valid1_before)begin
    $display("FF9F write invalidated an immutable cached row");errors=errors+1;end
   force dut.line_address=19'h12300;
   force dut.fill_compatibility=1'b0;force dut.fill_bit_plane=1'b1;
   force dut.fill_hoff=7'h7f;force dut.source_byte_index=12'd3;#1;
   if(dut.calculated_byte_address!=19'h12301)begin
    $display("FF9F virtual-row wrap address=%h",dut.calculated_byte_address);
    errors=errors+1;end
   force dut.fill_compatibility=1'b1;#1;
   if(dut.calculated_byte_address!=19'h12303)begin
    $display("compatibility mode incorrectly applied FF9F offset");errors=errors+1;end
   release dut.source_byte_index;release dut.fill_hoff;
   release dut.fill_bit_plane;release dut.fill_compatibility;release dut.line_address;
   horizontal_offset=0;
  end

  // FF98.LPR is sampled at raster boundaries.  In graphics mode 111 holds
  // the current DMA row indefinitely; returning to 000 advances exactly one
  // row.  Changing LPR must not discard an already rendered scanline.
  begin : vertical_raster_effect
   reg valid0_before,valid1_before;
   valid0_before=dut.h_valid0;valid1_before=dut.h_valid1;
   dut.dma_next_y=8'd10;dut.dma_next_address=19'h01000;
   dut.dma_line_in_row=0;dut.dma_advance_pending=0;
   lpr=3'b111;repeat(5)@(posedge clk);#1;
   if(dut.h_valid0!=valid0_before||dut.h_valid1!=valid1_before)begin
    $display("FF98.LPR write invalidated an immutable cached row");errors=errors+1;end
   force dut.state=5'd7;force dut.out_x=10'd639;
   force dut.fill_hdmi=1'b0;force dut.fill_cvbs=1'b0;
   force dut.fill_sequential=1'b1;force dut.fill_y=8'd10;
   // A timed write after prefetch began must not retarget the immutable row.
   // The HDMI phase places the following prefetch after HBORD, where it will
   // capture the new LPR normally.
   force dut.fill_compatibility=1'b0;
   force dut.fill_bit_plane=1'b1;force dut.fill_lpr=8'd1;
   force dut.glyph_line=4'd0;force dut.fill_base=19'h01000;
   force dut.fill_stride=11'd160;
   @(posedge clk);#1;
   release dut.fill_stride;release dut.fill_base;release dut.glyph_line;
   release dut.fill_lpr;release dut.fill_bit_plane;release dut.fill_compatibility;
   release dut.fill_y;release dut.fill_sequential;
   release dut.fill_cvbs;release dut.fill_hdmi;release dut.out_x;release dut.state;
   if(dut.dma_next_y!=8'd11||!dut.dma_advance_pending)begin
    $display("completed raster did not queue DMA handoff");errors=errors+1;end
   // Consume row 11 after the timed write.  Live infinite LPR must hold the
   // previous address even though that raster captured one-line LPR.
   force dut.configuration_diff=1'b0;force dut.state=4'd0;
   force dut.h_pending=1'b1;force dut.h_pending_y=8'd11;
   force dut.coalesce_count=3'd7;
   @(posedge clk);#1;
   release dut.coalesce_count;release dut.h_pending_y;release dut.h_pending;
   release dut.state;release dut.configuration_diff;
   if(dut.fill_base!=19'h01000||dut.row_remainder!=0||
      dut.dma_advance_pending)begin
    $display("live infinite LPR did not hold next DMA row: base=%h line=%0d pending=%b",
      dut.fill_base,dut.row_remainder,dut.dma_advance_pending);errors=errors+1;end
   // The inverse transition likewise takes effect on the next prefetched
   // row, not the infinite-LPR row already in progress.
   force dut.state=5'd7;force dut.out_x=10'd639;
   force dut.fill_hdmi=1'b0;force dut.fill_cvbs=1'b0;
   force dut.fill_sequential=1'b1;force dut.fill_y=8'd11;
   force dut.fill_compatibility=1'b0;
   force dut.fill_bit_plane=1'b1;force dut.fill_lpr=8'hff;
   force dut.glyph_line=4'd0;force dut.fill_base=19'h01000;
   force dut.fill_stride=11'd160;
   @(posedge clk);#1;
   release dut.fill_stride;release dut.fill_base;release dut.glyph_line;
   release dut.fill_lpr;release dut.fill_bit_plane;release dut.fill_compatibility;
   release dut.fill_y;
   release dut.fill_sequential;release dut.fill_cvbs;release dut.fill_hdmi;
   release dut.out_x;release dut.state;
   lpr=3'b000;
   force dut.configuration_diff=1'b0;force dut.state=4'd0;
   force dut.h_pending=1'b1;force dut.h_pending_y=8'd12;
   force dut.coalesce_count=3'd7;
   @(posedge clk);#1;
   release dut.coalesce_count;release dut.h_pending_y;release dut.h_pending;
   release dut.state;release dut.configuration_diff;
   if(dut.fill_base!=19'h010a0||dut.row_remainder!=0||
      dut.dma_advance_pending)begin
    $display("live one-line LPR did not advance next DMA row: base=%h line=%0d pending=%b",
      dut.fill_base,dut.row_remainder,dut.dma_advance_pending);errors=errors+1;end
  end

  // Compatibility alpha ROM dots are active-low.  A stored row of $c0 must
  // therefore decode as $3f, without changing native text or bitmap packing.
  force dut.glyph_cache=8'hc0;force dut.fill_compatibility=1'b1;
  force dut.fill_bit_plane=1'b0;force dut.character=8'h40;force dut.fill_gm=3'd0;
  force dut.source_x=10'd0;#1;
  if(dut.decoded_pixel!==1'b0)begin
   $display("compatibility font polarity wrong at stored one");errors=errors+1;end
  force dut.source_x=10'd2;#1;
  if(dut.decoded_pixel!==1'b1)begin
   $display("compatibility font polarity wrong at stored zero");errors=errors+1;end
  release dut.source_x;release dut.fill_gm;release dut.character;
  release dut.fill_bit_plane;release dut.fill_compatibility;release dut.glyph_cache;

  if(errors==0)$display("tb_gime_scanline_buffer PASS");
  else $display("tb_gime_scanline_buffer FAIL: %0d",errors);
  $finish;
 end
endmodule
