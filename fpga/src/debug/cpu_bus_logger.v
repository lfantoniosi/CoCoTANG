// Shared physical-CPU bus logger used by the CoCo 3 integration.  Its 40-bit
// entry format is identical to the proven CoCo 2 logger/HDMI overlay.
module cpu_bus_logger #(
    parameter integer LOG_ADDR_WIDTH=12,
    parameter integer LOG_COUNT_WIDTH=13,
    parameter integer LOG_DEPTH=4096,
    parameter [15:0] LOG_START_ADDRESS=16'h8002,
    parameter [15:0] LOG_WRITE_START_ADDRESS=16'h0000,
    parameter [15:0] LOG_WRITE_END_ADDRESS=16'h0000,
    // When set, every read from LOG_START_ADDRESS starts a fresh capture.
    // When clear, only the first matching read after reset rebases the log.
    parameter integer LOG_REBASE_EVERY_MATCH=0
) (
    input clk,input reset_n,input capture_enable,input bus_reset_n,
    input e_fall,input q,input rw_n,input [15:0] address,
    input [7:0] cpu_data,input [7:0] expected_data,input [2:0] s,
    input data_oe,input memory_wait,
    output reg log_we,output reg [LOG_ADDR_WIDTH-1:0] log_addr,
    output reg [39:0] log_data,
    output reg [LOG_COUNT_WIDTH-1:0] log_count,
    output reg rebase_pulse
);
    reg [15:0] sample_address=16'hffff;
    reg [7:0] sample_data=8'hff,sample_expected=8'hff;
    reg [2:0] sample_s=3'd7;
    reg sample_rw_n=1,sample_oe=0,sample_wait=1;
    reg q_previous=0,q_window_seen=0,q_window_met=0;
    reg [15:0] q_window_address=16'hffff;
    reg trigger_match=0,write_trigger_match=0;
    reg [24:0] last_observation=0;
    reg observation_valid=0,rebased=0,write_rebased=0;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            sample_address<=16'hffff; sample_data<=8'hff;
            sample_expected<=8'hff; sample_s<=3'd7; sample_rw_n<=1;
            sample_oe<=0; sample_wait<=1; q_previous<=0;
            q_window_seen<=0; q_window_met<=0;
            q_window_address<=16'hffff; trigger_match<=0;
            write_trigger_match<=0;
        end else begin
            sample_address<=address; sample_data<=cpu_data;
            sample_expected<=expected_data; sample_s<=s;
            sample_rw_n<=rw_n; sample_oe<=data_oe; sample_wait<=memory_wait;
            q_previous<=q;
            trigger_match<=sample_rw_n && sample_address==LOG_START_ADDRESS &&
                           LOG_START_ADDRESS!=16'h0000;
            write_trigger_match<=!sample_rw_n && sample_s==3'd0 &&
                (LOG_WRITE_START_ADDRESS!=0 || LOG_WRITE_END_ADDRESS!=0) &&
                sample_address>=LOG_WRITE_START_ADDRESS &&
                sample_address<=LOG_WRITE_END_ADDRESS;
            if (!q_previous && q) begin
                q_window_seen<=0; q_window_met<=0;
            end else if (q_previous && !q) begin
                // Use the input stage captured on the preceding 108 MHz
                // clock.  Apart from making the Q-window observation atomic,
                // this keeps the diagnostic logger off the GIME/MMU-to-I/O
                // critical path.
                q_window_seen<=sample_rw_n && sample_s<=3'd2;
                q_window_address<=sample_address;
                q_window_met<=sample_rw_n && sample_s<=3'd2 && sample_oe &&
                              !sample_wait && sample_data==sample_expected;
            end
        end
    end

    wire logged_memory_cycle=(sample_rw_n && sample_s<=3'd2) ||
                             (!sample_rw_n && sample_s==3'd0);
    wire e_window_met=sample_oe && !sample_wait &&
                      sample_data==sample_expected;
    wire q_window_for_sample=q_window_seen && q_window_met &&
                             q_window_address==sample_address;
    wire [1:0] timing_status=!logged_memory_cycle ? 2'b00 :
        !sample_rw_n ? 2'b10 : !e_window_met ? 2'b01 :
        q_window_for_sample ? 2'b11 : 2'b10;
    wire [24:0] observation={sample_rw_n,sample_address,sample_data};
    wire [39:0] entry={1'b1,sample_rw_n,sample_s,sample_oe,
                       sample_address,sample_data,sample_expected,timing_status};

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            log_we<=0; log_addr<=0; log_data<=0; log_count<=0;
            last_observation<=0; observation_valid<=0;
            rebased<=0; write_rebased<=0; rebase_pulse<=0;
        end else begin
            log_we<=0; rebase_pulse<=0;
            if (!capture_enable || !bus_reset_n) begin
                log_addr<=0; log_data<=0; log_count<=0;
                last_observation<=0; observation_valid<=0;
                rebased<=0; write_rebased<=0;
            end else if ((LOG_REBASE_EVERY_MATCH!=0 || !rebased) &&
                         e_fall && trigger_match) begin
                log_we<=1; log_addr<=0; log_data<=entry; log_count<=1;
                last_observation<=observation; observation_valid<=1;
                rebased<=1; rebase_pulse<=1;
            end else if (rebased &&
                         (LOG_REBASE_EVERY_MATCH!=0 || !write_rebased) && e_fall &&
                         write_trigger_match) begin
                log_we<=1; log_addr<=0; log_data<=entry; log_count<=1;
                last_observation<=observation; observation_valid<=1;
                write_rebased<=1; rebase_pulse<=1;
            end else if (e_fall &&
                         ((observation_valid && observation==last_observation) ||
                          log_count<LOG_DEPTH)) begin
                log_we<=1; log_data<=entry;
                if (observation_valid && observation==last_observation)
                    log_addr<=log_count[LOG_ADDR_WIDTH-1:0]-1'b1;
                else begin
                    log_addr<=log_count[LOG_ADDR_WIDTH-1:0];
                    log_count<=log_count+1'b1;
                end
                last_observation<=observation; observation_valid<=1;
            end
        end
    end
endmodule
