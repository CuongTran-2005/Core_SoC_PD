`timescale 1ns / 1ps

// ==============================================================================
// Testbench: tb_RISCV_uart
// Muc tieu: Kiem tra tich hop toan he thong RISC-V Core + SoC Peripheral (UART)
// - Core fetch tap lenh tu SRAM (IMEM: 0x05000000..0x050003FF)
// - Core ghi thanh ghi ULITE_TX (0x02000004) phat du lieu ra chan uart_tx_o
// - Loopback uart_tx_o -> uart_rx_i: Core doc ULITE_STATUS & ULITE_RX (0x02000000)
//   roi luu ket qua vao SRAM (DMEM: 0x05000400, 0x05000404) de verify
// ==============================================================================

module tb_RISCV_uart;
    parameter CLK_FREQ    = 50000000;
    parameter BAUDRATE    = 1000000;
    parameter C_SCK_RATIO = 50;
    parameter HEX_FILE    = "uart_test.hex";
    parameter MAX_CYC     = 10000;

    localparam integer BIT_CYCLES = CLK_FREQ / BAUDRATE; // 50 chu ky / bit

    // Clock 50 MHz (chu ky 20 ns)
    reg clk = 1'b0;
    reg rst = 1'b1;
    always #10 clk = ~clk;

    // Tin hieu ngoai vi
    wire        spi_clk_o, spi_mosi_o, uart_tx_o, intr_o;
    wire        uart_rx_i;
    wire [7:0]  spi_cs_o;
    wire [31:0] gpio_output_o, gpio_output_enable_o;

    wire        ext3_cfg_awvalid_o, ext3_cfg_wvalid_o, ext3_cfg_bready_o;
    wire        ext3_cfg_arvalid_o, ext3_cfg_rready_o;
    wire [31:0] ext3_cfg_awaddr_o, ext3_cfg_wdata_o, ext3_cfg_araddr_o;
    wire [3:0]  ext3_cfg_wstrb_o;

    // Noi loopback UART: TX quay nguoc lai RX
    assign uart_rx_i = uart_tx_o;

    // DUT: RISCV_core_SoC
    RISCV_core_SoC #(
        .CLK_FREQ    (CLK_FREQ),
        .BAUDRATE    (BAUDRATE),
        .C_SCK_RATIO (C_SCK_RATIO)
    ) dut (
        .clk                  (clk),
        .rst                  (rst),
        .spi_miso_i           (1'b0),
        .spi_clk_o            (spi_clk_o),
        .spi_mosi_o           (spi_mosi_o),
        .spi_cs_o             (spi_cs_o),
        .uart_rx_i            (uart_rx_i),
        .uart_tx_o            (uart_tx_o),
        .gpio_input_i         (32'b0),
        .gpio_output_o        (gpio_output_o),
        .gpio_output_enable_o (gpio_output_enable_o),
        .intr_o               (intr_o),
        .ext3_cfg_awready_i   (1'b0),
        .ext3_cfg_wready_i    (1'b0),
        .ext3_cfg_bvalid_i    (1'b0),
        .ext3_cfg_bresp_i     (2'b0),
        .ext3_cfg_arready_i   (1'b0),
        .ext3_cfg_rvalid_i    (1'b0),
        .ext3_cfg_rdata_i     (32'b0),
        .ext3_cfg_rresp_i     (2'b0),
        .ext3_irq_i           (1'b0),
        .ext3_cfg_awvalid_o   (ext3_cfg_awvalid_o),
        .ext3_cfg_awaddr_o    (ext3_cfg_awaddr_o),
        .ext3_cfg_wvalid_o    (ext3_cfg_wvalid_o),
        .ext3_cfg_wdata_o     (ext3_cfg_wdata_o),
        .ext3_cfg_wstrb_o     (ext3_cfg_wstrb_o),
        .ext3_cfg_bready_o    (ext3_cfg_bready_o),
        .ext3_cfg_arvalid_o   (ext3_cfg_arvalid_o),
        .ext3_cfg_araddr_o    (ext3_cfg_araddr_o),
        .ext3_cfg_rready_o    (ext3_cfg_rready_o)
    );

    // Truy cap bo nho SRAM macro ben trong SoC
    `define SRAM_MEM dut.u_core_soc.u_sram.u_sram.mem

    initial begin
        #1;
        $readmemh(HEX_FILE, `SRAM_MEM);
    end

    // Monitor giao dich AXI giua RISC-V va SoC
    reg [31:0] ar_addr_q;
    always @(posedge clk) if (!rst) begin
        if (dut.axi_arvalid && dut.axi_arready) ar_addr_q <= dut.axi_araddr;
        if (dut.axi_rvalid && dut.axi_rready) begin
            if (ar_addr_q[31:24] == 8'h05 && ar_addr_q[11:2] < 10'd256)
                $display("[%0t] FETCH IMEM: PC=%08h, Inst=%08h", $time, ar_addr_q, dut.axi_rdata);
            else if (ar_addr_q[31:24] == 8'h02)
                $display("[%0t] RD UART  : Addr=%08h, Data=%08h", $time, ar_addr_q, dut.axi_rdata);
            else
                $display("[%0t] RD MEM   : Addr=%08h, Data=%08h", $time, ar_addr_q, dut.axi_rdata);
        end

        if (dut.axi_awvalid && dut.axi_awready) begin
            if (dut.axi_awaddr[31:24] == 8'h02)
                $display("[%0t] WR UART  : Addr=%08h", $time, dut.axi_awaddr);
            else
                $display("[%0t] WR MEM   : Addr=%08h", $time, dut.axi_awaddr);
        end
        if (dut.axi_wvalid && dut.axi_wready)
            $display("[%0t] WDATA    : Data=%08h, Strb=%b", $time, dut.axi_wdata, dut.axi_wstrb);
    end

    // Monitor giai ma khung UART phat ra tren chan uart_tx_o
    integer   bit_idx;
    integer   tx_frame_cnt;
    reg [7:0] tx_mon_byte;
    reg [7:0] tx_captured [0:1];

    initial begin
        tx_frame_cnt   = 0;
        tx_captured[0] = 8'h00;
        tx_captured[1] = 8'h00;

        wait (rst === 1'b0);
        @(posedge clk);

        forever begin
            @(negedge uart_tx_o);
            repeat (BIT_CYCLES / 2) @(posedge clk);
            if (uart_tx_o === 1'b0) begin
                for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
                    repeat (BIT_CYCLES) @(posedge clk);
                    tx_mon_byte[bit_idx] = uart_tx_o;
                end
                repeat (BIT_CYCLES) @(posedge clk);
                if (uart_tx_o === 1'b1) begin
                    $display("[%0t] UART TX PIN: Phat frame #%0d = 0x%02h (Stop bit OK)",
                             $time, tx_frame_cnt + 1, tx_mon_byte);
                    if (tx_frame_cnt < 2)
                        tx_captured[tx_frame_cnt] = tx_mon_byte;
                    tx_frame_cnt = tx_frame_cnt + 1;
                end else begin
                    $display("[%0t] UART TX PIN: Loi Stop bit! Data = 0x%02h", $time, tx_mon_byte);
                end
            end
        end
    end

    integer cyc;
    integer errors;

    initial begin
        $dumpfile("tb_RISCV_uart.vcd");
        $dumpvars(0, tb_RISCV_uart);

        errors = 0;

        repeat (10) @(posedge clk);
        rst = 1'b0;
        $display("\n=======================================================");
        $display("[START] Bat dau chay test tong the RISC-V Core + UART");
        $display("=======================================================");

        // Doi Core chay den lenh ghi co ket thuc: DMEM[2] (word 258) = 0xCAFEBABE
        cyc = 0;
        while (`SRAM_MEM[258] !== 32'hCAFE_BABE && cyc < MAX_CYC) begin
            @(posedge clk);
            cyc = cyc + 1;
        end
        repeat (10) @(posedge clk);

        $display("\n---------------- KET QUA KIEM TRA ----------------");
        if (cyc >= MAX_CYC) begin
            $display("[FAIL] TIMEOUT: Core chua hoan thanh chuong trinh sau %0d chu ky!", MAX_CYC);
            errors = errors + 1;
        end else begin
            $display("[INFO] Core hoan thanh chuong trinh sau %0d chu ky.", cyc);
        end

        // 1. Kiem tra du lieu phat ra tren chan vat ly uart_tx_o
        if (tx_frame_cnt == 2 && tx_captured[0] === 8'h55 && tx_captured[1] === 8'hA5) begin
            $display("[PASS] Chan uart_tx_o phat dung 2 frame  = 0x%02h, 0x%02h",
                     tx_captured[0], tx_captured[1]);
        end else begin
            $display("[FAIL] Chan uart_tx_o sai! Count=%0d, Byte0=%02h (Exp 55), Byte1=%02h (Exp A5)",
                     tx_frame_cnt, tx_captured[0], tx_captured[1]);
            errors = errors + 1;
        end

        // 2. Kiem tra Core doc du lieu UART RX lan 1 vao DMEM[0] (0x05000400)
        if (`SRAM_MEM[256] === 32'h0000_0055) begin
            $display("[PASS] Core doc UART RX lan 1 vao DMEM[0] = %08h (Dung)", `SRAM_MEM[256]);
        end else begin
            $display("[FAIL] DMEM[0] nhan gia tri sai! Got=%08h, Exp=00000055", `SRAM_MEM[256]);
            errors = errors + 1;
        end

        // 3. Kiem tra Core doc du lieu UART RX lan 2 vao DMEM[1] (0x05000404)
        if (`SRAM_MEM[257] === 32'h0000_00A5) begin
            $display("[PASS] Core doc UART RX lan 2 vao DMEM[1] = %08h (Dung)", `SRAM_MEM[257]);
        end else begin
            $display("[FAIL] DMEM[1] nhan gia tri sai! Got=%08h, Exp=000000A5", `SRAM_MEM[257]);
            errors = errors + 1;
        end

        $display("--------------------------------------------------");
        if (errors == 0)
            $display("*** TONG THE TEST UART VOI CORE RISC-V: PASSED 100%% ***\n");
        else
            $display("*** TEST FAILED: Co %0d loi! ***\n", errors);

        $finish;
    end

endmodule