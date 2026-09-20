// Unified CoCo 3 scanline renderer. Mode decoding and row addressing follow
// the MiSTer/Gary Becker CoCo3FPGA core, but no framebuffer is used.
module gime_scanline_buffer (
 input clk,input reset_n,input bit_plane,input [3:0] hres,input [1:0] cres,
 input [2:0] lines_per_row_code,input [3:0] vertical_scroll,
 input [18:0] screen_base,input [7:0] horizontal_offset,input [95:0] palettes,
 input compatibility_mode,input compatibility_an_g,input [2:0] compatibility_gm,
 input compatibility_css,input blink,input cpu_write_strobe,input [18:0] cpu_write_addr,
 input hdmi_read_clk,input [9:0] hdmi_read_x,input [7:0] hdmi_display_y,
 input hdmi_display_valid,input [7:0] hdmi_prefetch_y,input hdmi_prefetch_valid,
 output reg [5:0] hdmi_pixel_data,
 input cvbs_read_clk,input [9:0] cvbs_read_x,input [7:0] cvbs_display_y,
 input cvbs_display_valid,input [7:0] cvbs_prefetch_y,input cvbs_prefetch_valid,
 output reg [5:0] cvbs_pixel_data,
 output reg memory_request,output reg [22:0] memory_addr,
 input [31:0] memory_data,input memory_valid
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
  input [2:0] gm;
  begin
   if(gm<=2)compatibility_lines_per_row=3;
   else if(gm<=4)compatibility_lines_per_row=2;
   else compatibility_lines_per_row=1;
  end
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
 function [5:0] blend_quarters;
  input [5:0] left;
  input [5:0] right;
  input [1:0] right_weight;
  reg [3:0] r_sum,g_sum,b_sum;
  begin
   // Rounded linear interpolation on each two-bit GIME colour component.
   // right_weight is 1, 2, or 3 quarters.
   r_sum=left[5:4]*(4-right_weight)+right[5:4]*right_weight+2;
   g_sum=left[3:2]*(4-right_weight)+right[3:2]*right_weight+2;
   b_sum=left[1:0]*(4-right_weight)+right[1:0]*right_weight+2;
   blend_quarters={r_sum[3:2],g_sum[3:2],b_sum[3:2]};
  end
 endfunction

 wire [9:0] native_graphics_bytes=graphics_row_bytes(hres);
 wire [7:0] native_columns=text_columns(hres);
 wire native_attributes=!bit_plane&&cres[0];
 wire [10:0] native_text_bytes=native_attributes?{2'b0,native_columns,1'b0}:
                                                  {3'b0,native_columns};
 wire [10:0] native_row_bytes=bit_plane?{1'b0,native_graphics_bytes}:native_text_bytes;
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
 reg [5:0] hdmi_line0[0:639],hdmi_line1[0:639];
 reg [5:0] cvbs_line0[0:639],cvbs_line1[0:639];
 reg h_valid0=0,h_valid1=0,c_valid0=0,c_valid1=0;
 reg h_dirty0=0,h_dirty1=0,c_dirty0=0,c_dirty1=0;
 reg [7:0] h_tag0=0,h_tag1=0,c_tag0=0,c_tag1=0;
 reg [18:0] h_start0=0,h_start1=0,c_start0=0,c_start1=0;
 reg [10:0] h_bytes0=0,h_bytes1=0,c_bytes0=0,c_bytes1=0;
 reg h_next_bank=0,c_next_bank=0;

 reg [7:0] hd_y_m=0,hd_y_s=0,hd_p_m=0,hd_p_s=0;
 reg hd_v_m=0,hd_v_s=0,hd_pv_m=0,hd_pv_s=0;
 reg [7:0] cv_y_m=0,cv_y_s=0,cv_p_m=0,cv_p_s=0;
 reg cv_v_m=0,cv_v_s=0,cv_pv_m=0,cv_pv_s=0;
 always @(posedge clk) begin
  hd_y_m<=hdmi_display_y;hd_y_s<=hd_y_m;hd_p_m<=hdmi_prefetch_y;hd_p_s<=hd_p_m;
  hd_v_m<=hdmi_display_valid;hd_v_s<=hd_v_m;hd_pv_m<=hdmi_prefetch_valid;hd_pv_s<=hd_pv_m;
  cv_y_m<=cvbs_display_y;cv_y_s<=cv_y_m;cv_p_m<=cvbs_prefetch_y;cv_p_s<=cv_p_m;
  cv_v_m<=cvbs_display_valid;cv_v_s<=cv_v_m;cv_pv_m<=cvbs_prefetch_valid;cv_pv_s<=cv_pv_m;
 end
 wire h_display_cached=(h_valid0&&h_tag0==hd_y_s)||(h_valid1&&h_tag1==hd_y_s);
 wire h_prefetch_cached=(h_valid0&&!h_dirty0&&h_tag0==hd_p_s)||
                         (h_valid1&&!h_dirty1&&h_tag1==hd_p_s);
 wire c_display_cached=(c_valid0&&c_tag0==cv_y_s)||(c_valid1&&c_tag1==cv_y_s);
 wire c_prefetch_cached=(c_valid0&&!c_dirty0&&c_tag0==cv_p_s)||
                         (c_valid1&&!c_dirty1&&c_tag1==cv_p_s);
 wire h_need=(hd_v_s&&!h_display_cached)||(hd_pv_s&&!h_prefetch_cached);
 wire c_need=(cv_v_s&&!c_display_cached)||(cv_pv_s&&!c_prefetch_cached);
 wire [7:0] h_need_y=(hd_v_s&&!h_display_cached)?hd_y_s:hd_p_s;
 wire [7:0] c_need_y=(cv_v_s&&!c_display_cached)?cv_y_s:cv_p_s;
 reg h_pending=0,c_pending=0;reg [7:0] h_pending_y=0,c_pending_y=0;
 reg [2:0] coalesce_count=0;

 reg fill_hdmi=0,fill_cvbs=0,fill_h_bank=0,fill_c_bank=0;
 reg [7:0] fill_y=0; reg fill_bit_plane=0; reg [1:0] fill_cres=0;
 reg fill_attributes=0;reg [2:0] fill_gm=0;reg fill_css=0;
 reg fill_compatibility=0,fill_blink=0;reg [7:0] fill_lpr=1;
 reg [10:0] fill_stride=0,fill_row_bytes=0;reg [12:0] fill_source_width=0;
 reg [3:0] fill_scale_integer=0;reg [9:0] fill_scale_remainder=0;
 reg [18:0] fill_base=0;reg [6:0] fill_hoff=0;reg [95:0] fill_palettes=0;
 reg [8:0] row_remainder=0;reg [7:0] source_row=0;reg [3:0] glyph_line=0;
 reg [9:0] out_x=0;reg [12:0] source_x=0;reg [13:0] scale_phase=0;
 reg [9:0] hdmi_out_x=0;reg [2:0] hdmi_filter_phase=0;
 reg [5:0] hdmi_filter_previous=0;
 reg [18:0] row_address=0,line_address=0,byte_address=0;
 reg [31:0] word_cache=0;reg [18:0] word_tag=0;reg word_valid=0;
 reg [7:0] character=0,attribute=0,glyph_cache=0;reg fill_dirty=0;
 reg text_cache_valid=0,graphics_cache_valid=0;
 reg [7:0] text_cache_column=0;reg [11:0] graphics_cache_index=0;

 wire [11:0] graphics_byte_index=fill_cres==0?source_x[12:3]:
  fill_cres==1?source_x[12:2]:source_x[12:1];
 wire [7:0] character_column=source_x[10:3];
 wire [18:0] pixel_byte_index=fill_bit_plane?{7'd0,graphics_byte_index}:
  fill_attributes?{10'd0,character_column,1'b0}:{11'd0,character_column};
 wire [18:0] calculated_byte_address=line_address+pixel_byte_index;
 wire [18:0] aligned_address={byte_address[18:2],2'b0};
 wire [7:0] cached_byte=byte_address[1:0]==0?word_cache[7:0]:
  byte_address[1:0]==1?word_cache[15:8]:byte_address[1:0]==2?word_cache[23:16]:word_cache[31:24];
 reg [11:0] font_addr=0;wire [7:0] font_data;
 coco3_char_rom font(.clk(clk),.addr(font_addr),.data(font_data));

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
     decoded_index=decoded_pixel?{1'b0,attribute[5:3]}:{1'b1,attribute[2:0]};
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
  CHECK_WORD=5,WAIT_WORD=6,GOT_CHARACTER=7,CHECK_ATTRIBUTE=8,WAIT_ATTRIBUTE=9,
  FONT_WAIT1=10,FONT_WAIT2=11,DECODE_PIXEL=12,COLOR_LOOKUP=13,WRITE_PIXEL=14;
 reg [3:0] state=IDLE;reg [13:0] phase_sum;reg [5:0] pixel_latched;
 reg [3:0] color_index_latched=0;reg [5:0] color_code_latched=0;
 wire write_hits_h0=h_valid0&&cpu_write_addr>=h_start0&&cpu_write_addr<h_start0+h_bytes0;
 wire write_hits_h1=h_valid1&&cpu_write_addr>=h_start1&&cpu_write_addr<h_start1+h_bytes1;
 wire write_hits_c0=c_valid0&&cpu_write_addr>=c_start0&&cpu_write_addr<c_start0+c_bytes0;
 wire write_hits_c1=c_valid1&&cpu_write_addr>=c_start1&&cpu_write_addr<c_start1+c_bytes1;
 wire write_hits_fill=state!=IDLE&&cpu_write_addr>=line_address&&
                      cpu_write_addr<line_address+fill_row_bytes;
 reg [16:0] mode_signature=17'h1ffff;reg [18:0] last_screen_base=19'h7ffff;
 reg [7:0] last_horizontal_offset=8'hff;reg [3:0] last_vertical_scroll=4'hf;
 wire [16:0] live_signature={compatibility_mode,compatibility_an_g,compatibility_gm,
  compatibility_css,bit_plane,hres,cres,lines_per_row_code,1'b0};
 wire configuration_diff=live_signature!=mode_signature||screen_base!=last_screen_base||
  horizontal_offset!=last_horizontal_offset||vertical_scroll!=last_vertical_scroll;
 reg configuration_diff_q=1'b1;

 always @(posedge clk or negedge reset_n) begin
  if(!reset_n) begin
   state<=IDLE;memory_request<=0;memory_addr<=0;h_valid0<=0;h_valid1<=0;
   c_valid0<=0;c_valid1<=0;h_dirty0<=0;h_dirty1<=0;c_dirty0<=0;c_dirty1<=0;
   mode_signature<=17'h1ffff;last_screen_base<=19'h7ffff;
   last_horizontal_offset<=8'hff;last_vertical_scroll<=4'hf;
   h_next_bank<=0;c_next_bank<=0;fill_dirty<=0;configuration_diff_q<=1'b1;
   h_pending<=0;c_pending<=0;coalesce_count<=0;
  end else begin
   // Register the wide mode comparison before it controls the renderer.  A
   // one-cycle-later flush is harmless and avoids making that comparison the
   // select input for nearly every state register in this 108 MHz block.
   configuration_diff_q<=configuration_diff;
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
   if(configuration_diff_q) begin
    mode_signature<=live_signature;last_screen_base<=screen_base;
    last_horizontal_offset<=horizontal_offset;last_vertical_scroll<=vertical_scroll;
    h_valid0<=0;h_valid1<=0;c_valid0<=0;c_valid1<=0;
    h_dirty0<=0;h_dirty1<=0;c_dirty0<=0;c_dirty1<=0;
    state<=IDLE;memory_request<=0;word_valid<=0;h_pending<=0;c_pending<=0;
    coalesce_count<=0;
   end else case(state)
    IDLE:if(h_pending&&coalesce_count==3'd7) begin
     // A row selected by the HDMI master is mirrored into both output RAMs.
     // CVBS therefore consumes the same immutable row without initiating a
     // second render or changing either cache's replacement order.
     fill_y<=h_pending_y;
     fill_hdmi<=1;fill_cvbs<=1;
     h_pending<=0;c_pending<=0;
     coalesce_count<=0;
     fill_h_bank<=(h_valid0&&h_tag0==h_pending_y)?1:
                  (h_valid1&&h_tag1==h_pending_y)?0:h_next_bank;
     fill_c_bank<=(c_valid0&&c_tag0==h_pending_y)?1:
                  (c_valid1&&c_tag1==h_pending_y)?0:c_next_bank;
     fill_bit_plane<=bit_plane;
     fill_cres<=compatibility_mode&&compatibility_an_g?
      ((compatibility_gm==0||compatibility_gm==2||compatibility_gm==4||compatibility_gm==6)?1:0):cres;
     fill_attributes<=!compatibility_mode&&native_attributes;
     fill_gm<=compatibility_gm;fill_css<=compatibility_css;
     fill_compatibility<=compatibility_mode;fill_blink<=blink;
     fill_lpr<=compatibility_mode?(!compatibility_an_g?12:
      compatibility_lines_per_row(compatibility_gm)):native_lines_per_row(lines_per_row_code);
     fill_stride<=live_stride;fill_row_bytes<=live_row_bytes;
     fill_source_width<=live_source_width;fill_base<=screen_base;
     fill_scale_integer<=scale_integer(live_source_width);
     fill_scale_remainder<=scale_remainder(live_source_width);
     fill_hoff<=horizontal_offset[6:0];fill_palettes<=palettes;
     row_remainder<={1'b0,h_pending_y}+
                    (compatibility_mode?9'd0:{5'd0,vertical_scroll});
     source_row<=0;word_valid<=0;fill_dirty<=0;text_cache_valid<=0;
     graphics_cache_valid<=0;state<=DIVIDE_ROW;
    end
    DIVIDE_ROW:begin
     if(row_remainder>=fill_lpr)begin row_remainder<=row_remainder-fill_lpr;
      source_row<=source_row+1'b1;end
     else begin glyph_line<=row_remainder[3:0];state<=ROW_ADDRESS;end
    end
    ROW_ADDRESS:begin row_address<=source_row*fill_stride;out_x<=0;source_x<=0;
     scale_phase<=0;hdmi_out_x<=0;hdmi_filter_phase<=0;
     hdmi_filter_previous<=0;state<=LINE_ADDRESS;end
    LINE_ADDRESS:begin line_address<=fill_base+row_address+{11'd0,fill_hoff,1'b0};
     state<=PIXEL_ADDRESS;end
    PIXEL_ADDRESS:begin
     if(fill_bit_plane&&graphics_cache_valid&&graphics_cache_index==graphics_byte_index)
      state<=DECODE_PIXEL;
     else if(!fill_bit_plane&&text_cache_valid&&text_cache_column==character_column)
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
       text_cache_column<=character_column;text_cache_valid<=1;state<=DECODE_PIXEL;
      end
      else begin
       if(fill_compatibility)begin
        if(fill_gm[0]&&cached_byte[6:5]==0)
         font_addr<={1'b1,2'b11,cached_byte[4:0],glyph_line};
        else font_addr<={1'b1,~cached_byte[5],cached_byte[5:0],glyph_line};
       end else font_addr<={1'b0,cached_byte[6:0],glyph_line};
       state<=FONT_WAIT1;
      end
     end else begin graphics_cache_index<=graphics_byte_index;
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
    FONT_WAIT2:begin glyph_cache<=font_data;text_cache_column<=character_column;
     text_cache_valid<=1;state<=DECODE_PIXEL;end
    DECODE_PIXEL:begin
     color_index_latched<=decoded_index;color_code_latched<=decoded_code;
     state<=COLOR_LOOKUP;
    end
    COLOR_LOOKUP:begin
     pixel_latched<=palette_rgb(fill_compatibility?color_code_latched:
       fill_palettes[color_index_latched*6+:6]);
     state<=WRITE_PIXEL;
    end
    WRITE_PIXEL:begin
     // Area-preserving 640 -> 512 horizontal filter for HDMI.  For every
     // five canonical pixels emit four samples at phases 0, 1.25, 2.5 and
     // 3.75.  CVBS retains the original 640-dot row.  This is a streaming
     // operation performed while the row is rendered, not a framebuffer.
     if(fill_hdmi)begin
      if(hdmi_filter_phase==0)begin
       if(fill_h_bank)hdmi_line1[hdmi_out_x]<=pixel_latched;
       else hdmi_line0[hdmi_out_x]<=pixel_latched;
       hdmi_out_x<=hdmi_out_x+1'b1;
      end else if(hdmi_filter_phase==2)begin
       if(fill_h_bank)hdmi_line1[hdmi_out_x]<=
        blend_quarters(hdmi_filter_previous,pixel_latched,2'd1);
       else hdmi_line0[hdmi_out_x]<=
        blend_quarters(hdmi_filter_previous,pixel_latched,2'd1);
       hdmi_out_x<=hdmi_out_x+1'b1;
      end else if(hdmi_filter_phase==3)begin
       if(fill_h_bank)hdmi_line1[hdmi_out_x]<=
        blend_quarters(hdmi_filter_previous,pixel_latched,2'd2);
       else hdmi_line0[hdmi_out_x]<=
        blend_quarters(hdmi_filter_previous,pixel_latched,2'd2);
       hdmi_out_x<=hdmi_out_x+1'b1;
      end else if(hdmi_filter_phase==4)begin
       if(fill_h_bank)hdmi_line1[hdmi_out_x]<=
        blend_quarters(hdmi_filter_previous,pixel_latched,2'd3);
       else hdmi_line0[hdmi_out_x]<=
        blend_quarters(hdmi_filter_previous,pixel_latched,2'd3);
       hdmi_out_x<=hdmi_out_x+1'b1;
      end
     end
     if(fill_cvbs)begin if(fill_c_bank)cvbs_line1[out_x]<=pixel_latched;
                      else cvbs_line0[out_x]<=pixel_latched;end
     hdmi_filter_previous<=pixel_latched;
     hdmi_filter_phase<=(hdmi_filter_phase==4)?0:hdmi_filter_phase+1'b1;
     if(out_x==CANONICAL_WIDTH-1'b1)begin
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
     state<=IDLE;
     end else begin
      out_x<=out_x+1'b1;phase_sum=scale_phase+fill_scale_remainder;
      source_x<=source_x+fill_scale_integer+(phase_sum>=14'd640);
      scale_phase<=(phase_sum>=14'd640)?(phase_sum-14'd640):phase_sum;
      state<=PIXEL_ADDRESS;
     end
    end
    default:state<=IDLE;
   endcase
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
