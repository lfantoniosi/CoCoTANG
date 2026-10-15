`timescale 1ns/1ps
module tb_gime_scanline_buffer;
 reg clk=0,hdmi_clk=0,cvbs_clk=0,reset_n=0;
 reg [95:0] palettes=0;reg [31:0] memory_data=32'h1b1b1b1b;
 reg memory_valid=0;wire memory_request;wire [22:0] memory_addr;
 wire [23:0] hdmi_pixel;wire [5:0] cvbs_pixel;
 wire [5:0] cvbs_border,cvbs_right_border;
 wire [5:0] hdmi_left_border,hdmi_right_border;wire hdmi_border_valid;
 wire [5:0] hdmi_vertical_left_border,hdmi_vertical_right_border;
 wire hdmi_vertical_border_valid;
 wire [5:0] cvbs_vertical_left_border,cvbs_vertical_right_border;
 wire cvbs_vertical_border_valid;
 integer transactions=0,errors=0,i,timeout,raster;
 integer responder_delay=0;reg slow_memory=0;
 integer slow_memory_extra=0;
 reg [1:0] responder_state=0;reg compatibility_mode=0,compatibility_an_g=1;
 reg [2:0] compatibility_gm=0,compatibility_sam_mode=0;
 reg compatibility_css=0;reg [18:0] signature_without_css=0;
 reg [3:0] hres=7;reg [1:0] cres=1;
 reg [7:0] active_height=8'd192;
 reg bit_plane=1;reg [2:0] lpr=0;reg [3:0] vertical_scroll=0;
 reg [18:0] screen_base=0;reg [3:0] video_bank=0;
 reg [7:0] horizontal_offset=0;reg cpu_write_strobe=0;reg [22:0] cpu_write_addr=0;
 reg compatibility_raster_write=0;reg [7:0] compatibility_raster_y=0;
 reg [4:0] compatibility_raster_byte=0;reg compatibility_raster_css=0;
 reg compatibility_border_write=0,compatibility_border_right=0;
 reg [8:0] compatibility_border_y=0,hdmi_border_raster_y=0;
 reg [8:0] cvbs_border_raster_y=0;
 reg [5:0] compatibility_border_rgb=0;reg hdmi_frame_start=0;
 reg [5:0] border_rgb=0;
 reg hdmi_active_50hz=0;
 reg hdmi_prefetch_valid=1,cvbs_prefetch_valid=0;
 reg [7:0] hdmi_prefetch_y=0,cvbs_prefetch_y=0;
 reg hdmi_display_valid=0,hdmi_picture_active=0;reg [7:0] hdmi_display_y=0;
 reg [9:0] cvbs_display_x=0;reg [7:0] cvbs_display_y=0;
 reg cvbs_display_valid=0;

 gime_scanline_buffer dut(
  .clk(clk),.reset_n(reset_n),.bit_plane(bit_plane),.hres(hres),.cres(cres),
  .active_height(active_height),
  .lines_per_row_code(lpr),.vertical_scroll(vertical_scroll),.screen_base(screen_base),
  .video_bank(video_bank),
  .horizontal_offset(horizontal_offset),.palettes(palettes),
  .border_rgb(border_rgb),
  .compatibility_mode(compatibility_mode),.compatibility_an_g(compatibility_an_g),
  .compatibility_gm(compatibility_gm),.compatibility_css(compatibility_css),
  .compatibility_sam_mode(compatibility_sam_mode),
  .compatibility_raster_write(compatibility_raster_write),
  .compatibility_raster_y(compatibility_raster_y),
  .compatibility_raster_byte(compatibility_raster_byte),
  .compatibility_raster_css(compatibility_raster_css),
  .compatibility_border_write(compatibility_border_write),
  .compatibility_border_right(compatibility_border_right),
  .compatibility_border_y(compatibility_border_y),
  .compatibility_border_rgb(compatibility_border_rgb),
  .artifact_mode(2'd0),.blink(1'b0),
  .cpu_write_strobe(cpu_write_strobe),.cpu_write_addr(cpu_write_addr),
  .hdmi_read_clk(hdmi_clk),.hdmi_read_x(10'd0),.hdmi_display_y(hdmi_display_y),
  .hdmi_display_valid(hdmi_display_valid),.hdmi_prefetch_y(hdmi_prefetch_y),
  .hdmi_picture_active(hdmi_picture_active),
  .hdmi_prefetch_valid(hdmi_prefetch_valid),.hdmi_pixel_data(hdmi_pixel),
  .hdmi_left_border_data(hdmi_left_border),
  .hdmi_right_border_data(hdmi_right_border),
  .hdmi_border_valid(hdmi_border_valid),
  .hdmi_vertical_left_border_data(hdmi_vertical_left_border),
  .hdmi_vertical_right_border_data(hdmi_vertical_right_border),
  .hdmi_vertical_border_valid(hdmi_vertical_border_valid),
  .hdmi_frame_start(hdmi_frame_start),
  .hdmi_active_50hz(hdmi_active_50hz),
  .hdmi_border_raster_y(hdmi_border_raster_y),
  .cvbs_read_clk(cvbs_clk),.cvbs_read_x(cvbs_display_x),.cvbs_display_y(cvbs_display_y),
  .cvbs_display_valid(cvbs_display_valid),.cvbs_prefetch_y(cvbs_prefetch_y),
  .cvbs_prefetch_valid(cvbs_prefetch_valid),
  .cvbs_border_raster_y(cvbs_border_raster_y),
  .cvbs_pixel_data(cvbs_pixel),
  .cvbs_border_data(cvbs_border),
  .cvbs_right_border_data(cvbs_right_border),
  .cvbs_vertical_left_border_data(cvbs_vertical_left_border),
  .cvbs_vertical_right_border_data(cvbs_vertical_right_border),
  .cvbs_vertical_border_valid(cvbs_vertical_border_valid),
  .memory_request(memory_request),.memory_addr(memory_addr),
  .memory_data(memory_data),.memory_valid(memory_valid));

 always #5 clk=~clk;always #18.5 hdmi_clk=~hdmi_clk;always #3.7 cvbs_clk=~cvbs_clk;
 always @(posedge clk) begin
  memory_valid<=0;
  if(memory_request&&responder_state==0)begin responder_state<=1;transactions<=transactions+1;
   // Seventy-five clocks per word is deliberately slower than the nominal
   // sixty-clock 1.79 MHz interleave cadence, covering SDRAM completion/drop
   // overhead while still requiring an 80-column row to meet its deadline.
   responder_delay<=slow_memory?74+slow_memory_extra:0;
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
  // Native even-HRES rows use the GIME's narrow 512-dot aperture; odd-HRES
  // rows use the full 640 dots.  This distinction is required by raster
  // demos which alternate 256- and 320-pixel modes between scanlines.
  if(dut.scale_integer_512(13'd256)!=0||
     dut.scale_remainder_512(13'd256)!=10'd256)begin
   $display("256-pixel narrow-aperture scaling is wrong");errors=errors+1;end
  force dut.fill_narrow_aperture=1'b1;force dut.out_x=10'd63;#1;
  if(dut.in_fill_aperture)begin
   $display("narrow-aperture left border is not blanked");errors=errors+1;end
  force dut.out_x=10'd64;#1;
  if(!dut.in_fill_aperture)begin
   $display("narrow-aperture first picture dot is blanked");errors=errors+1;end
  force dut.out_x=10'd576;#1;
  if(dut.in_fill_aperture)begin
   $display("narrow-aperture right border is not blanked");errors=errors+1;end
  release dut.out_x;release dut.fill_narrow_aperture;

  // Preserve the synchronous-RAM one-pixel look-ahead, but never request
  // nonexistent element 640 at the right edge of a 640-sample GIME line.
  cvbs_display_valid=1;cvbs_display_x=10'd638;
  @(posedge cvbs_clk);#1;
  if(dut.c_read_addr!=10'd639)begin
   $display("CVBS look-ahead address %0d",dut.c_read_addr);errors=errors+1;end
  cvbs_display_x=10'd639;
  @(posedge cvbs_clk);#1;
  if(dut.c_read_addr!=10'd639)begin
   $display("CVBS final address %0d",dut.c_read_addr);errors=errors+1;end
  cvbs_display_valid=0;cvbs_display_x=0;

  // Horizontal blank preloads the upcoming row's pixel zero.  The encoder
  // still outputs border, but the RAM value must be ready when active video
  // opens rather than leaving a one-pixel seam at the left edge.
  force dut.c_valid0=1;force dut.c_tag0=8'd23;force dut.c_border0=6'h16;
  force dut.c_right_border0=6'h3f;
  dut.cvbs_line0[0]=6'h2d;cvbs_display_y=8'd23;
  repeat(4)@(posedge cvbs_clk);#1;
  if(!dut.c_read_valid||dut.c_read_bank!=0||cvbs_pixel!==6'h2d||
     !dut.cvbs_border_valid||cvbs_border!==6'h16||
     cvbs_right_border!==6'h3f)begin
   $display("CVBS blanking did not preload pixel zero");errors=errors+1;end
  release dut.c_right_border0;release dut.c_border0;
  release dut.c_tag0;release dut.c_valid0;cvbs_display_y=0;

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
   $display("SG4 HDMI exact 2x boundary is wrong: %h expected %h bank=%b tags=%0d/%0d",
    dut.h_valid0&&dut.h_tag0==0 ? dut.hdmi_line0[8] : dut.hdmi_line1[8],
    dut.expand_rgb222(mapped(6'd2)),dut.h_valid0,dut.h_tag0,dut.h_tag1);
   errors=errors+1;end

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
  // prefetched. Preserve both the displayed row and that completed prefetch
  // across the write; invalidating the latter creates a thin black gap.
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
  timeout=0;
  while((dut.state!=0||dut.h_pending||memory_request)&&timeout<200000)begin
   @(posedge clk);timeout=timeout+1;
  end
  hdmi_prefetch_y=8'd2;cvbs_prefetch_y=8'd3;transactions=0;
  repeat(5)@(posedge clk);hdmi_prefetch_valid=1;cvbs_prefetch_valid=1;timeout=0;
  while((!((dut.h_valid0&&dut.h_tag0==2)||(dut.h_valid1&&dut.h_tag1==2))||
          !((dut.c_valid0&&dut.c_tag0==2)||(dut.c_valid1&&dut.c_tag1==2)||
            (dut.c_valid2&&dut.c_tag2==2)))&&timeout<6800)
   begin @(posedge clk);timeout=timeout+1;end
  if(timeout==6800)begin
   $display("master row mirror missed deadline h=%b/%0d %b/%0d c=%b/%0d %b/%0d %b/%0d state=%0d pending=%b/%0d",
    dut.h_valid0,dut.h_tag0,dut.h_valid1,dut.h_tag1,
    dut.c_valid0,dut.c_tag0,dut.c_valid1,dut.c_tag1,dut.c_valid2,dut.c_tag2,
    dut.state,dut.h_pending,dut.h_pending_y);
   $display("mirror diagnostics transactions=%0d slow=%b responder=%0d delay=%0d",
    transactions,slow_memory,responder_state,responder_delay);
   errors=errors+1;
  end
  if(transactions!=40)begin
   $display("phase-separated request caused %0d transactions",transactions);errors=errors+1;end
  else $display("master row mirrored in %0d clocks",timeout);

  // CVBS/component horizontal blank must still protect the row that will be
  // consumed on this physical scanline.  source_valid is low there, while
  // prefetch_y continues to identify current_y+1.
  force dut.c_valid0=1;force dut.c_valid1=1;force dut.c_valid2=1;
  force dut.c_tag0=8'd9;force dut.c_tag1=8'd10;force dut.c_tag2=8'd11;
  force dut.cv_v_s=0;force dut.cv_pv_s=1;force dut.cv_p_s=8'd10;
  force dut.c_next_bank=0;repeat(2)@(posedge clk);#1;
  if(dut.c_replacement_bank==0)begin
   $display("CVBS blanking replacement selected active row");errors=errors+1;end
  // HDMI owns the render and does not re-render a tag which still exists in
  // its own cache. The analogue mirror must therefore not evict HDMI's
  // current row merely because its round-robin pointer names that bank.
  force dut.h_valid0=1;force dut.h_tag0=8'd10;
  force dut.h_valid1=0;
  force dut.hd_pa_s=1;force dut.hd_y_s=8'd10;
  force dut.hd_pv_s=1;force dut.hd_p_s=8'd12;
  force dut.c_next_bank=1;repeat(2)@(posedge clk);#1;
  if(dut.c_replacement_bank!=2)begin
   $display("CVBS replacement evicted HDMI-retained row instead of free row");
   errors=errors+1;end
  release dut.hd_p_s;release dut.hd_pv_s;release dut.hd_y_s;release dut.hd_pa_s;
  release dut.h_tag0;release dut.h_valid0;release dut.h_valid1;
  release dut.c_next_bank;release dut.cv_p_s;release dut.cv_pv_s;release dut.cv_v_s;
  release dut.c_tag2;release dut.c_tag1;release dut.c_tag0;
  release dut.c_valid2;release dut.c_valid1;release dut.c_valid0;

  // A GIME raster handler commonly changes VOFF/mode in analogue horizontal
  // border.  Analogue scanout is one row behind HDMI here.  Since HDMI is the
  // sole producer for both RAM copies, retain its prefetched row 32 as well
  // as analogue's current/prefetched rows 30/31.  Dropping row 32 only from
  // the analogue mirror cannot self-heal: HDMI still considers it cached.
  @(negedge clk);
  dut.c_valid0=1;dut.c_tag0=8'd30;dut.c_dirty0=1;
  dut.c_valid1=1;dut.c_tag1=8'd31;dut.c_dirty1=1;
  dut.c_valid2=1;dut.c_tag2=8'd32;dut.c_dirty2=1;
  force dut.h_valid0=1;force dut.h_tag0=8'd31;
  force dut.h_valid1=1;force dut.h_tag1=8'd32;
  force dut.cv_v_s=0;force dut.cv_pv_s=1;force dut.cv_p_s=8'd31;
  force dut.hd_pa_s=1;force dut.hd_y_s=8'd31;
  force dut.hd_pv_s=1;force dut.hd_p_s=8'd32;
  force dut.state=4'd0;force dut.configuration_pending=1'b1;
  @(posedge clk);#1;
  if(!dut.c_valid0||!dut.c_valid1||!dut.c_valid2||
     !dut.c_dirty0||!dut.c_dirty1||!dut.c_dirty2)begin
   $display("analogue HBORD mode write discarded phase-shifted mirror row");
   errors=errors+1;
  end
  release dut.configuration_pending;release dut.state;
  release dut.h_tag1;release dut.h_valid1;release dut.h_tag0;release dut.h_valid0;
  release dut.hd_p_s;release dut.hd_pv_s;release dut.hd_y_s;release dut.hd_pa_s;
  release dut.cv_p_s;release dut.cv_pv_s;release dut.cv_v_s;

  // A mode write in HBORD must not cancel a row request which has already
  // crossed into the renderer but is still in its coalescing window.  Raster
  // demos issue this sequence repeatedly; dropping the request skips both
  // the visible row and its sequential DMA advance.
  @(negedge clk);
  force dut.state=4'd0;
  dut.h_pending=1'b1;dut.h_pending_y=8'd33;
  dut.coalesce_count=3'd4;
  dut.configuration_pending=1'b1;
  @(posedge clk);#1;
  if(!dut.h_pending||dut.h_pending_y!=8'd33||dut.coalesce_count!=0)begin
   $display("HBORD mode write discarded queued row request");errors=errors+1;
  end
  dut.h_pending=0;release dut.state;

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

  // DISTO FF9B is a prefix at the SDRAM boundary, not part of the GIME's
  // running 19-bit DMA address.  This preserves the card's documented wrap
  // from the end to the beginning of the same selected 512K bank.
  begin : disto_video_bank_wrap
   force dut.fill_video_bank=4'd2;force dut.aligned_address=19'h7fffc;
   force dut.word_valid=1'b0;force dut.state=5'd5;
   @(posedge clk);#1;
   if(memory_addr!=23'h17fffc)begin
    $display("DISTO bank prefix address=%h",memory_addr);errors=errors+1;end
   release dut.state;release dut.word_valid;release dut.aligned_address;
   release dut.fill_video_bank;
   force dut.dma_advance_bit_plane=1'b1;
   force dut.dma_advance_infinite=1'b0;force dut.dma_advance_row=1'b1;
   force dut.dma_advance_base=19'h7fff0;force dut.dma_advance_stride=11'd160;#1;
   if(dut.advanced_dma_address!=19'h00090)begin
    $display("DISTO video escaped 512K bank: %h",dut.advanced_dma_address);
    errors=errors+1;end
   release dut.dma_advance_stride;release dut.dma_advance_base;
   release dut.dma_advance_row;release dut.dma_advance_infinite;
   release dut.dma_advance_bit_plane;
   dut.memory_request=0;
  end

  begin : nocan3_video_banks
   integer bank_number;
   force dut.aligned_address=19'h7fffc;
   force dut.word_valid=1'b0;
   for(bank_number=0;bank_number<16;bank_number=bank_number+1)begin
    dut.fill_video_bank=bank_number;
    force dut.state=5'd5;
    @(posedge clk);#1;
    if(memory_addr!==((bank_number*524288)+524284))
     $fatal(1,"NoCan3 video bank %0d address=%h",bank_number,memory_addr);
    release dut.state;
   end
   release dut.word_valid;release dut.aligned_address;
   force dut.h_valid0=1'b1;force dut.h_start0=23'h700400;
   force dut.h_bytes0=10'd16;
   cpu_write_addr=23'h100408;#1;
   if(dut.write_hits_h0)$fatal(1,"upper video cache aliased lower CPU bank");
   cpu_write_addr=23'h700408;#1;
   if(!dut.write_hits_h0)$fatal(1,"upper CPU write missed video cache");
   release dut.h_valid0;release dut.h_start0;release dut.h_bytes0;
   dut.memory_request=0;
  end

  // XRoar computes the row advance at HBORD, then applies it at VBORD after
  // an early FF98 write.  A new LPR=7 suppresses the pending address step.
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
   // Consume row 11 after the timed write.  Live LPR=7 suppresses even the
   // completed one-line row's pending address step.
   force dut.configuration_diff=1'b0;force dut.state=4'd0;
   force dut.h_pending=1'b1;force dut.h_pending_y=8'd11;
   force dut.coalesce_count=3'd7;
   @(posedge clk);#1;
   release dut.coalesce_count;release dut.h_pending_y;release dut.h_pending;
   release dut.state;release dut.configuration_diff;
   if(dut.fill_base!=19'h01000||
      dut.row_remainder!=9'd0||
      dut.dma_advance_pending)begin
    $display("LPR 0->7 DMA handoff wrong: base=%h line=%0d pending=%b",
      dut.fill_base,dut.row_remainder,dut.dma_advance_pending);errors=errors+1;end
   // A new LPR=0 forces the VBORD step after the old held row.
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
    $display("LPR 7->0 DMA handoff wrong: base=%h line=%0d pending=%b",
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

  // A VDG CSS write changes individual bytes without invalidating a row.
  compatibility_mode=1;compatibility_css=0;#1;
  signature_without_css=dut.live_signature;
  compatibility_css=1;#1;
  if(dut.live_signature!==signature_without_css)begin
   $display("VDG CSS still invalidates complete cached lines");errors=errors+1;end
  for(i=0;i<32;i=i+1)begin
   compatibility_raster_y=8'd7;compatibility_raster_byte=i[4:0];
   compatibility_raster_css=i>=16;compatibility_raster_write=1;
   @(posedge clk);#1;
  end
  compatibility_raster_write=0;
  force dut.fill_raster_css_valid=1'b1;
  force dut.compatibility_css_read_addr={1'b0,8'd7,5'd0};
  repeat(2)@(posedge clk);#1;
  if(dut.pixel_compatibility_css!==1'b0)begin
   $display("VDG CSS raster lost first-half value");errors=errors+1;end
  release dut.compatibility_css_read_addr;
  force dut.compatibility_css_read_addr={1'b0,8'd7,5'd31};
  repeat(2)@(posedge clk);#1;
  if(dut.pixel_compatibility_css!==1'b1)begin
   $display("VDG CSS raster lost second-half value");errors=errors+1;end
  release dut.compatibility_css_read_addr;release dut.fill_raster_css_valid;

  force dut.fill_compatibility=1'b1;
  force dut.fill_bit_plane=1'b1;
  force dut.fill_gm=3'd2;
  force dut.fill_artifact_mode=2'd0;
  force dut.fill_left_css=1'b0;
  force dut.fill_right_css=1'b1;
  #1;
  if(dut.rendered_left_border!==6'h0c||dut.rendered_right_border!==6'h3f)begin
   $display("VDG row endpoint border colours are wrong");errors=errors+1;end
  release dut.fill_compatibility;release dut.fill_bit_plane;
  release dut.fill_gm;release dut.fill_artifact_mode;
  release dut.fill_left_css;release dut.fill_right_css;

  // A complete cached row includes both border endpoints in native and
  // compatibility modes. Later live border/mode changes cannot recolour it.
  force dut.h_v0_r=1'b1;force dut.h_tag0_r=8'd7;
  force dut.h_left_border0=6'h0c;force dut.h_right_border0=6'h3f;
  hdmi_display_y=7;hdmi_picture_active=1;hdmi_display_valid=0;
  compatibility_mode=0;
  border_rgb=6'h15;
  @(posedge hdmi_clk);#1;
  if(!hdmi_border_valid||hdmi_left_border!==6'h0c||hdmi_right_border!==6'h3f)begin
   $display("native row did not keep its committed border");errors=errors+1;end
  compatibility_mode=1;
  @(posedge hdmi_clk);#1;
  if(!hdmi_border_valid||hdmi_left_border!==6'h0c||hdmi_right_border!==6'h3f)begin
   $display("VDG border metadata was lost outside picture aperture");errors=errors+1;end
  hdmi_picture_active=0;
  @(posedge hdmi_clk);#1;
  if(hdmi_border_valid)begin
   $display("VDG border metadata remained valid outside raster row");errors=errors+1;end
  release dut.h_v0_r;release dut.h_tag0_r;
  release dut.h_left_border0;release dut.h_right_border0;
  border_rgb=0;

  compatibility_raster_y=0;compatibility_raster_byte=0;
  compatibility_raster_css=0;compatibility_raster_write=1;
  @(posedge clk);#1;compatibility_raster_write=0;
  if(dut.compatibility_css_display_valid!==1'b0)begin
   $display("partial VDG field became visible");errors=errors+1;end
  compatibility_raster_write=1;
  @(posedge clk);#1;compatibility_raster_write=0;
  if(dut.compatibility_css_display_valid!==1'b1)begin
   $display("complete VDG field was not published");errors=errors+1;end

  // Vertical border history is committed only after a complete VDG field.
  compatibility_border_y=0;compatibility_border_rgb=6'h0c;
  compatibility_border_write=1;
  @(posedge clk);#1;compatibility_border_write=0;
  if(dut.compatibility_border_display_valid!==1'b0)begin
   $display("partial VDG border field became visible");errors=errors+1;end
  compatibility_border_y=240;compatibility_border_rgb=6'h3f;
  compatibility_border_write=1;
  @(posedge clk);#1;compatibility_border_write=0;
  compatibility_border_right=1;compatibility_border_rgb=6'h0c;
  compatibility_border_write=1;
  @(posedge clk);#1;compatibility_border_write=0;
  compatibility_border_right=0;compatibility_border_y=0;
  compatibility_border_write=1;
  @(posedge clk);#1;compatibility_border_write=0;
  hdmi_border_raster_y=240;hdmi_frame_start=1;
  cvbs_border_raster_y=240;
  repeat(4)@(posedge hdmi_clk);#1;hdmi_frame_start=0;
  repeat(2)@(posedge hdmi_clk);#1;
  if(!hdmi_vertical_border_valid||hdmi_vertical_left_border!==6'h3f||
     hdmi_vertical_right_border!==6'h0c)begin
   $display("completed VDG vertical border field was not retained");errors=errors+1;end
  repeat(3)@(posedge cvbs_clk);#1;
  if(!cvbs_vertical_border_valid||cvbs_vertical_left_border!==6'h3f||
     cvbs_vertical_right_border!==6'h0c)begin
   $display("analogue VDG vertical border differs from HDMI");errors=errors+1;end


  // A row-zero tag from the old HDMI standard must not make the first row
  // of the new field look cached; the running DMA chain must restart too.
  @(negedge clk);
  hdmi_prefetch_valid=0;hdmi_display_valid=0;hdmi_picture_active=0;
  repeat(4) @(negedge clk);
  for(i=0;i<2;i=i+1)begin
   dut.state=0;dut.configuration_pending=0;
   dut.mode_signature=dut.live_signature;
   dut.last_screen_base=dut.frame_screen_base;
   dut.last_video_bank=dut.frame_video_bank;
   dut.h_valid0=1;dut.h_tag0=0;
   dut.c_valid0=1;dut.c_tag0=0;
   dut.dma_next_y=8'd47;dut.dma_next_address=19'h12345;
   hdmi_active_50hz=!hdmi_active_50hz;
   repeat(2) @(negedge clk);
   if(!dut.h_valid0||!dut.c_valid0)begin
    $display("standard-change cache test lost tags before the edge");
    errors=errors+1;
   end
   repeat(3) @(negedge clk);
   if(dut.h_valid0||dut.h_valid1||dut.c_valid0||dut.c_valid1||
      dut.c_valid2||dut.dma_next_y!=0||
      dut.dma_next_address!=screen_base)begin
    $display("standard-change cache/DMA reset failed on flip %0d",i);
    errors=errors+1;
   end
  end

  // BOINK can write VOFF/VSC early in vertical blank, before row zero is
  // requested.  Those values must still become the next field's DMA origin.
  @(negedge clk);compatibility_mode=0;bit_plane=1;
  hdmi_picture_active=0;hdmi_frame_start=1;
  repeat(4) @(negedge clk);hdmi_frame_start=0;
  repeat(4) @(negedge clk);
  if(!dut.upper_border_active)begin
   $display("HDMI upper-border window did not open");errors=errors+1;
  end
  screen_base=19'h12340;lpr=3'd3;vertical_scroll=3;
  repeat(4) @(negedge clk);
  if(dut.frame_screen_base!=19'h12340||
     dut.dma_next_address!=19'h12340||dut.dma_line_in_row!=3)begin
   $display("early upper-border VOFF/VSC was not captured: base=%h dma=%h line=%d upper=%b state=%d",
    dut.frame_screen_base,dut.dma_next_address,dut.dma_line_in_row,dut.upper_border,dut.state);errors=errors+1;
  end
  vertical_scroll=5;
  repeat(4) @(negedge clk);
  if(dut.dma_line_in_row!=5)begin
   $display("later upper-border VSC was not captured");errors=errors+1;
  end
  dut.state=6;dut.memory_request=1;
  dut.h_valid0=1;dut.h_tag0=0;
  screen_base=19'h12380;
  repeat(4) @(negedge clk);
  if(dut.state!=0||dut.memory_request||dut.h_valid0||
     dut.dma_next_address!=19'h12380)begin
   $display("upper-border VOFF write did not cancel stale row-zero fill");
   errors=errors+1;
  end
  hdmi_prefetch_y=0;hdmi_prefetch_valid=1;
  wait_hdmi_line();
  if(!((dut.h_valid0&&dut.h_tag0==0&&dut.h_start0[18:0]==19'h12380)||
       (dut.h_valid1&&dut.h_tag1==0&&dut.h_start1[18:0]==19'h12380)))begin
   $display("row zero fetched from old VOFF after setup change");
   errors=errors+1;
  end
  hdmi_prefetch_valid=0;
  hdmi_picture_active=1;
  repeat(4) @(negedge clk);
  screen_base=19'h23450;
  repeat(4) @(negedge clk);
  if(dut.frame_screen_base!=19'h12380)begin
   $display("VOFF changed after picture began");errors=errors+1;
  end

  // CHART.BAS updates palette entries 8-11 between adjacent cached rows.
  // The second row must retain the preceding paint palette, without
  // delaying the fixed outline entries.
  hdmi_prefetch_valid=0;
  repeat(5) @(negedge clk);
  force dut.state=4'd0;force dut.h_pending=1'b1;
  force dut.h_pending_y=8'd42;force dut.coalesce_count=3'd7;
  palettes[48+:24]=24'h123456;
  @(posedge clk);#1;
  palettes[48+:24]=24'habcdef;
  palettes[0+:6]=6'h3e;
  @(posedge clk);#1;
  if(dut.fill_palettes[48+:24]!==24'h123456||
     dut.fill_palettes[0+:6]!==6'h3e)begin
   $display("CHART paint palette advanced before its bitmap row");errors=errors+1;
  end
  active_height=8'd225;palettes[48+:24]=24'hfedcba;
  @(posedge clk);#1;
  if(dut.fill_palettes[48+:24]!==24'hfedcba)begin
   $display("non-192-line palette incorrectly delayed");errors=errors+1;
  end
  release dut.state;release dut.h_pending;release dut.h_pending_y;
  release dut.coalesce_count;

  if(errors==0)$display("tb_gime_scanline_buffer PASS");
  else $display("tb_gime_scanline_buffer FAIL: %0d",errors);
  $finish;
 end
endmodule
