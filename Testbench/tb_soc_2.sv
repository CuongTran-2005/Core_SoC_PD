`timescale 1ns/1ps

module tb_core_soc_2;

    localparam [31:0] UART_BASE = 32'h0200_0000;
    localparam [31:0] SPI_BASE  = 32'h0300_0000;
    localparam [31:0] GPIO_BASE = 32'h0400_0000;
    localparam [31:0] SRAM_BASE = 32'h0500_0000;

    localparam integer TIMEOUT_CYCLES = 1000;

    reg clk_i = 1'b0;
    reg rst_i = 1'b1;

    reg         inport_awvalid_i = 1'b0;
    reg [31:0]  inport_awaddr_i  = 32'b0;
    reg         inport_wvalid_i  = 1'b0;
    reg [31:0]  inport_wdata_i   = 32'b0;
    reg [3:0]   inport_wstrb_i   = 4'hF;
    reg         inport_bready_i  = 1'b0;
    reg         inport_arvalid_i = 1'b0;
    reg [31:0]  inport_araddr_i  = 32'b0;
    reg         inport_rready_i  = 1'b0;

    reg spi_miso_i = 1'b0;
    reg uart_rx_i  = 1'b1;
    reg [31:0] gpio_input_i = 32'b0;

    // External port 3 is not used by these tests.
    reg ext3_cfg_awready_i = 1'b0;
    reg ext3_cfg_wready_i  = 1'b0;
    reg ext3_cfg_bvalid_i  = 1'b0;
    reg [1:0] ext3_cfg_bresp_i = 2'b00;
    reg ext3_cfg_arready_i = 1'b0;
    reg ext3_cfg_rvalid_i  = 1'b0;
    reg [31:0] ext3_cfg_rdata_i = 32'b0;
    reg [1:0] ext3_cfg_rresp_i = 2'b00;
    reg ext3_irq_i = 1'b0;

    wire intr_o;
    wire inport_awready_o;
    wire inport_wready_o;
    wire inport_bvalid_o;
    wire [1:0] inport_bresp_o;
    wire inport_arready_o;
    wire inport_rvalid_o;
    wire [31:0] inport_rdata_o;
    wire [1:0] inport_rresp_o;
    wire spi_clk_o;
    wire spi_mosi_o;
    wire [7:0] spi_cs_o;
    wire uart_tx_o;
    wire [31:0] gpio_output_o;
    wire [31:0] gpio_output_enable_o;

    integer pass_count = 0;
    integer fail_count = 0;
    integer i;

    always #5 clk_i = ~clk_i;

    core_soc #(
        .CLK_FREQ(50000000),
        .BAUDRATE(1000000),
        .C_SCK_RATIO(50)
    ) dut (
        .clk_i(clk_i),
        .rst_i(rst_i),

        .inport_awvalid_i(inport_awvalid_i),
        .inport_awaddr_i(inport_awaddr_i),
        .inport_wvalid_i(inport_wvalid_i),
        .inport_wdata_i(inport_wdata_i),
        .inport_wstrb_i(inport_wstrb_i),
        .inport_bready_i(inport_bready_i),
        .inport_arvalid_i(inport_arvalid_i),
        .inport_araddr_i(inport_araddr_i),
        .inport_rready_i(inport_rready_i),

        .spi_miso_i(spi_miso_i),
        .uart_rx_i(uart_rx_i),
        .gpio_input_i(gpio_input_i),

        .ext3_cfg_awready_i(ext3_cfg_awready_i),
        .ext3_cfg_wready_i(ext3_cfg_wready_i),
        .ext3_cfg_bvalid_i(ext3_cfg_bvalid_i),
        .ext3_cfg_bresp_i(ext3_cfg_bresp_i),
        .ext3_cfg_arready_i(ext3_cfg_arready_i),
        .ext3_cfg_rvalid_i(ext3_cfg_rvalid_i),
        .ext3_cfg_rdata_i(ext3_cfg_rdata_i),
        .ext3_cfg_rresp_i(ext3_cfg_rresp_i),
        .ext3_irq_i(ext3_irq_i),

        .intr_o(intr_o),
        .inport_awready_o(inport_awready_o),
        .inport_wready_o(inport_wready_o),
        .inport_bvalid_o(inport_bvalid_o),
        .inport_bresp_o(inport_bresp_o),
        .inport_arready_o(inport_arready_o),
        .inport_rvalid_o(inport_rvalid_o),
        .inport_rdata_o(inport_rdata_o),
        .inport_rresp_o(inport_rresp_o),

        .spi_clk_o(spi_clk_o),
        .spi_mosi_o(spi_mosi_o),
        .spi_cs_o(spi_cs_o),
        .uart_tx_o(uart_tx_o),
        .gpio_output_o(gpio_output_o),
        .gpio_output_enable_o(gpio_output_enable_o),

        .ext3_cfg_awvalid_o(),
        .ext3_cfg_awaddr_o(),
        .ext3_cfg_wvalid_o(),
        .ext3_cfg_wdata_o(),
        .ext3_cfg_wstrb_o(),
        .ext3_cfg_bready_o(),
        .ext3_cfg_arvalid_o(),
        .ext3_cfg_araddr_o(),
        .ext3_cfg_rready_o()
    );

    // AXI4-Lite write: AW and W are driven independently and held
    // until their respective READY handshakes complete.
    task automatic axi_write;
        input [31:0] addr;
        input [31:0] data;
        input [3:0]  strb;
        integer aw_done;
        integer w_done;
        integer timeout;
        begin
            aw_done = 0;
            w_done  = 0;
            timeout = 0;

            @(negedge clk_i);
            inport_awaddr_i  = addr;
            inport_awvalid_i = 1'b1;
            inport_wdata_i   = data;
            inport_wstrb_i   = strb;
            inport_wvalid_i  = 1'b1;
            inport_bready_i  = 1'b0;

            while ((!aw_done || !w_done) && timeout < TIMEOUT_CYCLES) begin
                @(posedge clk_i);
                if (inport_awvalid_i && inport_awready_o)
                    aw_done = 1;
                if (inport_wvalid_i && inport_wready_o)
                    w_done = 1;

                @(negedge clk_i);
                if (aw_done) inport_awvalid_i = 1'b0;
                if (w_done)  inport_wvalid_i  = 1'b0;
                timeout = timeout + 1;
            end

            if (!aw_done || !w_done) begin
                $display("[%0d ns] [FAIL] WRITE timeout addr=%08h AW=%0d W=%0d",
                         $time, addr, aw_done, w_done);
                fail_count = fail_count + 1;
                inport_awvalid_i = 1'b0;
                inport_wvalid_i  = 1'b0;
            end
            else begin
                inport_bready_i = 1'b1;
                timeout = 0;
                while (!inport_bvalid_o && timeout < TIMEOUT_CYCLES) begin
                    @(posedge clk_i);
                    timeout = timeout + 1;
                end

                if (!inport_bvalid_o) begin
                    $display("[%0d ns] [FAIL] WRITE response timeout addr=%08h",
                             $time, addr);
                    fail_count = fail_count + 1;
                end
                else begin
                    if (inport_bresp_o == 2'b00) begin
                        $display("[%0d ns] [PASS] WRITE addr=%08h data=%08h BRESP=OKAY",
                                 $time, addr, data);
                        pass_count = pass_count + 1;
                    end
                    else begin
                        $display("[%0d ns] [FAIL] WRITE addr=%08h BRESP=%b",
                                 $time, addr, inport_bresp_o);
                        fail_count = fail_count + 1;
                    end
                    @(posedge clk_i);
                end
                @(negedge clk_i);
                inport_bready_i = 1'b0;
            end
        end
    endtask

    task automatic axi_read;
        input  [31:0] addr;
        output [31:0] data;
        integer timeout;
        reg got_data;
        begin
            data = 32'hxxxx_xxxx;
            got_data = 1'b0;
            timeout = 0;

            @(negedge clk_i);
            inport_araddr_i  = addr;
            inport_arvalid_i = 1'b1;
            inport_rready_i  = 1'b0;

            while (!got_data && timeout < TIMEOUT_CYCLES) begin
                @(posedge clk_i);
                if (inport_arvalid_i && inport_arready_o)
                    got_data = 1'b1;
                @(negedge clk_i);
                if (got_data)
                    inport_arvalid_i = 1'b0;
                timeout = timeout + 1;
            end

            if (!got_data) begin
                $display("[%0d ns] [FAIL] READ address handshake timeout addr=%08h",
                         $time, addr);
                fail_count = fail_count + 1;
                inport_arvalid_i = 1'b0;
            end
            else begin
                inport_rready_i = 1'b1;
                timeout = 0;
                while (!inport_rvalid_o && timeout < TIMEOUT_CYCLES) begin
                    @(posedge clk_i);
                    timeout = timeout + 1;
                end

                if (!inport_rvalid_o) begin
                    $display("[%0d ns] [FAIL] READ response timeout addr=%08h",
                             $time, addr);
                    fail_count = fail_count + 1;
                end
                else begin
                    data = inport_rdata_o;
                    if (inport_rresp_o == 2'b00) begin
                        $display("[%0d ns] [PASS] READ addr=%08h data=%08h RRESP=OKAY",
                                 $time, addr, data);
                        pass_count = pass_count + 1;
                    end
                    else begin
                        $display("[%0d ns] [FAIL] READ addr=%08h RRESP=%b",
                                 $time, addr, inport_rresp_o);
                        fail_count = fail_count + 1;
                    end
                    @(posedge clk_i);
                end
                @(negedge clk_i);
                inport_rready_i = 1'b0;
            end
        end
    endtask

    task automatic check_readback;
        input [31:0] addr;
        input [31:0] expected;
        reg [31:0] actual;
        integer old_fail_count;
        begin
            old_fail_count = fail_count;
            axi_read(addr, actual);
            if (fail_count == old_fail_count) begin
                if (actual === expected) begin
                    $display("[%0d ns] [PASS] READBACK addr=%08h expected=%08h",
                             $time, addr, expected);
                    pass_count = pass_count + 1;
                end
                else begin
                    $display("[%0d ns] [FAIL] READBACK addr=%08h expected=%08h actual=%08h",
                             $time, addr, expected, actual);
                    fail_count = fail_count + 1;
                end
            end
        end
    endtask

    reg [31:0] read_data;

    initial begin
        $display("==================================================");
        $display("[%0d ns] core_soc AXI4-Lite integration test", $time);
        $display("==================================================");

        repeat (10) @(posedge clk_i);
        @(negedge clk_i);
        rst_i = 1'b0;
        repeat (10) @(posedge clk_i);

        // ---------------------------------------------------------
        // TC01: SRAM write/read data integrity.
        // SRAM is connected to outport 5: address[26:24] = 3'b101.
        // ---------------------------------------------------------
        $display("\n[%0d ns] [TC01] SRAM write/read test", $time);
        axi_write(SRAM_BASE + 32'h0000_0000, 32'h1234_5678, 4'hF);
        check_readback(SRAM_BASE + 32'h0000_0000, 32'h1234_5678);

        axi_write(SRAM_BASE + 32'h0000_0004, 32'hA5A5_5A5A, 4'hF);
        check_readback(SRAM_BASE + 32'h0000_0004, 32'hA5A5_5A5A);

        axi_write(SRAM_BASE + 32'h0000_0008, 32'hDEAD_BEEF, 4'hF);
        check_readback(SRAM_BASE + 32'h0000_0008, 32'hDEAD_BEEF);

        // ---------------------------------------------------------
        // TC02: UART access smoke test.
        // Offset 0 is probed for AXI write/read response only.
        // Register meaning/readback depends on uart_lite register map.
        // ---------------------------------------------------------
        $display("\n[%0d ns] [TC02] UART AXI access test", $time);
        axi_write(UART_BASE, 32'h0000_0055, 4'hF);
        axi_read(UART_BASE, read_data);

        // ---------------------------------------------------------
        // TC03: SPI access smoke test.
        // Offset 0 is probed for AXI write/read response only.
        // Register meaning/readback depends on spi_lite register map.
        // ---------------------------------------------------------
        $display("\n[%0d ns] [TC03] SPI AXI access test", $time);
        axi_write(SPI_BASE, 32'h0000_0001, 4'hF);
        axi_read(SPI_BASE, read_data);

        // ---------------------------------------------------------
        // TC04: GPIO access test.
        // Check AXI response and visible GPIO output signals.
        // Exact register offset is dependent on gpio register map.
        // ---------------------------------------------------------
        $display("\n[%0d ns] [TC04] GPIO AXI access test", $time);
        axi_write(GPIO_BASE, 32'hA5A5_5A5A, 4'hF);
        axi_read(GPIO_BASE, read_data);
        $display("[%0d ns] [INFO] GPIO output=%08h output_enable=%08h",
                 $time, gpio_output_o, gpio_output_enable_o);

        repeat (20) @(posedge clk_i);

        $display("\n==================================================");
        $display("[%0d ns] TEST SUMMARY: PASS=%0d FAIL=%0d",
                 $time, pass_count, fail_count);
        $display("==================================================");

        if (fail_count == 0)
            $display("[%0d ns] ALL EXECUTED CHECKS PASSED", $time);
        else
            $display("[%0d ns] SOME CHECKS FAILED - inspect messages above", $time);

        #20;
        $finish;
    end

    initial begin
        #(TIMEOUT_CYCLES * 20 * 10);
        $display("[%0d ns] [FATAL] Global simulation watchdog expired", $time);
        $finish;
    end

endmodule