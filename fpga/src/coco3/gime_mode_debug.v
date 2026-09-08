module gime_mode_debug #(
    parameter integer STABLE_CYCLES = 1080000
) (
    input        clk,
    input        reset_n,
    input        button,
    output reg   bit_plane,
    output reg [2:0] hres,
    output reg [1:0] cres,
    output reg [1:0] lpf,
    output reg [2:0] lines_per_row_code
);
    localparam integer COUNTER_WIDTH =
        (STABLE_CYCLES <= 1) ? 1 : $clog2(STABLE_CYCLES);
    localparam integer MODES_PER_HEIGHT = 24;
    localparam integer MODE_COUNT = 72;

    reg button_meta = 1'b0;
    reg button_sync = 1'b0;
    reg button_state = 1'b0;
    reg [COUNTER_WIDTH-1:0] stable_count = {COUNTER_WIDTH{1'b0}};
    reg [6:0] selection = 7'd0;
    reg [4:0] mode_index;

    always @(*) begin
        if (selection < 7'd24) begin
            lpf = 2'b00;       // 192 lines
            mode_index = selection[4:0];
        end else if (selection < 7'd48) begin
            lpf = 2'b01;       // 199 visible lines (GIME 200-line quirk)
            mode_index = selection[4:0] - 5'd24;
        end else begin
            lpf = 2'b11;       // 225 lines
            mode_index = selection[4:0] - 5'd16;
        end

        bit_plane = 1'b0;
        hres = 3'b000;
        cres = 2'b00;
        lines_per_row_code = 3'b011; // eight scan lines per text row
        case (mode_index)
            // 32/40/64/80-column text, without and with attributes.
            5'd0:  begin hres=3'b000; cres=2'b00; end
            5'd1:  begin hres=3'b001; cres=2'b00; end
            5'd2:  begin hres=3'b100; cres=2'b00; end
            5'd3:  begin hres=3'b101; cres=2'b00; end
            5'd4:  begin hres=3'b000; cres=2'b01; end
            5'd5:  begin hres=3'b001; cres=2'b01; end
            5'd6:  begin hres=3'b100; cres=2'b01; end
            5'd7:  begin hres=3'b101; cres=2'b01; end
            // Common documented graphics modes, ordered by width/depth.
            5'd8:  begin bit_plane=1'b1; hres=3'b000; cres=2'b00; end // 128x2
            5'd9:  begin bit_plane=1'b1; hres=3'b001; cres=2'b00; end // 160x2
            5'd10: begin bit_plane=1'b1; hres=3'b010; cres=2'b00; end // 256x2
            5'd11: begin bit_plane=1'b1; hres=3'b011; cres=2'b00; end // 320x2
            5'd12: begin bit_plane=1'b1; hres=3'b100; cres=2'b00; end // 512x2
            5'd13: begin bit_plane=1'b1; hres=3'b101; cres=2'b00; end // 640x2
            5'd14: begin bit_plane=1'b1; hres=3'b011; cres=2'b01; end // 160x4
            5'd15: begin bit_plane=1'b1; hres=3'b100; cres=2'b01; end // 256x4
            5'd16: begin bit_plane=1'b1; hres=3'b101; cres=2'b01; end // 320x4
            5'd17: begin bit_plane=1'b1; hres=3'b110; cres=2'b01; end // 512x4
            5'd18: begin bit_plane=1'b1; hres=3'b111; cres=2'b01; end // 640x4
            5'd19: begin bit_plane=1'b1; hres=3'b010; cres=2'b01; end // 128x4
            5'd20: begin bit_plane=1'b1; hres=3'b100; cres=2'b10; end // 128x16
            5'd21: begin bit_plane=1'b1; hres=3'b101; cres=2'b10; end // 160x16
            5'd22: begin bit_plane=1'b1; hres=3'b110; cres=2'b10; end // 256x16
            5'd23: begin bit_plane=1'b1; hres=3'b111; cres=2'b10; end // 320x16
            default: ;
        endcase
        if (bit_plane)
            lines_per_row_code = 3'b000;
    end

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            button_meta <= 1'b0;
            button_sync <= 1'b0;
            button_state <= 1'b0;
            stable_count <= {COUNTER_WIDTH{1'b0}};
            selection <= 7'd0;
        end else begin
            button_meta <= button;
            button_sync <= button_meta;
            if (button_sync == button_state) begin
                stable_count <= {COUNTER_WIDTH{1'b0}};
            end else if (STABLE_CYCLES <= 1 || stable_count == STABLE_CYCLES-1) begin
                button_state <= button_sync;
                stable_count <= {COUNTER_WIDTH{1'b0}};
                if (button_sync)
                    selection <= selection == MODE_COUNT-1 ? 7'd0 : selection + 1'b1;
            end else begin
                stable_count <= stable_count + 1'b1;
            end
        end
    end
endmodule
