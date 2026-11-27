module RISCV_core_SoC
#(
     parameter CLK_FREQ    = 50000000
    ,parameter BAUDRATE    = 1000000
    ,parameter C_SCK_RATIO = 50
    ,parameter INIT_FILE   = "D:/ChuyendeViMach_1/Project_SoC_PD/Testbench/instruction/sram_init.hex"
)
(
    input  wire        clk,
    input  wire        rst,

    // SPI
    input  wire        spi_miso_i,
    output wire        spi_clk_o,
    output wire        spi_mosi_o,
    output wire [7:0]  spi_cs_o,

    // UART
    input  wire        uart_rx_i,
    output wire        uart_tx_o,

    // GPIO
    input  wire [31:0] gpio_input_i,
    output wire [31:0] gpio_output_o,
    output wire [31:0] gpio_output_enable_o,

    // Interrupt
    output wire        intr_o,

    // External peripheral 3 (AXI4-Lite master ra ngoài)
    input  wire        ext3_cfg_awready_i,
    input  wire        ext3_cfg_wready_i,
    input  wire        ext3_cfg_bvalid_i,
    input  wire [1:0]  ext3_cfg_bresp_i,
    input  wire        ext3_cfg_arready_i,
    input  wire        ext3_cfg_rvalid_i,
    input  wire [31:0] ext3_cfg_rdata_i,
    input  wire [1:0]  ext3_cfg_rresp_i,
    input  wire        ext3_irq_i,

    output wire        ext3_cfg_awvalid_o,
    output wire [31:0] ext3_cfg_awaddr_o,
    output wire        ext3_cfg_wvalid_o,
    output wire [31:0] ext3_cfg_wdata_o,
    output wire [3:0]  ext3_cfg_wstrb_o,
    output wire        ext3_cfg_bready_o,
    output wire        ext3_cfg_arvalid_o,
    output wire [31:0] ext3_cfg_araddr_o,
    output wire        ext3_cfg_rready_o
);

    //------------------------------------------------------------
    // AXI4-Lite bus giữa RISC_V (master) và core_soc (slave)
    //------------------------------------------------------------
    // Read address
    wire [31:0] axi_araddr;
    wire        axi_arvalid;
    wire        axi_arready;
    // Read data
    wire [31:0] axi_rdata;
    wire [1:0]  axi_rresp;
    wire        axi_rvalid;
    wire        axi_rready;
    // Write address
    wire [31:0] axi_awaddr;
    wire        axi_awvalid;
    wire        axi_awready;
    // Write data
    wire [31:0] axi_wdata;
    wire [3:0]  axi_wstrb;
    wire        axi_wvalid;
    wire        axi_wready;
    // Write response
    wire [1:0]  axi_bresp;
    wire        axi_bvalid;
    wire        axi_bready;

    //------------------------------------------------------------
    // RISC-V core wrapper
    //------------------------------------------------------------
    RISC_V u_riscv (
        .clk         (clk),
        .rst         (rst),

        .axi_araddr  (axi_araddr),
        .axi_arvalid (axi_arvalid),
        .axi_arready (axi_arready),

        .axi_rdata   (axi_rdata),
        .axi_rresp   (axi_rresp),
        .axi_rvalid  (axi_rvalid),
        .axi_rready  (axi_rready),

        .axi_awaddr  (axi_awaddr),
        .axi_awvalid (axi_awvalid),
        .axi_awready (axi_awready),

        .axi_wdata   (axi_wdata),
        .axi_wstrb   (axi_wstrb),
        .axi_wvalid  (axi_wvalid),
        .axi_wready  (axi_wready),

        .axi_bresp   (axi_bresp),
        .axi_bvalid  (axi_bvalid),
        .axi_bready  (axi_bready)
    );

    //------------------------------------------------------------
    // SoC system
    //------------------------------------------------------------
    core_soc #(
         .CLK_FREQ    (CLK_FREQ)
        ,.BAUDRATE    (BAUDRATE)
        ,.C_SCK_RATIO (C_SCK_RATIO)
        ,.INIT_FILE   (INIT_FILE)
    ) u_core_soc (
        .clk_i                  (clk),
        .rst_i                  (rst),

        // AXI4-Lite slave (từ RISC_V)
        .inport_awvalid_i       (axi_awvalid),
        .inport_awaddr_i        (axi_awaddr),
        .inport_awready_o       (axi_awready),
        .inport_wvalid_i        (axi_wvalid),
        .inport_wdata_i         (axi_wdata),
        .inport_wstrb_i         (axi_wstrb),
        .inport_wready_o        (axi_wready),
        .inport_bvalid_o        (axi_bvalid),
        .inport_bresp_o         (axi_bresp),
        .inport_bready_i        (axi_bready),
        .inport_arvalid_i       (axi_arvalid),
        .inport_araddr_i        (axi_araddr),
        .inport_arready_o       (axi_arready),
        .inport_rvalid_o        (axi_rvalid),
        .inport_rdata_o         (axi_rdata),
        .inport_rresp_o         (axi_rresp),
        .inport_rready_i        (axi_rready),

        // Ngoại vi
        .spi_miso_i             (spi_miso_i),
        .spi_clk_o              (spi_clk_o),
        .spi_mosi_o             (spi_mosi_o),
        .spi_cs_o               (spi_cs_o),
        .uart_rx_i              (uart_rx_i),
        .uart_tx_o              (uart_tx_o),
        .gpio_input_i           (gpio_input_i),
        .gpio_output_o          (gpio_output_o),
        .gpio_output_enable_o   (gpio_output_enable_o),

        // Interrupt
        .intr_o                 (intr_o),

        // External peripheral 3
        .ext3_cfg_awready_i     (ext3_cfg_awready_i),
        .ext3_cfg_wready_i      (ext3_cfg_wready_i),
        .ext3_cfg_bvalid_i      (ext3_cfg_bvalid_i),
        .ext3_cfg_bresp_i       (ext3_cfg_bresp_i),
        .ext3_cfg_arready_i     (ext3_cfg_arready_i),
        .ext3_cfg_rvalid_i      (ext3_cfg_rvalid_i),
        .ext3_cfg_rdata_i       (ext3_cfg_rdata_i),
        .ext3_cfg_rresp_i       (ext3_cfg_rresp_i),
        .ext3_irq_i             (ext3_irq_i),
        .ext3_cfg_awvalid_o     (ext3_cfg_awvalid_o),
        .ext3_cfg_awaddr_o      (ext3_cfg_awaddr_o),
        .ext3_cfg_wvalid_o      (ext3_cfg_wvalid_o),
        .ext3_cfg_wdata_o       (ext3_cfg_wdata_o),
        .ext3_cfg_wstrb_o       (ext3_cfg_wstrb_o),
        .ext3_cfg_bready_o      (ext3_cfg_bready_o),
        .ext3_cfg_arvalid_o     (ext3_cfg_arvalid_o),
        .ext3_cfg_araddr_o      (ext3_cfg_araddr_o),
        .ext3_cfg_rready_o      (ext3_cfg_rready_o)
    );

endmodule