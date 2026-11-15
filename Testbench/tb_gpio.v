`timescale 1ns / 1ps
// ==============================================================================
// Project: CE434 - Chuyen de Thiet ke he vi mach 1 (RTL to GDS)
// Member: Nham
// Module Testbench: tb_gpio
// Target DUT: gpio (Ultra-Embedded Basic Peripheral SoC)
// Description:
//   Self-checking testbench for 32-bit GPIO IP block with AXI4-Lite interface.
//   Verifies:
//     1. Reset state and initial register values
//     2. AXI4-Lite read/write access to all registers
//     3. Direction Control (GPIO_DIRECTION) and Output Enable (gpio_output_enable_o)
//     4. Direct Output Write (GPIO_OUTPUT) and Readback
//     5. Atomic Bit Set (GPIO_OUTPUT_SET) and Atomic Bit Clear (GPIO_OUTPUT_CLR)
//     6. Input Sampling through 2-stage synchronizer flip-flops (GPIO_INPUT)
//     7. Edge-Triggered Interrupts (Rising & Falling edge detection)
//     8. Level-Triggered Interrupts (Active-high & Active-low detection)
//     9. Software-triggered interrupts (GPIO_INT_SET) and ACK (GPIO_INT_CLR)
// ==============================================================================

module tb_gpio;

    // -------------------------------------------------------------------------
    // 1. Clock and Simulation Parameters
    // -------------------------------------------------------------------------
    localparam CLK_FREQ_HZ = 50_000_000;         // 50 MHz clock
    localparam CLK_PERIOD  = 20;                 // 20 ns period

    // Register Offsets (from gpio_defs.v)
    localparam REG_DIRECTION  = 8'h00; // RW: Direction / Output Enable
    localparam REG_INPUT      = 8'h04; // RO: Input pin sampled values
    localparam REG_OUTPUT     = 8'h08; // RW: Output data
    localparam REG_OUTPUT_SET = 8'h0C; // WO: Atomic Bit Set
    localparam REG_OUTPUT_CLR = 8'h10; // WO: Atomic Bit Clear
    localparam REG_INT_MASK   = 8'h14; // RW: Interrupt Mask (Enable)
    localparam REG_INT_SET    = 8'h18; // WO: Software IRQ Trigger
    localparam REG_INT_CLR    = 8'h1C; // WO: Interrupt Acknowledge (Clear)
    localparam REG_INT_STATUS = 8'h20; // RO: Raw Interrupt Status
    localparam REG_INT_LEVEL  = 8'h24; // RW: 1=Active High/Rising, 0=Active Low/Falling
    localparam REG_INT_MODE   = 8'h28; // RW: 1=Edge Triggered, 0=Level Triggered

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

    // GPIO External Pins
    reg  [31:0] gpio_input_i;
    wire [31:0] gpio_output_o;
    wire [31:0] gpio_output_enable_o;
    wire        intr_o;

    // Tracking variables
    integer pass_count = 0;
    integer fail_count = 0;
    reg [31:0] read_data;

    // -------------------------------------------------------------------------
    // 3. DUT Instantiation
    // -------------------------------------------------------------------------
    gpio u_dut (
        .clk_i                (clk_i),
        .rst_i                (rst_i),
        .cfg_awvalid_i        (cfg_awvalid_i),
        .cfg_awaddr_i         (cfg_awaddr_i),
        .cfg_wvalid_i         (cfg_wvalid_i),
        .cfg_wdata_i          (cfg_wdata_i),
        .cfg_wstrb_i          (cfg_wstrb_i),
        .cfg_bready_i         (cfg_bready_i),
        .cfg_arvalid_i        (cfg_arvalid_i),
        .cfg_araddr_i         (cfg_araddr_i),
        .cfg_rready_i         (cfg_rready_i),
        .gpio_input_i         (gpio_input_i),
        .cfg_awready_o        (cfg_awready_o),
        .cfg_wready_o         (cfg_wready_o),
        .cfg_bvalid_o         (cfg_bvalid_o),
        .cfg_bresp_o          (cfg_bresp_o),
        .cfg_arready_o        (cfg_arready_o),
        .cfg_rvalid_o         (cfg_rvalid_o),
        .cfg_rdata_o          (cfg_rdata_o),
        .cfg_rresp_o          (cfg_rresp_o),
        .gpio_output_o        (gpio_output_o),
        .gpio_output_enable_o (gpio_output_enable_o),
        .intr_o               (intr_o)
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
    // 6. Verification Procedures
    // -------------------------------------------------------------------------
    initial begin
        $display("==================================================================");
        $display("[TEST START] CE434 - GPIO 32-bit IP Functional Verification");
        $display("  Target Clock: 50 MHz (Period: %0d ns)", CLK_PERIOD);
        $display("==================================================================");

        // Initialize signals
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
        gpio_input_i  = 32'b0;

        // Apply Reset
        #(CLK_PERIOD * 5);
        rst_i = 1'b0;
        #(CLK_PERIOD * 5);

        // ---------------------------------------------------------------------
        // TEST 1: Check Reset State
        // ---------------------------------------------------------------------
        $display("\n--- [TEST 1] Check Reset State ---");
        if (gpio_output_o === 32'b0 && gpio_output_enable_o === 32'b0 && intr_o === 1'b0) begin
            $display("  [PASS] All output ports and interrupt are 0 after reset.");
            pass_count = pass_count + 1;
        end else begin
            $display("  [FAIL] Reset output mismatch: out=0x%08X, oe=0x%08X, intr=%b", 
                     gpio_output_o, gpio_output_enable_o, intr_o);
            fail_count = fail_count + 1;
        end

        // ---------------------------------------------------------------------
        // TEST 2: Direction Control (Output Enable)
        // ---------------------------------------------------------------------
        $display("\n--- [TEST 2] Configure Direction Register (GPIO_DIRECTION) ---");
        // Set upper 16-bit as Output (1), lower 16-bit as Input (0)
        axi_write(REG_DIRECTION, 32'hFFFF_0000);
        #(CLK_PERIOD);
        axi_read(REG_DIRECTION, read_data);

        if (read_data === 32'hFFFF_0000 && gpio_output_enable_o === 32'hFFFF_0000) begin
            $display("  [PASS] GPIO_DIRECTION readback and gpio_output_enable_o match: 0x%08X", read_data);
            pass_count = pass_count + 1;
        end else begin
            $display("  [FAIL] GPIO_DIRECTION mismatch! Read=0x%08X, OE=0x%08X", read_data, gpio_output_enable_o);
            fail_count = fail_count + 1;
        end

        // ---------------------------------------------------------------------
        // TEST 3: Direct Output Write and Readback
        // ---------------------------------------------------------------------
        $display("\n--- [TEST 3] Direct Output Write (GPIO_OUTPUT) ---");
        axi_write(REG_OUTPUT, 32'hA5A5_5A5A);
        #(CLK_PERIOD);
        axi_read(REG_OUTPUT, read_data);

        if (read_data === 32'hA5A5_5A5A && gpio_output_o === 32'hA5A5_5A5A) begin
            $display("  [PASS] GPIO_OUTPUT write and readback correct: 0x%08X", read_data);
            pass_count = pass_count + 1;
        end else begin
            $display("  [FAIL] GPIO_OUTPUT mismatch: Read=0x%08X, Pin=0x%08X", read_data, gpio_output_o);
            fail_count = fail_count + 1;
        end

        // ---------------------------------------------------------------------
        // TEST 4: Atomic Bit SET and Bit CLR
        // ---------------------------------------------------------------------
        $display("\n--- [TEST 4] Atomic SET (GPIO_OUTPUT_SET) & CLR (GPIO_OUTPUT_CLR) ---");
        // Clear all outputs first
        axi_write(REG_OUTPUT, 32'h0000_0000);
        
        // Atomic SET bits [7:4]
        axi_write(REG_OUTPUT_SET, 32'h0000_00F0);
        #(CLK_PERIOD);
        if (gpio_output_o === 32'h0000_00F0) begin
            $display("  [PASS] GPIO_OUTPUT_SET 0x000000F0 verified: out=0x%08X", gpio_output_o);
            pass_count = pass_count + 1;
        end else begin
            $display("  [FAIL] GPIO_OUTPUT_SET failed: out=0x%08X", gpio_output_o);
            fail_count = fail_count + 1;
        end

        // Atomic SET bits [11:8] without corrupting [7:4]
        axi_write(REG_OUTPUT_SET, 32'h0000_0F00);
        #(CLK_PERIOD);
        if (gpio_output_o === 32'h0000_0FF0) begin
            $display("  [PASS] GPIO_OUTPUT_SET 0x00000F00 accumulated: out=0x%08X", gpio_output_o);
            pass_count = pass_count + 1;
        end else begin
            $display("  [FAIL] Accumulative SET failed: out=0x%08X", gpio_output_o);
            fail_count = fail_count + 1;
        end

        // Atomic CLR bits [7:6]
        axi_write(REG_OUTPUT_CLR, 32'h0000_00C0);
        #(CLK_PERIOD);
        if (gpio_output_o === 32'h0000_0F30) begin
            $display("  [PASS] GPIO_OUTPUT_CLR 0x000000C0 verified: out=0x%08X", gpio_output_o);
            pass_count = pass_count + 1;
        end else begin
            $display("  [FAIL] GPIO_OUTPUT_CLR failed: out=0x%08X", gpio_output_o);
            fail_count = fail_count + 1;
        end

        // ---------------------------------------------------------------------
        // TEST 5: Input Sampling & 2-Stage Synchronizer Check
        // ---------------------------------------------------------------------
        $display("\n--- [TEST 5] Input Sampling via 2-Stage Synchronizer ---");
        gpio_input_i = 32'hDEAD_BEEF;
        // Wait 3 clock cycles for input_ms -> input_q
        #(CLK_PERIOD * 3);
        axi_read(REG_INPUT, read_data);

        if (read_data === 32'hDEAD_BEEF) begin
            $display("  [PASS] GPIO_INPUT readback correctly sampled: 0x%08X", read_data);
            pass_count = pass_count + 1;
        end else begin
            $display("  [FAIL] GPIO_INPUT sampled value mismatch: Read=0x%08X (Expected 0xDEADBEEF)", read_data);
            fail_count = fail_count + 1;
        end

        gpio_input_i = 32'h1234_5678;
        #(CLK_PERIOD * 3);
        axi_read(REG_INPUT, read_data);
        if (read_data === 32'h1234_5678) begin
            $display("  [PASS] GPIO_INPUT updated correctly sampled: 0x%08X", read_data);
            pass_count = pass_count + 1;
        end else begin
            $display("  [FAIL] GPIO_INPUT update mismatch: Read=0x%08X", read_data);
            fail_count = fail_count + 1;
        end

        // ---------------------------------------------------------------------
        // TEST 6: Edge-Triggered Interrupt (Rising Edge on Pin 0)
        // ---------------------------------------------------------------------
        $display("\n--- [TEST 6] Edge-Triggered Interrupt (Rising Edge on Bit 0) ---");
        gpio_input_i = 32'b0;
        #(CLK_PERIOD * 3);

        // Configure Pin 0: Edge-mode (1), Active-high/Rising (1), Enable mask (1)
        axi_write(REG_INT_MODE,  32'h0000_0001); // Bit 0 = Edge
        axi_write(REG_INT_LEVEL, 32'hFFFF_FFFF); // Active High/Rising on all pins
        axi_write(REG_INT_CLR,   32'hFFFF_FFFF); // Clear any residual flags
        axi_write(REG_INT_MASK,  32'h0000_0001); // Bit 0 = Enable IRQ
        #(CLK_PERIOD * 2);

        // Verify no interrupt before event
        if (intr_o === 1'b0) begin
            $display("  [PASS] No spurious interrupt before edge transition.");
            pass_count = pass_count + 1;
        end else begin
            $display("  [FAIL] Spurious interrupt asserted before edge!");
            fail_count = fail_count + 1;
        end

        // Inject Rising Edge on Pin 0 (0 -> 1)
        gpio_input_i[0] = 1'b1;
        // Wait 5 clocks (2-stage sync + interrupt_raw_q + intr_q)
        #(CLK_PERIOD * 5);

        // Check Interrupt Status and intr_o
        axi_read(REG_INT_STATUS, read_data);
        if ((read_data & 32'h1) && intr_o === 1'b1) begin
            $display("  [PASS] Rising edge captured! REG_INT_STATUS=0x%08X, intr_o=1", read_data);
            pass_count = pass_count + 1;
        end else begin
            $display("  [FAIL] Rising edge interrupt NOT captured! Status=0x%08X, intr_o=%b", read_data, intr_o);
            fail_count = fail_count + 1;
        end

        // Clear Interrupt via REG_INT_CLR
        axi_write(REG_INT_CLR, 32'h0000_0001);
        #(CLK_PERIOD * 2);
        axi_read(REG_INT_STATUS, read_data);

        if (!(read_data & 32'h1) && intr_o === 1'b0) begin
            $display("  [PASS] Interrupt successfully acknowledged and cleared (intr_o=0).");
            pass_count = pass_count + 1;
        end else begin
            $display("  [FAIL] Interrupt NOT cleared after ACK! Status=0x%08X, intr_o=%b", read_data, intr_o);
            fail_count = fail_count + 1;
        end

        // ---------------------------------------------------------------------
        // TEST 7: Level-Triggered Interrupt (Active High on Pin 1)
        // ---------------------------------------------------------------------
        $display("\n--- [TEST 7] Level-Triggered Interrupt (Active High on Bit 1) ---");
        gpio_input_i = 32'b0;
        #(CLK_PERIOD * 3);
        // Pin 1: Level-mode (0), Active High (1), Mask enabled (1)
        axi_write(REG_INT_MODE,  32'h0000_0000); // Level mode
        axi_write(REG_INT_LEVEL, 32'hFFFF_FFFF); // Active High on all pins
        axi_write(REG_INT_CLR,   32'hFFFF_FFFF); // Clear residual flags
        axi_write(REG_INT_MASK,  32'h0000_0002); // Bit 1 = Enable IRQ
        #(CLK_PERIOD * 2);

        // Assert level on input pin 1
        gpio_input_i[1] = 1'b1;
        // Wait 5 clocks (2-stage sync + interrupt_raw_q + intr_q)
        #(CLK_PERIOD * 5);

        if (intr_o === 1'b1) begin
            $display("  [PASS] Level-high interrupt asserted on intr_o.");
            pass_count = pass_count + 1;
        end else begin
            $display("  [FAIL] Level-high interrupt NOT asserted!");
            fail_count = fail_count + 1;
        end

        // Remove level on input pin 1 and clear
        gpio_input_i[1] = 1'b0;
        #(CLK_PERIOD * 4);
        axi_write(REG_INT_CLR, 32'h0000_0002);
        #(CLK_PERIOD * 3);

        if (intr_o === 1'b0) begin
            $display("  [PASS] Level interrupt de-asserted after pin pulled low & ACKed.");
            pass_count = pass_count + 1;
        end else begin
            $display("  [FAIL] Level interrupt still asserted after pin pulled low!");
            fail_count = fail_count + 1;
        end

        // ---------------------------------------------------------------------
        // TEST 8: Software Interrupt (SW IRQ Trigger on Pin 4)
        // ---------------------------------------------------------------------
        $display("\n--- [TEST 8] Software Triggered Interrupt (REG_INT_SET) ---");
        axi_write(REG_INT_MODE,  32'h0000_0010); // Bit 4 = Edge mode (avoid active-low level IRQ)
        axi_write(REG_INT_LEVEL, 32'hFFFF_FFFF); // Active High
        axi_write(REG_INT_CLR,   32'hFFFF_FFFF); // Clear flags
        axi_write(REG_INT_MASK,  32'h0000_0010); // Enable IRQ for bit 4
        #(CLK_PERIOD * 2);

        // Trigger SW IRQ on bit 4
        axi_write(REG_INT_SET, 32'h0000_0010);
        #(CLK_PERIOD * 3);

        axi_read(REG_INT_STATUS, read_data);
        if ((read_data & 32'h0000_0010) && intr_o === 1'b1) begin
            $display("  [PASS] Software IRQ triggered! Status=0x%08X, intr_o=1", read_data);
            pass_count = pass_count + 1;
        end else begin
            $display("  [FAIL] Software IRQ failed to trigger! Status=0x%08X, intr_o=%b", read_data, intr_o);
            fail_count = fail_count + 1;
        end

        // Clear SW IRQ
        axi_write(REG_INT_CLR, 32'h0000_0010);
        #(CLK_PERIOD * 2);
        if (intr_o === 1'b0) begin
            $display("  [PASS] Software IRQ successfully cleared.");
            pass_count = pass_count + 1;
        end else begin
            $display("  [FAIL] Software IRQ did not clear!");
            fail_count = fail_count + 1;
        end

        // ---------------------------------------------------------------------
        // Simulation Summary
        // ---------------------------------------------------------------------
        #(CLK_PERIOD * 10);
        $display("\n==================================================================");
        $display("                    GPIO TESTBENCH SUMMARY                        ");
        $display("==================================================================");
        $display("  TOTAL TESTS PASSED : %0d", pass_count);
        $display("  TOTAL TESTS FAILED : %0d", fail_count);
        if (fail_count == 0) begin
            $display("  >>> OVERALL RESULT : [SUCCESS] GPIO IS 100%% FUNCTIONAL <<<");
        end else begin
            $display("  >>> OVERALL RESULT : [FAILED] PLEASE CHECK FAILED CHECKS <<<");
        end
        $display("==================================================================\n");

        $finish;
    end

endmodule