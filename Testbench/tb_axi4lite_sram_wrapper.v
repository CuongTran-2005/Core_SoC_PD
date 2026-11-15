`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/15/2026 10:28:18 PM
// Design Name: 
// Module Name: tb_axi4lite_sram_wrapper
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


`timescale 1ns/1ps
// Verilog-2001 self-checking testbench for axi4lite_sram_wrapper.
// The SRAM behavioral model initializes memory contents to zero.
module tb_axi4lite_sram_wrapper;
    reg clk_i;
    reg rst_i;
    reg awvalid_i;
    reg [31:0] awaddr_i;
    reg wvalid_i;
    reg [31:0] wdata_i;
    reg [3:0] wstrb_i;
    reg bready_i;
    reg arvalid_i;
    reg [31:0] araddr_i;
    reg rready_i;
    wire awready_o, wready_o, bvalid_o, arready_o, rvalid_o;
    wire [1:0] bresp_o, rresp_o;
    wire [31:0] rdata_o;

    axi4lite_sram_wrapper dut (
        .clk_i(clk_i), .rst_i(rst_i),
        .awvalid_i(awvalid_i), .awaddr_i(awaddr_i),
        .wvalid_i(wvalid_i), .wdata_i(wdata_i), .wstrb_i(wstrb_i),
        .bready_i(bready_i), .arvalid_i(arvalid_i), .araddr_i(araddr_i),
        .rready_i(rready_i),
        .awready_o(awready_o), .wready_o(wready_o),
        .bvalid_o(bvalid_o), .bresp_o(bresp_o),
        .arready_o(arready_o), .rvalid_o(rvalid_o),
        .rdata_o(rdata_o), .rresp_o(rresp_o)
    );

    integer passed, failed, i;
    reg [31:0] reference_mem [0:1023];

    initial clk_i = 1'b0;
    always #10 clk_i = ~clk_i; // 50 MHz

    // Use Verilog-2001 task declarations; no SystemVerilog types.
    task check;
        input condition;
        input [8*120-1:0] message;
        begin
            if (condition === 1'b1) begin
                passed = passed + 1;
                $display("[PASS] %0s", message);
            end else begin
                failed = failed + 1;
                $display("[FAIL] %0s at %0t", message, $time);
            end
        end
    endtask

    task send_aw;
        input [31:0] addr;
        input integer delay_cycles;
        integer n;
        begin
            repeat (delay_cycles) @(negedge clk_i);
            @(negedge clk_i);
            awaddr_i = addr;
            awvalid_i = 1'b1;
            n = 0;
            // Evaluate READY before the sampling edge to avoid TB/DUT races.
            begin : wait_aw
                forever begin
                    #1;
                    if (awready_o === 1'b1) begin
                        @(posedge clk_i);
                        disable wait_aw;
                    end
                    @(negedge clk_i);
                    n = n + 1;
                    if (n > 100) begin
                        $display("[FATAL] AWREADY timeout");
                        $finish;
                    end
                end
            end
            @(negedge clk_i);
            awvalid_i = 1'b0;
        end
    endtask

    task send_w;
        input [31:0] data;
        input [3:0] strb;
        input integer delay_cycles;
        integer n;
        begin
            repeat (delay_cycles) @(negedge clk_i);
            @(negedge clk_i);
            wdata_i = data;
            wstrb_i = strb;
            wvalid_i = 1'b1;
            n = 0;
            begin : wait_w
                forever begin
                    #1;
                    if (wready_o === 1'b1) begin
                        @(posedge clk_i);
                        disable wait_w;
                    end
                    @(negedge clk_i);
                    n = n + 1;
                    if (n > 100) begin
                        $display("[FATAL] WREADY timeout");
                        $finish;
                    end
                end
            end
            @(negedge clk_i);
            wvalid_i = 1'b0;
        end
    endtask

    function [31:0] byte_mask;
        input [3:0] strb;
        begin
            byte_mask = {{8{strb[3]}}, {8{strb[2]}},
                         {8{strb[1]}}, {8{strb[0]}}};
        end
    endfunction

    task axi_write;
        input [31:0] addr;
        input [31:0] data;
        input [3:0] strb;
        input integer aw_delay;
        input integer w_delay;
        input integer hold_b_cycles;
        reg [31:0] old_word, mask;
        reg [1:0] resp_seen;
        integer n, j;
        begin
            $display("[WRITE] addr=%08h data=%08h strb=%b", addr, data, strb);
            fork
                send_aw(addr, aw_delay);
                send_w(data, strb, w_delay);
            join
            n = 0;
            while (bvalid_o !== 1'b1 && n < 30) begin
                @(negedge clk_i);
                n = n + 1;
            end
            check(bvalid_o === 1'b1, "BVALID arrives");
            if (bvalid_o !== 1'b1) begin
                $display("[FATAL] No BVALID");
                $finish;
            end
            resp_seen = bresp_o;
            for (j = 0; j < hold_b_cycles; j = j + 1) begin
                @(negedge clk_i);
                check(bvalid_o === 1'b1 && bresp_o === resp_seen,
                      "BVALID/BRESP stable when BREADY=0");
            end
            check(resp_seen === 2'b00, "BRESP is OKAY");
            @(negedge clk_i);
            bready_i = 1'b1;
            @(posedge clk_i);
            @(negedge clk_i);
            bready_i = 1'b0;
            check(bvalid_o === 1'b0, "BVALID cleared after handshake");

            mask = byte_mask(strb);
            old_word = reference_mem[addr[11:2]];
            reference_mem[addr[11:2]] = (old_word & ~mask) | (data & mask);
        end
    endtask

    task axi_read_check;
        input [31:0] addr;
        input integer hold_r_cycles;
        reg [31:0] observed;
        reg [1:0] resp_seen;
        integer n, j;
        begin
            $display("[READ ] addr=%08h", addr);
            @(negedge clk_i);
            araddr_i = addr;
            arvalid_i = 1'b1;
            n = 0;
            begin : wait_ar
                forever begin
                    #1;
                    if (arready_o === 1'b1) begin
                        @(posedge clk_i);
                        disable wait_ar;
                    end
                    @(negedge clk_i);
                    n = n + 1;
                    if (n > 100) begin
                        $display("[FATAL] ARREADY timeout");
                        $finish;
                    end
                end
            end
            @(negedge clk_i);
            arvalid_i = 1'b0;
            n = 0;
            while (rvalid_o !== 1'b1 && n < 30) begin
                @(negedge clk_i);
                n = n + 1;
            end
            check(rvalid_o === 1'b1, "RVALID arrives");
            if (rvalid_o !== 1'b1) begin
                $display("[FATAL] No RVALID");
                $finish;
            end
            observed = rdata_o;
            resp_seen = rresp_o;
            if (observed !== reference_mem[addr[11:2]])
                $display("[DETAIL] addr=%08h expected=%08h actual=%08h",
                         addr, reference_mem[addr[11:2]], observed);
            check(observed === reference_mem[addr[11:2]], "RDATA matches expected memory");
            check(resp_seen === 2'b00, "RRESP is OKAY");
            for (j = 0; j < hold_r_cycles; j = j + 1) begin
                @(negedge clk_i);
                check(rvalid_o === 1'b1 && rdata_o === observed && rresp_o === resp_seen,
                      "RVALID/RDATA/RRESP stable when RREADY=0");
            end
            @(negedge clk_i);
            rready_i = 1'b1;
            @(posedge clk_i);
            @(negedge clk_i);
            rready_i = 1'b0;
            check(rvalid_o === 1'b0, "RVALID cleared after handshake");
        end
    endtask

    initial begin
        #100000;
        $display("[FATAL] Global simulation timeout");
        $finish;
    end

    initial begin
        passed = 0;
        failed = 0;
        rst_i = 1'b1;
        awvalid_i = 0; awaddr_i = 0;
        wvalid_i = 0; wdata_i = 0; wstrb_i = 0;
        bready_i = 0; arvalid_i = 0; araddr_i = 0; rready_i = 0;
        for (i = 0; i < 1024; i = i + 1) reference_mem[i] = 32'b0;

        repeat (4) @(negedge clk_i);
        rst_i = 1'b0;
        repeat (2) @(negedge clk_i);

        $display("\n======= TEST 1: Full word read/write =======");
        axi_write(32'h00000008, 32'h12345678, 4'hF, 0, 0, 2);
        axi_read_check(32'h00000008, 3);

        $display("\n======= TEST 2: Byte writes (RMW) =======");
        axi_write(32'h00000008, 32'h000000AA, 4'b0001, 0, 0, 0);
        axi_read_check(32'h00000008, 0);
        axi_write(32'h00000008, 32'h0000BB00, 4'b0010, 0, 0, 0);
        axi_read_check(32'h00000008, 0);
        axi_write(32'h00000008, 32'h00CC0000, 4'b0100, 0, 0, 0);
        axi_read_check(32'h00000008, 0);
        axi_write(32'h00000008, 32'hDD000000, 4'b1000, 0, 0, 0);
        axi_read_check(32'h00000008, 0);

        $display("\n======= TEST 3: Halfword writes (RMW) =======");
        axi_write(32'h00000008, 32'h00001122, 4'b0011, 0, 0, 0);
        axi_read_check(32'h00000008, 1);
        axi_write(32'h00000008, 32'h33440000, 4'b1100, 0, 0, 0);
        axi_read_check(32'h00000008, 0);

        $display("\n======= TEST 4: AW before W =======");
        axi_write(32'h00000014, 32'hCAFEBABE, 4'hF, 0, 4, 2);
        axi_read_check(32'h00000014, 0);

        $display("\n======= TEST 5: W before AW =======");
        axi_write(32'h00000018, 32'hDEADBEEF, 4'hF, 4, 0, 0);
        axi_read_check(32'h00000018, 0);

        $display("\n======= TEST 6: First and last word =======");
        axi_write(32'h00000000, 32'h01020304, 4'hF, 0, 0, 0);
        axi_write(32'h00000FFC, 32'hF0E0D0C0, 4'hF, 0, 0, 0);
        axi_read_check(32'h00000000, 0);
        axi_read_check(32'h00000FFC, 2);

        $display("\n======= TEST 7: WSTRB=0000 =======");
        axi_write(32'h00000008, 32'hFFFFFFFF, 4'h0, 0, 0, 0);
        axi_read_check(32'h00000008, 0);

        $display("\n======= TEST 8: Consecutive transactions =======");
        for (i = 0; i < 8; i = i + 1)
            axi_write(32'h00000100 + 4*i, 32'hA5000000 + i, 4'hF, 0, 0, 0);
        for (i = 0; i < 8; i = i + 1)
            axi_read_check(32'h00000100 + 4*i, 0);

        $display("\n======= SUMMARY =======");
        $display("Checks PASS=%0d FAIL=%0d", passed, failed);
        if (failed == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TESTBENCH FAILED");
        $finish;
    end
endmodule

