module Arbiter (
    input  wire        clk,
    input  wire        rst,

    //==================================================
    // IMEM interface
    //==================================================
    input  wire        imem_req,
    input  wire [9:0]  imem_addr,
    output wire [31:0] imem_rdata,
    output wire        imem_ready,

    //==================================================
    // DMEM interface
    //==================================================
    input  wire        dmem_req,
    input  wire        dmem_busy,
    input  wire [31:0] dmem_addr,
    input  wire        dmem_we,
    input  wire [31:0] dmem_wdata,

    output wire [31:0] dmem_rdata,
    output wire        dmem_ready,

    //==================================================
    // AXI4-Lite Master: Read Address (AR)
    //==================================================
    output wire [31:0] axi_araddr,
    output wire        axi_arvalid,
    input  wire        axi_arready,

    //==================================================
    // AXI4-Lite Master: Read Data (R)
    //==================================================
    input  wire [31:0] axi_rdata,
    input  wire [1:0]  axi_rresp,
    input  wire        axi_rvalid,
    output wire        axi_rready,

    //==================================================
    // AXI4-Lite Master: Write Address (AW)
    //==================================================
    output wire [31:0] axi_awaddr,
    output wire        axi_awvalid,
    input  wire        axi_awready,

    //==================================================
    // AXI4-Lite Master: Write Data (W)
    //==================================================
    output wire [31:0] axi_wdata,
    output wire [3:0]  axi_wstrb,
    output wire        axi_wvalid,
    input  wire        axi_wready,

    //==================================================
    // AXI4-Lite Master: Write Response (B)
    //==================================================
    input  wire [1:0]  axi_bresp,
    input  wire        axi_bvalid,
    output wire        axi_bready
);

    //==================================================
    // Owner encoding
    //==================================================
    localparam OWNER_NONE = 2'b00;
    localparam OWNER_IMEM = 2'b01;
    localparam OWNER_DMEM = 2'b10;

    reg [1:0] grant_owner;

    //==================================================
    // Transaction tracking
    //==================================================
    reg [1:0] resp_owner;

    reg dmem_waiting;

    // Latch transaction information
    reg [31:0] addr_q;
    reg [31:0] wdata_q;

    // Independent AXI write channel tracking
    reg aw_done;
    reg w_done;

    //==================================================
    // FSM
    //==================================================
    localparam IDLE    = 3'd0;
    localparam RD_ADDR = 3'd1;
    localparam RD_DATA = 3'd2;
    localparam WR_ADDR = 3'd3;
    localparam WR_RESP = 3'd4;

    reg [2:0] state;

    //==================================================
    // Arbitration logic
    // Giữ nguyên nguyên tắc ưu tiên của bạn
    //==================================================
    always @(*) begin
        grant_owner = OWNER_NONE;

        if (dmem_busy) begin
            if (dmem_req && !dmem_waiting)
                grant_owner = OWNER_DMEM;
        end
        else begin
            if (imem_req)
                grant_owner = OWNER_IMEM;
        end
    end

    //==================================================
    // AXI4-Lite output assignments
    //==================================================

    // Read Address Channel
    assign axi_araddr  = addr_q;
    assign axi_arvalid = (state == RD_ADDR);

    // Read Data Channel
    assign axi_rready  = (state == RD_DATA);

    // Write Address Channel
    assign axi_awaddr  = addr_q;
    assign axi_awvalid = (state == WR_ADDR) && !aw_done;

    // Write Data Channel
    assign axi_wdata  = wdata_q;
    assign axi_wstrb  = 4'b1111;
    assign axi_wvalid = (state == WR_ADDR) && !w_done;

    // Write Response Channel
    assign axi_bready = (state == WR_RESP);

    //==================================================
    // Response routing
    //==================================================

    assign imem_rdata = axi_rdata;
    assign dmem_rdata = axi_rdata;

    // IMEM only performs read
    assign imem_ready = (state == RD_DATA) && axi_rvalid && axi_rready && (resp_owner == OWNER_IMEM);

    // DMEM can perform read or write
    assign dmem_ready = ((state == RD_DATA) && axi_rvalid && axi_rready && (resp_owner == OWNER_DMEM)) || 
								((state == WR_RESP) && axi_bvalid && axi_bready && (resp_owner == OWNER_DMEM));

    //==================================================
    // Main FSM
    //==================================================
    always @(posedge clk or posedge rst) begin

        if (rst) begin
            state        <= IDLE;
            resp_owner   <= OWNER_NONE;

            addr_q       <= 32'b0;
            wdata_q      <= 32'b0;

            aw_done      <= 1'b0;
            w_done       <= 1'b0;

            dmem_waiting <= 1'b0;
        end
        else begin

            case (state)

                //======================================
                // IDLE: Arbitration
                //======================================
                IDLE: begin

                    resp_owner <= OWNER_NONE;

                    aw_done <= 1'b0;
                    w_done  <= 1'b0;

                    // DMEM has priority
                    if (grant_owner == OWNER_DMEM) begin

                        resp_owner <= OWNER_DMEM;

                        // Preserve the original SRAM word mapping
                        addr_q  <= {20'b0, dmem_addr[11:2], 2'b00};
                        wdata_q <= dmem_wdata;

                        dmem_waiting <= 1'b1;

                        if (dmem_we)
                            state <= WR_ADDR;
                        else
                            state <= RD_ADDR;

                    end

                    // IMEM request
                    else if (grant_owner == OWNER_IMEM) begin

                        resp_owner <= OWNER_IMEM;

                        // IMEM address is word address
                        addr_q <= {20'b0, imem_addr, 2'b00};

                        state <= RD_ADDR;

                    end
                end

                //======================================
                // RD_ADDR: AR handshake
                //======================================
                RD_ADDR: begin

                    if (axi_arvalid && axi_arready) begin
                        state <= RD_DATA;
                    end

                end

                //======================================
                // RD_DATA: R handshake
                //======================================
                RD_DATA: begin

                    if (axi_rvalid && axi_rready) begin

                        state <= IDLE;

                        if (resp_owner == OWNER_DMEM)
                            dmem_waiting <= 1'b0;

                        resp_owner <= OWNER_NONE;

                    end

                end

                //======================================
                // WR_ADDR: AW and W handshakes
                //======================================
                WR_ADDR: begin

                    if (axi_awvalid && axi_awready)
                        aw_done <= 1'b1;

                    if (axi_wvalid && axi_wready)
                        w_done <= 1'b1;

                    // Wait until both channels complete
                    if (
                        (aw_done || (axi_awvalid && axi_awready)) &&
                        (w_done  || (axi_wvalid  && axi_wready))
                    ) begin
                        state <= WR_RESP;
                    end

                end

                //======================================
                // WR_RESP: B handshake
                //======================================
                WR_RESP: begin

                    if (axi_bvalid && axi_bready) begin

                        state <= IDLE;

                        dmem_waiting <= 1'b0;
                        resp_owner   <= OWNER_NONE;

                        aw_done <= 1'b0;
                        w_done  <= 1'b0;

                    end

                end

                default: begin
                    state      <= IDLE;
                    resp_owner <= OWNER_NONE;
                end

            endcase
        end
    end

endmodule
