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
    reg [1:0] select_reg = 2'b00;
    reg [1:0] bank = 2'd0;
    reg [SETTLE_WIDTH-1:0] settle_count = {SETTLE_WIDTH{1'b0}};
    reg       scanning = 1'b0;
    reg [7:0] address_low = 8'hff;
    reg [7:0] address_high = 8'hff;
    reg [23:0] snapshot = 24'hffffff;
    reg address_ready_reg = 1'b0;
    reg snapshot_valid_reg = 1'b0;
    // Pipeline the terminal-count decode before it drives every capture CE.
    // The selected mux bank is already held for SETTLE_CYCLES clocks, so this
    // preserves the sampling instant while removing a high-fanout 270 MHz
    // counter-to-CE path.
    (* syn_preserve = 1 *) reg capture_bank = 1'b0;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            select_reg <= 2'b00;
            bank <= 2'd0;
            settle_count <= {SETTLE_WIDTH{1'b0}};
            scanning <= 1'b0;
            address_low <= 8'hff;
            address_high <= 8'hff;
            snapshot <= 24'hffffff;
            address_ready_reg <= 1'b0;
            snapshot_valid_reg <= 1'b0;
            capture_bank <= 1'b0;
        end else begin
            if (scan_start) begin
                // Q rising begins acquisition of the active CPU cycle. Bank
                // zero has remained selected throughout the idle interval,
                // and the synchronizer has already delayed us beyond Q, so
                // capture it immediately and start settling the high bank.
                // This advances the address/S decode by another complete
                // bank interval without shortening settling after an actual
                // MSEL transition.
                address_low <= mp;
                select_reg <= 2'b01;
                bank <= 2'd1;
                settle_count <= {SETTLE_WIDTH{1'b0}};
                scanning <= 1'b1;
                capture_bank <= 1'b0;
                address_ready_reg <= 1'b0;
                snapshot_valid_reg <= 1'b0;
            end else if (scanning) begin
                // Use a bounded settling interval so input noise cannot
                // prevent the scanner from ever completing.
                if (capture_bank) begin
                    capture_bank <= 1'b0;
                    settle_count <= {SETTLE_WIDTH{1'b0}};
                    case (bank)
                        2'd0: begin
                            address_low <= mp;
                            select_reg <= 2'b01;
                            bank <= 2'd1;
                        end
                        2'd1: begin
                            address_high <= mp;
                            address_ready_reg <= 1'b1;
                            select_reg <= 2'b10;
                            bank <= 2'd2;
                        end
                        default: begin
                            // Publish one complete atomic snapshot, then hold
                            // it until acquisition begins in the next cycle.
                            snapshot <= {mp,address_high,address_low};
                            snapshot_valid_reg <= 1'b1;
                            select_reg <= 2'b00;
                            bank <= 2'd0;
                            scanning <= 1'b0;
                        end
                    endcase
                end else if (settle_count == SETTLE_CYCLES-1)
                    capture_bank <= 1'b1;
                else
                    settle_count <= settle_count + 1'b1;
            end
        end
    end

    // U10 routes A15,A14,A13 through MP0,MP1,MP2 respectively.  Publish the
    // address directly from the two settled address-bank registers instead
    // of waiting for the third (control) bank.  This advances the external
    // SAM S decode by one complete mux-bank interval while E is still low,
    // giving devices such as the MC6821 their required select setup time.
    // snapshot remains the atomic source for all control signals and its
    // valid pulse still marks completion of the complete transaction scan.
    wire [7:0] high_addr = {address_high[0], address_high[1], address_high[2],
                            address_high[7:3]};
    assign msel = select_reg;
    assign addr = {high_addr, address_low};
    assign rw_n = snapshot[16];
    assign cpu_reset_n = snapshot[17];
    assign slenb_n = snapshot[18];
    assign sernt_n = snapshot[19];
    assign cart_n = snapshot[20];
    assign keyint_n = snapshot[21];
    assign halt_n = snapshot[22];
    assign nmi_n = snapshot[23];
    assign address_ready = address_ready_reg;
    assign snapshot_valid = snapshot_valid_reg;
endmodule
