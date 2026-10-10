// Debug build uses the trace settings declared by top_coco3.
module top_coco3_contras_debug (
    input clkin,input s1,input s2,input [7:0] mp,output [1:0] msel,
    inout [7:0] cpu_data,output irq_n_in,output firq_n_in,output audio_out,
    output halt_drive,output e_out,output q_out,output hs_n,output fs_n,
    output [2:0] sam_s,output y_out,output pb_out,output cvbs_out,
    output tmds_clk_p,output tmds_clk_n,
    output [2:0] tmds_data_p,output [2:0] tmds_data_n,
    output mspi_sclk,output mspi_cs,output mspi_mosi,input mspi_miso,
    output sd_sclk,inout sd_cmd,inout sd_dat0,inout sd_dat1,
    inout sd_dat2,inout sd_dat3,
    output O_sdram_clk,output O_sdram_cke,output O_sdram_cs_n,
    output O_sdram_cas_n,output O_sdram_ras_n,output O_sdram_wen_n,
    inout [31:0] IO_sdram_dq,output [10:0] O_sdram_addr,
    output [1:0] O_sdram_ba,output [3:0] O_sdram_dqm
);
    top_coco3 #(
        .LOG_DEPTH(4092),
        .LOG_AUTO_START(1),
        .ENABLE_BUS_LOGGER(1),
        .DEBUG_OVERLAY(1)
    ) core (.*);
endmodule
