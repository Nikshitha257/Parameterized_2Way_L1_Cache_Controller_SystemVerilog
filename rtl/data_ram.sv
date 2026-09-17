`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10.07.2026 23:51:05
// Design Name: 
// Module Name: data_ram
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: Data payload storage for a 2-Way Set Associative Cache.
//              Holds the actual 16-byte cache lines.
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module data_ram #(
    parameter NUM_SETS = 128,
    parameter BLOCK_WIDTH = 128, // 16 bytes * 8 bits = 128 bits
    parameter INDEX_WIDTH = 7    // log2(128)
)(
    input  logic clk,
    input  logic [INDEX_WIDTH-1:0] index,

    // --- Way 0 Control & Data ---
    input  logic                   we_dway0,      // Write Enable for Way 0
    input  logic [BLOCK_WIDTH-1:0] data_in_way0, // Full 128-bit block to write
    
    output logic [BLOCK_WIDTH-1:0] data_out_way0, // Full 128-bit block read out

    // --- Way 1 Control & Data ---
    input  logic                   we_dway1,      // Write Enable for Way 1
    input  logic [BLOCK_WIDTH-1:0] data_in_way1, // Full 128-bit block to write
    
    output logic [BLOCK_WIDTH-1:0] data_out_way1  // Full 128-bit block read out
);

    // ==========================================
    // STEP 1: Declare Internal Memory Arrays
    // ==========================================
    // Two arrays, one for each way, each 128 bits wide and 128 rows deep.
    
    logic [BLOCK_WIDTH-1:0] ram_way0 [0:NUM_SETS-1];
    logic [BLOCK_WIDTH-1:0] ram_way1 [0:NUM_SETS-1];


    // ==========================================
    // STEP 2: Combinational Read Logic
    // ==========================================
    // The Data RAM outputs the full 16-byte block instantly based on the index.
    // The FSM will use the 'offset' bits later to pick out the specific 4-byte word.
    
    assign data_out_way0 = ram_way0[index];
    assign data_out_way1 = ram_way1[index];


    // ==========================================
    // STEP 3: Synchronous Write Logic
    // ==========================================
    // Notice there is no reset! We don't waste power/routing resetting 
    // data arrays because the Tag RAM's 'Valid' bit protects against garbage reads.

    always_ff @(posedge clk) begin
        if (we_dway0) begin
            ram_way0[index] <= data_in_way0;
        end
        
        if (we_dway1) begin
            ram_way1[index] <= data_in_way1;
        end
    end

endmodule

