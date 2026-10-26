// Shared physical-CPU bus logger used by the CoCo 3 integration.
module cpu_bus_logger #(
    parameter integer LOG_ADDR_WIDTH=12,
    parameter integer LOG_COUNT_WIDTH=13,
    parameter integer LOG_DEPTH=4096,
    parameter [15:0] LOG_START_ADDRESS=16'h8002,
    parameter [15:0] LOG_END_ADDRESS=16'h0000,
    parameter integer LOG_RING_MODE=0,
    parameter integer LOG_DEDUP=0,
    // Restrict start/rebase triggers to reads; capture still includes writes.
    parameter integer LOG_READS_ONLY=0
) (
    input clk,input reset_n,input capture_enable,input capture_clear,
    input nmi_event,input bus_reset_n,
    input e_fall,input q,input rw_n,input [15:0] address,
    input [7:0] cpu_data,input [7:0] expected_data,input [2:0] s,
    input data_oe,input memory_wait,
    input [5:0] mmu_task0_page,input [5:0] mmu_task1_page,
    input mmu_task,input mmu_enabled,
    output reg log_we,output reg [LOG_ADDR_WIDTH-1:0] log_addr,
    output reg [47:0] log_data,
    output reg [LOG_COUNT_WIDTH-1:0] log_count,
    output reg [LOG_ADDR_WIDTH-1:0] log_base,
    output reg rebase_pulse,output reg end_pulse
);
    reg [15:0] sample_address=16'hffff;
    reg [7:0] sample_data=8'hff,sample_expected=8'hff;
    reg [5:0] sample_mmu_task0=6'h3f,sample_mmu_task1=6'h3f;
    reg sample_mmu_task=0,sample_mmu_enabled=0;
    reg [2:0] sample_s=3'd7;
    reg sample_rw_n=1;
    reg [24:0] last_observation=0;
    reg observation_valid=0,rebased=0;
    reg [LOG_ADDR_WIDTH-1:0] ring_write_pointer=0;
    reg nmi_pending=0,end_reached=0;
    reg trigger_match=0;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            sample_address<=16'hffff; sample_data<=8'hff;
            sample_expected<=8'hff; sample_s<=3'd7; sample_rw_n<=1;
            sample_mmu_task0<=6'h3f;sample_mmu_task1<=6'h3f;
            sample_mmu_task<=0;sample_mmu_enabled<=0;
            trigger_match<=0;
        end else begin
            sample_address<=address; sample_data<=cpu_data;
            sample_expected<=expected_data; sample_s<=s;
            sample_mmu_task0<=mmu_task0_page;
            sample_mmu_task1<=mmu_task1_page;
            sample_mmu_task<=mmu_task;sample_mmu_enabled<=mmu_enabled;
            sample_rw_n<=rw_n;
            trigger_match<=(LOG_READS_ONLY==0 || rw_n) &&
                           address==LOG_START_ADDRESS;
        end
    end

    // Opcode/data reads and memory writes; skip I/O cycles.
    wire memory_cycle=(sample_rw_n && sample_s<=3'd2) ||
                      (!sample_rw_n && sample_s==3'd0);
    wire [24:0] observation={sample_rw_n,sample_address,sample_data};
    wire duplicate_cycle=LOG_DEDUP!=0 && observation_valid &&
                         observation==last_observation;
    wire [47:0] entry={1'b1,sample_rw_n,sample_address,sample_data,
                       sample_expected,sample_mmu_enabled,sample_mmu_task,
                       sample_mmu_task0,sample_mmu_task1};
    // Reserved signature in the otherwise-unused FFFC bus slot marks NMI.
    wire [47:0] nmi_entry={1'b1,1'b1,16'hfffc,8'h4e,8'h4d,
                           sample_mmu_enabled,sample_mmu_task,
                           sample_mmu_task0,sample_mmu_task1};

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            log_we<=0;log_addr<=0;log_data<=0;log_count<=0;log_base<=0;
            ring_write_pointer<=0;nmi_pending<=0;end_reached<=0;
            last_observation<=0;observation_valid<=0;rebased<=0;
            rebase_pulse<=0;end_pulse<=0;
        end else begin
            log_we<=0;rebase_pulse<=0;end_pulse<=0;
            if (!bus_reset_n || capture_clear) begin
                log_addr<=0;log_data<=0;log_count<=0;log_base<=0;
                ring_write_pointer<=0;nmi_pending<=0;end_reached<=0;
                last_observation<=0;observation_valid<=0;rebased<=0;
            end else begin
                if(capture_enable && nmi_event)
                    nmi_pending<=e_fall && memory_cycle;
                else nmi_pending<=0;

                if (!capture_enable) begin
                    // Keep the last trace intact after stop or completion.
                end else if (!end_reached && (nmi_event || nmi_pending) &&
                             !(e_fall && memory_cycle)) begin
                    if(log_count<LOG_DEPTH) begin
                        log_we<=1;log_data<=nmi_entry;
                        log_addr<=LOG_RING_MODE!=0 ? ring_write_pointer :
                                  log_count[LOG_ADDR_WIDTH-1:0];
                        if(LOG_RING_MODE!=0) begin
                            if(ring_write_pointer==LOG_DEPTH-1)
                                ring_write_pointer<=0;
                            else ring_write_pointer<=ring_write_pointer+1'b1;
                        end
                        log_count<=log_count+1'b1;
                    end else if(LOG_RING_MODE!=0) begin
                        log_we<=1;log_data<=nmi_entry;log_addr<=ring_write_pointer;
                        if(ring_write_pointer==LOG_DEPTH-1)
                            ring_write_pointer<=0;
                        else ring_write_pointer<=ring_write_pointer+1'b1;
                        log_base<=ring_write_pointer==LOG_DEPTH-1 ? 0 :
                                  ring_write_pointer+1'b1;
                    end
                    observation_valid<=0;
                end else if(e_fall && trigger_match) begin
                    // Every eligible access to the start address starts a
                    // fresh trace, including a later hit after a loader pass.
                    log_we<=1;log_addr<=0;log_data<=entry;log_count<=1;
                    log_base<=0;
                    ring_write_pointer<=LOG_RING_MODE!=0 ? 1 : 0;
                    last_observation<=observation;observation_valid<=1;
                    rebased<=1;
                    end_reached<=0;
                    rebase_pulse<=1;
                    if(LOG_END_ADDRESS!=0 && sample_rw_n &&
                       sample_address==LOG_END_ADDRESS) begin
                        end_pulse<=1;end_reached<=1;
                    end
                end else if (end_reached || !rebased) begin
                    // Wait for the first start-address read.
                end else if(e_fall && memory_cycle) begin
                    if(LOG_END_ADDRESS!=0 && sample_rw_n &&
                       sample_address==LOG_END_ADDRESS) begin
                        end_pulse<=1;end_reached<=1;
                    end
                    if(!duplicate_cycle) begin
                        if(log_count<LOG_DEPTH) begin
                            log_we<=1;log_data<=entry;
                            log_addr<=LOG_RING_MODE!=0 ? ring_write_pointer :
                                      log_count[LOG_ADDR_WIDTH-1:0];
                            if(LOG_RING_MODE!=0) begin
                                if(ring_write_pointer==LOG_DEPTH-1)
                                    ring_write_pointer<=0;
                                else ring_write_pointer<=ring_write_pointer+1'b1;
                            end
                            log_count<=log_count+1'b1;
                        end else if(LOG_RING_MODE!=0) begin
                            log_we<=1;log_data<=entry;log_addr<=ring_write_pointer;
                            if(ring_write_pointer==LOG_DEPTH-1)
                                ring_write_pointer<=0;
                            else ring_write_pointer<=ring_write_pointer+1'b1;
                            log_base<=ring_write_pointer==LOG_DEPTH-1 ? 0 :
                                      ring_write_pointer+1'b1;
                        end
                        last_observation<=observation;observation_valid<=1;
                    end
                end
            end
        end
    end
endmodule
