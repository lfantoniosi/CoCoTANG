// One 512-byte true-dual-port sector buffer.  The 16-bit port matches ATA
// words while the 8-bit port matches the SD controller's byte stream.
module glenside_sector_buffer (
    input wire clk,
    input wire [7:0] ata_addr,
    input wire ata_we,
    input wire [15:0] ata_wdata,
    output wire [15:0] ata_rdata,
    input wire [8:0] sd_addr,
    input wire sd_we,
    input wire [7:0] sd_wdata,
    output wire [7:0] sd_rdata
);
`ifdef __ICARUS__
    reg [7:0] memory [0:511];
    reg [15:0] ata_q;
    reg [7:0] sd_q;
    always @(posedge clk) begin
        ata_q <= {memory[{ata_addr,1'b1}],memory[{ata_addr,1'b0}]};
        if (ata_we) begin
            memory[{ata_addr,1'b0}] <= ata_wdata[7:0];
            memory[{ata_addr,1'b1}] <= ata_wdata[15:8];
        end
    end
    always @(posedge clk) begin
        sd_q <= memory[sd_addr];
        if (sd_we)
            memory[sd_addr] <= sd_wdata;
    end
    assign ata_rdata=ata_q;
    assign sd_rdata=sd_q;
`else
    wire [15:0] doa,dob;
    DPB #(
        .READ_MODE0(1'b0),.READ_MODE1(1'b0),
        .WRITE_MODE0(2'b00),.WRITE_MODE1(2'b00),
        .BIT_WIDTH_0(16),.BIT_WIDTH_1(8),
        .BLK_SEL_0(3'b000),.BLK_SEL_1(3'b000),
        .RESET_MODE("SYNC")
    ) sector_ram (
        .DOA(doa),.DOB(dob),.DIA(ata_wdata),.DIB({8'h00,sd_wdata}),
        .BLKSELA(3'b000),.BLKSELB(3'b000),
        // In Gowin's 16-bit DPB mode ADA[1:0] are independent byte-write
        // enables, not address bits.  Assert both for ATA word writes.
        .ADA({2'b00,ata_addr,2'b00,ata_we,ata_we}),
        .ADB({2'b00,sd_addr,3'b000}),
        .WREA(ata_we),.WREB(sd_we),.CLKA(clk),.CLKB(clk),
        .CEA(1'b1),.CEB(1'b1),.OCEA(1'b1),.OCEB(1'b1),
        .RESETA(1'b0),.RESETB(1'b0));
    assign ata_rdata=doa;
    assign sd_rdata=dob[7:0];
`endif
endmodule
