
`timescale 1ns/1ps

module tb_RISC_V_2;

    reg clk;
    reg rst;

    //==========================================================
    // AXI4-Lite signals
    //==========================================================

    wire [31:0] axi_araddr;
    wire        axi_arvalid;
    reg         axi_arready;

    reg  [31:0] axi_rdata;
    reg  [1:0]  axi_rresp;
    reg         axi_rvalid;
    wire        axi_rready;

    wire [31:0] axi_awaddr;
    wire        axi_awvalid;
    reg         axi_awready;

    wire [31:0] axi_wdata;
    wire [3:0]  axi_wstrb;
    wire        axi_wvalid;
    reg         axi_wready;

    reg  [1:0]  axi_bresp;
    reg         axi_bvalid;
    wire        axi_bready;

    //==========================================================
    // DUT
    //==========================================================

    RISC_V dut (
        .clk(clk),
        .rst(rst),

        .axi_araddr(axi_araddr),
        .axi_arvalid(axi_arvalid),
        .axi_arready(axi_arready),

        .axi_rdata(axi_rdata),
        .axi_rresp(axi_rresp),
        .axi_rvalid(axi_rvalid),
        .axi_rready(axi_rready),

        .axi_awaddr(axi_awaddr),
        .axi_awvalid(axi_awvalid),
        .axi_awready(axi_awready),

        .axi_wdata(axi_wdata),
        .axi_wstrb(axi_wstrb),
        .axi_wvalid(axi_wvalid),
        .axi_wready(axi_wready),

        .axi_bresp(axi_bresp),
        .axi_bvalid(axi_bvalid),
        .axi_bready(axi_bready)
    );

    //==========================================================
    // Clock
    //==========================================================

    initial clk = 0;
    always #5 clk = ~clk;

    //==========================================================
    // Test control
    //==========================================================

    integer test_phase;

    integer fetch_count;
    integer dmem_read_count;

    integer cycle_count;
    integer error_count;

    reg [31:0] last_araddr;

    //==========================================================
    // AXI Memory Model
    //==========================================================

    reg [31:0] pending_data;
    integer latency_count;
    reg response_pending;

    // Read memory
    function automatic [31:0] read_memory(
        input [31:0] addr
    );
    begin

        if (test_phase == 1) begin

            // Scenario 1: NOP instructions
            read_memory = 32'h00000013;

        end
        else begin

            // Scenario 2: RISC-V program
            case (addr)

                32'h00000000:
                    read_memory = 32'h04000093; // ADDI x1,x0,0x40

                32'h00000004:
                    read_memory = 32'h0000A103; // LW x2,0(x1)

                32'h00000008:
                    read_memory = 32'h0000006F; // JAL x0,0

                32'h00000040:
                    read_memory = 32'h12345678; // DMEM data

                default:
                    read_memory = 32'h00000013; // NOP

            endcase

        end

    end
    endfunction

    //==========================================================
    // AXI Read Channel Model
    //==========================================================

    always @(posedge clk) begin

        if (rst) begin

            axi_arready     <= 1'b1;

            axi_rvalid      <= 1'b0;
            axi_rdata       <= 32'b0;
            axi_rresp       <= 2'b00;

            pending_data    <= 32'b0;
            latency_count   <= 0;
            response_pending <= 1'b0;

        end
        else begin

            // -----------------------------------------------
            // Address handshake
            // -----------------------------------------------

            if (axi_arvalid && axi_arready) begin

                axi_arready <= 1'b0;

                pending_data <= read_memory(axi_araddr);

                latency_count <= 3;
                response_pending <= 1'b1;

                // Count transactions
                last_araddr = axi_araddr;

                if (axi_araddr == 32'h00000040)
                    dmem_read_count = dmem_read_count + 1;
                else
                    fetch_count = fetch_count + 1;

                $display(
                    "[%0t] AXI READ REQUEST: ADDR = %h",
                    $time, axi_araddr
                );

            end

            // -----------------------------------------------
            // Read response latency
            // -----------------------------------------------

            if (response_pending && !axi_rvalid) begin

                if (latency_count > 0) begin

                    latency_count <= latency_count - 1;

                end
                else begin

                    axi_rdata <= pending_data;
                    axi_rresp <= 2'b00;
                    axi_rvalid <= 1'b1;

                    response_pending <= 1'b0;

                    $display(
                        "[%0t] AXI READ RESPONSE: DATA = %h",
                        $time, pending_data
                    );

                end

            end

            // -----------------------------------------------
            // Read data handshake
            // -----------------------------------------------

            if (axi_rvalid && axi_rready) begin

                axi_rvalid <= 1'b0;
                axi_arready <= 1'b1;

                $display(
                    "[%0t] AXI READ COMPLETE",
                    $time
                );

            end

        end

    end

    //==========================================================
    // AXI Write Channel: Disabled
    //==========================================================

    initial begin

        axi_awready = 1'b0;
        axi_wready  = 1'b0;

        axi_bvalid  = 1'b0;
        axi_bresp   = 2'b00;

    end

    //==========================================================
    // Monitor
    //==========================================================

    always @(posedge clk) begin

        if (!rst)
            cycle_count = cycle_count + 1;

    end

    //==========================================================
    // Main Test
    //==========================================================

    initial begin

        rst = 1'b1;

        test_phase = 0;

        fetch_count = 0;
        dmem_read_count = 0;

        cycle_count = 0;
        error_count = 0;

        last_araddr = 0;

        $display("");
        $display("========================================");
        $display("       RISC-V CORE TESTBENCH");
        $display("========================================");

        //======================================================
        // RESET
        //======================================================

        repeat (5) @(posedge clk);
        @(negedge clk);

        rst = 1'b0;

        //======================================================
        // TEST 1: Instruction Fetch Only
        //======================================================

        $display("");
        $display("----------------------------------------");
        $display("TEST 1: INSTRUCTION FETCH");
        $display("----------------------------------------");

        test_phase = 1;

        // Wait for at least 3 instruction fetch transactions
        wait (fetch_count >= 3);

        repeat (5) @(posedge clk);

        $display("");
        $display("TEST 1 RESULT:");
        $display("Instruction fetch count = %0d", fetch_count);

        if (fetch_count >= 3) begin

            $display("[PASS] CPU sends instruction fetch requests");

        end
        else begin

            $display("[FAIL] No instruction fetch requests");
            error_count = error_count + 1;

        end

        //======================================================
        // RESET BEFORE TEST 2
        //======================================================

        @(negedge clk);
        rst = 1'b1;

        repeat (5) @(posedge clk);
        @(negedge clk);

        fetch_count = 0;
        dmem_read_count = 0;

        test_phase = 2;

        rst = 1'b0;

        //======================================================
        // TEST 2: Load Data From DMEM
        //======================================================

        $display("");
        $display("----------------------------------------");
        $display("TEST 2: INSTRUCTION FETCH + DMEM READ");
        $display("----------------------------------------");

        // Wait for DMEM transaction
        fork

            begin
                wait (dmem_read_count >= 1);
            end

            begin
                repeat (300) @(posedge clk);

                $display("[TIMEOUT] DMEM READ NOT DETECTED");

                error_count = error_count + 1;

            end

        join_any

        disable fork;

        repeat (15) @(posedge clk);

        $display("");
        $display("TEST 2 RESULT:");
        $display("Instruction fetch count = %0d", fetch_count);
        $display("DMEM read count         = %0d", dmem_read_count);

        if (dmem_read_count >= 1) begin

            $display("[PASS] CPU sends DMEM read request");

        end
        else begin

            $display("[FAIL] CPU does not send DMEM read request");

            error_count = error_count + 1;

        end

        //======================================================
        // FINAL RESULT
        //======================================================

        $display("");
        $display("========================================");
        $display("             FINAL RESULT");
        $display("========================================");

        if (error_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TEST FAILED: %0d errors", error_count);

        $display("Total cycles = %0d", cycle_count);

        $display("========================================");

        #50;
        $finish;

    end

    //==========================================================
    // Global timeout
    //==========================================================

    initial begin

        #20000;

        $display("[FATAL] GLOBAL TIMEOUT");

        $finish;

    end

endmodule
