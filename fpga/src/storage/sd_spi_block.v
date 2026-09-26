// SD-card SPI-mode single-block controller.
//
// The interface deliberately matches the byte-stream side of sd_reader so
// the Glenside ATA task-file and its sector buffer remain unchanged.  SPI
// wiring is the standard SD mapping: CMD=MOSI, DAT0=MISO and DAT3=CS_n.
module sd_spi_block #(
    parameter integer INIT_DIV = 135, // 108 MHz / (2*135) = 400 kHz
    parameter integer DATA_DIV = 54,  // 108 MHz / (2*54)  = 1.000 MHz
    parameter integer RESPONSE_TIMEOUT = 65535
) (
    input  wire        clk,
    input  wire        reset_n,
    input  wire        init,
    input  wire        read_start,
    input  wire        write_start,
    input  wire [31:0] sector,
    output reg         busy,
    output reg         done,
    output reg         error,
    output reg         data_valid,
    output reg  [8:0]  data_addr,
    output reg  [7:0]  data_out,
    input  wire [7:0]  data_in,
    output wire [31:0] capacity_sectors,
    output wire        sd_sclk,
    output reg         sd_cs_n,
    output wire        sd_mosi,
    input  wire        sd_miso
);
    localparam [5:0]
        ST_IDLE             = 6'd0,
        ST_INIT_CLOCK_START = 6'd1,
        ST_INIT_CLOCK_WAIT  = 6'd2,
        ST_CMD_SEND_START   = 6'd3,
        ST_CMD_SEND_WAIT    = 6'd4,
        ST_CMD_R1_START     = 6'd5,
        ST_CMD_R1_WAIT      = 6'd6,
        ST_CMD0_DONE        = 6'd7,
        ST_CMD8_DONE        = 6'd8,
        ST_CMD8_EXTRA_START = 6'd9,
        ST_CMD8_EXTRA_WAIT  = 6'd10,
        ST_CMD55_DONE       = 6'd11,
        ST_ACMD41_DONE      = 6'd12,
        ST_CMD58_DONE       = 6'd13,
        ST_CMD58_EXTRA_START= 6'd14,
        ST_CMD58_EXTRA_WAIT = 6'd15,
        ST_CMD16_DONE       = 6'd16,
        ST_READ_CMD_DONE    = 6'd17,
        ST_READ_TOKEN_START = 6'd18,
        ST_READ_TOKEN_WAIT  = 6'd19,
        ST_READ_DATA_START  = 6'd20,
        ST_READ_DATA_WAIT   = 6'd21,
        ST_READ_CRC_START   = 6'd22,
        ST_READ_CRC_WAIT    = 6'd23,
        ST_WRITE_CMD_DONE   = 6'd24,
        ST_WRITE_GAP_START  = 6'd25,
        ST_WRITE_GAP_WAIT   = 6'd26,
        ST_WRITE_TOKEN_START= 6'd27,
        ST_WRITE_TOKEN_WAIT = 6'd28,
        ST_WRITE_PREFETCH1  = 6'd29,
        ST_WRITE_PREFETCH2  = 6'd30,
        ST_WRITE_DATA_START = 6'd31,
        ST_WRITE_DATA_WAIT  = 6'd32,
        ST_WRITE_CRC_START  = 6'd33,
        ST_WRITE_CRC_WAIT   = 6'd34,
        ST_WRITE_RESP_START = 6'd35,
        ST_WRITE_RESP_WAIT  = 6'd36,
        ST_WRITE_BUSY_START = 6'd37,
        ST_WRITE_BUSY_WAIT  = 6'd38,
        ST_FINISH_START     = 6'd39,
        ST_FINISH_WAIT      = 6'd40,
        ST_TIMEOUT_INCREMENT= 6'd41;

    reg [5:0] state;
    reg [5:0] command;
    reg [31:0] argument;
    reg [7:0] command_crc;
    reg [2:0] command_index;
    reg [5:0] command_return;
    reg [7:0] last_r1;
    reg [2:0] extra_count;
    reg [7:0] ocr_first;
    reg card_v2;
    reg high_capacity;
    reg [15:0] init_retry_count;
    reg [15:0] timeout_count;
    reg [5:0] timeout_return;
    reg [3:0] init_clock_count;
    reg [8:0] byte_count;
    reg [1:0] crc_count;
    reg [15:0] block_crc;
    reg [7:0] received_crc_high;
    reg [7:0] write_byte;
    reg operation_error;

    // Capacity is not needed to address the card.  Report the largest LBA28
    // device until CSD parsing is added; HDB-DOS only requires LBA capability.
    assign capacity_sectors = 32'h0fffffff;

    function [7:0] command_byte;
        input [2:0] index;
        begin
            case (index)
                3'd0: command_byte={2'b01,command};
                3'd1: command_byte=argument[31:24];
                3'd2: command_byte=argument[23:16];
                3'd3: command_byte=argument[15:8];
                3'd4: command_byte=argument[7:0];
                default: command_byte=command_crc;
            endcase
        end
    endfunction

    // SD data-block CRC16: x^16 + x^12 + x^5 + 1, MSB first.
    function [15:0] crc16_byte;
        input [15:0] crc_in;
        input [7:0] data;
        reg [15:0] value;
        integer bit_index;
        begin
            value=crc_in;
            for(bit_index=7;bit_index>=0;bit_index=bit_index-1) begin
                if (value[15] ^ data[bit_index])
                    value={value[14:0],1'b0} ^ 16'h1021;
                else
                    value={value[14:0],1'b0};
            end
            crc16_byte=value;
        end
    endfunction

    // Mode-0 SPI byte engine.  MOSI changes on falling edges and MISO is
    // sampled on rising edges, as required by SD SPI mode.
    reg [15:0] clock_divider;
    reg [15:0] divider_count;
    reg spi_clock;
    reg spi_start;
    reg spi_active;
    reg spi_done;
    reg [7:0] spi_tx;
    reg [7:0] tx_shift;
    reg [7:0] rx_shift;
    reg [7:0] spi_rx;
    reg [2:0] bit_count;
    reg mosi_reg;

    assign sd_sclk=spi_clock;
    assign sd_mosi=mosi_reg;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            divider_count<=0;
            spi_clock<=0;
            spi_active<=0;
            spi_done<=0;
            tx_shift<=8'hff;
            rx_shift<=0;
            spi_rx<=8'hff;
            bit_count<=0;
            mosi_reg<=1;
        end else begin
            spi_done<=0;
            if (spi_start && !spi_active) begin
                divider_count<=0;
                spi_clock<=0;
                spi_active<=1;
                tx_shift<=spi_tx;
                rx_shift<=0;
                bit_count<=3'd7;
                mosi_reg<=spi_tx[7];
            end else if (spi_active) begin
                if (divider_count == clock_divider-1) begin
                    divider_count<=0;
                    if (!spi_clock) begin
                        spi_clock<=1;
                        rx_shift<={rx_shift[6:0],sd_miso};
                    end else begin
                        spi_clock<=0;
                        if (bit_count==0) begin
                            spi_active<=0;
                            spi_done<=1;
                            spi_rx<=rx_shift;
                            mosi_reg<=1;
                        end else begin
                            bit_count<=bit_count-1'b1;
                            tx_shift<={tx_shift[6:0],1'b1};
                            mosi_reg<=tx_shift[6];
                        end
                    end
                end else begin
                    divider_count<=divider_count+1'b1;
                end
            end
        end
    end

    task launch_command;
        input [5:0] cmd;
        input [31:0] arg;
        input [7:0] crc;
        input [5:0] return_state;
        begin
            command<=cmd;
            argument<=arg;
            command_crc<=crc;
            command_index<=0;
            command_return<=return_state;
            timeout_count<=0;
            timeout_return<=ST_IDLE;
            state<=ST_CMD_SEND_START;
        end
    endtask

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state<=ST_IDLE;
            busy<=0;
            done<=0;
            error<=0;
            data_valid<=0;
            data_addr<=0;
            data_out<=0;
            sd_cs_n<=1;
            clock_divider<=INIT_DIV;
            spi_start<=0;
            spi_tx<=8'hff;
            command<=0;
            argument<=0;
            command_crc<=8'hff;
            command_index<=0;
            command_return<=ST_IDLE;
            last_r1<=8'hff;
            extra_count<=0;
            ocr_first<=0;
            card_v2<=0;
            high_capacity<=0;
            init_retry_count<=0;
            timeout_count<=0;
            init_clock_count<=0;
            byte_count<=0;
            crc_count<=0;
            block_crc<=0;
            received_crc_high<=0;
            write_byte<=0;
            operation_error<=0;
        end else begin
            done<=0;
            data_valid<=0;
            spi_start<=0;

            case (state)
                ST_IDLE: begin
                    sd_cs_n<=1;
                    if (init) begin
                        busy<=1;
                        error<=0;
                        operation_error<=0;
                        clock_divider<=INIT_DIV;
                        init_clock_count<=0;
                        init_retry_count<=0;
                        card_v2<=0;
                        high_capacity<=0;
                        state<=ST_INIT_CLOCK_START;
                    end else if (read_start) begin
                        busy<=1;
                        error<=0;
                        operation_error<=0;
                        byte_count<=0;
                        launch_command(6'd17,
                            high_capacity ? sector : {sector[22:0],9'b0},
                            8'hff,ST_READ_CMD_DONE);
                    end else if (write_start) begin
                        busy<=1;
                        error<=0;
                        operation_error<=0;
                        byte_count<=0;
                        launch_command(6'd24,
                            high_capacity ? sector : {sector[22:0],9'b0},
                            8'hff,ST_WRITE_CMD_DONE);
                    end
                end

                ST_INIT_CLOCK_START: if (!spi_active) begin
                    sd_cs_n<=1; spi_tx<=8'hff; spi_start<=1;
                    state<=ST_INIT_CLOCK_WAIT;
                end
                ST_INIT_CLOCK_WAIT: if (spi_done) begin
                    if (init_clock_count==4'd9)
                        launch_command(6'd0,32'd0,8'h95,ST_CMD0_DONE);
                    else begin
                        init_clock_count<=init_clock_count+1'b1;
                        state<=ST_INIT_CLOCK_START;
                    end
                end

                ST_CMD_SEND_START: if (!spi_active) begin
                    // Assert CS in this dedicated launch state rather than
                    // through every caller of launch_command.  Besides being
                    // protocol-equivalent, this keeps initialization retry
                    // decisions off the 108-MHz chip-select timing path.
                    sd_cs_n<=0;
                    spi_tx<=command_byte(command_index); spi_start<=1;
                    state<=ST_CMD_SEND_WAIT;
                end
                ST_CMD_SEND_WAIT: if (spi_done) begin
                    if (command_index==3'd5) state<=ST_CMD_R1_START;
                    else begin
                        command_index<=command_index+1'b1;
                        state<=ST_CMD_SEND_START;
                    end
                end
                ST_CMD_R1_START: if (!spi_active) begin
                    spi_tx<=8'hff; spi_start<=1; state<=ST_CMD_R1_WAIT;
                end
                ST_CMD_R1_WAIT: if (spi_done) begin
                    if (!spi_rx[7]) begin
                        last_r1<=spi_rx;
                        state<=command_return;
                    end else if (timeout_count==RESPONSE_TIMEOUT) begin
                        operation_error<=1;
                        state<=ST_FINISH_START;
                    end else begin
                        timeout_return<=ST_CMD_R1_START;
                        state<=ST_TIMEOUT_INCREMENT;
                    end
                end

                ST_CMD0_DONE: begin
                    if (last_r1==8'h01) begin
                        init_retry_count<=0;
                        launch_command(6'd8,32'h000001aa,8'h87,ST_CMD8_DONE);
                    end else if (init_retry_count==16'hffff) begin
                        operation_error<=1;
                        state<=ST_FINISH_START;
                    end else begin
                        init_retry_count<=init_retry_count+1'b1;
                        launch_command(6'd0,32'd0,8'h95,ST_CMD0_DONE);
                    end
                end
                ST_CMD8_DONE: begin
                    if (last_r1==8'h01) begin
                        card_v2<=1;
                        extra_count<=0; state<=ST_CMD8_EXTRA_START;
                    end else begin
                        // An illegal CMD8 is an older SDSC card; continue
                        // initialization without the HCS request.
                        high_capacity<=0;
                        launch_command(6'd55,32'd0,8'hff,ST_CMD55_DONE);
                    end
                end
                ST_CMD8_EXTRA_START: if (!spi_active) begin
                    spi_tx<=8'hff; spi_start<=1; state<=ST_CMD8_EXTRA_WAIT;
                end
                ST_CMD8_EXTRA_WAIT: if (spi_done) begin
                    if (extra_count==3)
                        launch_command(6'd55,32'd0,8'hff,ST_CMD55_DONE);
                    else begin extra_count<=extra_count+1'b1; state<=ST_CMD8_EXTRA_START; end
                end
                ST_CMD55_DONE:
                    launch_command(6'd41,card_v2 ? 32'h40000000 : 32'd0,
                                   8'hff,ST_ACMD41_DONE);
                ST_ACMD41_DONE: begin
                    if (last_r1==0) begin
                        init_retry_count<=0;
                        launch_command(6'd58,32'd0,8'hff,ST_CMD58_DONE);
                    end else if (init_retry_count==16'hffff) begin
                        operation_error<=1;
                        state<=ST_FINISH_START;
                    end else begin
                        init_retry_count<=init_retry_count+1'b1;
                        launch_command(6'd55,32'd0,8'hff,ST_CMD55_DONE);
                    end
                end
                ST_CMD58_DONE: begin
                    if (last_r1!=0) begin operation_error<=1; state<=ST_FINISH_START; end
                    else begin extra_count<=0; state<=ST_CMD58_EXTRA_START; end
                end
                ST_CMD58_EXTRA_START: if (!spi_active) begin
                    spi_tx<=8'hff; spi_start<=1; state<=ST_CMD58_EXTRA_WAIT;
                end
                ST_CMD58_EXTRA_WAIT: if (spi_done) begin
                    if (extra_count==0) ocr_first<=spi_rx;
                    if (extra_count==3) begin
                        high_capacity<=card_v2 && ocr_first[6];
                        if (card_v2 && ocr_first[6]) begin
                            clock_divider<=DATA_DIV;
                            sd_cs_n<=1; busy<=0; state<=ST_IDLE;
                        end else begin
                            launch_command(6'd16,32'd512,8'hff,ST_CMD16_DONE);
                        end
                    end else begin extra_count<=extra_count+1'b1; state<=ST_CMD58_EXTRA_START; end
                end
                ST_CMD16_DONE: begin
                    if (last_r1!=0) begin operation_error<=1; state<=ST_FINISH_START; end
                    else begin clock_divider<=DATA_DIV; sd_cs_n<=1; busy<=0; state<=ST_IDLE; end
                end

                ST_READ_CMD_DONE: begin
                    if (last_r1!=0) begin operation_error<=1; state<=ST_FINISH_START; end
                    else begin timeout_count<=0; state<=ST_READ_TOKEN_START; end
                end
                ST_READ_TOKEN_START: if (!spi_active) begin
                    spi_tx<=8'hff; spi_start<=1; state<=ST_READ_TOKEN_WAIT;
                end
                ST_READ_TOKEN_WAIT: if (spi_done) begin
                    if (spi_rx==8'hfe) begin
                        byte_count<=0;
                        block_crc<=0;
                        state<=ST_READ_DATA_START;
                    end
                    else if (spi_rx!=8'hff || timeout_count==RESPONSE_TIMEOUT) begin
                        operation_error<=1; state<=ST_FINISH_START;
                    end else begin
                        timeout_return<=ST_READ_TOKEN_START;
                        state<=ST_TIMEOUT_INCREMENT;
                    end
                end
                ST_READ_DATA_START: if (!spi_active) begin
                    spi_tx<=8'hff; spi_start<=1; state<=ST_READ_DATA_WAIT;
                end
                ST_READ_DATA_WAIT: if (spi_done) begin
                    data_addr<=byte_count;
                    data_out<=spi_rx;
                    data_valid<=1;
                    block_crc<=crc16_byte(block_crc,spi_rx);
                    if (byte_count==9'd511) begin crc_count<=0; state<=ST_READ_CRC_START; end
                    else begin byte_count<=byte_count+1'b1; state<=ST_READ_DATA_START; end
                end
                ST_READ_CRC_START: if (!spi_active) begin
                    spi_tx<=8'hff; spi_start<=1; state<=ST_READ_CRC_WAIT;
                end
                ST_READ_CRC_WAIT: if (spi_done) begin
                    if (crc_count==1) begin
                        if ({received_crc_high,spi_rx} != block_crc)
                            operation_error<=1;
                        state<=ST_FINISH_START;
                    end else begin
                        received_crc_high<=spi_rx;
                        crc_count<=crc_count+1'b1;
                        state<=ST_READ_CRC_START;
                    end
                end

                ST_WRITE_CMD_DONE: begin
                    if (last_r1!=0) begin operation_error<=1; state<=ST_FINISH_START; end
                    else state<=ST_WRITE_GAP_START;
                end
                ST_WRITE_GAP_START: if (!spi_active) begin
                    spi_tx<=8'hff; spi_start<=1; state<=ST_WRITE_GAP_WAIT;
                end
                ST_WRITE_GAP_WAIT: if (spi_done) state<=ST_WRITE_TOKEN_START;
                ST_WRITE_TOKEN_START: if (!spi_active) begin
                    spi_tx<=8'hfe; spi_start<=1; state<=ST_WRITE_TOKEN_WAIT;
                end
                ST_WRITE_TOKEN_WAIT: if (spi_done) begin
                    byte_count<=0;
                    data_addr<=0;
                    block_crc<=0;
                    state<=ST_WRITE_PREFETCH1;
                end
                ST_WRITE_PREFETCH1: state<=ST_WRITE_PREFETCH2;
                ST_WRITE_PREFETCH2: begin write_byte<=data_in; state<=ST_WRITE_DATA_START; end
                ST_WRITE_DATA_START: if (!spi_active) begin
                    spi_tx<=write_byte; spi_start<=1; state<=ST_WRITE_DATA_WAIT;
                end
                ST_WRITE_DATA_WAIT: if (spi_done) begin
                    block_crc<=crc16_byte(block_crc,write_byte);
                    if (byte_count==9'd511) begin crc_count<=0; state<=ST_WRITE_CRC_START; end
                    else begin
                        byte_count<=byte_count+1'b1;
                        data_addr<=byte_count+1'b1;
                        state<=ST_WRITE_PREFETCH1;
                    end
                end
                ST_WRITE_CRC_START: if (!spi_active) begin
                    spi_tx<=(crc_count==0) ? block_crc[15:8] : block_crc[7:0];
                    spi_start<=1;
                    state<=ST_WRITE_CRC_WAIT;
                end
                ST_WRITE_CRC_WAIT: if (spi_done) begin
                    if (crc_count==1) state<=ST_WRITE_RESP_START;
                    else begin crc_count<=crc_count+1'b1; state<=ST_WRITE_CRC_START; end
                end
                ST_WRITE_RESP_START: if (!spi_active) begin
                    spi_tx<=8'hff; spi_start<=1; state<=ST_WRITE_RESP_WAIT;
                end
                ST_WRITE_RESP_WAIT: if (spi_done) begin
                    if ((spi_rx & 8'h1f)!=8'h05) operation_error<=1;
                    timeout_count<=0;
                    state<=ST_WRITE_BUSY_START;
                end
                ST_WRITE_BUSY_START: if (!spi_active) begin
                    spi_tx<=8'hff; spi_start<=1; state<=ST_WRITE_BUSY_WAIT;
                end
                ST_WRITE_BUSY_WAIT: if (spi_done) begin
                    if (spi_rx==8'hff) state<=ST_FINISH_START;
                    else if (timeout_count==RESPONSE_TIMEOUT) begin
                        operation_error<=1;
                        state<=ST_FINISH_START;
                    end else begin
                        timeout_return<=ST_WRITE_BUSY_START;
                        state<=ST_TIMEOUT_INCREMENT;
                    end
                end

                // Timeout counters advance only once per complete SPI byte.
                // Isolating the increment from the three caller branches
                // removes their select logic from the 16-bit carry path.
                ST_TIMEOUT_INCREMENT: begin
                    timeout_count<=timeout_count+1'b1;
                    state<=timeout_return;
                end

                ST_FINISH_START: if (!spi_active) begin
                    sd_cs_n<=1; spi_tx<=8'hff; spi_start<=1; state<=ST_FINISH_WAIT;
                end
                ST_FINISH_WAIT: if (spi_done) begin
                    error<=operation_error;
                    done<=1;
                    busy<=0;
                    state<=ST_IDLE;
                end
                default: state<=ST_IDLE;
            endcase
        end
    end
endmodule
