module coco_bus_mux (
    input         clk,
    input         reset_n,
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
    output        snapshot_valid
);
    reg [1:0] select_reg = 2'b11;
    reg [2:0] phase = 3'd0;
    reg [23:0] previous = 24'hffffff;
    reg [23:0] filtered = 24'hffffff;
    reg [23:0] snapshot = 24'hffffff;
    reg snapshot_valid_reg = 1'b0;
    integer i;

    task sample_bank;
        input integer base;
        begin
            for (i = 0; i < 8; i = i + 1) begin
                if (previous[base+i] == mp[i])
                    filtered[base+i] <= mp[i];
                previous[base+i] <= mp[i];
            end
        end
    endtask

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            select_reg <= 2'b11;
            phase <= 3'd0;
            previous <= 24'hffffff;
            filtered <= 24'hffffff;
            snapshot <= 24'hffffff;
            snapshot_valid_reg <= 1'b0;
        end else begin
            snapshot_valid_reg <= 1'b0;
            case (phase)
                3'd0: begin select_reg <= 2'b00; phase <= 3'd1; end
                3'd1: begin sample_bank(0); select_reg <= 2'b01; phase <= 3'd2; end
                3'd2: phase <= 3'd3;
                3'd3: begin sample_bank(8); select_reg <= 2'b10; phase <= 3'd4; end
                3'd4: phase <= 3'd5;
                default: begin
                    sample_bank(16);
                    snapshot[15:0] <= filtered[15:0];
                    snapshot[23:16] <= filtered[23:16];
                    select_reg <= 2'b00;
                    phase <= 3'd0;
                    snapshot_valid_reg <= 1'b1;
                end
            endcase
        end
    end

    // U10 routes A15,A14,A13 through MP5,MP6,MP7 respectively.
    wire [7:0] high_addr = {snapshot[13], snapshot[14], snapshot[15],
                            snapshot[12], snapshot[11:8]};
    assign msel = select_reg;
    assign addr = {high_addr, snapshot[7:0]};
    assign rw_n = snapshot[16];
    assign cpu_reset_n = snapshot[17];
    assign slenb_n = snapshot[18];
    assign sernt_n = snapshot[19];
    assign cart_n = snapshot[20];
    assign keyint_n = snapshot[21];
    assign halt_n = snapshot[22];
    assign nmi_n = snapshot[23];
    assign snapshot_valid = snapshot_valid_reg;
endmodule
