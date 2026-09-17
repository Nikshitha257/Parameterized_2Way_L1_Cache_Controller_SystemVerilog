`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10.07.2026 00:00:42
// Design Name: interface.sv
// Module Name: interface
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description:  Defines the communication buses between CPU, Cache, and Memory.
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
// ------------------------------------------------------------------------------
// Interface: cpu_cache_if
// Connects the CPU (or Testbench Driver) to the Cache Controller
// ------------------------------------------------------------------------------
interface cpu_cache_if #(
    parameter ADDRESS_WIDTH = 32,
    parameter DATA_WIDTH = 32
)(input logic clk, input logic rst);

    // Core signals
    logic [ADDRESS_WIDTH-1:0] addr;
    logic [DATA_WIDTH-1:0]    data_write;
    logic [DATA_WIDTH-1:0]    data_read;
    logic                     req;       // CPU requests a transaction
    logic                     rw;        // 0 = Read, 1 = Write
    
    // Handshake signals
    logic                     ready;     // Cache is ready to accept a new request
    logic                     valid_out; // Cache has completed the read/write

    // CPU Perspective (The Master)
    modport cpu (
        input  clk, rst, data_read, ready, valid_out,
        output addr, data_write, req, rw
    );

    // Cache Perspective (The Slave to the CPU)
    modport cache (
        input  clk, rst, addr, data_write, req, rw,
        output data_read, ready, valid_out
    );

endinterface


// ------------------------------------------------------------------------------
// Interface: cache_mem_if
// Connects the Cache Controller to Main Memory
// ------------------------------------------------------------------------------
interface cache_mem_if #(
    parameter ADDRESS_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter BLOCK_SIZE = 16 // 16 bytes = 128 bits total data width for a line
)(input logic clk, input logic rst);

    // Memory operates on entire cache blocks (lines), not single words
    localparam BLOCK_BITS = BLOCK_SIZE * 8; 

    // Signals
    logic [ADDRESS_WIDTH-1:0] addr;
    logic [BLOCK_BITS-1:0]    data_write; // Pushing a dirty line to memory
    logic [BLOCK_BITS-1:0]    data_read;  // Fetching a new line from memory
    logic                     req;        // Cache requests a transaction
    logic                     rw;         // 0 = Read, 1 = Write
    
    // Handshake
    logic                     ready;      // Memory is ready for a request
    logic                     valid_out;  // Memory has finished processing (after 3 cycles)

    // Cache Perspective (The Master to Memory)
    modport cache (
        input  clk, rst, data_read, ready, valid_out,
        output addr, data_write, req, rw
    );

    // Memory Perspective (The Slave to the Cache)
    modport mem (
        input  clk, rst, addr, data_write, req, rw,
        output data_read, ready, valid_out
    );

endinterface
