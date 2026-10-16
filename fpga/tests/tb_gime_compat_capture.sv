`timescale 1ns/1ps
module tb_gime_compat_capture;
 reg clk=0,reset_n=0,enable=0,frame_start=0,sample=0,css=0;
 reg [7:0] y=0;reg [4:0] col=0;reg [12:0] read_addr=0;
 reg [10:0] row_bytes=32;reg [7:0] lpr=1;
 reg renderer_request=0,memory_valid=0;
 wire renderer_valid,memory_request,display_valid;
 wire [22:0] memory_addr;wire [8:0] read_data;
 reg [31:0] memory_data=0;
 reg [7:0] live_pixel=0;
 integer memory_state=0,delay_left=0,memory_delay=2;
 integer field_id,iy,ix,timeout,expected_field=0;
 reg check_addresses=0;
 reg cpu_write=0;
 always #5 clk=~clk;
 gime_compat_capture dut(
  .clk(clk),.reset_n(reset_n),.enable(enable),.hdmi_frame_start(frame_start),
  .sample(sample),.sample_y(y),.sample_byte(col),.sample_css(css),
  .screen_base(19'h600),.video_bank(4'd0),.row_bytes(row_bytes),.lines_per_row(lpr),
  .cpu_write_strobe(cpu_write),.cpu_write_addr(23'h600),
  .read_addr(read_addr),.read_data(read_data),.display_valid(display_valid),
  .renderer_request(renderer_request),.renderer_addr(23'h1234),
  .renderer_valid(renderer_valid),.memory_request(memory_request),
  .memory_addr(memory_addr),.memory_valid(memory_valid),.memory_data(memory_data));
 always @(posedge clk)begin
  memory_valid<=0;
  if(memory_state==0&&memory_request)begin
   memory_state<=1;delay_left<=memory_delay;
   if(check_addresses&&memory_addr!=((19'h600+(y/lpr)*row_bytes+
                         (row_bytes==16?col/2:col))&23'h7ffffc))
    $fatal(1,"capture address y=%0d col=%0d addr=%h",y,col,memory_addr);
  end else if(memory_state==1)begin
   if(delay_left==0)begin
    memory_data<={4{live_pixel}};memory_valid<=1;memory_state<=2;
   end else delay_left<=delay_left-1;
  end else if(memory_state==2&&!memory_request)memory_state<=0;
 end
 task hdmi_boundary;
  begin
   @(negedge clk);frame_start=1;repeat(6)@(negedge clk);
   frame_start=0;repeat(6)@(negedge clk);
  end
 endtask
 task check_display;
  input integer id;
  integer r,c;
  begin
   if(!display_valid)$fatal(1,"completed capture not published");
   for(r=0;r<192;r=r+37)
    for(c=0;c<32;c=c+7)begin
     @(negedge clk);read_addr=r*32+c;
     repeat(2)@(negedge clk);
     if(read_data!=={1'((r+c+id)&1),
                    8'((id==8&&r==0&&c>0&&c<8)?9:id)})
      $fatal(1,"torn capture field=%0d y=%0d col=%0d got=%h",id,r,c,read_data);
    end
  end
 endtask
 task capture_field;
  input integer id,switch_midway;
  begin
   for(iy=0;iy<192;iy=iy+1)
    for(ix=0;ix<32;ix=ix+1)begin
     @(negedge clk);y=iy;col=ix;css=(iy+ix+id)&1;
     // A CPU write between two byte samples must invalidate the captured
     // word cache, without changing the byte already stored in the field.
     cpu_write=id==8&&iy==0&&ix==1;
     live_pixel=cpu_write?id+1:id;sample=1;
     @(negedge clk);sample=0;cpu_write=0;
     repeat(19)@(negedge clk);
     if(switch_midway&&iy==96&&ix==0)begin
      hdmi_boundary();check_display(expected_field);
     end
    end
   repeat(50)@(negedge clk);
   // Simulate the game erasing/redrawing its sprites immediately after
   // scanout. Displayed bytes must retain the beam-time sample throughout.
   live_pixel=8'hff;
  end
 endtask
 initial begin
  repeat(4)@(negedge clk);reset_n=1;
  // Native fetches retain the request/ack/drop handshake.
  renderer_request=1;live_pixel=8'h5a;timeout=0;
  while(!renderer_valid&&timeout<100)begin @(negedge clk);timeout=timeout+1;end
  if(timeout==100||memory_data!==32'h5a5a5a5a)$fatal(1,"native memory arbitration");
  renderer_request=0;repeat(6)@(negedge clk);
  enable=1;check_addresses=1;
  capture_field(1,0);hdmi_boundary();check_display(1);
  capture_field(2,0);check_display(1);
  // HDMI's half-line and the complete-line machine raster need not share
  // a frame edge. Switch HDMI in the middle of capture, then let several
  // machine fields lap it without overwriting the displayed sprites.
  expected_field=2;capture_field(3,1);check_display(2);
  capture_field(4,0);check_display(2);
  capture_field(5,0);check_display(2);
  hdmi_boundary();check_display(5);
  // Also check the 16-byte/repeated-row PMODE addressing.
  row_bytes=16;lpr=3;capture_field(6,0);hdmi_boundary();check_display(6);
  // An SDRAM overrun must keep the last complete field, never publish a
  // partially captured sprite. It must recover on the following field.
  check_addresses=0;memory_delay=30;capture_field(7,0);
  hdmi_boundary();check_display(6);
  memory_delay=2;check_addresses=1;capture_field(8,0);
  hdmi_boundary();check_display(8);
  @(negedge clk);read_addr=1;repeat(2)@(negedge clk);
  if(read_data[7:0]!==8'd9)$fatal(1,"CPU write did not refresh the capture word cache");
  enable=0;repeat(4)@(negedge clk);
  if(display_valid)$fatal(1,"graphics snapshot survived leaving compatibility graphics");
  $display("tb_gime_compat_capture PASS");$finish;
 end
 initial begin #30000000;$fatal(1,"capture test timeout");end
endmodule
