module coco_framebuffer (
    input write_clk, input write_en, input [15:0] write_addr, input [5:0] write_data,
    input read_clk, input [15:0] read_addr, output reg [5:0] read_data
);
    reg [5:0] memory [0:49151];
    always @(posedge write_clk)
        if (write_en && write_addr < 49152) memory[write_addr] <= write_data;
    always @(posedge read_clk)
        if (read_addr < 49152) read_data <= memory[read_addr];
        else read_data <= 6'd0;
endmodule
