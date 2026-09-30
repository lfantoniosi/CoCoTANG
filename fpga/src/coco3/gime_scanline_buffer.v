// Unified CoCo 3 scanline renderer. Mode decoding and row addressing follow
// the MiSTer/Gary Becker CoCo3FPGA core, but no framebuffer is used.
module gime_scanline_buffer (
 input clk,input reset_n,input bit_plane,input [3:0] hres,input [1:0] cres,
 input [2:0] lines_per_row_code,input [3:0] vertical_scroll,
 input [18:0] screen_base,input [1:0] video_bank,
 input [7:0] horizontal_offset,input [95:0] palettes,input [5:0] border_rgb,
 input compatibility_mode,input compatibility_an_g,input [2:0] compatibility_gm,
 input [2:0] compatibility_sam_mode,
 input compatibility_css,
 input compatibility_raster_write,input [7:0] compatibility_raster_y,
 input [4:0] compatibility_raster_byte,input compatibility_raster_css,
 input compatibility_border_write,input compatibility_border_right,
 input [8:0] compatibility_border_y,input [5:0] compatibility_border_rgb,
 input [1:0] artifact_mode,input blink,
 input cpu_write_strobe,input [20:0] cpu_write_addr,
 input hdmi_read_clk,input [9:0] hdmi_read_x,input [7:0] hdmi_display_y,
 input hdmi_frame_start,input hdmi_active_50hz,
 input [8:0] hdmi_border_raster_y,
 input hdmi_display_valid,input hdmi_picture_active,
 input [7:0] hdmi_prefetch_y,input hdmi_prefetch_valid,
 output reg [23:0] hdmi_pixel_data,
 output reg [5:0] hdmi_left_border_data,output reg [5:0] hdmi_right_border_data,
 output reg hdmi_border_valid,
 output reg [5:0] hdmi_vertical_left_border_data,
 output reg [5:0] hdmi_vertical_right_border_data,
 output reg hdmi_vertical_border_valid,
 input cvbs_read_clk,input [9:0] cvbs_read_x,input [7:0] cvbs_display_y,
 input cvbs_display_valid,input [7:0] cvbs_prefetch_y,input cvbs_prefetch_valid,
 input [8:0] cvbs_border_raster_y,
 output reg [5:0] cvbs_pixel_data,output reg [5:0] cvbs_border_data,
 output reg [5:0] cvbs_right_border_data,
 output reg cvbs_border_valid,
 output reg [5:0] cvbs_vertical_left_border_data,
 output reg [5:0] cvbs_vertical_right_border_data,
 output reg cvbs_vertical_border_valid,
 output reg memory_request,output reg [22:0] memory_addr,
 input [31:0] memory_data,input memory_valid,
 output [7:0] debug_dma_next_y,output [7:0] debug_fill_y,
 output [3:0] debug_state,
 output [7:0] trace_cache_y,output trace_cache_valid,
 output [20:0] trace_cache_start,
 output [18:0] trace_dma_next_address,
 output [3:0] trace_dma_line
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
 function [3:0] scale_integer_512;
  input [12:0] width;
  begin case(width)
   13'd512:scale_integer_512=1;13'd640:scale_integer_512=1;
   13'd1024:scale_integer_512=2;13'd1280:scale_integer_512=2;
   13'd2048:scale_integer_512=4;13'd2560:scale_integer_512=5;
   13'd4096:scale_integer_512=8;13'd5120:scale_integer_512=10;
   default:scale_integer_512=0;
  endcase end
 endfunction
 function [9:0] scale_remainder_512;
  input [12:0] width;
  begin case(width)
   13'd640:scale_remainder_512=128;
   13'd1280:scale_remainder_512=256;
   13'd512,13'd1024,13'd2048,13'd2560,13'd4096,13'd5120:
    scale_remainder_512=0;
   default:scale_remainder_512=width[9:0];
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
 reg [5:0] cvbs_line0[0:639],cvbs_line1[0:639],cvbs_line2[0:639];
 reg h_valid0=0,h_valid1=0,c_valid0=0,c_valid1=0,c_valid2=0;
 reg h_dirty0=0,h_dirty1=0,c_dirty0=0,c_dirty1=0,c_dirty2=0;
 reg [7:0] h_tag0=0,h_tag1=0,c_tag0=0,c_tag1=0,c_tag2=0;
 reg [20:0] h_start0=0,h_start1=0,c_start0=0,c_start1=0,c_start2=0;
 reg [10:0] h_bytes0=0,h_bytes1=0,c_bytes0=0,c_bytes1=0,c_bytes2=0;
 reg [5:0] h_left_border0=0,h_left_border1=0;
 reg [5:0] h_right_border0=0,h_right_border1=0;
 reg [5:0] c_border0=0,c_border1=0,c_border2=0;
 reg [5:0] c_right_border0=0,c_right_border1=0,c_right_border2=0;
 reg h_next_bank=0;
 reg [1:0] c_next_bank=0;

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
 wire c_display_cached=(c_valid0&&c_tag0==cv_y_s)||
                        (c_valid1&&c_tag1==cv_y_s)||
                        (c_valid2&&c_tag2==cv_y_s);
 wire c_prefetch_cached=(c_valid0&&c_tag0==cv_p_s)||
                         (c_valid1&&c_tag1==cv_p_s)||
                         (c_valid2&&c_tag2==cv_p_s);
 wire h_need=(hd_v_s&&!h_display_cached)||(hd_pv_s&&!h_prefetch_cached);
 wire c_need=(cv_v_s&&!c_display_cached)||(cv_pv_s&&!c_prefetch_cached);
 wire [7:0] h_need_y=(hd_v_s&&!h_display_cached)?hd_y_s:hd_p_s;
 wire [7:0] c_need_y=(cv_v_s&&!c_display_cached)?cv_y_s:cv_p_s;
 // Prefer an unused CVBS bank.  Once all three are live, advance round-robin
 // but skip the bank selected by the current scanline.  Three retained rows
 // cover the one-line phase excursion of alternating 262/263-line fields.
 // During horizontal blank source_valid is low even though the analogue
 // consumer is about to scan the same logical row.  prefetch_y remains N+1,
 // so use it to protect N across the complete line.  Otherwise a change in
 // render duration (notably 256 -> 320 dots) can make round-robin replacement
 // overwrite the row just before component/CVBS starts reading it.
 wire cv_line_active=cv_v_s||(cv_pv_s&&cv_p_s!=0);
 wire [7:0] cv_active_y=cv_v_s?cv_y_s:(cv_p_s-1'b1);
 wire h_keep_tag0=h_valid0&&hd_pa_s&&
                  ((h_tag0==hd_y_s)||(hd_pv_s&&h_tag0==hd_p_s));
 wire h_keep_tag1=h_valid1&&hd_pa_s&&
                  ((h_tag1==hd_y_s)||(hd_pv_s&&h_tag1==hd_p_s));
 // The CVBS RAM is a mirror written by the HDMI-mastered renderer.  Across a
 // raster configuration write it must retain every row which HDMI retains,
 // even when analogue scanout is one row behind.  Otherwise HDMI continues
 // to report its prefetch as cached and never recreates the invalidated
 // analogue copy.  Also retain the row analogue is consuming so its bank
 // cannot be selected for replacement before that physical line completes.
 wire c_keep_tag0=(h_keep_tag0&&c_tag0==h_tag0)||
                  (h_keep_tag1&&c_tag0==h_tag1)||
                  (cv_line_active&&((c_tag0==cv_active_y)||
                                    (cv_pv_s&&c_tag0==cv_p_s)));
 wire c_keep_tag1=(h_keep_tag0&&c_tag1==h_tag0)||
                  (h_keep_tag1&&c_tag1==h_tag1)||
                  (cv_line_active&&((c_tag1==cv_active_y)||
                                    (cv_pv_s&&c_tag1==cv_p_s)));
 wire c_keep_tag2=(h_keep_tag0&&c_tag2==h_tag0)||
                  (h_keep_tag1&&c_tag2==h_tag1)||
                  (cv_line_active&&((c_tag2==cv_active_y)||
                                    (cv_pv_s&&c_tag2==cv_p_s)));
 // The HDMI producer will not re-render a row still held in its own cache.
 // Evicting that row from the analogue mirror makes a later CVBS read blank,
 // even though HDMI remains correct. Prefer a bank not held by either output,
 // rotating the preference to spread writes across the three RAMs.
 // Requests are coalesced for seven clocks. Pipeline the cross-clock tag
 // comparisons before the replacement priority mux; their choice still
 // settles before the request can start a fill.
 reg c_keep_tag0_q=0,c_keep_tag1_q=0,c_keep_tag2_q=0;
 always @(posedge clk)begin
  c_keep_tag0_q<=c_keep_tag0;
  c_keep_tag1_q<=c_keep_tag1;
  c_keep_tag2_q<=c_keep_tag2;
 end
 wire c_free0=!c_valid0||!c_keep_tag0_q;
 wire c_free1=!c_valid1||!c_keep_tag1_q;
 wire c_free2=!c_valid2||!c_keep_tag2_q;
 reg [1:0] c_replacement_bank=0;
 always @* begin
  if(!c_valid0)c_replacement_bank=2'd0;
  else if(!c_valid1)c_replacement_bank=2'd1;
  else if(!c_valid2)c_replacement_bank=2'd2;
  else case(c_next_bank)
   2'd0:c_replacement_bank=c_free0?2'd0:c_free1?2'd1:
                            c_free2?2'd2:2'd0;
   2'd1:c_replacement_bank=c_free1?2'd1:c_free2?2'd2:
                            c_free0?2'd0:2'd1;
   2'd2:c_replacement_bank=c_free2?2'd2:c_free0?2'd0:
                            c_free1?2'd1:2'd2;
   default:c_replacement_bank=2'd0;
  endcase
 end
 reg [1:0] c_replacement_bank_q=0;
 reg h_pending=0,c_pending=0;reg [7:0] h_pending_y=0,c_pending_y=0;
 reg [2:0] coalesce_count=0;

 reg fill_hdmi=0,fill_cvbs=0,fill_h_bank=0;
 reg [1:0] fill_c_bank=0;
 reg fill_sequential=0;
 reg [7:0] fill_y=0; reg fill_bit_plane=0; reg [1:0] fill_cres=0;
 reg fill_attributes=0;reg [2:0] fill_gm=0;reg fill_css=0;
 reg fill_compatibility=0,fill_blink=0;reg [1:0] fill_artifact_mode=0;
 reg fill_raster_css_valid=0;
 reg fill_left_css=0,fill_right_css=0;
 reg [7:0] fill_lpr=1;
 reg [10:0] fill_stride=0,fill_row_bytes=0;reg [12:0] fill_source_width=0;
 reg [3:0] fill_scale_integer=0;reg [9:0] fill_scale_remainder=0;
 reg fill_narrow_aperture=0;reg [5:0] fill_border_rgb=0;
 reg [18:0] fill_base=0;reg [6:0] fill_hoff=0;reg [95:0] fill_palettes=0;
 reg [1:0] fill_video_bank=0;
 reg [8:0] row_remainder=0;reg [7:0] source_row=0;reg [3:0] glyph_line=0;
 reg [9:0] out_x=0;reg [12:0] source_x=0;reg [9:0] scale_phase=0;
 // Cache the byte/character indices alongside source_x.  Deriving them
 // through the colour-resolution mux in PIXEL_ADDRESS put that mux, the
 // row-address adder and the cache-tag comparison on one 108 MHz path.
 reg [11:0] source_byte_index=0;
 reg [7:0] source_character_column=0;
 reg [9:0] hdmi_out_x=0;reg [2:0] hdmi_filter_phase=0;
 reg [255:0] artifact_bits=0;
 reg [260:0] artifact_shift=0;
 reg artifact_bit_write_pending=0;
 reg [7:0] artifact_bit_write_addr=0;
 reg artifact_bit_write_data=0;
 reg [18:0] row_address=0,line_address=0,byte_address=0;
 reg [31:0] word_cache=0;reg [18:0] word_tag=0;reg word_valid=0;
 reg [7:0] character=0,attribute=0,glyph_cache=0;reg fill_dirty=0;
 reg text_cache_valid=0,graphics_cache_valid=0;
 reg [7:0] text_cache_column=0;reg [11:0] graphics_cache_index=0;

 initial begin
  hdmi_left_border_data=0;
  hdmi_right_border_data=0;
  hdmi_border_valid=0;
  hdmi_vertical_left_border_data=0;
  hdmi_vertical_right_border_data=0;
  hdmi_vertical_border_valid=0;
  cvbs_vertical_left_border_data=0;
  cvbs_vertical_right_border_data=0;
  cvbs_vertical_border_valid=0;
  cvbs_right_border_data=0;
 end

 // One captured CSS bit per VDG source byte. The physical raster samples
 // $FF22 while this renderer can run ahead, so the completed field is read
 // from the opposite bank on the next field.
 reg compatibility_css_raster[0:16383];
 reg compatibility_css_capture_bank=0;
 reg compatibility_css_capture_started=0;
 reg compatibility_css_display_valid=0;
 reg [13:0] compatibility_css_read_addr=0;
 reg compatibility_css_read_data=0;
 wire compatibility_css_frame_start=compatibility_raster_write&&
       compatibility_raster_y==8'd0&&compatibility_raster_byte==5'd0;
 wire compatibility_css_write_bank=compatibility_css_frame_start?
       !compatibility_css_capture_bank:compatibility_css_capture_bank;
 wire compatibility_css_display_bank=!compatibility_css_capture_bank;
 always @(posedge clk or negedge reset_n) begin
  if(!reset_n)begin
   compatibility_css_capture_bank<=0;
   compatibility_css_capture_started<=0;
   compatibility_css_display_valid<=0;
   compatibility_css_read_data<=0;
  end else if(!compatibility_mode)begin
   compatibility_css_capture_started<=0;
   compatibility_css_display_valid<=0;
  end else begin
   if(compatibility_raster_write)begin
    compatibility_css_raster[{compatibility_css_write_bank,
                              compatibility_raster_y,
                              compatibility_raster_byte}]<=compatibility_raster_css;
    if(compatibility_css_frame_start)begin
     compatibility_css_capture_bank<=!compatibility_css_capture_bank;
     compatibility_css_capture_started<=1'b1;
     if(compatibility_css_capture_started)
      compatibility_css_display_valid<=1'b1;
    end
   end
   compatibility_css_read_data<=compatibility_css_raster[compatibility_css_read_addr];
  end
 end
 wire pixel_compatibility_css=fill_raster_css_valid?
                              compatibility_css_read_data:fill_css;
 wire fill_artifact_border=fill_compatibility&&fill_bit_plane&&
                           fill_gm==3'd7&&fill_artifact_mode!=0;
 wire [5:0] rendered_left_border=!fill_compatibility?fill_border_rgb:
  !fill_bit_plane?6'd0:fill_artifact_border?
  (fill_left_css?6'h3e:6'h18):(fill_left_css?6'h3f:6'h0c);
 wire [5:0] rendered_right_border=!fill_compatibility?fill_border_rgb:
  !fill_bit_plane?6'd0:fill_artifact_border?
  (fill_right_css?6'h3e:6'h18):(fill_right_css?6'h3f:6'h0c);

 // Vertical borders have no rendered picture row to carry CSS. Capture
 // their actual VDG raster colours before HDMI consumes them, so the small
 // VDG/HDMI frame-rate difference cannot make a live FF22 change sweep from
 // the bottom border through the top of the next frame.
 reg [5:0] compatibility_border_left[0:1023];
 reg [5:0] compatibility_border_right_rgb[0:1023];
 reg compatibility_border_capture_bank=0;
 reg compatibility_border_capture_started=0;
 reg compatibility_border_display_valid=0;
 wire compatibility_border_frame_start=compatibility_border_write&&
       !compatibility_border_right&&compatibility_border_y==9'd0;
 wire compatibility_border_write_bank=compatibility_border_frame_start?
       !compatibility_border_capture_bank:compatibility_border_capture_bank;
 wire compatibility_border_display_bank=!compatibility_border_capture_bank;
 always @(posedge clk or negedge reset_n) begin
  if(!reset_n)begin
   compatibility_border_capture_bank<=0;
   compatibility_border_capture_started<=0;
   compatibility_border_display_valid<=0;
  end else if(!compatibility_mode)begin
   compatibility_border_capture_started<=0;
   compatibility_border_display_valid<=0;
  end else if(compatibility_border_write)begin
   if(compatibility_border_right)
    compatibility_border_right_rgb[{compatibility_border_write_bank,
                                    compatibility_border_y}]<=compatibility_border_rgb;
   else
    compatibility_border_left[{compatibility_border_write_bank,
                               compatibility_border_y}]<=compatibility_border_rgb;
   if(compatibility_border_frame_start)begin
    compatibility_border_capture_bank<=!compatibility_border_capture_bank;
    compatibility_border_capture_started<=1;
    if(compatibility_border_capture_started)
     compatibility_border_display_valid<=1;
   end
  end
 end

 // Both terms are strictly below 640, so eleven bits cover the complete
 // 0..1278 sum.  Keeping this at fourteen bits needlessly lengthened the
 // source-index update carry chain on the 108 MHz renderer clock.
 wire [10:0] next_scale_phase_sum={1'b0,scale_phase}+
                                  {1'b0,fill_scale_remainder};
 wire [12:0] next_source_x=source_x+fill_scale_integer+
     (next_scale_phase_sum>=(fill_narrow_aperture?11'd512:11'd640));
 wire in_fill_aperture=!fill_narrow_aperture||
                       (out_x>=10'd64&&out_x<10'd576);
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
   decoded_code=fill_cres==0?(decoded_index[0]?vdg_code({pixel_compatibility_css,2'b0}):0):
                              vdg_code({pixel_compatibility_css,decoded_index[1:0]});
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
    semigraphics_color={pixel_compatibility_css,character[7:6]};
   end else begin
    if(glyph_line<6)semigraphics_pixel=source_x[2]?character[2]:character[3];
    else semigraphics_pixel=source_x[2]?character[0]:character[1];
    semigraphics_color=character[6:4];
   end
   decoded_code=semigraphics_pixel?vdg_code(semigraphics_color):
                                    (pixel_compatibility_css?6'd4:6'd2);
  end else begin
   decoded_pixel=(~decoded_pixel)^inverse_character;
   decoded_code=decoded_pixel?vdg_code(pixel_compatibility_css?3'd7:3'd0):
                              (pixel_compatibility_css?6'd4:6'd2);
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
 wire write_hits_c2=c_valid2&&cpu_write_addr>=c_start2&&cpu_write_addr<c_start2+c_bytes2;
wire [20:0] fill_physical_start={fill_video_bank,line_address};
wire write_hits_fill=state!=IDLE&&cpu_write_addr>=fill_physical_start&&
                      cpu_write_addr<fill_physical_start+fill_row_bytes;
reg [18:0] mode_signature=19'h7ffff;reg [18:0] last_screen_base=19'h7ffff;
reg [18:0] frame_screen_base=0;
reg [1:0] frame_video_bank=0,last_video_bank=0;
 // Running GIME DMA state.  This cannot be reconstructed as y*stride when
 // FF98.LPR or FF9F.HVEN changes during the picture: each raster advances
 // from the address left by the preceding raster.
 reg [7:0] dma_next_y=0;
 reg [18:0] dma_next_address=0;
 reg [3:0] dma_line_in_row=0;
 // HBORD computes the completed row's advance, but VBORD applies it after
 // early-left-border FF98 writes.
 reg dma_advance_pending=0;
 reg [18:0] dma_advance_base=0;
 reg [10:0] dma_advance_stride=0;
 reg [3:0] dma_advance_glyph=0;
 reg dma_advance_bit_plane=0,dma_advance_compatibility=0;
 reg [7:0] dma_advance_lpr=1;
wire dma_advance_infinite=dma_advance_compatibility?
  dma_advance_lpr==8'hff:
  lines_per_row_code==3'b111;
wire dma_advance_row=dma_advance_compatibility?
  dma_advance_glyph+1'b1>=dma_advance_lpr:
   native_advance_row(lines_per_row_code,dma_advance_glyph);
wire [18:0] advanced_dma_address=
  dma_advance_bit_plane&&dma_advance_infinite ? dma_advance_base :
  dma_advance_row ? (dma_advance_base+dma_advance_stride) :
                          dma_advance_base;
wire [3:0] advanced_dma_line=
  (dma_advance_bit_plane&&dma_advance_infinite)||dma_advance_row ?
  4'd0 : dma_advance_glyph+1'b1;
 reg upper_border_q=0;
 reg hdmi_frame_meta=0,hdmi_frame_sync=0,hdmi_frame_prev=0;
 reg upper_border_active=0;
 reg upper_border_setup_abort=0;
 reg [3:0] frame_initial_scroll=0;
 reg [2:0] frame_initial_lpr=0;
 wire hdmi_frame_rise=hdmi_frame_sync&&!hdmi_frame_prev;
 // Track the entire upper border, not just the last source-row prefetch.
 // VOFF/VSC setup writes can occur well before that narrow prefetch window.
 wire upper_border=(upper_border_active&&!hd_pa_s)||
                   (hd_pv_s&&hd_p_s==0&&!hd_v_s);
 reg hdmi_50_meta=0,hdmi_50_sync=0,hdmi_50_prev=0;
 wire hdmi_standard_changed=hdmi_50_sync!=hdmi_50_prev;
 wire upper_border_setup_changed=upper_border&&
   (!upper_border_q||screen_base!=frame_screen_base||
    video_bank!=frame_video_bank||
    vertical_scroll!=frame_initial_scroll||
    lines_per_row_code!=frame_initial_lpr);
 // LPR is a raster control.  BOINK switches it to 111 to hold the current
 // DMA row and back to 000 to advance it.  It must be sampled for the next
 // fill, not treated as a mode change which aborts the renderer and flushes
 // its two immutable scanline buffers.
 wire [18:0] live_signature={artifact_mode,compatibility_mode,compatibility_an_g,
  compatibility_gm,(compatibility_mode?1'b0:compatibility_css),bit_plane,hres,cres,
  compatibility_sam_mode,1'b0};
 // FF9C vertical fine scroll is a raster control, just like FF98.LPR.  It is
 // sampled when a row fill begins; changing it must not abort that fill or
 // invalidate the row currently being scanned.  Doing so can blank only the
 // first of HDMI's two copies of a native row, producing a one-pixel-high
 // horizontal gap in raster demos.
wire configuration_diff=live_signature!=mode_signature||
  frame_screen_base!=last_screen_base||frame_video_bank!=last_video_bank;
reg configuration_pending=1'b1;
 assign debug_dma_next_y=dma_next_y;
 assign debug_fill_y=fill_y;
 assign debug_state=state[3:0];
 assign trace_cache_y=hd_y_s;
 assign trace_cache_valid=(h_valid0&&h_tag0==hd_y_s)||
                          (h_valid1&&h_tag1==hd_y_s);
 assign trace_cache_start=(h_valid0&&h_tag0==hd_y_s)?h_start0:
                          (h_valid1&&h_tag1==hd_y_s)?h_start1:21'd0;
 assign trace_dma_next_address=dma_next_address;
 assign trace_dma_line=dma_line_in_row;

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
 reg [1:0] cvbs_write_bank=0;
 reg [9:0] cvbs_write_x=0;
 reg [5:0] cvbs_write_data=0;
 always @(posedge clk) begin
  // The renderer first registers a complete write command so the inferred
  // line RAM has a short, timing-safe data path.
  hdmi_write_pending<=0;
  cvbs_write_pending<=0;
  if(renderer_write)begin
   if(fill_hdmi)begin
    if(!renderer_artifact||hdmi_filter_phase!=1)begin
     hdmi_write_pending<=1;
     hdmi_write_data<=renderer_hdmi_pixel;
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
   case(cvbs_write_bank)
    2'd0:cvbs_line0[cvbs_write_x]<=cvbs_write_data;
    2'd1:cvbs_line1[cvbs_write_x]<=cvbs_write_data;
    default:cvbs_line2[cvbs_write_x]<=cvbs_write_data;
   endcase
  end
 end

 always @(posedge clk or negedge reset_n) begin
 if(!reset_n) begin
   state<=IDLE;memory_request<=0;memory_addr<=0;h_valid0<=0;h_valid1<=0;
   c_valid0<=0;c_valid1<=0;c_valid2<=0;
   h_dirty0<=0;h_dirty1<=0;c_dirty0<=0;c_dirty1<=0;c_dirty2<=0;
   mode_signature<=19'h7ffff;last_screen_base<=19'h7ffff;
   frame_screen_base<=0;frame_video_bank<=0;last_video_bank<=0;
   h_next_bank<=0;c_next_bank<=0;fill_dirty<=0;configuration_pending<=1'b1;
   h_pending<=0;c_pending<=0;coalesce_count<=0;
   fill_sequential<=0;dma_next_y<=0;dma_next_address<=0;
   dma_line_in_row<=0;dma_advance_pending<=0;upper_border_q<=0;
   hdmi_frame_meta<=0;hdmi_frame_sync<=0;hdmi_frame_prev<=0;
   upper_border_active<=0;upper_border_setup_abort<=0;
   frame_initial_scroll<=0;frame_initial_lpr<=0;
   hdmi_50_meta<=0;hdmi_50_sync<=0;hdmi_50_prev<=0;
   c_replacement_bank_q<=0;
   artifact_bit_write_pending<=0;
   fill_raster_css_valid<=0;
   compatibility_css_read_addr<=0;
  end else begin
   hdmi_50_meta<=hdmi_active_50hz;
   hdmi_50_sync<=hdmi_50_meta;
   hdmi_50_prev<=hdmi_50_sync;
   hdmi_frame_meta<=hdmi_frame_start;
   hdmi_frame_sync<=hdmi_frame_meta;
   hdmi_frame_prev<=hdmi_frame_sync;
   if(hd_pa_s)upper_border_active<=0;
   else if(hdmi_frame_rise)upper_border_active<=1;
   // Register this abort decision so HDMI tag comparison and setup changes
   // do not form a long combinational path through the renderer state mux.
   upper_border_setup_abort<=upper_border_active&&upper_border_setup_changed;
   if(hdmi_standard_changed||upper_border_setup_abort)begin
    // A new field or a frame-setup write invalidates speculative row zero.
    // Abort an in-flight fill too, or FINALIZE_LINE could publish a row
    // rendered from the previous VOFF/VSC after the new setup was captured.
    state<=IDLE;memory_request<=0;word_valid<=0;
    h_valid0<=0;h_valid1<=0;
    c_valid0<=0;c_valid1<=0;c_valid2<=0;
    h_dirty0<=0;h_dirty1<=0;
    c_dirty0<=0;c_dirty1<=0;c_dirty2<=0;
    h_pending<=0;c_pending<=0;coalesce_count<=0;
    h_next_bank<=0;c_next_bank<=0;
    fill_sequential<=0;dma_next_y<=0;
    dma_next_address<=screen_base;
    dma_advance_pending<=0;
    dma_line_in_row<=compatibility_mode||
      native_lines_per_row(lines_per_row_code)==8'd1||
      vertical_scroll>=native_lines_per_row(lines_per_row_code)?
      4'd0:vertical_scroll;
    frame_screen_base<=screen_base;frame_video_bank<=video_bank;
    frame_initial_scroll<=vertical_scroll;
    frame_initial_lpr<=lines_per_row_code;
    upper_border_q<=upper_border;
    configuration_pending<=1;
    artifact_bit_write_pending<=0;
   end else begin
   // Bank selection is consumed only after the seven-clock request
   // coalescing interval.  Register it here so synchronized CVBS scanout tags
   // do not feed the fill-bank register through the complete replacement
   // priority chain in one 108-MHz cycle.
   c_replacement_bank_q<=c_replacement_bank;
   // Register the dynamically indexed artifact-row write before touching the
   // 256-bit store.  Driving its decoder directly from WRITE_PIXEL made the
   // renderer state cone a marginal 108-MHz path and could corrupt a raster
   // on hardware even when post-route slack was only a few picoseconds.
   artifact_bit_write_pending<=0;
   if(artifact_bit_write_pending)
    artifact_bits[artifact_bit_write_addr]<=artifact_bit_write_data;
   // Collapse the wide live-mode comparison into a single pending bit.  The
   // renderer consumes it only at IDLE, so mode inputs do not become a wide
   // combinational select path into all of the renderer state registers.
   if(configuration_diff)configuration_pending<=1'b1;
   // The GIME transfers VOFF into its running video address during vertical
   // blank.  Capture frame setup throughout the upper border, including
   // before HDMI starts the row-zero prefetch.
   upper_border_q<=upper_border;
   if(upper_border)begin
    frame_screen_base<=screen_base;frame_video_bank<=video_bank;
   end
   if(upper_border_setup_changed)begin
    dma_next_y<=0;dma_next_address<=screen_base;
    dma_advance_pending<=0;
    frame_initial_scroll<=vertical_scroll;
    frame_initial_lpr<=lines_per_row_code;
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
    if(write_hits_c2)c_dirty2<=1;
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
    last_video_bank<=frame_video_bank;
    // During upper border row zero is only speculative.  Do not preserve it
    // across a late frame-setup write; discard and regenerate it.  The next
    // row is protected only while an actual picture row is being displayed.
    h_valid0<=h_keep_tag0;
    h_valid1<=h_keep_tag1;
    // cv_v_s covers only active horizontal pixels. Raster handlers write
    // GIME registers in HBORD, where it is low although the same analogue
    // row is still in progress. Preserve the current and prefetched rows
    // using the full-line identity derived from prefetch_y; otherwise each
    // scrolling/mode write creates a component/CVBS-only black scanline.
    c_valid0<=c_valid0&&c_keep_tag0;
    c_valid1<=c_valid1&&c_keep_tag1;
    c_valid2<=c_valid2&&c_keep_tag2;
    h_dirty0<=h_dirty0&&hd_pa_s&&
              ((h_tag0==hd_y_s)||(hd_pv_s&&h_tag0==hd_p_s));
    h_dirty1<=h_dirty1&&hd_pa_s&&
              ((h_tag1==hd_y_s)||(hd_pv_s&&h_tag1==hd_p_s));
    c_dirty0<=c_dirty0&&c_keep_tag0;
    c_dirty1<=c_dirty1&&c_keep_tag1;
    c_dirty2<=c_dirty2&&c_keep_tag2;
   memory_request<=0;word_valid<=0;c_pending<=0;
   // A horizontal-border register write can arrive after scanout has
   // already queued the following row but before its short coalescing delay
   // expires.  Do not discard that request: BOINK performs several such
   // raster writes, and losing the queued row leaves a black scanline (and
   // skips the corresponding sequential DMA handoff).  Restart the delay so
   // the fill captures the newly settled mode inputs, while retaining the
   // requested logical row.
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
     last_video_bank<=frame_video_bank;
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
                  (c_valid2&&c_tag2==h_pending_y)?2:c_replacement_bank_q;
     fill_bit_plane<=bit_plane;
     fill_cres<=compatibility_mode&&compatibility_an_g?
      ((compatibility_gm==0||compatibility_gm==2||compatibility_gm==4||compatibility_gm==6)?1:0):cres;
     fill_attributes<=!compatibility_mode&&native_attributes;
     fill_gm<=compatibility_gm;fill_css<=compatibility_css;
     fill_raster_css_valid<=compatibility_mode&&
                            compatibility_css_display_valid;
     fill_compatibility<=compatibility_mode;fill_blink<=blink;
     fill_video_bank<=frame_video_bank;
     fill_artifact_mode<=artifact_mode;
     fill_lpr<=compatibility_mode?(!compatibility_an_g?12:
      compatibility_lines_per_row(compatibility_sam_mode)):
      native_lines_per_row(lines_per_row_code);
     fill_stride<=live_stride;fill_row_bytes<=live_row_bytes;
     fill_source_width<=live_source_width;
     // HRES selects two physical GIME apertures. Even HRES values are the
     // 256/512-dot family and occupy 512 master dots; odd values are the
     // 320/640-dot family and occupy all 640. Keeping every row at 640 erased
     // raster tricks which switch HRES between scanlines (Sock Master).
     fill_narrow_aperture<=!compatibility_mode&&!hres[0];
     fill_border_rgb<=border_rgb;
     fill_scale_integer<=(!compatibility_mode&&!hres[0])?
       scale_integer_512(live_source_width):scale_integer(live_source_width);
     fill_scale_remainder<=(!compatibility_mode&&!hres[0])?
       scale_remainder_512(live_source_width):scale_remainder(live_source_width);
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
     if(fill_compatibility)begin
      fill_left_css<=fill_css;fill_right_css<=fill_css;
     end
     scale_phase<=0;hdmi_out_x<=0;hdmi_filter_phase<=0;
     state<=LINE_ADDRESS;end
    LINE_ADDRESS:begin line_address<=fill_base+row_address;
     state<=PIXEL_ADDRESS;end
    PIXEL_ADDRESS:begin
     if(fill_compatibility)
      compatibility_css_read_addr<={compatibility_css_display_bank,
                                    fill_y,source_byte_index[4:0]};
     if(!in_fill_aperture)begin
      pixel_latched<=fill_border_rgb;
      hdmi_pixel_latched<=expand_rgb222(fill_border_rgb);
      state<=WRITE_PIXEL;
     end else if(fill_bit_plane&&graphics_cache_valid&&graphics_cache_index==source_byte_index)begin
      state<=DECODE_PIXEL;
     end
     else if(!fill_bit_plane&&text_cache_valid&&
             text_cache_column==source_character_column)
      state<=DECODE_PIXEL;
     else begin byte_address<=calculated_byte_address;state<=CHECK_WORD;end
    end
    CHECK_WORD:begin
     if(!word_valid||word_tag!=aligned_address)begin
      memory_addr<={2'b00,fill_video_bank,aligned_address};
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
     if(!word_valid||word_tag!=aligned_address)begin
      memory_addr<={2'b00,fill_video_bank,aligned_address};
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
     if(fill_compatibility)begin
      if(source_x==0)fill_left_css<=pixel_compatibility_css;
      fill_right_css<=pixel_compatibility_css;
     end
     color_index_latched<=decoded_index;color_code_latched<=decoded_code;
     state<=COLOR_LOOKUP;
    end
    COLOR_LOOKUP:begin
     pixel_latched<=palette_rgb(fill_compatibility?color_code_latched:
       fill_palettes[color_index_latched*6+:6]);
     hdmi_pixel_latched<=expand_rgb222(
       palette_rgb(fill_compatibility?color_code_latched:
       fill_palettes[color_index_latched*6+:6]));
     if(artifact_active)begin
      artifact_bit_write_pending<=1;
      artifact_bit_write_addr<=source_x[7:0];
      artifact_bit_write_data<=color_index_latched[0];
     end
     state<=WRITE_PIXEL;
    end
    WRITE_PIXEL:begin
     // Native GIME keeps all 640 pixels. Compatibility video still occupies
     // the 512-dot HDMI aperture, so its five canonical positions advance
     // the output address four times.
     if(fill_hdmi&&(!fill_compatibility||hdmi_filter_phase!=1))
      hdmi_out_x<=hdmi_out_x+1'b1;
     hdmi_filter_phase<=(hdmi_filter_phase==4)?0:hdmi_filter_phase+1'b1;
     if(out_x==CANONICAL_WIDTH-1'b1)begin
      if(artifact_active)begin
       // MAME evaluates the six-dot window through PMODE 4's set-level
       // border. Set-bit padding avoids artificial cyan/green edge lines.
       artifact_shift<={3'b111,color_index_latched[0],
                        artifact_bits[254:0],2'b11};
       out_x<=0;source_x<=0;scale_phase<=0;hdmi_out_x<=0;
       hdmi_filter_phase<=0;
       state<=ARTIFACT_DECODE;
      end else state<=FINALIZE_LINE;
     end else begin
      out_x<=out_x+1'b1;
      if(in_fill_aperture)begin
       source_x<=next_source_x;
       source_byte_index<=next_source_byte_index;
       source_character_column<=next_source_x[10:3];
       scale_phase<=next_scale_phase_sum>=(fill_narrow_aperture?11'd512:11'd640)?
                    (next_scale_phase_sum-(fill_narrow_aperture?11'd512:11'd640)):
                    next_scale_phase_sum[9:0];
      end
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
       if(fill_h_bank)begin h_tag1<=fill_y;h_start1<={fill_video_bank,line_address};h_bytes1<=fill_row_bytes;
        h_left_border1<=rendered_left_border;
        h_right_border1<=rendered_right_border;
        h_valid1<=1;h_dirty1<=fill_dirty;
        if(h_valid0&&h_tag0==fill_y)begin h_valid0<=0;h_dirty0<=0;end end
       else begin h_tag0<=fill_y;h_start0<={fill_video_bank,line_address};h_bytes0<=fill_row_bytes;
        h_left_border0<=rendered_left_border;
        h_right_border0<=rendered_right_border;
        h_valid0<=1;h_dirty0<=fill_dirty;
        if(h_valid1&&h_tag1==fill_y)begin h_valid1<=0;h_dirty1<=0;end end
       h_next_bank<=!fill_h_bank;
      end
      if(fill_cvbs)begin
       case(fill_c_bank)
        2'd0:begin c_tag0<=fill_y;c_start0<={fill_video_bank,line_address};c_bytes0<=fill_row_bytes;
         c_border0<=rendered_left_border;
         c_right_border0<=rendered_right_border;
         c_valid0<=1;c_dirty0<=fill_dirty;
         if(c_valid1&&c_tag1==fill_y)begin c_valid1<=0;c_dirty1<=0;end
         if(c_valid2&&c_tag2==fill_y)begin c_valid2<=0;c_dirty2<=0;end end
        2'd1:begin c_tag1<=fill_y;c_start1<={fill_video_bank,line_address};c_bytes1<=fill_row_bytes;
         c_border1<=rendered_left_border;
         c_right_border1<=rendered_right_border;
         c_valid1<=1;c_dirty1<=fill_dirty;
         if(c_valid0&&c_tag0==fill_y)begin c_valid0<=0;c_dirty0<=0;end
         if(c_valid2&&c_tag2==fill_y)begin c_valid2<=0;c_dirty2<=0;end end
        default:begin c_tag2<=fill_y;c_start2<={fill_video_bank,line_address};c_bytes2<=fill_row_bytes;
         c_border2<=rendered_left_border;
         c_right_border2<=rendered_right_border;
         c_valid2<=1;c_dirty2<=fill_dirty;
         if(c_valid0&&c_tag0==fill_y)begin c_valid0<=0;c_dirty0<=0;end
         if(c_valid1&&c_tag1==fill_y)begin c_valid1<=0;c_dirty1<=0;end end
       endcase
       c_next_bank <= (fill_c_bank == 2'd2) ? 2'd0 : fill_c_bank + 1'b1;
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
 end

 reg [7:0] h_tag0_m=0,h_tag0_r=0,h_tag1_m=0,h_tag1_r=0;
 reg border_bank_m=0,border_bank_s=0;
 reg border_valid_m=0,border_valid_s=0;
 reg border_read_bank=0,border_read_valid=0;
 wire border_bank_for_read=hdmi_frame_start?border_bank_s:border_read_bank;
 wire border_valid_for_read=hdmi_frame_start?border_valid_s:border_read_valid;
 always @(posedge hdmi_read_clk)begin
  border_bank_m<=compatibility_border_display_bank;
  border_bank_s<=border_bank_m;
  border_valid_m<=compatibility_border_display_valid;
  border_valid_s<=border_valid_m;
  if(hdmi_frame_start)begin
   border_read_bank<=border_bank_s;
   border_read_valid<=border_valid_s;
  end
  hdmi_vertical_left_border_data<=compatibility_border_left[
       {border_bank_for_read,hdmi_border_raster_y}];
  hdmi_vertical_right_border_data<=compatibility_border_right_rgb[
       {border_bank_for_read,hdmi_border_raster_y}];
  hdmi_vertical_border_valid<=compatibility_mode&&border_valid_for_read;
 end
 // The analogue border is not a picture-cache row. Read the same captured
 // VDG raster colours used by HDMI, rather than falling back to a live FF22
 // value at the picture-to-bottom-border transition.
 reg cvbs_border_bank_m=0,cvbs_border_bank_s=0;
 reg cvbs_border_valid_m=0,cvbs_border_valid_s=0;
 always @(posedge cvbs_read_clk)begin
  cvbs_border_bank_m<=compatibility_border_display_bank;
  cvbs_border_bank_s<=cvbs_border_bank_m;
  cvbs_border_valid_m<=compatibility_border_display_valid;
  cvbs_border_valid_s<=cvbs_border_valid_m;
  cvbs_vertical_left_border_data<=compatibility_border_left[
       {cvbs_border_bank_s,cvbs_border_raster_y}];
  cvbs_vertical_right_border_data<=compatibility_border_right_rgb[
       {cvbs_border_bank_s,cvbs_border_raster_y}];
  cvbs_vertical_border_valid<=compatibility_mode&&cvbs_border_valid_s;
 end
 reg h_v0_m=0,h_v0_r=0,h_v1_m=0,h_v1_r=0;
 reg h_read_bank=0,h_read_valid=0;
 reg [9:0] h_read_addr=0;
 always @(posedge hdmi_read_clk)begin
  h_read_addr<=hdmi_read_x;
  h_tag0_m<=h_tag0;h_tag0_r<=h_tag0_m;h_tag1_m<=h_tag1;h_tag1_r<=h_tag1_m;
  h_v0_m<=h_valid0;h_v0_r<=h_v0_m;h_v1_m<=h_valid1;h_v1_r<=h_v1_m;
  // A committed cache entry is the complete logical raster: its rendered
  // pixels and both border endpoints were captured by the same fill. Select
  // it in the left border, then hold that bank through the entire scanline.
  if(!hdmi_picture_active)begin
   h_read_valid<=0;hdmi_pixel_data<=0;hdmi_border_valid<=0;end
  else if(hdmi_read_x==0)begin
   // Select once at the physical scanline boundary.  A fill which completes
   // after pixel zero is deliberately deferred until the next scanline,
   // preventing the characteristic black-left/valid-right half line.
   if(h_v0_r&&h_tag0_r==hdmi_display_y)begin
    h_read_bank<=0;h_read_valid<=1;hdmi_pixel_data<=hdmi_line0[h_read_addr];
    hdmi_left_border_data<=h_left_border0;
    hdmi_right_border_data<=h_right_border0;hdmi_border_valid<=1;
   end
   else if(h_v1_r&&h_tag1_r==hdmi_display_y)begin
    h_read_bank<=1;h_read_valid<=1;hdmi_pixel_data<=hdmi_line1[h_read_addr];
    hdmi_left_border_data<=h_left_border1;
    hdmi_right_border_data<=h_right_border1;hdmi_border_valid<=1;
   end
   else begin h_read_valid<=0;hdmi_pixel_data<=0;hdmi_border_valid<=0;end
  end else if(!hdmi_display_valid)begin
   // Border samples still belong to this row, even when the picture pixel
   // RAM is masked by the output timing generator.
   hdmi_pixel_data<=0;
  end else if(h_read_valid)begin
   if(h_read_bank)hdmi_pixel_data<=hdmi_line1[h_read_addr];
   else hdmi_pixel_data<=hdmi_line0[h_read_addr];
  end else hdmi_pixel_data<=0;
 end
 reg [7:0] c_tag0_m=0,c_tag0_r=0,c_tag1_m=0,c_tag1_r=0,
           c_tag2_m=0,c_tag2_r=0;
 reg c_v0_m=0,c_v0_r=0,c_v1_m=0,c_v1_r=0,c_v2_m=0,c_v2_r=0;
 reg [1:0] c_read_bank=0;
 reg c_read_valid=0;
 reg [9:0] c_read_addr=0;
 always @(posedge cvbs_read_clk)begin
  // CVBS is always the 640-sample path in the CoCo 3 top.  Preload zero in
  // blanking, then request the following sample so the registered BSRAM
  // address does not add a visible horizontal pixel of delay.
  c_read_addr<=cvbs_display_valid ?
               (cvbs_read_x==10'd639 ? 10'd639 : cvbs_read_x+1'b1) : 10'd0;
  c_tag0_m<=c_tag0;c_tag0_r<=c_tag0_m;c_tag1_m<=c_tag1;c_tag1_r<=c_tag1_m;
  c_tag2_m<=c_tag2;c_tag2_r<=c_tag2_m;
  c_v0_m<=c_valid0;c_v0_r<=c_v0_m;c_v1_m<=c_valid1;c_v1_r<=c_v1_m;
  c_v2_m<=c_valid2;c_v2_r<=c_v2_m;
  // Refresh data throughout border selection; validity below still decides
  // whether the encoder uses it. This keeps tag comparison off the register
  // enable path without changing the selected row's border colour.
  if(!cvbs_display_valid||cvbs_read_x==0)
   begin cvbs_border_data<=c_border0;
         cvbs_right_border_data<=c_right_border0;end
  if(!cvbs_display_valid)begin
   // source_y is already the upcoming row throughout horizontal blank.
   // Select its bank and preload pixel zero while the encoder is still
   // drawing border, so synchronous BSRAM latency cannot leak the previous
   // border/row into the left edge of the active component/CVBS picture.
   if(c_v0_r&&c_tag0_r==cvbs_display_y)begin
    c_read_bank<=0;c_read_valid<=1;cvbs_pixel_data<=cvbs_line0[c_read_addr];
    cvbs_border_data<=c_border0;cvbs_right_border_data<=c_right_border0;
    cvbs_border_valid<=1;end
   else if(c_v1_r&&c_tag1_r==cvbs_display_y)begin
    c_read_bank<=1;c_read_valid<=1;cvbs_pixel_data<=cvbs_line1[c_read_addr];
    cvbs_border_data<=c_border1;cvbs_right_border_data<=c_right_border1;
    cvbs_border_valid<=1;end
   else if(c_v2_r&&c_tag2_r==cvbs_display_y)begin
    c_read_bank<=2;c_read_valid<=1;cvbs_pixel_data<=cvbs_line2[c_read_addr];
    cvbs_border_data<=c_border2;cvbs_right_border_data<=c_right_border2;
    cvbs_border_valid<=1;end
   else begin c_read_valid<=0;cvbs_pixel_data<=0;cvbs_border_valid<=0;end
  end
  else if(cvbs_read_x==0)begin
   if(c_v0_r&&c_tag0_r==cvbs_display_y)begin
    c_read_bank<=0;c_read_valid<=1;cvbs_pixel_data<=cvbs_line0[c_read_addr];
    cvbs_border_data<=c_border0;cvbs_right_border_data<=c_right_border0;
    cvbs_border_valid<=1;end
   else if(c_v1_r&&c_tag1_r==cvbs_display_y)begin
    c_read_bank<=1;c_read_valid<=1;cvbs_pixel_data<=cvbs_line1[c_read_addr];
    cvbs_border_data<=c_border1;cvbs_right_border_data<=c_right_border1;
    cvbs_border_valid<=1;end
   else if(c_v2_r&&c_tag2_r==cvbs_display_y)begin
    c_read_bank<=2;c_read_valid<=1;cvbs_pixel_data<=cvbs_line2[c_read_addr];
    cvbs_border_data<=c_border2;cvbs_right_border_data<=c_right_border2;
    cvbs_border_valid<=1;end
   else begin c_read_valid<=0;cvbs_pixel_data<=0;cvbs_border_valid<=0;end
  end else if(c_read_valid)begin
   case(c_read_bank)
    2'd0:cvbs_pixel_data<=cvbs_line0[c_read_addr];
    2'd1:cvbs_pixel_data<=cvbs_line1[c_read_addr];
    default:cvbs_pixel_data<=cvbs_line2[c_read_addr];
   endcase
  end else cvbs_pixel_data<=0;
 end
endmodule
