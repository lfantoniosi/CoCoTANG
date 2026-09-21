// Shared physical-CPU bus logger used by the CoCo 3 integration.
module cpu_bus_logger #(
    parameter integer LOG_ADDR_WIDTH=12,
    parameter integer LOG_COUNT_WIDTH=13,
    parameter integer LOG_DEPTH=4096,
    parameter [15:0] LOG_START_ADDRESS=16'h8002,
    parameter [15:0] LOG_WRITE_START_ADDRESS=16'h0000,
    parameter [15:0] LOG_WRITE_END_ADDRESS=16'h0000,
    // Optional data qualification for write triggers.  Mask bits set to one
    // must equal the corresponding value bits; a zero mask accepts any data.
    parameter [7:0] LOG_WRITE_DATA_MASK=8'h00,
    parameter [7:0] LOG_WRITE_DATA_VALUE=8'h00,
    // Retain only accesses in this inclusive logical-address window.  One
    // extra address can be admitted for an out-of-window trigger/event.
    parameter [15:0] LOG_CAPTURE_START_ADDRESS=16'h0000,
    parameter [15:0] LOG_CAPTURE_END_ADDRESS=16'hffff,
    parameter [15:0] LOG_CAPTURE_EXTRA_ADDRESS=16'hffff,
    // Software landmark. FF9B is an FPGA-owned, unimplemented GIME address,
    // so this write has no machine-visible side effect.
    parameter [15:0] LOG_MARKER_ADDRESS=16'hff9b,
    parameter [7:0] LOG_MARKER_DATA=8'hc7,
    // When set, every matching read or write starts a fresh capture.  When
    // clear, only the first read and first write match after reset rebase it.
    parameter integer LOG_REBASE_EVERY_MATCH=0
) (
    input clk,input reset_n,input capture_enable,input capture_clear,
    input bus_reset_n,
    input e_fall,input q,input rw_n,input [15:0] address,
    input [7:0] cpu_data,input [7:0] expected_data,input [2:0] s,
    input data_oe,input memory_wait,
    input [5:0] mmu_task0_page,input [5:0] mmu_task1_page,
    input mmu_task,input mmu_enabled,
    output reg log_we,output reg [LOG_ADDR_WIDTH-1:0] log_addr,
    output reg [47:0] log_data,
    output reg [LOG_COUNT_WIDTH-1:0] log_count,
    output reg [LOG_ADDR_WIDTH-1:0] log_base,
    output reg rebase_pulse,output reg marker_pulse
);
    reg [15:0] sample_address=16'hffff;
    reg [7:0] sample_data=8'hff,sample_expected=8'hff;
    reg [5:0] sample_mmu_task0=6'h3f,sample_mmu_task1=6'h3f;
    reg sample_mmu_task=0,sample_mmu_enabled=0;
    reg [2:0] sample_s=3'd7;
    reg sample_rw_n=1,sample_oe=0,sample_wait=1;
    reg q_previous=0,q_window_seen=0,q_window_met=0;
    reg [15:0] q_window_address=16'hffff;
    reg trigger_match=0,write_trigger_match=0;
    reg [24:0] last_observation=0;
    reg observation_valid=0,rebased=0,write_rebased=0;
    wire marker_match=e_fall && !sample_rw_n && sample_s==3'd0 &&
                      sample_address==LOG_MARKER_ADDRESS &&
                      sample_data==LOG_MARKER_DATA;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            sample_address<=16'hffff; sample_data<=8'hff;
            sample_expected<=8'hff; sample_s<=3'd7; sample_rw_n<=1;
            sample_mmu_task0<=6'h3f;sample_mmu_task1<=6'h3f;
            sample_mmu_task<=0;sample_mmu_enabled<=0;
            sample_oe<=0; sample_wait<=1; q_previous<=0;
            q_window_seen<=0; q_window_met<=0;
            q_window_address<=16'hffff; trigger_match<=0;
            write_trigger_match<=0;
            marker_pulse<=0;
        end else begin
            // This detector remains live while normal capture is stopped.
            marker_pulse<=marker_match;
            sample_address<=address; sample_data<=cpu_data;
            sample_expected<=expected_data; sample_s<=s;
            sample_mmu_task0<=mmu_task0_page;
            sample_mmu_task1<=mmu_task1_page;
            sample_mmu_task<=mmu_task;sample_mmu_enabled<=mmu_enabled;
            sample_rw_n<=rw_n; sample_oe<=data_oe; sample_wait<=memory_wait;
            q_previous<=q;
            trigger_match<=sample_rw_n && sample_address==LOG_START_ADDRESS &&
                           LOG_START_ADDRESS!=16'h0000;
            write_trigger_match<=!sample_rw_n && sample_s==3'd0 &&
                (LOG_WRITE_START_ADDRESS!=0 || LOG_WRITE_END_ADDRESS!=0) &&
                sample_address>=LOG_WRITE_START_ADDRESS &&
                sample_address<=LOG_WRITE_END_ADDRESS &&
                (sample_data&LOG_WRITE_DATA_MASK)==
                (LOG_WRITE_DATA_VALUE&LOG_WRITE_DATA_MASK);
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
    wire capture_address_match=
        (sample_address>=LOG_CAPTURE_START_ADDRESS &&
         sample_address<=LOG_CAPTURE_END_ADDRESS) ||
        sample_address==LOG_CAPTURE_EXTRA_ADDRESS;
    wire [47:0] entry={1'b1,sample_rw_n,sample_address,sample_data,
                       sample_expected,sample_mmu_enabled,sample_mmu_task,
                       sample_mmu_task0,sample_mmu_task1};

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            log_we<=0; log_addr<=0; log_data<=0; log_count<=0; log_base<=0;
            last_observation<=0; observation_valid<=0;
            rebased<=0; write_rebased<=0; rebase_pulse<=0;
        end else begin
            log_we<=0; rebase_pulse<=0;
            if (!bus_reset_n || capture_clear) begin
                log_addr<=0; log_data<=0; log_count<=0; log_base<=0;
                last_observation<=0; observation_valid<=0;
                rebased<=0; write_rebased<=0;
            end else if (marker_match) begin
                // Retain the landmark itself as entry zero, even while
                // ordinary capture is stopped, and discard the old trace.
                log_we<=1; log_addr<=0; log_data<=entry; log_count<=1;
                log_base<=0;
                last_observation<=observation; observation_valid<=1;
                rebased<=1; write_rebased<=1;
            end else if (!capture_enable) begin
                // Retain a stopped or completed manual capture.
            end else if ((LOG_REBASE_EVERY_MATCH!=0 || !rebased) &&
                         e_fall && trigger_match) begin
                log_we<=1; log_addr<=0; log_data<=entry; log_count<=1;
                log_base<=0;
                last_observation<=observation; observation_valid<=1;
                rebased<=1; rebase_pulse<=1;
            end else if ((LOG_REBASE_EVERY_MATCH!=0 || !write_rebased) && e_fall &&
                         write_trigger_match) begin
                log_we<=1; log_addr<=0; log_data<=entry; log_count<=1;
                log_base<=0;
                last_observation<=observation; observation_valid<=1;
                // A write trigger is independent of LOG_START_ADDRESS.  This
                // permits a write-only logger and also arms normal capture
                // if the reset-vector/read trigger was never observed.
                rebased<=1; write_rebased<=1; rebase_pulse<=1;
            end else if (e_fall && capture_address_match) begin
                log_we<=1; log_data<=entry;
                if (observation_valid && observation==last_observation)
                    log_addr<=log_addr;
                else if(log_count<LOG_DEPTH) begin
                    log_addr<=log_count[LOG_ADDR_WIDTH-1:0];
                    log_count<=log_count+1'b1;
                end else log_we<=0;
                last_observation<=observation; observation_valid<=1;
            end else if (e_fall) begin
                // Preserve true consecutive-cycle duplicate detection even
                // when intervening accesses are intentionally not retained.
                last_observation<=observation; observation_valid<=1;
            end
        end
    end
endmodule
