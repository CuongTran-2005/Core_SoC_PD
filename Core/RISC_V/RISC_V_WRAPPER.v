module RISC_V_WRAPPER (
    input  wire        CLOCK_50,
    input  wire [0:0]  KEY,

    // AXI4-Lite Master interface

    // Read Address
    output wire [31:0] axi_araddr,
    output wire        axi_arvalid,
    input  wire        axi_arready,

    // Read Data
    input  wire [31:0] axi_rdata,
    input  wire [1:0]  axi_rresp,
    input  wire        axi_rvalid,
    output wire        axi_rready,

    // Write Address
    output wire [31:0] axi_awaddr,
    output wire        axi_awvalid,
    input  wire        axi_awready,

    // Write Data
    output wire [31:0] axi_wdata,
    output wire [3:0]  axi_wstrb,
    output wire        axi_wvalid,
    input  wire        axi_wready,

    // Write Response
    input  wire [1:0]  axi_bresp,
    input  wire        axi_bvalid,
    output wire        axi_bready
);

    RISC_V u_risc_v (
        .clk          (CLOCK_50),
        .rst          (KEY),

        .axi_araddr   (axi_araddr),
        .axi_arvalid  (axi_arvalid),
        .axi_arready  (axi_arready),

        .axi_rdata    (axi_rdata),
        .axi_rresp    (axi_rresp),
        .axi_rvalid   (axi_rvalid),
        .axi_rready   (axi_rready),

        .axi_awaddr   (axi_awaddr),
        .axi_awvalid  (axi_awvalid),
        .axi_awready  (axi_awready),

        .axi_wdata    (axi_wdata),
        .axi_wstrb    (axi_wstrb),
        .axi_wvalid   (axi_wvalid),
        .axi_wready   (axi_wready),

        .axi_bresp    (axi_bresp),
        .axi_bvalid   (axi_bvalid),
        .axi_bready   (axi_bready)
    );

endmodule
