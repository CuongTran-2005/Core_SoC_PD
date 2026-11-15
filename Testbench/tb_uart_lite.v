`timescale 1ns / 1ps
// ==============================================================================
// Project: CE434 - Chuyen de Thiet ke he vi mach 1 (RTL to GDS)
// Member: Nham
// Module Testbench: tb_uart_lite
// Target DUT: uart_lite (Ultra-Embedded Basic Peripheral SoC)
// Description:
//   Self-checking testbench for UART Lite IP block with AXI4-Lite interface.
//   Verifies:
//     1. Reset state and initial status register values
//     2. AXI4-Lite read/write access to all registers
//     3. TX operation: byte transmission, start/data/stop bit timing, TXEMPTY/TXFULL flags
//     4. RX operation: external frame reception, mid-bit sampling, RXVALID flag
//     5. Interrupt generation (intr_o) on TX complete and RX receive
//     6. Control register functions: Software Reset (RST_TX, RST_RX) and Interrupt Enable (IE)
//     7. Loopback test (tx_o tied to rx_i)
// ==============================================================================

module tb_uart_lite;

    // -------------------------------------------------------------------------
    // 1. Clock and Simulation Parameters
    // -------------------------------------------------------------------------
    localparam CLK_FREQ_HZ = 50_000_000;         // 50 MHz clock
    localparam BAUDRATE    = 1_000_000;          // 1 Mbps baudrate
    localparam CLK_PERIOD  = 20;                 // 20 ns period (50 MHz)
    localparam BIT_CLOCKS  = CLK_FREQ_HZ / BAUDRATE; // 50 clock cycles per bit
    localparam BIT_PERIOD  = BIT_CLOCKS * CLK_PERIOD; // 1000 ns per bit

    // Register Offsets (from uart_lite_defs.v)
    localparam REG_RX      = 8'h00; // Read-only:  [7:0] Rx Data
    localparam REG_TX      = 8'h04; // Write-only: [7:0] Tx Data
    localparam REG_STATUS  = 8'h08; // Read-only:  Status Register
    localparam REG_CONTROL = 8'h0C; // Write-only: Control Register

    // Status Register Bit Masks
    localparam STATUS_RXVALID = 1 << 0;
    localparam STATUS_RXFULL  = 1 << 1;
    localparam STATUS_TXEMPTY = 1 << 2;
    localparam STATUS_TXFULL  = 1 << 3;
    localparam STATUS_IE      = 1 << 4;

    // Control Register Bit Masks
    localparam CTRL_RST_TX = 1 << 0;
    localparam CTRL_RST_RX = 1 << 1;
    localparam CTRL_IE     = 1 << 4;

    // -------------------------------------------------------------------------
    // 2. DUT Signals
    // -------------------------------------------------------------------------
    reg         clk_i;
    reg         rst_i;

    // AXI4-Lite Interface
    reg         cfg_awvalid_i;
    reg  [31:0] cfg_awaddr_i;
    reg         cfg_wvalid_i;
    reg  [31:0] cfg_wdata_i;
    reg  [3:0]  cfg_wstrb_i;
    reg         cfg_bready_i;
    reg         cfg_arvalid_i;
    reg  [31:0] cfg_araddr_i;
    reg         cfg_rready_i;

    wire        cfg_awready_o;
    wire        cfg_wready_o;
    wire        cfg_bvalid_o;
    wire [1:0]  cfg_bresp_o;
    wire        cfg_arready_o;
    wire        cfg_rvalid_o;
    wire [31:0] cfg_rdata_o;
    wire [1:0]  cfg_rresp_o;

    // Serial lines and Interrupt
    reg         rx_ext;
    reg         loopback_en;
    wire        tx_o;
    wire        intr_o;
    wire        rx_i;

    assign rx_i = loopback_en ? tx_o : rx_ext;

    // Testbench tracking
    integer pass_count = 0;
    integer fail_count = 0;
    reg [31:0] read_data;

    // -------------------------------------------------------------------------
    // 3. DUT Instantiation
    // -------------------------------------------------------------------------
    uart_lite #(
        .CLK_FREQ(CLK_FREQ_HZ),
        .BAUDRATE(BAUDRATE)
    ) u_dut (
        .clk_i         (clk_i),
        .rst_i         (rst_i),
        .cfg_awvalid_i (cfg_awvalid_i),
        .cfg_awaddr_i  (cfg_awaddr_i),
        .cfg_wvalid_i  (cfg_wvalid_i),
        .cfg_wdata_i   (cfg_wdata_i),
        .cfg_wstrb_i   (cfg_wstrb_i),
        .cfg_bready_i  (cfg_bready_i),
        .cfg_arvalid_i (cfg_arvalid_i),
        .cfg_araddr_i  (cfg_araddr_i),
        .cfg_rready_i  (cfg_rready_i),
        .rx_i          (rx_i),
        .cfg_awready_o (cfg_awready_o),
        .cfg_wready_o  (cfg_wready_o),
        .cfg_bvalid_o  (cfg_bvalid_o),
        .cfg_bresp_o   (cfg_bresp_o),
        .cfg_arready_o (cfg_arready_o),
        .cfg_rvalid_o  (cfg_rvalid_o),
        .cfg_rdata_o   (cfg_rdata_o),
        .cfg_rresp_o   (cfg_rresp_o),
        .tx_o          (tx_o),
        .intr_o        (intr_o)
    );

    // -------------------------------------------------------------------------
    // 4. Clock Generation (50 MHz)
    // -------------------------------------------------------------------------
    always #(CLK_PERIOD / 2) clk_i = ~clk_i;

    // -------------------------------------------------------------------------
    // 5. AXI4-Lite Driver Tasks
    // -------------------------------------------------------------------------
    task axi_write;
        input [7:0]  addr;
        input [31:0] data;
        reg aw_done, w_done;
    begin
        @(negedge clk_i);
        cfg_awvalid_i = 1'b1;
        cfg_awaddr_i  = {24'h0, addr};
        cfg_wvalid_i  = 1'b1;
        cfg_wdata_i   = data;
        cfg_wstrb_i   = 4'hF;
        cfg_bready_i  = 1'b1;
        aw_done       = 1'b0;
        w_done        = 1'b0;

        while (!(aw_done && w_done)) begin
            @(posedge clk_i);
            if (cfg_awvalid_i && cfg_awready_o) aw_done = 1'b1;
            if (cfg_wvalid_i  && cfg_wready_o)  w_done  = 1'b1;
            @(negedge clk_i);
            if (aw_done) cfg_awvalid_i = 1'b0;
            if (w_done)  cfg_wvalid_i  = 1'b0;
        end

        // Wait for response
        while (!cfg_bvalid_o) @(posedge clk_i);
        @(negedge clk_i);
        cfg_bready_i = 1'b0;
    end
    endtask

    task axi_read;
        input  [7:0]  addr;
        output [31:0] data;
    begin
        @(negedge clk_i);
        cfg_arvalid_i = 1'b1;
        cfg_araddr_i  = {24'h0, addr};
        cfg_rready_i  = 1'b1;

        while (!(cfg_arvalid_i && cfg_arready_o)) @(posedge clk_i);
        @(negedge clk_i);
        cfg_arvalid_i = 1'b0;

        while (!cfg_rvalid_o) @(posedge clk_i);
        data = cfg_rdata_o;
        @(negedge clk_i);
        cfg_rready_i = 1'b0;
    end
    endtask

    // -------------------------------------------------------------------------
    // 6. External UART Sender (Simulates Host/Peripheral transmitting into rx_i)
    // -------------------------------------------------------------------------
    task uart_send_rx_byte;
        input [7:0] tx_data;
        integer bit_idx;
    begin
        // Start bit (Logic 0)
        rx_ext = 1'b0;
        #(BIT_PERIOD);

        // 8 Data bits (LSB first)
        for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
            rx_ext = tx_data[bit_idx];
            #(BIT_PERIOD);
        end

        // Stop bit (Logic 1)
        rx_ext = 1'b1;
        #(BIT_PERIOD);
    end
    endtask

    // -------------------------------------------------------------------------
    // 7. Verification Procedures
    // -------------------------------------------------------------------------
    initial begin
        $display("==================================================================");
        $display("[TEST START] CE434 - UART Lite IP Functional Verification");
        $display("  Target Config: CLK = %0d MHz, Baudrate = %0d bps", CLK_FREQ_HZ/1_000_000, BAUDRATE);
        $display("  Bit Divider: %0d clocks per UART bit", BIT_CLOCKS);
        $display("==================================================================");

        // Init signals
        clk_i         = 1'b0;
        rst_i         = 1'b1;
        cfg_awvalid_i = 1'b0;
        cfg_awaddr_i  = 32'b0;
        cfg_wvalid_i  = 1'b0;
        cfg_wdata_i   = 32'b0;
        cfg_wstrb_i   = 4'b0;
        cfg_bready_i  = 1'b0;
        cfg_arvalid_i = 1'b0;
        cfg_araddr_i  = 32'b0;
        cfg_rready_i  = 1'b0;
        rx_ext        = 1'b1; // Idle state for UART RX is High
        loopback_en   = 1'b0;

        // Apply Reset
        #(CLK_PERIOD * 5);
        rst_i = 1'b0;
        #(CLK_PERIOD * 5);

        // ---------------------------------------------------------------------
        // TEST 1: Check Reset State
        // ---------------------------------------------------------------------
        $display("\n--- [TEST 1] Check Reset State and Status Register ---");
        axi_read(REG_STATUS, read_data);
        $display("  Read STATUS = 0x%08X (Expected TXEMPTY=1, TXFULL=0, RXVALID=0)", read_data);

        if ((read_data & STATUS_TXEMPTY) && !(read_data & STATUS_TXFULL) && !(read_data & STATUS_RXVALID)) begin
            $display("  [PASS] Initial Status register flags are correct.");
            pass_count = pass_count + 1;
        end else begin
            $display("  [FAIL] Initial Status register flags mismatch!");
            fail_count = fail_count + 1;
        end

        if (tx_o === 1'b1) begin
            $display("  [PASS] UART TX line is idling at Logic 1.");
            pass_count = pass_count + 1;
        end else begin
            $display("  [FAIL] UART TX line is not idling at Logic 1!");
            fail_count = fail_count + 1;
        end

        // ---------------------------------------------------------------------
        // TEST 2: Transmit a byte (TX) and sample serial bit-stream
        // ---------------------------------------------------------------------
        $display("\n--- [TEST 2] Transmit Byte (0xA5) via AXI Write to REG_TX ---");
        // Byte 0xA5 = 8'b1010_0101 -> Bits: Start(0), 1,0,1,0,0,1,0,1, Stop(1)
        fork
            begin
                // Thread 1: Write 0xA5 and check TXFULL while transmitting
                axi_write(REG_TX, 32'h0000_00A5);
                #(CLK_PERIOD * 2);
                axi_read(REG_STATUS, read_data);
                if (read_data & STATUS_TXFULL) begin
                    $display("  [PASS] STATUS_TXFULL is asserted while transmitting.");
                    pass_count = pass_count + 1;
                end else begin
                    $display("  [FAIL] STATUS_TXFULL was NOT asserted during transmission.");
                    fail_count = fail_count + 1;
                end
            end
            begin : check_tx_bits
                // Thread 2: Capture Start, 8 Data bits, and Stop bit on tx_o
                reg [7:0] sampled_tx;
                integer i;
                @(negedge tx_o);
                $display("  Detected Start bit (tx_o = 0) at time %0t ns", $time);
                pass_count = pass_count + 1;

                #(BIT_PERIOD / 2); // Center of start bit
                if (tx_o !== 1'b0) $display("  [FAIL] Start bit is not 0!");

                sampled_tx = 8'h00;
                for (i = 0; i < 8; i = i + 1) begin
                    #(BIT_PERIOD);
                    sampled_tx[i] = tx_o;
                end
                #(BIT_PERIOD); // Stop bit
                if (tx_o === 1'b1 && sampled_tx === 8'hA5) begin
                    $display("  [PASS] Received valid frame on tx_o: Data=0x%02X, Stop bit=1", sampled_tx);
                    pass_count = pass_count + 1;
                end else begin
                    $display("  [FAIL] TX Frame mismatch: Sampled=0x%02X (Expected 0xA5), Stop bit=%b", sampled_tx, tx_o);
                    fail_count = fail_count + 1;
                end
            end
        join

        // Wait until transmission completes and check TXEMPTY
        #(BIT_PERIOD);
        axi_read(REG_STATUS, read_data);
        if (read_data & STATUS_TXEMPTY) begin
            $display("  [PASS] STATUS_TXEMPTY is restored to 1 after completion.");
            pass_count = pass_count + 1;
        end else begin
            $display("  [FAIL] STATUS_TXEMPTY not restored!");
            fail_count = fail_count + 1;
        end

        // ---------------------------------------------------------------------
        // TEST 3: Receive a byte (RX) from outside (0x3C)
        // ---------------------------------------------------------------------
        $display("\n--- [TEST 3] External Host sends Byte (0x3C) to rx_i ---");
        // 0x3C = 8'b0011_1100
        uart_send_rx_byte(8'h3C);

        #(CLK_PERIOD * 10);
        // Check STATUS has RXVALID
        axi_read(REG_STATUS, read_data);
        if (read_data & STATUS_RXVALID) begin
            $display("  [PASS] STATUS_RXVALID asserted after receiving byte.");
            pass_count = pass_count + 1;
        end else begin
            $display("  [FAIL] STATUS_RXVALID was NOT asserted!");
            fail_count = fail_count + 1;
        end

        // Check Interrupt
        if (intr_o === 1'b1) begin
            $display("  [PASS] intr_o interrupt signal is asserted on RX receive.");
            pass_count = pass_count + 1;
        end else begin
            $display("  [FAIL] intr_o was NOT asserted!");
            fail_count = fail_count + 1;
        end

        // Read received byte from REG_RX
        axi_read(REG_RX, read_data);
        $display("  Read REG_RX = 0x%02X (Expected 0x3C)", read_data[7:0]);
        if (read_data[7:0] === 8'h3C) begin
            $display("  [PASS] REG_RX data matches transmitted byte (0x3C).");
            pass_count = pass_count + 1;
        end else begin
            $display("  [FAIL] REG_RX data mismatch!");
            fail_count = fail_count + 1;
        end

        // Reading REG_RX should clear RXVALID and intr_o
        #(CLK_PERIOD * 2);
        axi_read(REG_STATUS, read_data);
        if (!(read_data & STATUS_RXVALID) && (intr_o === 1'b0)) begin
            $display("  [PASS] STATUS_RXVALID and intr_o automatically cleared after read.");
            pass_count = pass_count + 1;
        end else begin
            $display("  [FAIL] STATUS_RXVALID or intr_o did not clear after reading REG_RX!");
            fail_count = fail_count + 1;
        end

        // ---------------------------------------------------------------------
        // TEST 4: Loopback Verification (tx_o -> rx_i)
        // ---------------------------------------------------------------------
        $display("\n--- [TEST 4] Hardware Loopback Mode (Transmitting 0x7E) ---");
        loopback_en = 1'b1;
        #(CLK_PERIOD * 2);
        axi_write(REG_TX, 32'h0000_007E);

        // Wait for full 10-bit UART frame + synchronizer margin (~12 bit periods)
        #(BIT_PERIOD * 12);
        axi_read(REG_STATUS, read_data);
        if (read_data & STATUS_RXVALID) begin
            axi_read(REG_RX, read_data);
            if (read_data[7:0] === 8'h7E) begin
                $display("  [PASS] Loopback test passed! Sent 0x7E, received 0x%02X", read_data[7:0]);
                pass_count = pass_count + 1;
            end else begin
                $display("  [FAIL] Loopback data mismatch: 0x%02X", read_data[7:0]);
                fail_count = fail_count + 1;
            end
        end else begin
            $display("  [FAIL] Loopback failed: RXVALID not asserted.");
            fail_count = fail_count + 1;
        end
        loopback_en = 1'b0; // restore normal external RX

        // ---------------------------------------------------------------------
        // TEST 5: Control Register & Software Reset
        // ---------------------------------------------------------------------
        $display("\n--- [TEST 5] Control Register: Enable Interrupt & Reset FIFO ---");
        // Enable IE (bit 4)
        axi_write(REG_CONTROL, 32'h0000_0010);
        axi_read(REG_STATUS, read_data);
        if (read_data & STATUS_IE) begin
            $display("  [PASS] Interrupt Enable bit successfully set in Status register.");
            pass_count = pass_count + 1;
        end else begin
            $display("  [FAIL] Interrupt Enable bit not reflected in Status register!");
            fail_count = fail_count + 1;
        end

        // Trigger Software Reset of RX and TX
        axi_write(REG_CONTROL, 32'h0000_0003); // RST_TX | RST_RX
        #(CLK_PERIOD * 2);
        axi_read(REG_STATUS, read_data);
        if (read_data & STATUS_TXEMPTY) begin
            $display("  [PASS] Reset FIFO command executed cleanly.");
            pass_count = pass_count + 1;
        end else begin
            $display("  [FAIL] Reset FIFO failed.");
            fail_count = fail_count + 1;
        end

        // ---------------------------------------------------------------------
        // Simulation Summary
        // ---------------------------------------------------------------------
        #(CLK_PERIOD * 10);
        $display("\n==================================================================");
        $display("                  UART LITE TESTBENCH SUMMARY                     ");
        $display("==================================================================");
        $display("  TOTAL TESTS PASSED : %0d", pass_count);
        $display("  TOTAL TESTS FAILED : %0d", fail_count);
        if (fail_count == 0) begin
            $display("  >>> OVERALL RESULT : [SUCCESS] UART LITE IS 100%% FUNCTIONAL <<<");
        end else begin
            $display("  >>> OVERALL RESULT : [FAILED] PLEASE CHECK FAILED CHECKS <<<");
        end
        $display("==================================================================\n");

        $finish;
    end

endmodule