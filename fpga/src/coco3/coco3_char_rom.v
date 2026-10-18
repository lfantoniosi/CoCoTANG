// Native bank from the BSD-licensed CoCo3FPGA/MiSTer core.
// Compatibility bank uses XRoar's GIME font, encoded for the existing
// character/inverse mapping by scripts/update_compat_font.py. See the
// attributed reference in tests/data/gime_font_xroar.hex.
// Bank 0 is native GIME text; bank 1 is GIME compatibility text.
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
