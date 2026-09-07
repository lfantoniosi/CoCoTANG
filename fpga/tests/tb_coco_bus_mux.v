`timescale 1ns/1ps
module tb_coco_bus_mux;
    reg clk=0,reset_n=0; reg [7:0] mp;
    wire [1:0] msel; wire [15:0] addr;
    wire rw_n,cpu_reset_n,slenb_n,sernt_n,cart_n,keyint_n,halt_n,nmi_n,valid;
    coco_bus_mux dut(.clk(clk),.reset_n(reset_n),.mp(mp),.msel(msel),.addr(addr),
      .rw_n(rw_n),.cpu_reset_n(cpu_reset_n),.slenb_n(slenb_n),.sernt_n(sernt_n),
      .cart_n(cart_n),.keyint_n(keyint_n),.halt_n(halt_n),.nmi_n(nmi_n),
      .snapshot_valid(valid));
    always #5 clk=~clk;
    always @(*) case(msel)
      2'b00: mp=8'ha3;
      2'b01: mp={1'b0,1'b1,1'b1,1'b1,4'h5}; // A15..8 = d5
      2'b10: mp=8'b10110111;
      default: mp=8'hff;
    endcase
    initial begin
      repeat(3) @(posedge clk); reset_n=1;
      repeat(30) @(posedge clk);
      if(addr!==16'hd5a3) $fatal(1,"address reconstruction: %h",addr);
      if({nmi_n,halt_n,keyint_n,cart_n,sernt_n,slenb_n,cpu_reset_n,rw_n}!==8'b10110111)
        $fatal(1,"control reconstruction");
      $display("tb_coco_bus_mux PASS"); $finish;
    end
endmodule
