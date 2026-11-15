`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/15/2026 10:52:30 PM
// Design Name: 
// Module Name: tb_sram_2k_macro
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


`timescale 1ns / 1ps

// Standalone Verilog-2001 testbench for sram_2k_macro.
// Run this testbench as Simulation Top; no AXI wrapper is needed.
module tb_sram_2k_macro;
    reg         CLK;
    reg         CEN;
    reg         WEN;
    reg [9:0]   A;
    reg [31:0]  D;
    wire [31:0] Q;

    integer passes;
    integer fails;
    reg [31:0] expected_q;

    // T_ACCESS = 1.2 ns (same default as provided SRAM model).
    sram_2k_macro #(
        .T_ACCESS(1.2),
        .INIT_FILE("")
    ) dut (
        .CLK (CLK),
        .CEN (CEN),
        .WEN (WEN),
        .A   (A),
        .D   (D),
        .Q   (Q)
    );

    initial CLK = 1'b0;
    always #5 CLK = ~CLK;  // 10 ns period (100 MHz)

    task check_q;
        input [31:0] expected;
        input [8*80-1:0] label;
        begin
            if (Q !== expected) begin
                fails = fails + 1;
                $display("[FAIL] %0s: Q=%h expected=%h at %0t", label, Q, expected, $time);
            end else begin
                passes = passes + 1;
                $display("[PASS] %0s: Q=%h at %0t", label, Q, $time);
            end
        end
    endtask

    // Drive signals at falling edge, keep them stable across the rising edge.
    // Sample Q 2 ns after rising edge (> T_ACCESS=1.2 ns).
    task write_word;
        input [9:0] addr;
        input [31:0] value;
        begin
            @(negedge CLK);
            CEN = 1'b0;
            WEN = 1'b0;
            A   = addr;
            D   = value;
            @(posedge CLK);
            #2;
            $display("[WRITE] A=%0d D=%h at %0t", addr, value, $time);
            @(negedge CLK);
            CEN = 1'b1;
            WEN = 1'b1;
        end
    endtask

    task read_word_check;
        input [9:0] addr;
        input [31:0] expected;
        begin
            @(negedge CLK);
            CEN = 1'b0;
            WEN = 1'b1;
            A   = addr;
            @(posedge CLK);
            #2;
            $display("[READ ] A=%0d Q=%h at %0t", addr, Q, $time);
            check_q(expected, "read word");
            @(negedge CLK);
            CEN = 1'b1;
        end
    endtask

    initial begin
        CEN = 1'b1;
        WEN = 1'b1;
        A   = 10'd0;
        D   = 32'd0;
        passes = 0;
        fails  = 0;

        #1;
        $display("\n=== TEST 1: Initial memory contents ===");
        // Model initializes all words to zero when INIT_FILE is empty.
        read_word_check(10'd7, 32'h00000000);

        $display("\n=== TEST 2: Write then read ===");
        write_word(10'd2, 32'h12345678);
        read_word_check(10'd2, 32'h12345678);

        $display("\n=== TEST 3: Overwrite same address ===");
        write_word(10'd2, 32'hAABBCCDD);
        read_word_check(10'd2, 32'hAABBCCDD);

        $display("\n=== TEST 4: Different addresses do not alias ===");
        write_word(10'd3, 32'hDEADBEEF);
        write_word(10'd4, 32'hCAFEBABE);
        read_word_check(10'd2, 32'hAABBCCDD);
        read_word_check(10'd3, 32'hDEADBEEF);
        read_word_check(10'd4, 32'hCAFEBABE);

        $display("\n=== TEST 5: First and last word ===");
        write_word(10'd0,    32'h01020304);
        write_word(10'd1023, 32'hF0E0D0C0);
        read_word_check(10'd0,    32'h01020304);
        read_word_check(10'd1023, 32'hF0E0D0C0);

        $display("\n=== TEST 6: CEN=1 disables write ===");
        @(negedge CLK);
        CEN = 1'b1;
        WEN = 1'b0;
        A   = 10'd2;
        D   = 32'hFFFFFFFF;
        @(posedge CLK);
        #2;
        @(negedge CLK);
        CEN = 1'b1;
        WEN = 1'b1;
        read_word_check(10'd2, 32'hAABBCCDD);

        $display("\n=== TEST 7: Q holds during write and idle ===");
        // The last read returned AABBCCDD. Writes do not update Q.
        check_q(32'hAABBCCDD, "Q before write");
        write_word(10'd9, 32'h11112222);
        check_q(32'hAABBCCDD, "Q unchanged by write");
        repeat (3) @(posedge CLK);
        #2;
        check_q(32'hAABBCCDD, "Q unchanged during idle");
        read_word_check(10'd9, 32'h11112222);

        $display("\n=== TEST 8: Read access delay (1.2 ns) ===");
        write_word(10'd10, 32'h55667788);
        // Q was last read as 11112222.
        @(negedge CLK);
        CEN = 1'b0;
        WEN = 1'b1;
        A   = 10'd10;
        @(posedge CLK);
        #0.5;
        check_q(32'h11112222, "Q remains old before 1.2 ns");
        #1.0;
        check_q(32'h55667788, "Q updates after 1.2 ns");
        @(negedge CLK);
        CEN = 1'b1;

        $display("\n=== TEST 9: Consecutive writes ===");
        // One write at each rising clock edge.
        @(negedge CLK);
        CEN = 1'b0; WEN = 1'b0; A = 10'd100; D = 32'hABC00001;
        @(negedge CLK);
        A = 10'd101; D = 32'hABC00002;
        @(negedge CLK);
        A = 10'd102; D = 32'hABC00003;
        @(negedge CLK);
        CEN = 1'b1; WEN = 1'b1;
        read_word_check(10'd100, 32'hABC00001);
        read_word_check(10'd101, 32'hABC00002);
        read_word_check(10'd102, 32'hABC00003);

        $display("\n=== TEST 10: Read address must be captured on clock ===");
        read_word_check(10'd100, 32'hABC00001);
        @(negedge CLK);
        CEN = 1'b1;
        WEN = 1'b1;
        A = 10'd101; // Change address while disabled: Q must hold.
        @(posedge CLK);
        #2;
        check_q(32'hABC00001, "Q holds when address changes at idle");

        $display("\n========== SUMMARY ==========");
        $display("PASS=%0d FAIL=%0d", passes, fails);
        if (fails == 0)
            $display("ALL SRAM MACRO TESTS PASSED");
        else
            $display("SRAM MACRO TESTS FAILED");
        $finish;
    end

    initial begin
        #100000;
        $display("[FAIL] Global simulation timeout");
        $finish;
    end
endmodule

