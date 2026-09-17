`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10.07.2026 00:16:46
// Design Name: 
// Module Name: tag_ram
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: Metadata storage for a 2-Way Set Associative Cache.
//              Holds Tags, Valid bits, Dirty bits, and LRU tracking.
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module tag_ram #(
    parameter NUM_SETS = 128,
    parameter TAG_WIDTH = 21,
    parameter INDEX_WIDTH = 7 // log2(128)
)(
    input  logic clk,
    input  logic rst,
    input  logic [INDEX_WIDTH-1:0] index,

    // --- Way 0 Control & Data ---
    input  logic                 we_tway0,             // Write Enable (Cache Miss Replacement)
    input  logic                 update_dirty_way0,   // Set dirty bit only (CPU Write Hit)
    input  logic [TAG_WIDTH-1:0] tag_in_way0,
    input  logic                 valid_in_way0,
    input  logic                 dirty_in_way0,
    
    output logic [TAG_WIDTH-1:0] tag_out_way0,
    output logic                 valid_out_way0,
    output logic                 dirty_out_way0,

    // --- Way 1 Control & Data ---
    input  logic                 we_tway1,             
    input  logic                 update_dirty_way1,   
    input  logic [TAG_WIDTH-1:0] tag_in_way1,
    input  logic                 valid_in_way1,
    input  logic                 dirty_in_way1,
    
    output logic [TAG_WIDTH-1:0] tag_out_way1,
    output logic                 valid_out_way1,
    output logic                 dirty_out_way1,

    // --- LRU Control & Data ---
    input  logic                 update_lru,
    input  logic                 lru_in,
    
    output logic                 lru_out
);

    // ==========================================
    // STEP 1: Declare Internal Memory Arrays
    // ==========================================
    // These represent the physical SRAM blocks inside the chip.
    // [0:NUM_SETS-1] defines the depth (128 rows).
    
    // Way 0 Arrays
    logic [TAG_WIDTH-1:0] tag_array_w0   [0:NUM_SETS-1];
    logic  valid_array_w0 [0:NUM_SETS-1];
    logic  dirty_array_w0 [0:NUM_SETS-1];

    // Way 1 Arrays
    logic [TAG_WIDTH-1:0] tag_array_w1   [0:NUM_SETS-1];
    logic  valid_array_w1 [0:NUM_SETS-1];
    logic  dirty_array_w1 [0:NUM_SETS-1];

    // LRU Array (1 bit per set)
    // 0 = Replace Way 0, 1 = Replace Way 1
    logic lru_array [0:NUM_SETS-1];


    // ==========================================
    // STEP 2: Combinational Read Logic
    // ==========================================
    // The moment the CPU provides an 'index', these outputs 
    // instantly show the data for that specific set.
    
    assign tag_out_way0   = tag_array_w0[index];
    assign valid_out_way0 = valid_array_w0[index];
    assign dirty_out_way0 = dirty_array_w0[index];

    assign tag_out_way1   = tag_array_w1[index];
    assign valid_out_way1 = valid_array_w1[index];
    assign dirty_out_way1 = dirty_array_w1[index];

    assign lru_out        = lru_array[index];


    // ==========================================
    // STEP 3: Synchronous Write Logic
    // ==========================================
    // All modifications happen exactly on the rising edge of the clock.
    
    integer i; // Used for the reset loop

    always_ff @(posedge clk) begin
        if (rst) begin
            // On system reset, invalidate all cache lines.
            // We don't necessarily need to clear tags/dirty/lru because 
            // if valid == 0, the controller ignores the other data anyway.
            for (i = 0; i < NUM_SETS; i = i + 1) begin
                valid_array_w0[i] <= 1'b0;
                valid_array_w1[i] <= 1'b0;
                lru_array[i]      <= 1'b0; // Default LRU to Way 0
            end
        end 
        
        else begin
            // ---------------------------------
            // Way 0 Write Operations
            // ---------------------------------
            if (we_tway0) begin
                // Cache Miss: Overwrite the whole line
                tag_array_w0[index]   <= tag_in_way0;
                valid_array_w0[index] <= valid_in_way0;
                dirty_array_w0[index] <= dirty_in_way0;//cache controller sets dirty_in_way0=1'b0 only as the data is fresh
            end 
            else if (update_dirty_way0) begin
                // CPU Write Hit: Data modified, tag stays the same
                dirty_array_w0[index] <= 1'b1; 
            end

            // ---------------------------------
            // Way 1 Write Operations
            // ---------------------------------
            if (we_tway1) begin
                // Cache Miss: Overwrite the whole line
                //even write/read miss the new data need to be fetch from main memory to cache occurs in UPDATE_CACHE state
                tag_array_w1[index]   <= tag_in_way1;
                valid_array_w1[index] <= valid_in_way1;
                dirty_array_w1[index] <= dirty_in_way1;
            end 
            else if (update_dirty_way1) begin
                // CPU Write Hit: Data modified, tag stays the same
                dirty_array_w1[index] <= 1'b1; 
            end

            // ---------------------------------
            // LRU Update Operation
            // ---------------------------------
            if (update_lru) begin
                lru_array[index] <= lru_in;
            end
        end
    end

endmodule