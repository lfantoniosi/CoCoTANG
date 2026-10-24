`timescale 1ns/1ps
module tb_cpu_bus_probe_screen;
    reg pixel_clk=0,reset=0;
    reg [9:0] x=0,y=0;
    reg [7:0] test_data=8'ha5,data_readback=8'ha5;
    reg [23:0] mux_banks=24'hd5c3a5;
    reg [15:0] cpu_address=16'hd8a5;
    reg [7:0] mp_live=8'hd5,extras=8'h3f;
    reg [11:0] outputs={2'b10,1'b1,1'b1,1'b1,4'b1111,3'b000};
    wire [23:0] rgb;
    cpu_bus_probe_screen dut(.*);
    always #5 pixel_clk=~pixel_clk;
    reg [335:0] row;
    reg [7:0] c;
    integer file;
    initial begin
        repeat (4) @(negedge pixel_clk);
        row=dut.text_line(1);
        if (row[335 -:88]!=="DATA OUT:A5") $fatal(1,"Data label/value missing: %s",row);
        row=dut.text_line(4);
        if (row[335 -:128]!=="CPU ADDRESS:D8A5") $fatal(1,"Address label/value missing: %s",row);
        // Every displayed character must have a glyph, including input labels.
        for (integer line=0;line<19;line=line+1) begin
            row=dut.text_line(line);
            for (integer column=0;column<42;column=column+1) begin
                c=row[335-column*8 -:8];
                if (c!=" " && dut.glyph(c)==0) $fatal(1,"Missing glyph %h row %d",c,line);
            end
        end
        // Preview the actual RTL pixel renderer, rather than a mockup.
        file=$fopen("/private/tmp/cocotang-pin-probe.ppm","wb");
        $fwrite(file,"P6\n720 480\n255\n");
        for (integer yy=0;yy<480;yy=yy+1)
            for (integer xx=0;xx<720;xx=xx+1) begin
                x=xx;y=yy;#1;
                $fwrite(file,"%c%c%c",rgb[23:16],rgb[15:8],rgb[7:0]);
            end
        $fclose(file);
        // Values change only on the next frame, so labels remain coherent.
        test_data=8'h5a;x=10;y=10;
        repeat (4) @(negedge pixel_clk);
        row=dut.text_line(1);
        if (row[263 -:16]!=="A5") $fatal(1,"Display changed within a frame");
        x=0;y=0;@(negedge pixel_clk);
        row=dut.text_line(1);
        if (row[263 -:16]!=="5A") $fatal(1,"Display did not refresh at frame boundary");
        $display("PASS: HDMI labels, hex values, glyph coverage, frame snapshot; preview rendered");
        $finish;
    end
endmodule
