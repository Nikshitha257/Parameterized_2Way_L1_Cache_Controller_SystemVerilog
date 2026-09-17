`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 13.07.2026 21:45:07
// Design Name: 
// Module Name: tb_cache
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: OOP & Constraint Random Verification Environment for Cache
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

// ==========================================
// 1. TRANSACTION CLASS
// ==========================================
class cache_transaction;
    // --- Random Inputs ---
    rand bit [31:0] addr;
    rand bit [31:0] data_write;
    rand bit        rw;         // 0 = Read, 1 = Write
    // --- Captured Outputs ---
    bit [31:0] data_read;
    // --- Constraints ---
    // Word-Aligned constraint (addresses must end in 00)
    constraint word_align_c {
        addr[1:0] == 2'b00;
    }
    // Restrict to 64KB memory limit
    constraint mem_limit_c {
        addr <= 32'h0000_0020;
    }
    // --- Deep Copy Function ---
    // Creates a brand new object in memory with the exact same data
    function cache_transaction copy();
        copy = new();
        copy.addr       = this.addr;
        copy.data_write = this.data_write;
        copy.rw         = this.rw;
        copy.data_read  = this.data_read;
    endfunction
    // --- display---
    function void print(input string name = "Transaction");
        $display("[%s] RW: %s | Addr: 0x%08h | WData: 0x%08h | RData: 0x%08h", 
                 name, (rw ? "WRITE" : "READ "), addr, data_write, data_read);
    endfunction
endclass


// ==========================================
// 2. GENERATOR & DRIVER
// ==========================================
class generator;
    cache_transaction tr;
    mailbox #(cache_transaction) mbx;
    mailbox #(cache_transaction) mbxref;
    event sconext;
    event done;
    int count;
    
    function new(mailbox #(cache_transaction) mbx, mailbox #(cache_transaction) mbxref);
        this.mbx = mbx;
        this.mbxref = mbxref;
        tr = new();
    endfunction
    
    task run();
    repeat(count)begin  
       assert(tr.randomize)else $error("[GEN]:Randomization failed");
       mbx.put(tr.copy);
       mbxref.put(tr.copy);
       tr.print("GEN");
       @(sconext); //once dcoreboard completed tasks then nxt stimulus is generated
    end
   ->done;
  endtask
endclass

class driver;
   cache_transaction tr;
   mailbox#(cache_transaction) mbx;
   virtual cpu_cache_if vif;
   function new(mailbox#(cache_transaction) mbx);
        this.mbx=mbx;
   endfunction
   
   task reset();
        vif.req <= 1'b0;
        vif.addr <= '0;
        vif.data_write <= '0;
        vif.rw <= 1'b0;
        $display("[DRV] : RESET DONE");
    endtask

    task run();
        forever begin
            mbx.get(tr);
            // 1. Drive the CPU request pins
            @(posedge vif.clk);
            vif.addr       <= tr.addr;  
            vif.rw         <= tr.rw;
            vif.data_write <= tr.data_write;
            vif.req        <= 1'b1;

            // 2. Wait for Cache to finish (handles variable latency!)
            wait(vif.valid_out == 1'b1);
            
            tr.print("DRV");
            
            // 3. Drop request and wait 1 cycle
            @(posedge vif.clk);
            vif.req <= 1'b0;
        end
    endtask
endclass
// ==============================================
// 3. MONITOR & SCOREBOARD
// ==============================================
class monitor;
    cache_transaction tr;
    mailbox #(cache_transaction) mbx;
    virtual cpu_cache_if vif;

    function new(mailbox #(cache_transaction) mbx);
        this.mbx = mbx;
    endfunction

    task run();
        forever begin
            @(posedge vif.clk);
            
            // A transaction is complete when the CPU has requested it AND cache says valid
            if (vif.req && vif.valid_out) begin
                tr = new();
                tr.addr       = vif.addr;
                tr.rw         = vif.rw;
                tr.data_write = vif.data_write;
                tr.data_read  = vif.data_read;
                
                tr.print("MON");
                mbx.put(tr); // Send to Scoreboard
            end
        end
    endtask
endclass

class scoreboard;
    cache_transaction tr_mon; // From Monitor
    cache_transaction tr_ref; // From Generator
    mailbox #(cache_transaction) mbx_mon;
    mailbox #(cache_transaction) mbx_ref;
    event sconext;

    // --- Tracking Variables ---
    int pass_count = 0;
    int fail_count = 0;

    // --- The Golden Memory ---
    // Associative array mapping 32-bit addresses to 32-bit data words
    bit [31:0] golden_mem [int]; 

    function new(mailbox #(cache_transaction) mbx_mon, mailbox #(cache_transaction) mbx_ref);
        this.mbx_mon = mbx_mon;
        this.mbx_ref = mbx_ref;
    endfunction

     task run();
        forever begin
            mbx_mon.get(tr_mon);
            mbx_ref.get(tr_ref);

            if (tr_ref.rw == 1'b1) begin
                // --- WRITE ---
                golden_mem[tr_ref.addr] = tr_ref.data_write;
                $display("[SCO] : WRITE stored in Golden Mem (Addr: 0x%08h | Data: 0x%08h)", tr_ref.addr, tr_ref.data_write);
            end 
            else begin
                // --- READ ---
                // If we've never written to this address, memory returns 'X' (or 0). 
                // We only check if the address exists in our Golden Mem.
                if (golden_mem.exists(tr_ref.addr)) begin
                    if (tr_mon.data_read == golden_mem[tr_ref.addr]) begin
                        $display("[SCO] : READ MATCH! Addr: 0x%08h | Data: 0x%08h", tr_ref.addr, tr_mon.data_read);
                        pass_count++;
                    end else begin
                        $error("[SCO] : READ MISMATCH! Addr: 0x%08h | Expected: 0x%08h | Actual: 0x%08h", tr_ref.addr, golden_mem[tr_ref.addr], tr_mon.data_read);
                        fail_count++;
                    end
                end 
                else begin
                    $display("[SCO] : READ TO UNINITIALIZED ADDR (Addr: 0x%08h | Actual: 0x%08h) - Skipping Match Check", tr_ref.addr, tr_mon.data_read);
                    // Add it to memory so future checks work
                    golden_mem[tr_ref.addr] = tr_mon.data_read; 
                end
            end
            
            $display("-------------------------------------------------");
            ->sconext; // Tell Generator to make the next transaction
        end
    endtask
 // --- Final Report ---
    function void report();
        $display("=================================================");
        $display("              SCOREBOARD SUMMARY                 ");
        $display("=================================================");
        $display("Total Read Matches   (PASS) : %0d", pass_count);
        $display("Total Read Mismatches(FAIL) : %0d", fail_count);
        $display("=================================================");
        if (fail_count == 0 && pass_count > 0)
            $display("           TEST STATUS: PASSED                   ");
        else if (fail_count > 0)
            $display("           TEST STATUS: FAILED                   ");
        else
            $display("           TEST STATUS: INCOMPLETE (NO READS)    ");
        $display("=================================================");
    endfunction
endclass

// ==========================================
// 4. ENVIRONMENT 
// ==========================================
class environment;
    generator  gen;
    driver     drv;
    monitor    mon;
    scoreboard sco;

    mailbox #(cache_transaction) gdmbx; // Gen -> Drv
    mailbox #(cache_transaction) msmbx; // Mon -> Sco
    mailbox #(cache_transaction) mbxref; // Gen -> Sco

    event next;
    virtual cpu_cache_if vif;
    function new(virtual cpu_cache_if vif);
        this.vif = vif;
        gdmbx  = new();
        msmbx  = new();
        mbxref = new();

        gen = new(gdmbx, mbxref);
        drv = new(gdmbx);
        mon = new(msmbx);
        sco = new(msmbx, mbxref);

        drv.vif = this.vif;
        mon.vif = this.vif;

        gen.sconext = next;
        sco.sconext = next;
    endfunction
    
   task pre_test();
        drv.reset();
    endtask

    task test();
        fork
            gen.run();
            drv.run();
            mon.run();
            sco.run();
        join_any
        
        // As soon as the generator completes its 20 runs, safely kill 
        // the background forever loops (driver, monitor, scoreboard)
        disable fork; 
    endtask

    task post_test();
        wait(gen.done.triggered);
        sco.report();
        $display("[ENV] : Simulation Finished!");
    endtask

    task run();
        pre_test();
        test();
        post_test();
    endtask
endclass

// ==========================================
// 5. TESTBENCH TOP (Physical Environment)
// ==========================================
module tb_cache();
    // --- Clock and Reset ---
    logic clk;
    logic rst;

    initial begin
        clk = 0;
        forever #5 clk = ~clk; 
    end
    // --- Interfaces ---
    cpu_cache_if cpu_bus(.clk(clk), .rst(rst));
    cache_mem_if mem_bus(.clk(clk), .rst(rst));
    // --- DUT (Design Under Test) ---
    cache_controller dut (
        .clk(clk),
        .rst(rst),
        .cpu_bus(cpu_bus.cache),
        .mem_bus(mem_bus.cache)
    );
    
    // --- Simulated Main Memory --- 
    // As memory module is hardcoded unlike cpu 
    //so we need to instantiate the interfaced using in cache controller in main_memory module
    main_memory mem (
        .clk(clk),
        .rst(rst),
        .bus(mem_bus.mem)
    );
     // --- Environment Instance ---
    environment env;
    initial begin
        $display("--- Starting OOP Cache Verification ---");
        
        // 1. Generate Physical Reset
        rst = 1;
        #20; 
        rst = 0;
        // 2. Initialize and Run the Environment
        env = new(cpu_bus);
        env.gen.count = 2000; // Generate 20 randomized transactions!
        env.run();
        #50;
        $display("--- Simulation Complete ---");
        $finish;
    end
endmodule