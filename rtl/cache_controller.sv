`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11.07.2026 18:46:43
// Design Name: 
// Module Name: cache_controller
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: FSM and control logic for the 2-Way Set Associative Cache.
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
module cache_controller #(
    parameter ADDRESS_WIDTH = 32,
    parameter DATA_WIDTH    = 32,
    parameter BLOCK_SIZE    = 16, // bytes
    parameter NUM_SETS      = 128
)(
    input logic clk,
    input logic rst,
    
    // Interfaces (as defined in interface.sv)
    cpu_cache_if.cache cpu_bus,
    cache_mem_if.cache mem_bus
);

    // ==========================================
    // Derived Parameters & Address Breakdown
    // ==========================================
    localparam OFFSET_WIDTH = $clog2(BLOCK_SIZE);         // 4 bits
    localparam INDEX_WIDTH  = $clog2(NUM_SETS);           // 7 bits
    localparam TAG_WIDTH    = ADDRESS_WIDTH - INDEX_WIDTH - OFFSET_WIDTH; // 21 bits
    localparam BLOCK_BITS   = BLOCK_SIZE * 8;             // 128 bits

    logic [TAG_WIDTH-1:0]    cpu_tag;
    logic [INDEX_WIDTH-1:0]  cpu_index;
    logic [OFFSET_WIDTH-1:0] cpu_offset;

    assign cpu_tag    = cpu_bus.addr[ADDRESS_WIDTH-1 : INDEX_WIDTH+OFFSET_WIDTH];
    assign cpu_index  = cpu_bus.addr[INDEX_WIDTH+OFFSET_WIDTH-1 : OFFSET_WIDTH];
    assign cpu_offset = cpu_bus.addr[OFFSET_WIDTH-1 : 0];


    // ==========================================
    // Internal Signals for Tag and Data RAMs
    // ==========================================
    // Tag RAM signals
    logic                 we_tway0, we_tway1;
    logic                 update_dirty_way0, update_dirty_way1;
    logic [TAG_WIDTH-1:0] tag_in_way0, tag_in_way1;
    logic                 valid_in_way0, valid_in_way1;
    logic                 dirty_in_way0, dirty_in_way1;
    logic [TAG_WIDTH-1:0] tag_out_way0, tag_out_way1;
    logic                 valid_out_way0, valid_out_way1;
    logic                 dirty_out_way0, dirty_out_way1;
    
    logic                 update_lru, lru_in, lru_out;

    // Data RAM signals
    logic                 we_dway0, we_dway1;
    logic [BLOCK_BITS-1:0] data_in_way0, data_in_way1;
    logic [BLOCK_BITS-1:0] data_out_way0, data_out_way1;

    // ==========================================
    // Instantiations
    // ==========================================
    tag_ram #(
        .NUM_SETS(NUM_SETS), .TAG_WIDTH(TAG_WIDTH), .INDEX_WIDTH(INDEX_WIDTH)
    ) tag_memory (
        .clk(clk), .rst(rst), .index(cpu_index),
        .we_tway0(we_tway0), .update_dirty_way0(update_dirty_way0),
        .tag_in_way0(tag_in_way0), .valid_in_way0(valid_in_way0), .dirty_in_way0(dirty_in_way0),
        .tag_out_way0(tag_out_way0), .valid_out_way0(valid_out_way0), .dirty_out_way0(dirty_out_way0),
        
        .we_tway1(we_tway1), .update_dirty_way1(update_dirty_way1),
        .tag_in_way1(tag_in_way1), .valid_in_way1(valid_in_way1), .dirty_in_way1(dirty_in_way1),
        .tag_out_way1(tag_out_way1), .valid_out_way1(valid_out_way1), .dirty_out_way1(dirty_out_way1),
        
        .update_lru(update_lru), .lru_in(lru_in), .lru_out(lru_out)
    );

    data_ram #(
        .NUM_SETS(NUM_SETS), .BLOCK_WIDTH(BLOCK_BITS), .INDEX_WIDTH(INDEX_WIDTH)
    ) data_memory (
        .clk(clk), .index(cpu_index),
        .we_dway0(we_dway0), .data_in_way0(data_in_way0), .data_out_way0(data_out_way0),
        .we_dway1(we_dway1), .data_in_way1(data_in_way1), .data_out_way1(data_out_way1)
    );

    // ==========================================
    // FSM State Definition
    // ==========================================
    typedef enum logic [2:0] {
        IDLE         = 3'd0,
        CHECK_TAG    = 3'd1,
        WRITE_BACK   = 3'd2,
        READ_MEMORY  = 3'd3,
        UPDATE_CACHE = 3'd4,
        RESPOND      = 3'd5
    } state_t;

    state_t state, next_state;

    // ==========================================
    // Hit/Miss Logic (Combinational)
    // ==========================================
    logic hit_way0, hit_way1, cache_hit;
    
    // STEP 1: Determine a hit
    // A hit happens if the Tags match AND the line is Valid.
    assign hit_way0 = (cpu_tag == tag_out_way0) && valid_out_way0;
    assign hit_way1 = (cpu_tag == tag_out_way1) && valid_out_way1;
    assign cache_hit = hit_way0 | hit_way1;


    // ==========================================
    // FSM Sequential Block (State Memory)
    // ==========================================
    always_ff @(posedge clk) begin
        if (rst) state <= IDLE;
        else     state <= next_state;
    end

    // ==========================================
    // FSM Combinational Block (Next State & Outputs)
    // ==========================================
    always_comb begin
        // Variable for Read-Modify-Write operation
        logic [BLOCK_BITS-1:0] merged_data;
        merged_data = '0; 

        // Default assignments to prevent latches
        next_state = state;
        
        cpu_bus.ready     = 1'b0;
        cpu_bus.valid_out = 1'b0;
        cpu_bus.data_read = '0;

        mem_bus.req        = 1'b0;
        mem_bus.rw         = 1'b0;
        mem_bus.addr       = '0;
        mem_bus.data_write = '0;

        // Default RAM control signals (all zero)
        we_tway0 = 0; we_tway1 = 0;
        update_dirty_way0 = 0; update_dirty_way1 = 0;
        update_lru = 0; lru_in = 0;
        
        tag_in_way0 = '0; valid_in_way0 = 0; dirty_in_way0 = 0; data_in_way0 = '0;
        tag_in_way1 = '0; valid_in_way1 = 0; dirty_in_way1 = 0; data_in_way1 = '0;
        we_dway0 = 0;we_dway1 = 0;

        case (state)
            IDLE: begin
                // STEP 2: Logic for IDLE
                cpu_bus.ready = 1'b1; // Tell the CPU we are ready for a request
                
                if (cpu_bus.req) begin
                    next_state = CHECK_TAG;
                end
            end

            CHECK_TAG: begin
                // STEP 3: Logic for CHECK_TAG
                if (cache_hit) begin
                    // --- IT'S A HIT! --- 
                    if (cpu_bus.rw == 1'b1) begin 
                        // --- WRITE HIT ---
                        if (hit_way0) begin
                            merged_data = data_out_way0; 
                            
                            case (cpu_offset[3:2])
                                2'b00: merged_data[31:0]   = cpu_bus.data_write;
                                2'b01: merged_data[63:32]  = cpu_bus.data_write;
                                2'b10: merged_data[95:64]  = cpu_bus.data_write;
                                2'b11: merged_data[127:96] = cpu_bus.data_write;
                            endcase
                            
                            data_in_way0 = merged_data;
                            we_dway0 = 1'b1;
                            update_dirty_way0 = 1'b1;
                            
                            update_lru = 1'b1;
                            lru_in = 1'b1; 
                        end 
                        else begin
                            merged_data = data_out_way1; 
                            case (cpu_offset[3:2])
                                2'b00: merged_data[31:0]   = cpu_bus.data_write;
                                2'b01: merged_data[63:32]  = cpu_bus.data_write;
                                2'b10: merged_data[95:64]  = cpu_bus.data_write;
                                2'b11: merged_data[127:96] = cpu_bus.data_write;
                            endcase
                            
                            data_in_way1 = merged_data;
                            we_dway1 = 1'b1;
                            update_dirty_way1 = 1'b1;
                            
                            update_lru = 1'b1; // Must be 1 to enable the write!
                            lru_in = 1'b0;     // Point to way 0
                        end
                    end 
                    else begin
                        // --- READ HIT ---
                        if (hit_way0) begin
                            update_lru = 1'b1;
                            lru_in = 1'b1; 
                        end else begin
                            update_lru = 1'b1; // Must be 1 to enable the write!
                            lru_in = 1'b0; 
                        end
                    end
                    // Whether read or write hit, we go to respond next
                    next_state = RESPOND;  
                end else begin
                    // --- IT'S A MISS! ---
                    if (lru_out == 1'b0) begin 
                        // Evicting Way 0
                        if (dirty_out_way0 == 1'b1) begin
                            next_state = WRITE_BACK;
                        end else begin
                            next_state = READ_MEMORY;
                        end   
                    end else begin 
                        // Evicting Way 1
                        if (dirty_out_way1 == 1'b1) begin
                            next_state = WRITE_BACK;
                        end else begin
                            next_state = READ_MEMORY;
                        end
                    end
                end
            end

            WRITE_BACK: begin
                // STEP 4: Logic for WRITE_BACK
                // Push dirty data to memory. When memory is valid_out, where do we go?
                mem_bus.req = 1'b1;// (Wake up, memory!)
                mem_bus.rw = 1'b1; //(want to do a Write)
                if(lru_out == 1'b0)begin
                     mem_bus.data_write = data_out_way0;
                     mem_bus.addr = {tag_out_way0, cpu_index, 4'b0000};
                end
                else begin
                     mem_bus.data_write = data_out_way1;
                     mem_bus.addr = {tag_out_way1, cpu_index, 4'b0000};
                end
                if (mem_bus.valid_out == 1'b1) begin
                      next_state = READ_MEMORY;
                end
            end
           READ_MEMORY: begin
                // STEP 5: Logic for READ_MEMORY
                // Request data from memory. When memory is valid_out, where do we go?
                mem_bus.req=1'b1;
                mem_bus.rw =1'b0;
                mem_bus.addr = {cpu_tag, cpu_index, 4'b0000};
                if (mem_bus.valid_out == 1'b1) begin
                    next_state = UPDATE_CACHE;
                end
            end
            UPDATE_CACHE: begin
                // STEP 6: Logic for UPDATE_CACHE
                // Overwrite the chosen way with the new memory data and tag.
                if(lru_out==1'b0)begin
                     data_in_way0 = mem_bus.data_read;//replace the least recently used data
                     we_dway0 = 1'b1;
                     we_tway0 = 1'b1;
                     tag_in_way0 = cpu_tag;
                     valid_in_way0 = 1'b1;
                     dirty_in_way0 = 1'b0;//as the data is fresh now 
                     update_lru = 1'b1;
                     lru_in = 1'b1;
                end
                else begin
                     data_in_way1 = mem_bus.data_read;//replace the least recently used data
                     we_dway1 = 1'b1;
                     we_tway1 = 1'b1;
                     tag_in_way1 = cpu_tag;
                     valid_in_way1 = 1'b1;
                     dirty_in_way1 = 1'b0;//as the data is fresh now 
                     update_lru = 1'b1;
                     lru_in = 1'b0;
                end
                  //Loop back to CHECK_TAG so a Write-Miss can turn into a Write-Hit!
                  next_state = CHECK_TAG;
            end

             RESPOND: begin
                // STEP 7: Logic for RESPOND
                // Send valid_out and data to the CPU. Return to IDLE.
                cpu_bus.valid_out = 1'b1;
                // POWER SAVING: Only drive the read data wires if the CPU asked for a read!
                if (~cpu_bus.rw) begin
                    if (hit_way0) begin
                        case (cpu_offset[3:2])
                            2'b00: cpu_bus.data_read = data_out_way0[31:0];
                            2'b01: cpu_bus.data_read = data_out_way0[63:32];
                            2'b10: cpu_bus.data_read = data_out_way0[95:64];
                            2'b11: cpu_bus.data_read = data_out_way0[127:96];
                        endcase
                    end 
                    else if (hit_way1) begin
                        case (cpu_offset[3:2])
                            2'b00: cpu_bus.data_read = data_out_way1[31:0];
                            2'b01: cpu_bus.data_read = data_out_way1[63:32];
                            2'b10: cpu_bus.data_read = data_out_way1[95:64];
                            2'b11: cpu_bus.data_read = data_out_way1[127:96];
                        endcase
                    end
                end

                next_state = IDLE;
            end
          default: next_state = IDLE;
        endcase
    end
endmodule
