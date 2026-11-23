module top_soc_top
#(
     parameter CLK_FREQ    = 50000000
    ,parameter BAUDRATE    = 1000000
    ,parameter C_SCK_RATIO = 50
)
(
    // Clock / reset
     input           clk
    ,input           rst

    // Peripherals
    ,input           spi_miso_i
    ,output          spi_clk_o
    ,output          spi_mosi_o
    ,output [  7:0]  spi_cs_o
    ,input           uart_rx_i
    ,output          uart_tx_o
    ,input  [ 31:0]  gpio_input_i
    ,output [ 31:0]  gpio_output_o
    ,output [ 31:0]  gpio_output_enable_o

    // Interrupt
    ,output          intr_o

    // External AXI4-Lite master port (ext3)
    ,input           ext3_cfg_awready_i
    ,input           ext3_cfg_wready_i
    ,input           ext3_cfg_bvalid_i
    ,input  [  1:0]  ext3_cfg_bresp_i
    ,input           ext3_cfg_arready_i
    ,input           ext3_cfg_rvalid_i
    ,input  [ 31:0]  ext3_cfg_rdata_i
    ,input  [  1:0]  ext3_cfg_rresp_i
    ,input           ext3_irq_i
    ,output          ext3_cfg_awvalid_o
    ,output [ 31:0]  ext3_cfg_awaddr_o
    ,output          ext3_cfg_wvalid_o
    ,output [ 31:0]  ext3_cfg_wdata_o
    ,output [  3:0]  ext3_cfg_wstrb_o
    ,output          ext3_cfg_bready_o
    ,output          ext3_cfg_arvalid_o
    ,output [ 31:0]  ext3_cfg_araddr_o
    ,output          ext3_cfg_rready_o
);

    //-------------------------------------------------------------
    // AXI4-Lite wires: RISC_V_WRAPPER (master) <-> core_soc (slave)
    //-------------------------------------------------------------
    wire [31:0] axi_araddr;
    wire        axi_arvalid;
    wire        axi_arready;

    wire [31:0] axi_rdata;
    wire [1:0]  axi_rresp;
    wire        axi_rvalid;
    wire        axi_rready;

    wire [31:0] axi_awaddr;
    wire        axi_awvalid;
    wire        axi_awready;

    wire [31:0] axi_wdata;
    wire [3:0]  axi_wstrb;
    wire        axi_wvalid;
    wire        axi_wready;

    wire [1:0]  axi_bresp;
    wire        axi_bvalid;
    wire        axi_bready;

    //-------------------------------------------------------------
    // RISC-V core wrapper
    //-------------------------------------------------------------
    RISC_V_WRAPPER u_core (
         .clk         (clk)
        ,.rst         (rst)

        ,.axi_araddr  (axi_araddr)
        ,.axi_arvalid (axi_arvalid)
        ,.axi_arready (axi_arready)

        ,.axi_rdata   (axi_rdata)
        ,.axi_rresp   (axi_rresp)
        ,.axi_rvalid  (axi_rvalid)
        ,.axi_rready  (axi_rready)

        ,.axi_awaddr  (axi_awaddr)
        ,.axi_awvalid (axi_awvalid)
        ,.axi_awready (axi_awready)

        ,.axi_wdata   (axi_wdata)
        ,.axi_wstrb   (axi_wstrb)
        ,.axi_wvalid  (axi_wvalid)
        ,.axi_wready  (axi_wready)

        ,.axi_bresp   (axi_bresp)
        ,.axi_bvalid  (axi_bvalid)
        ,.axi_bready  (axi_bready)
    );

    //-------------------------------------------------------------
    // SoC
    //-------------------------------------------------------------
    core_soc
    #(
         .CLK_FREQ    (CLK_FREQ)
        ,.BAUDRATE    (BAUDRATE)
        ,.C_SCK_RATIO (C_SCK_RATIO)
    )
    u_soc (
         .clk_i                (clk)
        ,.rst_i                (rst)

        // inport <- core master
        ,.inport_awvalid_i     (axi_awvalid)
        ,.inport_awaddr_i      (axi_awaddr)
        ,.inport_wvalid_i      (axi_wvalid)
        ,.inport_wdata_i       (axi_wdata)
        ,.inport_wstrb_i       (axi_wstrb)
        ,.inport_bready_i      (axi_bready)
        ,.inport_arvalid_i     (axi_arvalid)
        ,.inport_araddr_i      (axi_araddr)
        ,.inport_rready_i      (axi_rready)

        ,.inport_awready_o     (axi_awready)
        ,.inport_wready_o      (axi_wready)
        ,.inport_bvalid_o      (axi_bvalid)
        ,.inport_bresp_o       (axi_bresp)
        ,.inport_arready_o     (axi_arready)
        ,.inport_rvalid_o      (axi_rvalid)
        ,.inport_rdata_o       (axi_rdata)
        ,.inport_rresp_o       (axi_rresp)

        // Peripherals
        ,.spi_miso_i           (spi_miso_i)
        ,.spi_clk_o            (spi_clk_o)
        ,.spi_mosi_o           (spi_mosi_o)
        ,.spi_cs_o             (spi_cs_o)
        ,.uart_rx_i            (uart_rx_i)
        ,.uart_tx_o            (uart_tx_o)
        ,.gpio_input_i         (gpio_input_i)
        ,.gpio_output_o        (gpio_output_o)
        ,.gpio_output_enable_o (gpio_output_enable_o)

        ,.intr_o               (intr_o)

        // ext3
        ,.ext3_cfg_awready_i   (ext3_cfg_awready_i)
        ,.ext3_cfg_wready_i    (ext3_cfg_wready_i)
        ,.ext3_cfg_bvalid_i    (ext3_cfg_bvalid_i)
        ,.ext3_cfg_bresp_i     (ext3_cfg_bresp_i)
        ,.ext3_cfg_arready_i   (ext3_cfg_arready_i)
        ,.ext3_cfg_rvalid_i    (ext3_cfg_rvalid_i)
        ,.ext3_cfg_rdata_i     (ext3_cfg_rdata_i)
        ,.ext3_cfg_rresp_i     (ext3_cfg_rresp_i)
        ,.ext3_irq_i           (ext3_irq_i)
        ,.ext3_cfg_awvalid_o   (ext3_cfg_awvalid_o)
        ,.ext3_cfg_awaddr_o    (ext3_cfg_awaddr_o)
        ,.ext3_cfg_wvalid_o    (ext3_cfg_wvalid_o)
        ,.ext3_cfg_wdata_o     (ext3_cfg_wdata_o)
        ,.ext3_cfg_wstrb_o     (ext3_cfg_wstrb_o)
        ,.ext3_cfg_bready_o    (ext3_cfg_bready_o)
        ,.ext3_cfg_arvalid_o   (ext3_cfg_arvalid_o)
        ,.ext3_cfg_araddr_o    (ext3_cfg_araddr_o)
        ,.ext3_cfg_rready_o    (ext3_cfg_rready_o)
    );

endmodule