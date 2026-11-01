module coco_bus_mux #(
    parameter integer SETTLE_CYCLES = 7
) (
    input         clk,
    input         reset_n,
    input         scan_start,
    input  [7:0]  mp,
    output [1:0]  msel,
    output [15:0] addr,
    output        rw_n,
    output        cpu_reset_n,
    output        slenb_n,
    output        sernt_n,
    output        cart_n,
    output        keyint_n,
    output        halt_n,
    output        nmi_n,
    output        address_ready,
    output        snapshot_valid
);
    // Allow the 6809 outputs, 74HC139 selector and LVC245 path to settle.
    // SETTLE_CYCLES is selected by the top level for about 44 ns per switched
    // bank.  Shorter diagnostic settings produced mixed-byte snapshots on
    // the prototype (for example, FFFE appeared as FEFF).  Acquisition starts
    // just after Q rises, once the address and external mux inputs are stable.
    localparam integer SETTLE_WIDTH =
        (SETTLE_CYCLES < 1) ? 1 : $clog2(SETTLE_CYCLES+1);
    // MSEL itself records the active phase: 00 idle, 01 high address,
    // 10 controls. A separate bank/scanning state is unnecessary.
    reg [1:0] select_reg=0;
    reg [SETTLE_WIDTH-1:0] settle_count=0;
    reg [7:0] address_low=8'hff,address_high=8'hff,snapshot=8'hff;
    reg address_ready_reg=0,snapshot_valid_reg=0;
    (* syn_preserve = 1 *) reg capture_bank=0;
    wire capture_high=!scan_start && capture_bank && select_reg[0];
    wire capture_controls=!scan_start && capture_bank && select_reg[1];

    // Local data enables avoid the scanner's nested priority mux. The
    // capture edges and the external bank settling interval are unchanged.
    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)begin
            address_low<=8'hff;address_high<=8'hff;snapshot<=8'hff;
        end else begin
            if(scan_start)address_low<=mp;
            if(capture_high)address_high<={mp[0],mp[1],mp[2],mp[7:3]};
            if(capture_controls)snapshot<=mp;
        end
    end
    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)begin
            select_reg<=0;settle_count<=0;capture_bank<=0;
            address_ready_reg<=0;snapshot_valid_reg<=0;
        end else if(scan_start)begin
            select_reg<=2'b01;settle_count<=0;capture_bank<=0;
            address_ready_reg<=0;snapshot_valid_reg<=0;
        end else if(|select_reg)begin
            if(capture_bank)begin
                settle_count<=0;capture_bank<=0;
                if(select_reg[0])begin
                    select_reg<=2'b10;address_ready_reg<=1;
                end else begin
                    select_reg<=0;snapshot_valid_reg<=1;
                end
            end else if(settle_count==SETTLE_CYCLES-1)
                capture_bank<=1;
            else settle_count<=settle_count+1'b1;
        end
    end

    // The high-bank latch stores the CPU high byte directly. Publish the
    // address directly from the two settled address-bank registers instead
    // of waiting for the third (control) bank.  This advances the external
    // SAM S decode by one complete mux-bank interval while E is still low,
    // giving devices such as the MC6821 their required select setup time.
    // snapshot remains the atomic source for all control signals and its
    // valid pulse still marks completion of the complete transaction scan.
    wire [7:0] high_addr = address_high;
    assign msel = select_reg;
    assign addr = {high_addr, address_low};
    assign rw_n = snapshot[0];
    assign cpu_reset_n = snapshot[1];
    assign slenb_n = snapshot[2];
    assign sernt_n = snapshot[3];
    assign cart_n = snapshot[4];
    assign keyint_n = snapshot[5];
    assign halt_n = snapshot[6];
    assign nmi_n = snapshot[7];
    assign address_ready = address_ready_reg;
    assign snapshot_valid = snapshot_valid_reg;
endmodule
