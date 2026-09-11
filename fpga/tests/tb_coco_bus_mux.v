`timescale 1ns/1ps
module tb_coco_bus_mux;
    reg clk=0,reset_n=0,scan_start=0; reg [7:0] mp=8'ha3;
    wire [1:0] msel; wire [15:0] addr;
    wire rw_n,cpu_reset_n,slenb_n,sernt_n,cart_n,keyint_n,halt_n,nmi_n,valid;
    coco_bus_mux dut(.clk(clk),.reset_n(reset_n),.scan_start(scan_start),
      .mp(mp),.msel(msel),.addr(addr),
      .rw_n(rw_n),.cpu_reset_n(cpu_reset_n),.slenb_n(slenb_n),.sernt_n(sernt_n),
      .cart_n(cart_n),.keyint_n(keyint_n),.halt_n(halt_n),.nmi_n(nmi_n),
      .snapshot_valid(valid));
    always #5 clk=~clk;
    // Model decoder/buffer propagation: the previous bank remains visible
    // for 17 ns after MSEL changes.
    always @(msel) case(msel)
      2'b00: mp <= #17 8'ha3;
      2'b01: mp <= #17 {1'b0,1'b1,1'b1,1'b1,4'h5}; // A15..8 = d5
      2'b10: mp <= #17 8'b10110111;
      default: mp <= #17 8'hff;
    endcase
    integer valid_count=0;
    always @(posedge valid) valid_count=valid_count+1;
    initial begin
      repeat(3) @(posedge clk); reset_n=1;
      @(posedge clk); scan_start=1;
      @(posedge clk); scan_start=0;
      repeat(70) @(posedge clk);
      if(valid_count!=1) $fatal(1,"expected one snapshot, got %0d",valid_count);
      if(addr!==16'hd5a3) $fatal(1,"address reconstruction: %h",addr);
      if({nmi_n,halt_n,keyint_n,cart_n,sernt_n,slenb_n,cpu_reset_n,rw_n}!==8'b10110111)
        $fatal(1,"control reconstruction");
      // It must remain idle until another Q-aligned scan_start pulse.
      repeat(30) @(posedge clk);
      if(valid_count!=1) $fatal(1,"scanner republished without scan_start");
      $display("tb_coco_bus_mux PASS"); $finish;
    end
endmodule
