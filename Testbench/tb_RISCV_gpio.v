`timescale 1ns / 1ps

// ==============================================================================
// Testbench: tb_RISCV_gpio
// Muc tieu: Kiem tra tich hop toan he thong RISC-V Core + SoC Peripheral (GPIO)
// - Core fetch tap lenh tu SRAM (IMEM)
// - Core ghi thanh ghi GPIO_DIRECTION va GPIO_OUTPUT
// - Core doc thanh ghi GPIO_INPUT va luu nguoc vao SRAM (DMEM)
// ==============================================================================

module tb_RISCV_gpio;
    parameter CLK_FREQ    = 50000000;
    parameter BAUDRATE    = 1000000;
    parameter C_SCK_RATIO = 50;
    parameter HEX_FILE    = "../Testbench/intruction/gpio_test.hex";
    parameter MAX_CYC     = 5000;

    // Clock 50 MHz (chu ky 20 ns)
    reg clk = 1'b0;
    reg rst = 1'b1;
    always #10 clk = ~clk;

    // Tin hieu ngoai vi
    wire        spi_clk_o, spi_mosi_o, uart_tx_o, intr_o;
    wire [7:0]  spi_cs_o;
    reg  [31:0] gpio_input_i;
    wire [31:0] gpio_output_o, gpio_output_enable_o;

    wire        ext3_cfg_awvalid_o, ext3_cfg_wvalid_o, ext3_cfg_bready_o;
    wire        ext3_cfg_arvalid_o, ext3_cfg_rready_o;
    wire [31:0] ext3_cfg_awaddr_o, ext3_cfg_wdata_o, ext3_cfg_araddr_o;
    wire [3:0]  ext3_cfg_wstrb_o;

    // DUT
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
        .uart_rx_i            (1'b1),
        .uart_tx_o            (uart_tx_o),
        .gpio_input_i         (gpio_input_i),
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

    // Monitor giao dich AXI
    reg [31:0] ar_addr_q;
    always @(posedge clk) if (!rst) begin
        if (dut.axi_arvalid && dut.axi_arready) ar_addr_q <= dut.axi_araddr;
        if (dut.axi_rvalid && dut.axi_rready) begin
            if (ar_addr_q[31:24] == 8'h05 && ar_addr_q[11:2] < 10'd256)
                $display("[%0t] FETCH IMEM: PC=%08h, Inst=%08h", $time, ar_addr_q, dut.axi_rdata);
            else if (ar_addr_q[31:24] == 8'h04)
                $display("[%0t] RD GPIO  : Addr=%08h, Data=%08h", $time, ar_addr_q, dut.axi_rdata);
            else
                $display("[%0t] RD MEM   : Addr=%08h, Data=%08h", $time, ar_addr_q, dut.axi_rdata);
        end

        if (dut.axi_awvalid && dut.axi_awready) begin
            if (dut.axi_awaddr[31:24] == 8'h04)
                $display("[%0t] WR GPIO  : Addr=%08h", $time, dut.axi_awaddr);
            else
                $display("[%0t] WR MEM   : Addr=%08h", $time, dut.axi_awaddr);
        end
        if (dut.axi_wvalid && dut.axi_wready)
            $display("[%0t] WDATA    : Data=%08h, Strb=%b", $time, dut.axi_wdata, dut.axi_wstrb);
    end

    integer cyc;
    integer errors;

    initial begin
        $dumpfile("tb_RISCV_gpio.vcd");
        $dumpvars(0, tb_RISCV_gpio);

        errors = 0;
        // Testbench gia lap chan vao cua GPIO
        gpio_input_i = 32'h1234_5678;

        repeat (10) @(posedge clk);
        rst = 1'b0;
        $display("\n=======================================================");
        $display("[START] Bat dau chay test tong the RISC-V Core + GPIO");
        $display("=======================================================");

        // Doi Core chay den lenh ghi co ket thuc: DMEM[1] (word 257) = 0xCAFEBABE
        cyc = 0;
        while (`SRAM_MEM[257] !== 32'hCAFE_AABE && cyc < MAX_CYC) begin
            @(posedge clk);
            cyc = cyc + 1;
        end
        repeat (10) @(posedge clk);

        $display("\n---------------- KET QUA KIEM TRA ----------------");
        if (cyc >= MAX_CYC) begin
            $display("[FAIL] TIMEOUT: Core chua hoan thanh chuong trinh!");
            errors = errors + 1;
        end else begin
            $display("[INFO] Core hoan thanh chuong trinh sau %0d chu ky.", cyc);
        end

        // 1. Kiem tra huong chan GPIO (Direction)
        if (gpio_output_enable_o === 32'hFFFF_0000) begin
            $display("[PASS] GPIO Direction (Output Enable) = %08h (Dung)", gpio_output_enable_o);
        end else begin
            $display("[FAIL] GPIO Direction sai! Got=%08h, Exp=FFFF0000", gpio_output_enable_o);
            errors = errors + 1;
        end

        // 2. Kiem tra xuat du lieu GPIO (Output)
        if (gpio_output_o === 32'hA5A5_0000) begin
            $display("[PASS] GPIO Output Data               = %08h (Dung)", gpio_output_o);
        end else begin
            $display("[FAIL] GPIO Output Data sai! Got=%08h, Exp=A5A50000", gpio_output_o);
            errors = errors + 1;
        end

        // 3. Kiem tra doc du lieu GPIO Input vao DMEM
        if (`SRAM_MEM[256] === 32'h1234_5678) begin
            $display("[PASS] Core doc dung GPIO Input vao DMEM = %08h (Dung)", `SRAM_MEM[256]);
        end else begin
            $display("[FAIL] DMEM[0] nhan gia tri sai! Got=%08h, Exp=12345678", `SRAM_MEM[256]);
            errors = errors + 1;
        end

        $display("--------------------------------------------------");
        if (errors == 0)
            $display("*** TONG THE TEST GPIO VOI CORE RISC-V: PASSED 100%% ***\n");
        else
            $display("*** TEST FAILED: Co %0d loi! ***\n", errors);

        $finish;
    end

endmodule
