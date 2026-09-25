// Glenside IDE register adapter backed by a 512-byte sector interface.
//
// The original adapter exposes an ATA task-file on $FFx0-$FFx7 and uses
// $FFx8 as the upper-byte latch needed by the CoCo's 8-bit data bus.  Data
// words are written latch-first and read data-first, exactly like the
// physical Glenside board.
module glenside_ata #(
    parameter [15:0] IDE_BASE = 16'hff50,
    parameter integer INIT_TIMEOUT_CYCLES = 1080000000
) (
    input wire clk,
    input wire reset_n,
    input wire cpu_enable,
    input wire e_fall,
    input wire [15:0] cpu_addr,
    input wire cpu_rw_n,
    input wire [7:0] cpu_wdata,
    output reg [7:0] cpu_rdata,
    output wire cpu_data_oe,

    output reg sd_init,
    output reg sd_read_start,
    output reg sd_write_start,
    output reg [31:0] sd_sector,
    input wire sd_busy,
    input wire sd_done,
    input wire sd_error,
    input wire sd_data_valid,
    input wire [8:0] sd_data_addr,
    input wire [7:0] sd_data_in,
    output wire [7:0] sd_data_out,
    input wire [31:0] capacity_sectors
);
    localparam [7:0] ST_ERR  = 8'h01;
    localparam [7:0] ST_DRQ  = 8'h08;
    localparam [7:0] ST_DSC  = 8'h10;
    localparam [7:0] ST_DRDY = 8'h40;
    localparam [7:0] ST_BSY  = 8'h80;

    localparam [3:0] S_INIT_START = 4'd0;
    localparam [3:0] S_INIT_WAIT  = 4'd1;
    localparam [3:0] S_READY      = 4'd2;
    localparam [3:0] S_READ_START = 4'd3;
    localparam [3:0] S_READ_WAIT  = 4'd4;
    localparam [3:0] S_WRITE_DATA = 4'd5;
    localparam [3:0] S_WRITE_START= 4'd6;
    localparam [3:0] S_WRITE_WAIT = 4'd7;
    localparam [3:0] S_IDENTIFY   = 4'd8;
    localparam [3:0] S_READ_NEXT  = 4'd9;
    localparam [3:0] S_WRITE_NEXT = 4'd10;
    localparam [3:0] S_TEST_FILL  = 4'd11;

    localparam integer INIT_COUNT_WIDTH = $clog2(INIT_TIMEOUT_CYCLES + 1);

    wire [15:0] sector_cpu_word;
    wire [7:0] sector_sd_byte;
    reg [3:0] state;
    reg [7:0] status_reg;
    reg [7:0] error_reg;
    reg [7:0] features_reg;
    reg [8:0] sector_count_reg;
    reg [7:0] lba_low_reg;
    reg [7:0] lba_mid_reg;
    reg [7:0] lba_high_reg;
    reg [7:0] device_head_reg;
    reg [7:0] high_latch;
    reg [8:0] data_pointer;
    reg [8:0] identify_pointer;
    reg [8:0] test_pointer;
    reg [8:0] remaining_sectors;
    reg [27:0] active_lba;
    reg [31:0] identify_capacity;
    reg [7:0] command_reg;
    reg command_pending;
    reg identify_transfer;
    reg sd_busy_seen;
    reg card_ready;
    reg [INIT_COUNT_WIDTH-1:0] init_timeout;

    wire selected = cpu_enable && (cpu_addr[15:4] == IDE_BASE[15:4]);
    wire [3:0] register_number = cpu_addr[3:0];
    assign cpu_data_oe = selected && cpu_rw_n;
    assign sd_data_out = sector_sd_byte;

    wire cpu_word_write = selected && e_fall && !cpu_rw_n &&
        (register_number == 4'h0) && (state == S_WRITE_DATA) && status_reg[3];
    wire test_word_write = state == S_TEST_FILL;
    wire sector_sd_write = sd_data_valid && (state == S_READ_WAIT);

    wire [7:0] sector_ata_addr = test_word_write ?
        test_pointer[8:1] : data_pointer[8:1];
    wire [15:0] sector_ata_wdata = test_word_write ?
        {test_pointer[7:0] + 8'd1,test_pointer[7:0]} :
        {high_latch,cpu_wdata};

    function [15:0] identify_word;
        input [7:0] word_number;
        begin
            case (word_number)
                8'd0:  identify_word = 16'h0040; // fixed disk
                8'd1:  identify_word = 16'h3fff;
                8'd3:  identify_word = 16'h0010;
                8'd6:  identify_word = 16'h003f;
                // Serial number "00000000000000000001"
                8'd10,8'd11,8'd12,8'd13,8'd14,
                8'd15,8'd16,8'd17,8'd18: identify_word = 16'h3030;
                8'd19: identify_word = 16'h3031;
                // Firmware revision "1.0     "
                8'd23: identify_word = 16'h312e;
                8'd24: identify_word = 16'h3020;
                8'd25,8'd26: identify_word = 16'h2020;
                // Model "CoCoTANG SD IDE" padded to 40 characters.
                8'd27: identify_word = 16'h436f;
                8'd28: identify_word = 16'h436f;
                8'd29: identify_word = 16'h5441;
                8'd30: identify_word = 16'h4e47;
                8'd31: identify_word = 16'h2053;
                8'd32: identify_word = 16'h4420;
                8'd33: identify_word = 16'h4944;
                8'd34: identify_word = 16'h4520;
                8'd35,8'd36,8'd37,8'd38,8'd39,8'd40,8'd41,8'd42,
                8'd43,8'd44,8'd45,8'd46: identify_word = 16'h2020;
                8'd47: identify_word = 16'h8001;
                8'd49: identify_word = 16'h0200; // LBA supported
                8'd53: identify_word = 16'h0001;
                8'd54: identify_word = 16'h3fff;
                8'd55: identify_word = 16'h0010;
                8'd56: identify_word = 16'h003f;
                8'd57: identify_word = 16'hfc10;
                8'd58: identify_word = 16'h00fb;
                8'd60: identify_word = identify_capacity[15:0];
                8'd61: identify_word = identify_capacity[31:16];
                default: identify_word = 16'h0000;
            endcase
        end
    endfunction

    wire [15:0] ata_read_word=identify_transfer ?
        identify_word(data_pointer[8:1]) : sector_cpu_word;

    glenside_sector_buffer sector_buffer(
        .clk(clk),
        .ata_addr(sector_ata_addr),
        .ata_we(cpu_word_write || test_word_write),
        .ata_wdata(sector_ata_wdata),
        .ata_rdata(sector_cpu_word),
        .sd_addr(sd_data_addr),.sd_we(sector_sd_write),
        .sd_wdata(sd_data_in),.sd_rdata(sector_sd_byte));

    always @* begin
        case (register_number)
            4'h0: cpu_rdata = ata_read_word[7:0];
            4'h1: cpu_rdata = error_reg;
            4'h2: cpu_rdata = sector_count_reg[7:0];
            4'h3: cpu_rdata = lba_low_reg;
            4'h4: cpu_rdata = lba_mid_reg;
            4'h5: cpu_rdata = lba_high_reg;
            4'h6: cpu_rdata = device_head_reg;
            4'h7: cpu_rdata = status_reg;
            4'h8: cpu_rdata = high_latch;
            default: cpu_rdata = 8'hff;
        endcase
    end

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state <= S_INIT_START;
            status_reg <= ST_BSY;
            error_reg <= 8'h00;
            features_reg <= 8'h00;
            sector_count_reg <= 9'd1;
            lba_low_reg <= 8'h00;
            lba_mid_reg <= 8'h00;
            lba_high_reg <= 8'h00;
            device_head_reg <= 8'he0;
            high_latch <= 8'h00;
            data_pointer <= 9'd0;
            identify_pointer <= 9'd0;
            test_pointer <= 9'd0;
            remaining_sectors <= 9'd0;
            active_lba <= 28'd0;
            identify_capacity <= 32'd0;
            command_reg <= 8'h00;
            command_pending <= 1'b0;
            identify_transfer <= 1'b0;
            sd_sector <= 32'd0;
            sd_init <= 1'b0;
            sd_read_start <= 1'b0;
            sd_write_start <= 1'b0;
            sd_busy_seen <= 1'b0;
            card_ready <= 1'b0;
            init_timeout <= INIT_TIMEOUT_CYCLES;
        end else begin
            sd_init <= 1'b0;
            sd_read_start <= 1'b0;
            sd_write_start <= 1'b0;

            // Dispatch commands from a local register.  The task-file write
            // still asserts BSY immediately, but the extra 108 MHz cycle
            // removes the external CPU data bus from the ATA state path.
            if (command_pending) begin
                command_pending <= 1'b0;
                case (command_reg)
                    8'h10,8'h70,8'he7,8'hef: begin
                        status_reg <= ST_DRDY | ST_DSC;
                        state <= S_READY;
                    end
                    8'h90: begin
                        if (card_ready) begin
                            status_reg <= ST_DRDY | ST_DSC;
                            // ATA diagnostic code $01 means device 0 passed.
                            // HDB-DOS requires this exact value after $90.
                            error_reg <= 8'h01;
                            state <= S_READY;
                        end else begin
                            status_reg <= ST_BSY;
                            state <= S_INIT_START;
                        end
                    end
                    8'hec: begin
                        identify_pointer <= 9'd0;
                        data_pointer <= 9'd0;
                        identify_transfer <= 1'b0;
                        identify_capacity <=
                            (capacity_sectors > 32'h0fffffff) ?
                            32'h0fffffff : capacity_sectors;
                        status_reg <= ST_BSY;
                        state <= S_IDENTIFY;
                    end
                    // Private hardware diagnostic: fill the sector DPB with
                    // two copies of 00..FF, then expose it through the normal
                    // ATA data port.  No SD-card transaction is performed.
                    8'he2: begin
                        identify_transfer <= 1'b0;
                        test_pointer <= 9'd0;
                        data_pointer <= 9'd0;
                        remaining_sectors <= 9'd1;
                        status_reg <= ST_BSY;
                        state <= S_TEST_FILL;
                    end
                    8'h20,8'h21: begin
                        identify_transfer <= 1'b0;
                        if (card_ready && device_head_reg[6]) begin
                            active_lba <= {device_head_reg[3:0],lba_high_reg,lba_mid_reg,lba_low_reg};
                            sd_sector <= {4'b0,device_head_reg[3:0],lba_high_reg,lba_mid_reg,lba_low_reg};
                            remaining_sectors <= sector_count_reg;
                            status_reg <= ST_BSY;
                            state <= S_READ_START;
                        end else begin
                            status_reg <= ST_DRDY | ST_DSC | ST_ERR;
                            error_reg <= 8'h04;
                        end
                    end
                    8'h30,8'h31: begin
                        identify_transfer <= 1'b0;
                        if (card_ready && device_head_reg[6]) begin
                            active_lba <= {device_head_reg[3:0],lba_high_reg,lba_mid_reg,lba_low_reg};
                            sd_sector <= {4'b0,device_head_reg[3:0],lba_high_reg,lba_mid_reg,lba_low_reg};
                            remaining_sectors <= sector_count_reg;
                            data_pointer <= 9'd0;
                            status_reg <= ST_DRDY | ST_DSC | ST_DRQ;
                            state <= S_WRITE_DATA;
                        end else begin
                            status_reg <= ST_DRDY | ST_DSC | ST_ERR;
                            error_reg <= 8'h04;
                        end
                    end
                    default: begin
                        status_reg <= ST_DRDY | ST_DSC | ST_ERR;
                        error_reg <= 8'h04;
                        state <= S_READY;
                    end
                endcase
            end

            case (state)
                S_INIT_START: begin
                    sd_init <= 1'b1;
                    sd_busy_seen <= 1'b0;
                    init_timeout <= INIT_TIMEOUT_CYCLES;
                    state <= S_INIT_WAIT;
                end
                S_INIT_WAIT: begin
                    if (sd_busy)
                        sd_busy_seen <= 1'b1;
                    if (sd_busy_seen && !sd_busy) begin
                        card_ready <= !sd_error;
                        status_reg <= sd_error ?
                                      (ST_DRDY | ST_DSC | ST_ERR) :
                                      (ST_DRDY | ST_DSC);
                        // $01 is the ATA device-0 diagnostic pass code.
                        error_reg <= sd_error ? 8'h04 : 8'h01;
                        state <= S_READY;
                    end else if (init_timeout != 0) begin
                        init_timeout <= init_timeout - 1'b1;
                    end else begin
                        card_ready <= 1'b0;
                        status_reg <= ST_DRDY | ST_DSC | ST_ERR;
                        error_reg <= 8'h04;
                        state <= S_READY;
                    end
                end
                S_READ_START: begin
                    if (!sd_busy) begin
                        sd_read_start <= 1'b1;
                        sd_busy_seen <= 1'b0;
                        state <= S_READ_WAIT;
                    end
                end
                S_READ_WAIT: begin
                    if (sd_busy)
                        sd_busy_seen <= 1'b1;
                    if (sd_done || (sd_busy_seen && !sd_busy)) begin
                        if (sd_error) begin
                            status_reg <= ST_DRDY | ST_DSC | ST_ERR;
                            error_reg <= 8'h40;
                        end else begin
                            data_pointer <= 9'd0;
                            status_reg <= ST_DRDY | ST_DSC | ST_DRQ;
                        end
                        state <= S_READY;
                    end
                end
                S_WRITE_START: begin
                    if (!sd_busy) begin
                        sd_write_start <= 1'b1;
                        sd_busy_seen <= 1'b0;
                        state <= S_WRITE_WAIT;
                    end
                end
                S_WRITE_WAIT: begin
                    if (sd_busy)
                        sd_busy_seen <= 1'b1;
                    if (sd_done || (sd_busy_seen && !sd_busy)) begin
                        if (sd_error) begin
                            status_reg <= ST_DRDY | ST_DSC | ST_ERR;
                            error_reg <= 8'h40;
                            state <= S_READY;
                        end else if (remaining_sectors > 9'd1) begin
                            remaining_sectors <= remaining_sectors - 1'b1;
                            sector_count_reg <= remaining_sectors - 1'b1;
                            active_lba <= active_lba + 1'b1;
                            status_reg <= ST_BSY;
                            state <= S_WRITE_NEXT;
                        end else begin
                            remaining_sectors <= 9'd0;
                            sector_count_reg <= 9'd0;
                            status_reg <= ST_DRDY | ST_DSC;
                            state <= S_READY;
                        end
                    end
                end
                S_IDENTIFY: begin
                    if (identify_pointer == 9'd255) begin
                        data_pointer <= 9'd0;
                        identify_transfer <= 1'b1;
                        status_reg <= ST_DRDY | ST_DSC | ST_DRQ;
                        state <= S_READY;
                    end else begin
                        identify_pointer <= identify_pointer + 1'b1;
                    end
                end
                S_READ_NEXT: begin
                    sd_sector <= {4'b0,active_lba};
                    device_head_reg[3:0] <= active_lba[27:24];
                    lba_high_reg <= active_lba[23:16];
                    lba_mid_reg <= active_lba[15:8];
                    lba_low_reg <= active_lba[7:0];
                    state <= S_READ_START;
                end
                S_WRITE_NEXT: begin
                    sd_sector <= {4'b0,active_lba};
                    device_head_reg[3:0] <= active_lba[27:24];
                    lba_high_reg <= active_lba[23:16];
                    lba_mid_reg <= active_lba[15:8];
                    lba_low_reg <= active_lba[7:0];
                    data_pointer <= 9'd0;
                    status_reg <= ST_DRDY | ST_DSC | ST_DRQ;
                    state <= S_WRITE_DATA;
                end
                S_TEST_FILL: begin
                    if (test_pointer == 9'd510) begin
                        data_pointer <= 9'd0;
                        status_reg <= ST_DRDY | ST_DSC | ST_DRQ;
                        state <= S_READY;
                    end else begin
                        test_pointer <= test_pointer + 9'd2;
                    end
                end
                default: begin
                    // S_READY and S_WRITE_DATA are driven by task-file accesses.
                end
            endcase

            if (selected && e_fall) begin
                if (!cpu_rw_n) begin
                    case (register_number)
                        4'h0: begin
                            if (state == S_WRITE_DATA && status_reg[3]) begin
                                if (data_pointer == 9'd510) begin
                                    status_reg <= ST_BSY;
                                    state <= S_WRITE_START;
                                end else begin
                                    data_pointer <= data_pointer + 9'd2;
                                end
                            end
                        end
                        4'h1: features_reg <= cpu_wdata;
                        4'h2: sector_count_reg <= (cpu_wdata == 0) ? 9'd256 : {1'b0,cpu_wdata};
                        4'h3: lba_low_reg <= cpu_wdata;
                        4'h4: lba_mid_reg <= cpu_wdata;
                        4'h5: lba_high_reg <= cpu_wdata;
                        4'h6: device_head_reg <= cpu_wdata;
                        4'h7: begin
                            error_reg <= 8'h00;
                            status_reg <= ST_BSY;
                            command_reg <= cpu_wdata;
                            command_pending <= 1'b1;
                        end
                        4'h8: high_latch <= cpu_wdata;
                        default: begin end
                    endcase
                end else begin
                    case (register_number)
                        4'h0: begin
                            if (status_reg[3] && state == S_READY) begin
                                high_latch <= ata_read_word[15:8];
                                if (data_pointer == 9'd510) begin
                                    identify_transfer <= 1'b0;
                                    if (remaining_sectors > 9'd1) begin
                                        remaining_sectors <= remaining_sectors - 1'b1;
                                        sector_count_reg <= remaining_sectors - 1'b1;
                                        active_lba <= active_lba + 1'b1;
                                        status_reg <= ST_BSY;
                                        state <= S_READ_NEXT;
                                    end else begin
                                        remaining_sectors <= 9'd0;
                                        sector_count_reg <= 9'd0;
                                        status_reg <= ST_DRDY | ST_DSC;
                                    end
                                end else begin
                                    data_pointer <= data_pointer + 9'd2;
                                end
                            end
                        end
                        default: begin end
                    endcase
                end
            end
        end
    end
endmodule
