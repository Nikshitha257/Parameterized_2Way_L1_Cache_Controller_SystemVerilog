`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 13.07.2026 17:01:08
// Design Name: 
// Module Name: main_memory
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: Simulated Main Memory for Cache Controller Testbench.
//              Models a 64KB memory with artificial read/write latency.
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
module main_memory #(
    parameter ADDRESS_WIDTH = 32,
    parameter BLOCK_SIZE    = 16, // bytes
    parameter LATENCY       = 4   // Artificial clock cycle delay for realistic simulation
)(
    input logic clk,
    input logic rst,
    
    // Memory Interface (Slave Port)
    cache_mem_if.mem bus
);

    // ==========================================
    // Memory Array Definition
    // ==========================================
    localparam BLOCK_BITS = BLOCK_SIZE * 8; // 128 bits per block
    
    // We model 64KB of memory to prevent Vivado from crashing.
    // 64KB = 65,536 Bytes. 
    // 65,536 / 16 bytes per block = 4,096 total blocks.
    localparam MEM_DEPTH = 4096;
    localparam ADDR_BITS = $clog2(MEM_DEPTH); // 12 bits

    // The physical 2D array representing our RAM
    logic [BLOCK_BITS-1:0] mem_array [0:MEM_DEPTH-1];


    // ==========================================
    // Internal Signals & Address Slicing
    // ==========================================
    logic [ADDR_BITS-1:0] block_addr;
    
    // The CPU gives us a 32-bit address. 
    // We ignore the bottom 4 bits [3:0] because we operate on 16-byte blocks.
    // We slice the next 12 bits [15:4] to index into our 4096-depth array.
    assign block_addr = bus.addr[4 +: ADDR_BITS]; 


    // ==========================================
    // FSM State Definition (To mimic latency)
    // ==========================================
    typedef enum logic [1:0] {
        IDLE = 2'd0,
        BUSY = 2'd1,
        DONE = 2'd2
    } state_t;

    state_t state;
    logic [3:0] delay_timer;


    // ==========================================
    // Memory Controller Logic
    // ==========================================
    always_ff @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            delay_timer <= '0;
            bus.ready <= 1'b0;
            bus.valid_out <= 1'b0;
            bus.data_read <= '0;
            
            // Optional: Initialize memory to some known pattern for debugging
            /*
            integer i;
            for (i = 0; i < MEM_DEPTH; i = i + 1) begin
                mem_array[i] <= {4{32'hDEADBEEF}}; 
            end
            */
        end 
        else begin
            // Default handshakes
            bus.ready <= 1'b0;
            bus.valid_out <= 1'b0;

            case (state)
                IDLE: begin
                    bus.ready <= 1'b1; // We are ready for a request!
                    
                    if (bus.req) begin
                        state <= BUSY;
                        delay_timer <= LATENCY; // Start the delay countdown
                    end
                end

                BUSY: begin
                    if (delay_timer == 0) begin
                        state <= DONE;
                        // Perform the actual Read or Write
                        if (bus.rw == 1'b1) begin
                            // WRITE BACK: Store dirty block into memory
                            mem_array[block_addr] <= bus.data_write;
                        end 
                        else begin
                            // READ MISS: Fetch block from memory
                            bus.data_read <= mem_array[block_addr];
                        end
                    end 
                    else begin
                        delay_timer <= delay_timer - 1; // Wait...
                    end
                end

                DONE: begin
                    bus.valid_out <= 1'b1; // Tell cache the data is ready / write is done
                    state <= IDLE;         // Go back to listening
                end
            endcase
        end
    end

endmodule