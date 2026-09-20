// Character generator from the BSD-licensed CoCo3FPGA/MiSTer core.
// Bank 0 is the native GIME font; bank 1 is the compatibility MC6847 font.
module coco3_char_rom (
    input clk,
    input [11:0] addr,
    output reg [7:0] data
);
    reg [7:0] memory [0:4095];
`ifdef __ICARUS__
    initial $readmemh("src/coco3/coco3_char.hex", memory);
`else
    // Gowin runs synthesis from impl/gwsynthesis.
    initial $readmemh("../../src/coco3/coco3_char.hex", memory);
`endif
    always @(posedge clk) data <= memory[addr];
endmodule
