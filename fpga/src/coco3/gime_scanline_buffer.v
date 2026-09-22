// Unified CoCo 3 scanline renderer. Mode decoding and row addressing follow
// the MiSTer/Gary Becker CoCo3FPGA core, but no framebuffer is used.
module gime_scanline_buffer #(
 parameter integer NATIVE_HDMI_640=1
) (
 input clk,input reset_n,input bit_plane,input [3:0] hres,input [1:0] cres,
 input [2:0] lines_per_row_code,input [3:0] vertical_scroll,
 input [18:0] screen_base,input [7:0] horizontal_offset,input [95:0] palettes,
 input compatibility_mode,input compatibility_an_g,input [2:0] compatibility_gm,
 input [2:0] compatibility_sam_mode,
 input compatibility_css,input [1:0] artifact_mode,input blink,
 input cpu_write_strobe,input [18:0] cpu_write_addr,
 input hdmi_read_clk,input [9:0] hdmi_read_x,input [7:0] hdmi_display_y,
 input hdmi_display_valid,input hdmi_picture_active,
 input [7:0] hdmi_prefetch_y,input hdmi_prefetch_valid,
 output reg [23:0] hdmi_pixel_data,
 input cvbs_read_clk,input [9:0] cvbs_read_x,input [7:0] cvbs_display_y,
 input cvbs_display_valid,input [7:0] cvbs_prefetch_y,input cvbs_prefetch_valid,
 output reg [5:0] cvbs_pixel_data,
 output reg memory_request,output reg [22:0] memory_addr,
 input [31:0] memory_data,input memory_valid,
 output [7:0] debug_dma_next_y,output [7:0] debug_fill_y,
 output [3:0] debug_state
);
 localparam [9:0] CANONICAL_WIDTH=10'd640;

 function [5:0] palette_rgb;
  input [5:0] color;
  begin palette_rgb={color[5],color[2],color[4],color[1],color[3],color[0]}; end
 endfunction
 function [5:0] vdg_code;
  input [2:0] color; reg [5:0] code;
  begin
   case(color)
    0:code=6'd18; 1:code=6'd54; 2:code=6'd9; 3:code=6'd36;
    4:code=6'd63; 5:code=6'd27; 6:code=6'd45; default:code=6'd38;
   endcase
   vdg_code=code;
  end
 endfunction
 function [9:0] graphics_row_bytes;
  input [3:0] value;
  begin case(value)
   0:graphics_row_bytes=16; 1:graphics_row_bytes=20;
   2:graphics_row_bytes=32; 3:graphics_row_bytes=40;
   4:graphics_row_bytes=64; 5:graphics_row_bytes=80;
   6:graphics_row_bytes=128; 7:graphics_row_bytes=160;
   8:graphics_row_bytes=256; 9:graphics_row_bytes=320;
   10:graphics_row_bytes=512; default:graphics_row_bytes=640;
  endcase end
 endfunction
 function [7:0] text_columns;
  input [3:0] value;
  begin case({value[2],value[0]})
   2'b00:text_columns=32;2'b01:text_columns=40;
   2'b10:text_columns=64;default:text_columns=80;
  endcase end
 endfunction
 function [7:0] native_lines_per_row;
  input [2:0] value;
  begin case(value)
   3'b000,3'b001:native_lines_per_row=1;3'b010:native_lines_per_row=2;
   3'b011:native_lines_per_row=8;3'b100:native_lines_per_row=9;
   3'b101:native_lines_per_row=10;3'b110:native_lines_per_row=11;
   default:native_lines_per_row=8'hff;
  endcase end
 endfunction
 function [7:0] compatibility_lines_per_row;
  input [2:0] sam_mode;
  begin
   if(sam_mode<=3)compatibility_lines_per_row=3;
   else if(sam_mode<=5)compatibility_lines_per_row=2;
   else compatibility_lines_per_row=1;
 end
 endfunction
 function native_advance_row;
  input [2:0] value;
  input [3:0] glyph;
  begin case(value)
   3'b000,3'b001:native_advance_row=1'b1;
   3'b010:native_advance_row=glyph>=4'd1;
   3'b011:native_advance_row=glyph>=4'd7;
   3'b100:native_advance_row=glyph>=4'd8;
   3'b101:native_advance_row=glyph>=4'd9;
   3'b110:native_advance_row=glyph>=4'd10;
   default:native_advance_row=1'b0;
  endcase end
 endfunction
 function [3:0] scale_integer;
  input [12:0] width;
  begin case(width)
   13'd640:scale_integer=1;13'd1024:scale_integer=1;
   13'd1280:scale_integer=2;13'd2048:scale_integer=3;
   13'd2560:scale_integer=4;13'd4096:scale_integer=6;
   13'd5120:scale_integer=8;default:scale_integer=0;
  endcase end
 endfunction
 function [9:0] scale_remainder;
  input [12:0] width;
  begin case(width)
   13'd1024:scale_remainder=384;13'd2048:scale_remainder=128;
   13'd4096:scale_remainder=256;
   13'd640,13'd1280,13'd2560,13'd5120:scale_remainder=0;
   default:scale_remainder=width[9:0];
  endcase end
 endfunction
 function compatibility_inverse;
  input [1:0] gm_low; input [1:0] char_group;
  begin case({gm_low,char_group})
   4'b0000,4'b0001,4'b0101,4'b1010,4'b1011,
   4'b1100,4'b1110,4'b1111:compatibility_inverse=1;
   default:compatibility_inverse=0;
  endcase end
 endfunction
 function [23:0] expand_rgb222;
  input [5:0] color;
  begin expand_rgb222={{4{color[5:4]}},{4{color[3:2]}},{4{color[1:0]}}};end
 endfunction
 function [23:0] blend_quarters;
  input [23:0] left;
  input [23:0] right;
  input [1:0] right_weight;
  reg [9:0] r_sum,g_sum,b_sum;
  begin
   // Keep the fractional coverage produced by the 640-to-512 reduction.
   // Quantizing this result back to RGB222 made one-dot black text vanish
   // into grey backgrounds.
   r_sum=left[23:16]*(4-right_weight)+right[23:16]*right_weight+2;
   g_sum=left[15:8]*(4-right_weight)+right[15:8]*right_weight+2;
   b_sum=left[7:0]*(4-right_weight)+right[7:0]*right_weight+2;
   blend_quarters={r_sum[9:2],g_sum[9:2],b_sum[9:2]};
  end
 endfunction

 wire [9:0] native_graphics_bytes=graphics_row_bytes(hres);
 wire [7:0] native_columns=text_columns(hres);
 wire native_attributes=!bit_plane&&cres[0];
 wire [10:0] native_text_bytes=native_attributes?{2'b0,native_columns,1'b0}:
                                                  {3'b0,native_columns};
 wire [10:0] native_row_bytes=bit_plane?{1'b0,native_graphics_bytes}:native_text_bytes;
 // Pixel packing follows the MC6847 GM pins.  The SAM video mode controls
 // vertical row repetition below, but must not override the 16/32-byte GM
 // packing: Mega-Bug uses a GM/SAM combination whose vertical geometry is
 // 96 rows while each decoded colour row remains 32 bytes wide.
 wire [10:0] compatibility_row_bytes=!compatibility_an_g?11'd32:
  ((compatibility_gm==0||compatibility_gm==1||compatibility_gm==3||
    compatibility_gm==5)?11'd16:11'd32);
 wire [10:0] live_row_bytes=compatibility_mode?compatibility_row_bytes:native_row_bytes;
 wire [10:0] live_stride=compatibility_mode?compatibility_row_bytes:
  horizontal_offset[7]?(hres[3]?11'd1024:11'd256):native_row_bytes;
 wire [12:0] native_graphics_width=cres==0?{native_graphics_bytes,3'b0}:
  cres==1?{1'b0,native_graphics_bytes,2'b0}:{2'b0,native_graphics_bytes,1'b0};
 wire [12:0] compatibility_width=!compatibility_an_g?13'd256:
  compatibility_gm==0?13'd64:compatibility_gm==7?13'd256:13'd128;
 wire [12:0] live_source_width=compatibility_mode?compatibility_width:
  bit_plane?native_graphics_width:{2'b0,native_columns,3'b0};

 // One renderer and common tags/fetch policy. The pixel RAM is mirrored only
 // because HDMI and CVBS have unrelated read clocks; this is still two lines
 // per output, never a framebuffer.
 reg [23:0] hdmi_line0[0:639],hdmi_line1[0:639];
 reg [5:0] cvbs_line0[0:639],cvbs_line1[0:639];
 reg h_valid0=0,h_valid1=0,c_valid0=0,c_valid1=0;
 reg h_dirty0=0,h_dirty1=0,c_dirty0=0,c_dirty1=0;
 reg [7:0] h_tag0=0,h_tag1=0,c_tag0=0,c_tag1=0;
 reg [18:0] h_start0=0,h_start1=0,c_start0=0,c_start1=0;
 reg [10:0] h_bytes0=0,h_bytes1=0,c_bytes0=0,c_bytes1=0;
 reg h_next_bank=0,c_next_bank=0;

 reg [7:0] hd_y_m=0,hd_y_s=0,hd_p_m=0,hd_p_s=0;
 reg hd_v_m=0,hd_v_s=0,hd_pa_m=0,hd_pa_s=0,hd_pv_m=0,hd_pv_s=0;
 reg [7:0] cv_y_m=0,cv_y_s=0,cv_p_m=0,cv_p_s=0;
 reg cv_v_m=0,cv_v_s=0,cv_pv_m=0,cv_pv_s=0;
 always @(posedge clk) begin
  hd_y_m<=hdmi_display_y;hd_y_s<=hd_y_m;hd_p_m<=hdmi_prefetch_y;hd_p_s<=hd_p_m;
  hd_v_m<=hdmi_display_valid;hd_v_s<=hd_v_m;hd_pv_m<=hdmi_prefetch_valid;hd_pv_s<=hd_pv_m;
  hd_pa_m<=hdmi_picture_active;hd_pa_s<=hd_pa_m;
  cv_y_m<=cvbs_display_y;cv_y_s<=cv_y_m;cv_p_m<=cvbs_prefetch_y;cv_p_s<=cv_p_m;
  cv_v_m<=cvbs_display_valid;cv_v_s<=cv_v_m;cv_pv_m<=cvbs_prefetch_valid;cv_pv_s<=cv_pv_m;
 end
 wire h_display_cached=(h_valid0&&h_tag0==hd_y_s)||(h_valid1&&h_tag1==hd_y_s);
 // A cached row remains immutable until normal two-line replacement.  CPU
 // writes are remembered as dirty for diagnostics, but must not trigger an
 // immediate same-tag refill: in 80-column attribute mode that refill can
 // run into scanout and write the dual-clock line RAM while HDMI reads it.
 // The row is naturally fetched again after the two-entry cache rolls over,
 // giving raster-safe (at most one-frame-late) CPU/video coherence.
 wire h_prefetch_cached=(h_valid0&&h_tag0==hd_p_s)||
                         (h_valid1&&h_tag1==hd_p_s);
 wire c_display_cached=(c_valid0&&c_tag0==cv_y_s)||(c_valid1&&c_tag1==cv_y_s);
 wire c_prefetch_cached=(c_valid0&&c_tag0==cv_p_s)||
                         (c_valid1&&c_tag1==cv_p_s);
 wire h_need=(hd_v_s&&!h_display_cached)||(hd_pv_s&&!h_prefetch_cached);
 wire c_need=(cv_v_s&&!c_display_cached)||(cv_pv_s&&!c_prefetch_cached);
 wire [7:0] h_need_y=(hd_v_s&&!h_display_cached)?hd_y_s:hd_p_s;
 wire [7:0] c_need_y=(cv_v_s&&!c_display_cached)?cv_y_s:cv_p_s;
 reg h_pending=0,c_pending=0;reg [7:0] h_pending_y=0,c_pending_y=0;
 reg [2:0] coalesce_count=0;

 reg fill_hdmi=0,fill_cvbs=0,fill_h_bank=0,fill_c_bank=0;
 reg fill_sequential=0;
 reg [7:0] fill_y=0; reg fill_bit_plane=0; reg [1:0] fill_cres=0;
 reg fill_attributes=0;reg [2:0] fill_gm=0;reg fill_css=0;
 reg fill_compatibility=0,fill_blink=0;reg [1:0] fill_artifact_mode=0;
 reg [7:0] fill_lpr=1;
 reg [10:0] fill_stride=0,fill_row_bytes=0;reg [12:0] fill_source_width=0;
 reg [3:0] fill_scale_integer=0;reg [9:0] fill_scale_remainder=0;
 reg [18:0] fill_base=0;reg [6:0] fill_hoff=0;reg [95:0] fill_palettes=0;
 reg [8:0] row_remainder=0;reg [7:0] source_row=0;reg [3:0] glyph_line=0;
 reg [9:0] out_x=0;reg [12:0] source_x=0;reg [9:0] scale_phase=0;
 // Cache the byte/character indices alongside source_x.  Deriving them
 // through the colour-resolution mux in PIXEL_ADDRESS put that mux, the
 // row-address adder and the cache-tag comparison on one 108 MHz path.
 reg [11:0] source_byte_index=0;
 reg [7:0] source_character_column=0;
 reg [9:0] hdmi_out_x=0;reg [2:0] hdmi_filter_phase=0;
 reg [23:0] hdmi_filter_previous=0;
 reg [255:0] artifact_bits=0;
 reg [260:0] artifact_shift=0;
 reg [18:0] row_address=0,line_address=0,byte_address=0;
 reg [31:0] word_cache=0;reg [18:0] word_tag=0;reg word_valid=0;
 reg [7:0] character=0,attribute=0,glyph_cache=0;reg fill_dirty=0;
 reg text_cache_valid=0,graphics_cache_valid=0;
 reg [7:0] text_cache_column=0;reg [11:0] graphics_cache_index=0;

 // Both terms are strictly below 640, so eleven bits cover the complete
 // 0..1278 sum.  Keeping this at fourteen bits needlessly lengthened the
 // source-index update carry chain on the 108 MHz renderer clock.
 wire [10:0] next_scale_phase_sum={1'b0,scale_phase}+
                                  {1'b0,fill_scale_remainder};
 wire [12:0] next_source_x=source_x+fill_scale_integer+
     (next_scale_phase_sum>=11'd640);
 wire [11:0] next_source_byte_index=fill_cres==0?next_source_x[12:3]:
  fill_cres==1?next_source_x[12:2]:next_source_x[12:1];
 wire [18:0] pixel_byte_index=fill_bit_plane?{7'd0,source_byte_index}:
  fill_attributes?{10'd0,source_character_column,1'b0}:
                  {11'd0,source_character_column};
 // FF9F selects a byte within a 256-byte virtual row and the fetch wraps at
 // that boundary even when HVEN is clear.  BOINK depends on this: allowing
 // the sum to carry into the next page tears the bouncing image into bands.
 wire [8:0] horizontal_byte_sum={1'b0,fill_hoff,1'b0}+pixel_byte_index[8:0];
 wire [18:0] calculated_byte_address=fill_compatibility?
  line_address+pixel_byte_index:
  line_address+{11'd0,horizontal_byte_sum[7:0]};
 wire [18:0] aligned_address={byte_address[18:2],2'b0};
 wire [7:0] cached_byte=byte_address[1:0]==0?word_cache[7:0]:
  byte_address[1:0]==1?word_cache[15:8]:byte_address[1:0]==2?word_cache[23:16]:word_cache[31:24];
 reg [11:0] font_addr=0;wire [7:0] font_data;
 coco3_char_rom font(.clk(clk),.addr(font_addr),.data(font_data));

 wire artifact_active=fill_compatibility&&fill_bit_plane&&fill_gm==3'd7&&
                      fill_artifact_mode!=0;
 wire [5:0] artifact_neighborhood={
  artifact_shift[0],artifact_shift[1],artifact_shift[2],
  artifact_shift[3],artifact_shift[4],artifact_shift[5]};
 wire [5:0] artifact_rgb;
 wire [3:0] artifact_color_index;
 ntsc_artifact_decode artifact_decoder(
  .neighborhood(artifact_neighborhood),.odd_pixel(source_x[0]),
  .reverse_phase(fill_artifact_mode==2),.css(fill_css),
  .color_index(artifact_color_index),.rgb(artifact_rgb));

 reg [3:0] decoded_index;reg decoded_pixel;reg [5:0] decoded_code;
 reg semigraphics_pixel;reg inverse_character;reg [2:0] semigraphics_color;
 always @(*) begin
  case(fill_cres)
   0:decoded_index={3'b0,cached_byte[7-source_x[2:0]]};
   1:case(source_x[1:0])
    0:decoded_index={2'b0,cached_byte[7:6]};1:decoded_index={2'b0,cached_byte[5:4]};
    2:decoded_index={2'b0,cached_byte[3:2]};default:decoded_index={2'b0,cached_byte[1:0]};
   endcase
   default:decoded_index=source_x[0]?cached_byte[3:0]:cached_byte[7:4];
  endcase
  // Character rows retain their normal MSB-to-LSB horizontal order.  The
  // compatibility character set in the CoCo 3 ROM stores the dot polarity
  // inverted; that polarity correction is applied only in the VDG alpha
  // branch below, never to native GIME text or bitmap graphics.
  decoded_pixel=glyph_cache[7-source_x[2:0]];decoded_code=0;
  semigraphics_pixel=0;semigraphics_color=0;
  inverse_character=compatibility_inverse(fill_gm[1:0],character[6:5]);
  if(!fill_compatibility) begin
   if(!fill_bit_plane) begin
    if(fill_attributes) begin
     if(attribute[7]&&fill_blink)decoded_pixel=0;
     if(attribute[6]&&glyph_line==fill_lpr-1'b1)
      decoded_pixel=(source_x[2:0]!=0&&source_x[2:0]!=7);
     // Native text uses the upper palette bank (8-15) for foreground and
     // the lower bank (0-7) for background.  The attribute itself keeps the
     // documented FFFBBB layout; only the palette-bank select differs.
     decoded_index=decoded_pixel?{1'b1,attribute[5:3]}:{1'b0,attribute[2:0]};
    end else decoded_index=decoded_pixel?1:0;
   end
  end else if(fill_bit_plane) begin
   decoded_code=fill_cres==0?(decoded_index[0]?vdg_code({fill_css,2'b0}):0):
                              vdg_code({fill_css,decoded_index[1:0]});
  end else if(character[7]) begin
   // PIA1 PB4 is both GM0 and the VDG INT/EXT selection used by the CoCo:
   // low selects SG4, high selects SG6.  Bits are ordered top-to-bottom as
   // 3/2 then 1/0 for SG4, and 5/4, 3/2, 1/0 for SG6; within each pair the
   // high bit is the left block.  These are decoded directly and never pass
   // through the compatibility font-ROM polarity correction.
   if(fill_gm[0]) begin
    if(glyph_line<4)semigraphics_pixel=source_x[2]?character[4]:character[5];
    else if(glyph_line<8)semigraphics_pixel=source_x[2]?character[2]:character[3];
    else semigraphics_pixel=source_x[2]?character[0]:character[1];
    semigraphics_color={fill_css,character[7:6]};
   end else begin
    if(glyph_line<6)semigraphics_pixel=source_x[2]?character[2]:character[3];
    else semigraphics_pixel=source_x[2]?character[0]:character[1];
    semigraphics_color=character[6:4];
   end
   decoded_code=semigraphics_pixel?vdg_code(semigraphics_color):
                                    (fill_css?6'd4:6'd2);
  end else begin
   decoded_pixel=(~decoded_pixel)^inverse_character;
   decoded_code=decoded_pixel?vdg_code(fill_css?3'd7:3'd0):
                              (fill_css?6'd4:6'd2);
  end
 end

 localparam IDLE=0,DIVIDE_ROW=1,ROW_ADDRESS=2,LINE_ADDRESS=3,PIXEL_ADDRESS=4,
  CHECK_WORD=5,WAIT_WORD=6,FINALIZE_LINE=7,CHECK_ATTRIBUTE=8,WAIT_ATTRIBUTE=9,
  FONT_WAIT1=10,FONT_WAIT2=11,DECODE_PIXEL=12,COLOR_LOOKUP=13,WRITE_PIXEL=14,
  ARTIFACT_WRITE=15,ARTIFACT_DECODE=16;
 reg [4:0] state=IDLE;reg [5:0] pixel_latched;
 reg [23:0] hdmi_pixel_latched=0;
 reg [5:0] artifact_pixel_latched=0;
 reg [3:0] artifact_color_latched=0;
 reg [3:0] color_index_latched=0;reg [5:0] color_code_latched=0;
 wire write_hits_h0=h_valid0&&cpu_write_addr>=h_start0&&cpu_write_addr<h_start0+h_bytes0;
 wire write_hits_h1=h_valid1&&cpu_write_addr>=h_start1&&cpu_write_addr<h_start1+h_bytes1;
 wire write_hits_c0=c_valid0&&cpu_write_addr>=c_start0&&cpu_write_addr<c_start0+c_bytes0;
 wire write_hits_c1=c_valid1&&cpu_write_addr>=c_start1&&cpu_write_addr<c_start1+c_bytes1;
 wire write_hits_fill=state!=IDLE&&cpu_write_addr>=line_address&&
                      cpu_write_addr<line_address+fill_row_bytes;
reg [18:0] mode_signature=19'h7ffff;reg [18:0] last_screen_base=19'h7ffff;
reg [18:0] frame_screen_base=0;
 // Running GIME DMA state.  This cannot be reconstructed as y*stride when
 // FF98.LPR or FF9F.HVEN changes during the picture: each raster advances
 // from the address left by the preceding raster.
 reg [7:0] dma_next_y=0;
 reg [18:0] dma_next_address=0;
 reg [3:0] dma_line_in_row=0;
 // A rendered raster captures its pixels and mode at fill start, but the
 // physical GIME tests the live LPR value when advancing to the following
 // raster.  Keep the completed descriptor until that following sequential
 // row is actually requested.  Anchoring the handoff to consumption avoids
 // losing it when speculative rendering finishes after an HDMI row edge.
 reg dma_advance_pending=0;
 reg [18:0] dma_advance_base=0;
 reg [10:0] dma_advance_stride=0;
 reg [3:0] dma_advance_glyph=0;
 reg dma_advance_bit_plane=0,dma_advance_compatibility=0;
 reg [7:0] dma_advance_lpr=1;
wire dma_advance_infinite=dma_advance_compatibility?
  dma_advance_lpr==8'hff:lines_per_row_code==3'b111;
wire dma_advance_row=dma_advance_compatibility?
  dma_advance_glyph+1'b1>=dma_advance_lpr:
  native_advance_row(lines_per_row_code,dma_advance_glyph);
wire [18:0] advanced_dma_address=
  (dma_advance_bit_plane&&dma_advance_infinite)?dma_advance_base:
  dma_advance_row?(dma_advance_base+dma_advance_stride):dma_advance_base;
wire [3:0] advanced_dma_line=
  (dma_advance_bit_plane&&dma_advance_infinite)||dma_advance_row?
  4'd0:dma_advance_glyph+1'b1;
 reg upper_border_q=0;
 wire upper_border=hd_pv_s&&hd_p_s==0&&!hd_v_s;
 // LPR is a raster control.  BOINK switches it to 111 to hold the current
 // DMA row and back to 000 to advance it.  It must be sampled for the next
 // fill, not treated as a mode change which aborts the renderer and flushes
 // its two immutable scanline buffers.
 wire [18:0] live_signature={artifact_mode,compatibility_mode,compatibility_an_g,
  compatibility_gm,compatibility_css,bit_plane,hres,cres,
  compatibility_sam_mode,1'b0};
 // FF9C vertical fine scroll is a raster control, just like FF98.LPR.  It is
 // sampled when a row fill begins; changing it must not abort that fill or
 // invalidate the row currently being scanned.  Doing so can blank only the
 // first of HDMI's two copies of a native row, producing a one-pixel-high
 // horizontal gap in raster demos.
wire configuration_diff=live_signature!=mode_signature||
  frame_screen_base!=last_screen_base;
reg configuration_pending=1'b1;
 assign debug_dma_next_y=dma_next_y;
 assign debug_fill_y=fill_y;
 assign debug_state=state[3:0];

 // Keep the dual-clock line RAM write port independent of the renderer's
 // asynchronously-reset control process. Artifact pixels retain their MAME
 // palette index in HDMI RAM, while CVBS continues to consume RGB222.
 wire renderer_write=state==WRITE_PIXEL||state==ARTIFACT_WRITE;
 wire renderer_artifact=state==ARTIFACT_WRITE;
 // Artifact rows carry a tagged palette index; normal GIME/VDG pixels are
 // expanded before filtering so the HDMI cache retains eight-bit coverage.
 wire [23:0] renderer_hdmi_pixel=hdmi_pixel_latched;
 wire [5:0] renderer_cvbs_pixel=renderer_artifact?
  artifact_pixel_latched:pixel_latched;
 reg hdmi_write_pending=0;
 reg hdmi_write_bank=0;
 reg [9:0] hdmi_write_x=0;
 reg [23:0] hdmi_write_data=0;
 reg cvbs_write_pending=0;
 reg cvbs_write_bank=0;
 reg [9:0] cvbs_write_x=0;
 reg [5:0] cvbs_write_data=0;
 always @(posedge clk) begin
  // The renderer first registers a complete write command.  Keeping the
  // RGB expansion/artifact selection and 640-to-512 blend on this side of
  // the register gives the inferred line RAM a short, timing-safe data path.
  hdmi_write_pending<=0;
  cvbs_write_pending<=0;
  if(renderer_write)begin
   if(fill_hdmi)begin
    if((NATIVE_HDMI_640!=0&&!fill_compatibility)||hdmi_filter_phase==0||
       (renderer_artifact&&hdmi_filter_phase!=1))begin
     hdmi_write_pending<=1;
     hdmi_write_data<=renderer_hdmi_pixel;
    end else if(hdmi_filter_phase==2)begin
     hdmi_write_pending<=1;
     hdmi_write_data<=blend_quarters(hdmi_filter_previous,
                                     renderer_hdmi_pixel,2'd1);
    end else if(hdmi_filter_phase==3)begin
     hdmi_write_pending<=1;
     hdmi_write_data<=blend_quarters(hdmi_filter_previous,
                                     renderer_hdmi_pixel,2'd2);
    end else if(hdmi_filter_phase==4)begin
     hdmi_write_pending<=1;
     hdmi_write_data<=blend_quarters(hdmi_filter_previous,
                                     renderer_hdmi_pixel,2'd3);
    end
    hdmi_write_bank<=fill_h_bank;
    hdmi_write_x<=hdmi_out_x;
   end
   if(fill_cvbs)begin
    cvbs_write_pending<=1;
    cvbs_write_bank<=fill_c_bank;
    cvbs_write_x<=out_x;
    cvbs_write_data<=renderer_cvbs_pixel;
   end
  end
  if(hdmi_write_pending)begin
   if(hdmi_write_bank)hdmi_line1[hdmi_write_x]<=hdmi_write_data;
   else hdmi_line0[hdmi_write_x]<=hdmi_write_data;
  end
  if(cvbs_write_pending)begin
   if(cvbs_write_bank)cvbs_line1[cvbs_write_x]<=cvbs_write_data;
   else cvbs_line0[cvbs_write_x]<=cvbs_write_data;
  end
 end

 always @(posedge clk or negedge reset_n) begin
 if(!reset_n) begin
   state<=IDLE;memory_request<=0;memory_addr<=0;h_valid0<=0;h_valid1<=0;
   c_valid0<=0;c_valid1<=0;h_dirty0<=0;h_dirty1<=0;c_dirty0<=0;c_dirty1<=0;
   mode_signature<=19'h7ffff;last_screen_base<=19'h7ffff;
   frame_screen_base<=0;
   h_next_bank<=0;c_next_bank<=0;fill_dirty<=0;configuration_pending<=1'b1;
   h_pending<=0;c_pending<=0;coalesce_count<=0;
   fill_sequential<=0;dma_next_y<=0;dma_next_address<=0;
   dma_line_in_row<=0;dma_advance_pending<=0;upper_border_q<=0;
  end else begin
   // Collapse the wide live-mode comparison into a single pending bit.  The
   // renderer consumes it only at IDLE, so mode inputs do not become a wide
   // combinational select path into all of the renderer state registers.
   if(configuration_diff)configuration_pending<=1'b1;
   // The GIME transfers VOFF into its running video address during vertical
   // blank.  HDMI's upper border continuously requests logical row zero, so
   // it provides a safe equivalent latch window without adding those border
   // lines to the logical row number.
   upper_border_q<=upper_border;
   if(upper_border)frame_screen_base<=screen_base;
   if(upper_border&&(!upper_border_q||screen_base!=frame_screen_base))begin
    dma_next_y<=0;dma_next_address<=screen_base;
    dma_advance_pending<=0;
    dma_line_in_row<=compatibility_mode||
      native_lines_per_row(lines_per_row_code)==8'd1||
      vertical_scroll>=native_lines_per_row(lines_per_row_code)?
      4'd0:vertical_scroll;
   end
   // Capture output-domain line requests before doing row/mode setup.  This
   // is a request pipeline only; pixels remain exclusively in the two line
   // buffers below.  Sampling only while idle prevents a completed fill from
   // leaving a stale request queued behind itself.
   if(state==IDLE)begin
    // HDMI is the sole producer clock for the shared logical scanlines.
    // CVBS reads the mirrored RAM copy but must not enqueue a nearby row and
    // evict the line which HDMI is about to display.
    if(!h_pending&&h_need)begin h_pending<=1;h_pending_y<=h_need_y;end
    c_pending<=0;
    if(h_pending)begin
     if(coalesce_count!=3'd7)coalesce_count<=coalesce_count+1'b1;
    end else coalesce_count<=0;
   end
   if(cpu_write_strobe) begin
    if(write_hits_h0)h_dirty0<=1;if(write_hits_h1)h_dirty1<=1;
    if(write_hits_c0)c_dirty0<=1;if(write_hits_c1)c_dirty1<=1;
    if(write_hits_fill)fill_dirty<=1;
   end
   // A raster-time mode write describes a future row.  At HBORD the next row
   // is normally already cached, because scanout is one native raster behind
   // the GIME interrupt generator.  Preserve both the row being displayed and
   // that completed prefetch.  Invalidating the prefetch leaves only one 480p
   // half-line in which to rebuild it and produces DEMO.BIN's thin black gaps.
   // Rows capture all mode/address state when their fill starts, so an active
   // fill is immutable as well; subsequent fills see the new live settings.
   if(configuration_pending&&state==IDLE)begin
    configuration_pending<=1'b0;
    mode_signature<=live_signature;last_screen_base<=frame_screen_base;
    // During upper border row zero is only speculative.  Do not preserve it
    // across a late frame-setup write; discard and regenerate it.  The next
    // row is protected only while an actual picture row is being displayed.
    h_valid0<=h_valid0&&hd_pa_s&&
              ((h_tag0==hd_y_s)||(hd_pv_s&&h_tag0==hd_p_s));
    h_valid1<=h_valid1&&hd_pa_s&&
              ((h_tag1==hd_y_s)||(hd_pv_s&&h_tag1==hd_p_s));
    c_valid0<=c_valid0&&cv_v_s&&
              ((c_tag0==cv_y_s)||(cv_pv_s&&c_tag0==cv_p_s));
    c_valid1<=c_valid1&&cv_v_s&&
              ((c_tag1==cv_y_s)||(cv_pv_s&&c_tag1==cv_p_s));
    h_dirty0<=h_dirty0&&hd_pa_s&&
              ((h_tag0==hd_y_s)||(hd_pv_s&&h_tag0==hd_p_s));
    h_dirty1<=h_dirty1&&hd_pa_s&&
              ((h_tag1==hd_y_s)||(hd_pv_s&&h_tag1==hd_p_s));
    c_dirty0<=c_dirty0&&cv_v_s&&
              ((c_tag0==cv_y_s)||(cv_pv_s&&c_tag0==cv_p_s));
    c_dirty1<=c_dirty1&&cv_v_s&&
              ((c_tag1==cv_y_s)||(cv_pv_s&&c_tag1==cv_p_s));
   memory_request<=0;word_valid<=0;h_pending<=0;c_pending<=0;
   coalesce_count<=0;
   end else begin
    // Raster-time writes describe the following row.  Consume their mode
    // signature while the current immutable fill continues, rather than
    // carrying the pending change to IDLE and flushing the completed
    // prefetch.  Delaying that consumption reintroduced one-line gaps in
    // DEMO.BIN and BOINK.
    if(configuration_pending)begin
     configuration_pending<=1'b0;
     mode_signature<=live_signature;
     last_screen_base<=frame_screen_base;
    end
    case(state)
    IDLE:if(h_pending&&coalesce_count==3'd7) begin
     // A row selected by the HDMI master is mirrored into both output RAMs.
     // CVBS therefore consumes the same immutable row without initiating a
     // second render or changing either cache's replacement order.
     fill_y<=h_pending_y;
     fill_hdmi<=1;fill_cvbs<=1;
     fill_sequential<=h_pending_y==dma_next_y;
     h_pending<=0;c_pending<=0;
     coalesce_count<=0;
     // Refresh a dirty prefetched row in its existing bank.  Choosing the
     // opposite bank here consumed the only other entry--the row currently
     // being displayed.  If that refill completed between the two doubled
     // HDMI scanlines, the second copy had no matching tag and went black.
     // Dirty displayed rows are intentionally still accepted by
     // h_display_cached above, so a same-tag refill request is the upcoming
     // prefetch row and is safe to update in place.
     // Never replace the bank currently being scanned.  A raster-time mode
     // change may invalidate the other cache tag without advancing the
     // round-robin pointer; blindly using h_next_bank in that case writes
     // into the displayed row and produces black/partially updated pixels
     // from the left edge until the fill catches scanout.
     fill_h_bank<=(h_valid0&&h_tag0==h_pending_y)?0:
                  (h_valid1&&h_tag1==h_pending_y)?1:
                  (hd_v_s&&h_valid0&&h_tag0==hd_y_s)?1:
                  (hd_v_s&&h_valid1&&h_tag1==hd_y_s)?0:h_next_bank;
     fill_c_bank<=(c_valid0&&c_tag0==h_pending_y)?0:
                  (c_valid1&&c_tag1==h_pending_y)?1:
                  (cv_v_s&&c_valid0&&c_tag0==cv_y_s)?1:
                  (cv_v_s&&c_valid1&&c_tag1==cv_y_s)?0:c_next_bank;
     fill_bit_plane<=bit_plane;
     fill_cres<=compatibility_mode&&compatibility_an_g?
      ((compatibility_gm==0||compatibility_gm==2||compatibility_gm==4||compatibility_gm==6)?1:0):cres;
     fill_attributes<=!compatibility_mode&&native_attributes;
     fill_gm<=compatibility_gm;fill_css<=compatibility_css;
     fill_compatibility<=compatibility_mode;fill_blink<=blink;
     fill_artifact_mode<=artifact_mode;
     fill_lpr<=compatibility_mode?(!compatibility_an_g?12:
      compatibility_lines_per_row(compatibility_sam_mode)):
      native_lines_per_row(lines_per_row_code);
     fill_stride<=live_stride;fill_row_bytes<=live_row_bytes;
     fill_source_width<=live_source_width;
     fill_scale_integer<=scale_integer(live_source_width);
     fill_scale_remainder<=scale_remainder(live_source_width);
     fill_hoff<=horizontal_offset[6:0];fill_palettes<=palettes;
     // Native LPR=0/1 is one raster line per memory row.  The real GIME
     // forces its fine-scroll counter to zero in this mode; FF9C must not
     // skip whole bitmap rows.  HDMI border lines never enter h_pending_y,
     // which starts at zero on the first logical picture line.
     if(h_pending_y==dma_next_y)begin
      row_remainder<={5'd0,dma_advance_pending?
                            advanced_dma_line:dma_line_in_row};
      fill_base<=dma_advance_pending?
                 advanced_dma_address:dma_next_address;
      if(dma_advance_pending)begin
       dma_next_address<=advanced_dma_address;
       dma_line_in_row<=advanced_dma_line;
       dma_advance_pending<=0;
      end
     end else begin
      row_remainder<={1'b0,h_pending_y}+
       ((compatibility_mode||native_lines_per_row(lines_per_row_code)==8'd1)?
        9'd0:{5'd0,vertical_scroll});
      fill_base<=frame_screen_base;
     end
     source_row<=0;word_valid<=0;fill_dirty<=0;text_cache_valid<=0;
     graphics_cache_valid<=0;state<=DIVIDE_ROW;
    end
    DIVIDE_ROW:begin
     if(row_remainder>=fill_lpr)begin row_remainder<=row_remainder-fill_lpr;
      source_row<=source_row+1'b1;end
     else begin glyph_line<=row_remainder[3:0];state<=ROW_ADDRESS;end
    end
    ROW_ADDRESS:begin row_address<=source_row*fill_stride;out_x<=0;source_x<=0;
     source_byte_index<=0;source_character_column<=0;
     scale_phase<=0;hdmi_out_x<=0;hdmi_filter_phase<=0;
     hdmi_filter_previous<=0;state<=LINE_ADDRESS;end
    LINE_ADDRESS:begin line_address<=fill_base+row_address;
     state<=PIXEL_ADDRESS;end
    PIXEL_ADDRESS:begin
     if(fill_bit_plane&&graphics_cache_valid&&graphics_cache_index==source_byte_index)
      state<=DECODE_PIXEL;
     else if(!fill_bit_plane&&text_cache_valid&&
             text_cache_column==source_character_column)
      state<=DECODE_PIXEL;
     else begin byte_address<=calculated_byte_address;state<=CHECK_WORD;end
    end
    CHECK_WORD:begin
     if(!word_valid||word_tag!=aligned_address)begin memory_addr<={4'd0,aligned_address};
      memory_request<=1;state<=WAIT_WORD;end
     else if(!fill_bit_plane)begin
      character<=cached_byte;
      if(fill_attributes)begin byte_address<=byte_address+1'b1;state<=CHECK_ATTRIBUTE;end
      else if(fill_compatibility&&cached_byte[7])begin
       text_cache_column<=source_character_column;text_cache_valid<=1;
       state<=DECODE_PIXEL;
      end
      else begin
       if(fill_compatibility)begin
        if(fill_gm[0]&&cached_byte[6:5]==0)
         font_addr<={1'b1,2'b11,cached_byte[4:0],glyph_line};
        else font_addr<={1'b1,~cached_byte[5],cached_byte[5:0],glyph_line};
       end else font_addr<={1'b0,cached_byte[6:0],glyph_line};
       state<=FONT_WAIT1;
      end
     end else begin graphics_cache_index<=source_byte_index;
      graphics_cache_valid<=1;state<=DECODE_PIXEL;end
    end
    WAIT_WORD:if(memory_valid)begin word_cache<=memory_data;word_tag<=aligned_address;
     word_valid<=1;memory_request<=0;state<=CHECK_WORD;end
    CHECK_ATTRIBUTE:begin
     if(!word_valid||word_tag!=aligned_address)begin memory_addr<={4'd0,aligned_address};
      memory_request<=1;state<=WAIT_ATTRIBUTE;end
     else begin attribute<=cached_byte;font_addr<={1'b0,character[6:0],glyph_line};
      state<=FONT_WAIT1;end
    end
    WAIT_ATTRIBUTE:if(memory_valid)begin word_cache<=memory_data;word_tag<=aligned_address;
     word_valid<=1;memory_request<=0;state<=CHECK_ATTRIBUTE;end
    FONT_WAIT1:state<=FONT_WAIT2;
    FONT_WAIT2:begin glyph_cache<=font_data;
     text_cache_column<=source_character_column;
     text_cache_valid<=1;state<=DECODE_PIXEL;end
    DECODE_PIXEL:begin
     color_index_latched<=decoded_index;color_code_latched<=decoded_code;
     state<=COLOR_LOOKUP;
    end
    COLOR_LOOKUP:begin
     pixel_latched<=palette_rgb(fill_compatibility?color_code_latched:
       fill_palettes[color_index_latched*6+:6]);
     hdmi_pixel_latched<=expand_rgb222(
       palette_rgb(fill_compatibility?color_code_latched:
       fill_palettes[color_index_latched*6+:6]));
     state<=WRITE_PIXEL;
    end
    WRITE_PIXEL:begin
     if(artifact_active)artifact_bits[source_x[7:0]]<=color_index_latched[0];
     // Area-preserving 640 -> 512 horizontal filter for HDMI.  For every
     // five canonical pixels emit four samples at phases 0, 1.25, 2.5 and
     // 3.75.  CVBS retains the original 640-dot row.  This is a streaming
     // operation performed while the row is rendered, not a framebuffer.
     if(fill_hdmi&&((NATIVE_HDMI_640!=0&&!fill_compatibility)||
                    hdmi_filter_phase!=1))
      hdmi_out_x<=hdmi_out_x+1'b1;
     hdmi_filter_previous<=renderer_hdmi_pixel;
     hdmi_filter_phase<=(hdmi_filter_phase==4)?0:hdmi_filter_phase+1'b1;
     if(out_x==CANONICAL_WIDTH-1'b1)begin
      if(artifact_active)begin
       // MAME evaluates the six-dot window through PMODE 4's set-level
       // border. Set-bit padding avoids artificial cyan/green edge lines.
       artifact_shift<={3'b111,color_index_latched[0],
                        artifact_bits[254:0],2'b11};
       out_x<=0;source_x<=0;scale_phase<=0;hdmi_out_x<=0;
       hdmi_filter_phase<=0;hdmi_filter_previous<=0;
       state<=ARTIFACT_DECODE;
      end else state<=FINALIZE_LINE;
     end else begin
      out_x<=out_x+1'b1;source_x<=next_source_x;
      source_byte_index<=next_source_byte_index;
      source_character_column<=next_source_x[10:3];
      scale_phase<=(next_scale_phase_sum>=11'd640)?
                   (next_scale_phase_sum-11'd640):next_scale_phase_sum[9:0];
      state<=PIXEL_ADDRESS;
     end
    end
    ARTIFACT_DECODE:begin
     artifact_pixel_latched<=artifact_rgb;
     artifact_color_latched<=artifact_color_index;
     hdmi_pixel_latched<={20'ha5c3e,artifact_color_index};
     state<=ARTIFACT_WRITE;
    end
    ARTIFACT_WRITE:begin
     if(fill_hdmi&&hdmi_filter_phase!=1)
      hdmi_out_x<=hdmi_out_x+1'b1;
     hdmi_filter_previous<=renderer_hdmi_pixel;
     hdmi_filter_phase<=(hdmi_filter_phase==4)?0:hdmi_filter_phase+1'b1;
     if(out_x==CANONICAL_WIDTH-1'b1)state<=FINALIZE_LINE;
     else begin
      if(hdmi_filter_phase==4)
       artifact_shift<=artifact_shift>>2;
      out_x<=out_x+1'b1;source_x<=next_source_x;
      scale_phase<=(next_scale_phase_sum>=11'd640)?
                   (next_scale_phase_sum-11'd640):next_scale_phase_sum[9:0];
      state<=ARTIFACT_DECODE;
     end
    end
    FINALIZE_LINE:begin
      if(fill_hdmi)begin
       if(fill_h_bank)begin h_tag1<=fill_y;h_start1<=line_address;h_bytes1<=fill_row_bytes;
        h_valid1<=1;h_dirty1<=fill_dirty;
        if(h_valid0&&h_tag0==fill_y)begin h_valid0<=0;h_dirty0<=0;end end
       else begin h_tag0<=fill_y;h_start0<=line_address;h_bytes0<=fill_row_bytes;
        h_valid0<=1;h_dirty0<=fill_dirty;
        if(h_valid1&&h_tag1==fill_y)begin h_valid1<=0;h_dirty1<=0;end end
       h_next_bank<=!fill_h_bank;
      end
      if(fill_cvbs)begin
       if(fill_c_bank)begin c_tag1<=fill_y;c_start1<=line_address;c_bytes1<=fill_row_bytes;
        c_valid1<=1;c_dirty1<=fill_dirty;
        if(c_valid0&&c_tag0==fill_y)begin c_valid0<=0;c_dirty0<=0;end end
       else begin c_tag0<=fill_y;c_start0<=line_address;c_bytes0<=fill_row_bytes;
        c_valid0<=1;c_dirty0<=fill_dirty;
        if(c_valid1&&c_tag1==fill_y)begin c_valid1<=0;c_dirty1<=0;end end
       c_next_bank<=!fill_c_bank;
      end
      if(fill_sequential)begin
       dma_next_y<=fill_y+1'b1;
       dma_advance_pending<=1;
       dma_advance_base<=fill_base;dma_advance_stride<=fill_stride;
       dma_advance_glyph<=glyph_line;
       dma_advance_bit_plane<=fill_bit_plane;
       dma_advance_compatibility<=fill_compatibility;
       dma_advance_lpr<=fill_lpr;
      end
      state<=IDLE;
    end
     default:state<=IDLE;
    endcase
   end
  end
 end

 reg [7:0] h_tag0_m=0,h_tag0_r=0,h_tag1_m=0,h_tag1_r=0;
 reg h_v0_m=0,h_v0_r=0,h_v1_m=0,h_v1_r=0;
 reg h_read_bank=0,h_read_valid=0;
 reg [9:0] h_read_addr=0;
 always @(posedge hdmi_read_clk)begin
  h_read_addr<=hdmi_read_x;
  h_tag0_m<=h_tag0;h_tag0_r<=h_tag0_m;h_tag1_m<=h_tag1;h_tag1_r<=h_tag1_m;
  h_v0_m<=h_valid0;h_v0_r<=h_v0_m;h_v1_m<=h_valid1;h_v1_r<=h_v1_m;
  if(!hdmi_display_valid)begin h_read_valid<=0;hdmi_pixel_data<=0;end
  else if(hdmi_read_x==0)begin
   // Select once at the physical scanline boundary.  A fill which completes
   // after pixel zero is deliberately deferred until the next scanline,
   // preventing the characteristic black-left/valid-right half line.
   if(h_v0_r&&h_tag0_r==hdmi_display_y)begin
    h_read_bank<=0;h_read_valid<=1;hdmi_pixel_data<=hdmi_line0[h_read_addr];end
   else if(h_v1_r&&h_tag1_r==hdmi_display_y)begin
    h_read_bank<=1;h_read_valid<=1;hdmi_pixel_data<=hdmi_line1[h_read_addr];end
   else begin h_read_valid<=0;hdmi_pixel_data<=0;end
  end else if(h_read_valid)begin
   if(h_read_bank)hdmi_pixel_data<=hdmi_line1[h_read_addr];
   else hdmi_pixel_data<=hdmi_line0[h_read_addr];
  end else hdmi_pixel_data<=0;
 end
 reg [7:0] c_tag0_m=0,c_tag0_r=0,c_tag1_m=0,c_tag1_r=0;
 reg c_v0_m=0,c_v0_r=0,c_v1_m=0,c_v1_r=0;
 reg c_read_bank=0,c_read_valid=0;
 reg [9:0] c_read_addr=0;
 always @(posedge cvbs_read_clk)begin
  // CVBS is always the 640-sample path in the CoCo 3 top.  Preload zero in
  // blanking, then request the following sample so the registered BSRAM
  // address does not add a visible horizontal pixel of delay.
  c_read_addr<=cvbs_display_valid ? cvbs_read_x+1'b1 : 10'd0;
  c_tag0_m<=c_tag0;c_tag0_r<=c_tag0_m;c_tag1_m<=c_tag1;c_tag1_r<=c_tag1_m;
  c_v0_m<=c_valid0;c_v0_r<=c_v0_m;c_v1_m<=c_valid1;c_v1_r<=c_v1_m;
  if(!cvbs_display_valid)begin c_read_valid<=0;cvbs_pixel_data<=0;end
  else if(cvbs_read_x==0)begin
   if(c_v0_r&&c_tag0_r==cvbs_display_y)begin
    c_read_bank<=0;c_read_valid<=1;cvbs_pixel_data<=cvbs_line0[c_read_addr];end
   else if(c_v1_r&&c_tag1_r==cvbs_display_y)begin
    c_read_bank<=1;c_read_valid<=1;cvbs_pixel_data<=cvbs_line1[c_read_addr];end
   else begin c_read_valid<=0;cvbs_pixel_data<=0;end
  end else if(c_read_valid)begin
   if(c_read_bank)cvbs_pixel_data<=cvbs_line1[c_read_addr];
   else cvbs_pixel_data<=cvbs_line0[c_read_addr];
  end else cvbs_pixel_data<=0;
 end
endmodule
