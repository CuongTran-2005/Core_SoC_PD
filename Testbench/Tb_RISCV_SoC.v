`timescale 1ns / 1ps

// Testbench kiem tra SRAM: nap sram_init.hex, de RISC-V tu fetch/thuc thi,
// roi kiem tra ket qua ghi vao DMEM. Khong test ngoai vi.
module tb_sram;
    parameter CLK_FREQ    = 50000000;
    parameter BAUDRATE    = 1000000;
    parameter C_SCK_RATIO = 50;
    parameter HEX_FILE = "D:/ChuyendeViMach_1/Project_SoC_PD/Testbench/intruction/sram_init.hex";
    parameter MAX_CYC  = 20000;

    // 50 MHz
    reg clk = 1'b0;
    reg rst = 1'b1;
    always #10 clk = ~clk;

    //------------------------------------------------------------
    // DUT (ngoai vi noi muc idle)
    //------------------------------------------------------------
    wire        spi_clk_o, spi_mosi_o, uart_tx_o, intr_o;
    wire [7:0]  spi_cs_o;
    wire [31:0] gpio_output_o, gpio_output_enable_o;

    wire        ext3_cfg_awvalid_o, ext3_cfg_wvalid_o, ext3_cfg_bready_o;
    wire        ext3_cfg_arvalid_o, ext3_cfg_rready_o;
    wire [31:0] ext3_cfg_awaddr_o, ext3_cfg_wdata_o, ext3_cfg_araddr_o;
    wire [3:0]  ext3_cfg_wstrb_o;

    RISCV_core_SoC
    #(
         .CLK_FREQ    (CLK_FREQ)
        ,.BAUDRATE    (BAUDRATE)
        ,.C_SCK_RATIO (C_SCK_RATIO)
    ) dut (
        .clk                  (clk),
        .rst                  (rst),
        .spi_miso_i           (1'b0),
        .spi_clk_o            (spi_clk_o),
        .spi_mosi_o           (spi_mosi_o),
        .spi_cs_o             (spi_cs_o),
        .uart_rx_i            (1'b1),
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

    // Mang nho ben trong SRAM macro
    `define SRAM_MEM dut.u_core_soc.u_sram.u_sram.mem

    //------------------------------------------------------------
    // Nap chuong trinh vao SRAM khi con reset
    // (tre 1 ns de khong dua nhau voi initial cua macro luc t=0)
    //------------------------------------------------------------
    initial begin
        #1;
        $readmemh(HEX_FILE, `SRAM_MEM);
    end

    //------------------------------------------------------------
    // Monitor giao dich AXI giua RISC-V va SoC (RD IMEM = fetch lenh,
    // word index < 256; RD/AW/W con lai la truy cap DMEM)
    //------------------------------------------------------------
    reg [31:0] ar_addr_q;
    always @(posedge clk) if (!rst) begin
        if (dut.axi_arvalid && dut.axi_arready) ar_addr_q <= dut.axi_araddr;
        if (dut.axi_rvalid && dut.axi_rready && ar_addr_q[11:2] < 10'd256)
            $display("[%0t] RD IMEM  addr=%08h data=%08h", $time, ar_addr_q, dut.axi_rdata);
        if (dut.axi_rvalid && dut.axi_rready && ar_addr_q[11:2] >= 10'd256)
            $display("[%0t] RD addr=%08h data=%08h", $time, ar_addr_q, dut.axi_rdata);

        if (dut.axi_awvalid && dut.axi_awready)
            $display("[%0t] AW  addr=%08h", $time, dut.axi_awaddr);
        if (dut.axi_wvalid && dut.axi_wready)
            $display("[%0t] W   data=%08h strb=%b", $time, dut.axi_wdata, dut.axi_wstrb);
    end

    //------------------------------------------------------------
    // Dieu khien mo phong + kiem tra
    //------------------------------------------------------------
    integer cyc;
    integer errors;

    task check;
        input integer widx;
        input [31:0]  expected;
        begin
            if (`SRAM_MEM[widx] !== expected) begin
                $display("FAIL: mem[%0d] (byte 0x%03h) = %h, expected %h",
                         widx, widx*4, `SRAM_MEM[widx], expected);
                errors = errors + 1;
            end else
                $display("OK  : mem[%0d] (byte 0x%03h) = %h", widx, widx*4, expected);
        end
    endtask

    initial begin
        $dumpfile("tb_sram.vcd");
        $dumpvars(0, tb_sram);

        errors = 0;
        repeat (10) @(posedge clk);
        rst = 1'b0;

        // Cho chuong trinh ghi xong ket qua cuoi cung (DMEM[3] = word 259 = 8)
        cyc = 0;
        while (`SRAM_MEM[259] !== 32'd8 && cyc < MAX_CYC) begin
            @(posedge clk);
            cyc = cyc + 1;
        end
        repeat (10) @(posedge clk);

        if (cyc >= MAX_CYC)
            $display("TIMEOUT: chuong trinh chua ghi xong sau %0d chu ky", MAX_CYC);

        $display("---- Kiem tra DMEM ----");
        check(256, 32'd15);   // 0x400
        check(257, 32'd7);    // 0x404
        check(258, 32'd22);   // 0x408 = 15 + 7
        check(259, 32'd8);    // 0x40C = 15 - 7

        if (errors == 0 && cyc < MAX_CYC) $display("*** PASS ***");
        else                              $display("*** FAIL: %0d loi ***", errors);
        $finish;
    end

endmodule