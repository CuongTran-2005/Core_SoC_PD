//-----------------------------------------------------------------
// AXI4-Lite slave wrapper cho sram_2k_macro (1024 x 32, single port)
//
//  - Dia chi   : addr[11:2] -> A[9:0]  (cua so 4 KB)
//  - WSTRB     : full word (4'hF)  -> ghi 1 chu ky
//                partial (sb/sh)   -> read-modify-write (macro khong co byte enable)
//  - Response  : luon OKAY
//  - Reset     : rst_i active-high, async (giong axi4lite_dist)
//  - Moi lenh vao macro deu lay tu thanh ghi -> CEN/WEN/A/D on dinh cho macro
//-----------------------------------------------------------------
module axi4lite_sram_wrapper
#(
    parameter INIT_FILE = ""
)
(
     input           clk_i
    ,input           rst_i

    // AXI4-Lite slave: noi vao outportN cua axi4lite_dist
    ,input           awvalid_i
    ,input  [ 31:0]  awaddr_i
    ,input           wvalid_i
    ,input  [ 31:0]  wdata_i
    ,input  [  3:0]  wstrb_i
    ,input           bready_i
    ,input           arvalid_i
    ,input  [ 31:0]  araddr_i
    ,input           rready_i
    ,output          awready_o
    ,output          wready_o
    ,output          bvalid_o
    ,output [  1:0]  bresp_o
    ,output          arready_o
    ,output          rvalid_o
    ,output [ 31:0]  rdata_o
    ,output [  1:0]  rresp_o
);

localparam S_IDLE = 3'd0;
localparam S_RD   = 3'd1;   // truy cap doc macro (cung la pha doc cua RMW)
localparam S_WR   = 3'd2;   // truy cap ghi macro
localparam S_RRSP = 3'd3;   // giu rvalid
localparam S_BRSP = 3'd4;   // giu bvalid

reg [2:0]  state_q;
reg        aw_q;            // da nhan AW
reg        w_q;             // da nhan W
reg        wr_q;            // lenh dang xu ly la ghi
reg [9:0]  addr_q;
reg [31:0] wdata_q;
reg [3:0]  wstrb_q;

wire idle_w = (state_q == S_IDLE);

// Chi nhan lenh o IDLE. Doc bi chan khi co ghi dang cho / dang den
// (dung chung addr_q, va macro chi co 1 cong)
assign awready_o = idle_w && !aw_q;
assign wready_o  = idle_w && !w_q;
assign arready_o = idle_w && !aw_q && !w_q && !awvalid_i;

wire aw_hs_w = awvalid_i && awready_o;
wire w_hs_w  = wvalid_i  && wready_o;
wire ar_hs_w = arvalid_i && arready_o;

always @ (posedge clk_i or posedge rst_i)
if (rst_i)
begin
    state_q <= S_IDLE;
    aw_q    <= 1'b0;
    w_q     <= 1'b0;
    wr_q    <= 1'b0;
    addr_q  <= 10'b0;
    wdata_q <= 32'b0;
    wstrb_q <= 4'b0;
end
else
begin
    if (aw_hs_w)
    begin
        aw_q   <= 1'b1;
        addr_q <= awaddr_i[11:2];
    end
    if (w_hs_w)
    begin
        w_q     <= 1'b1;
        wdata_q <= wdata_i;
        wstrb_q <= wstrb_i;
    end

    case (state_q)
    S_IDLE:
    begin
        if (aw_q && w_q)                    // da co du AW + W
        begin
            aw_q    <= 1'b0;
            w_q     <= 1'b0;
            wr_q    <= 1'b1;
            state_q <= (wstrb_q == 4'hF) ? S_WR : S_RD;
        end
        else if (ar_hs_w)
        begin
            addr_q  <= araddr_i[11:2];
            wr_q    <= 1'b0;
            state_q <= S_RD;
        end
    end
    S_RD:   state_q <= wr_q ? S_WR : S_RRSP;
    S_WR:   state_q <= S_BRSP;
    S_RRSP: if (rready_i) state_q <= S_IDLE;
    S_BRSP: if (bready_i) state_q <= S_IDLE;
    default: state_q <= S_IDLE;
    endcase
end

//-----------------------------------------------------------------
// SRAM macro
//-----------------------------------------------------------------
wire        rd_acc_w = (state_q == S_RD);
wire        wr_acc_w = (state_q == S_WR);
wire [31:0] q_w;
wire [31:0] mask_w   = {{8{wstrb_q[3]}}, {8{wstrb_q[2]}}, {8{wstrb_q[1]}}, {8{wstrb_q[0]}}};

sram_2k_macro #(.INIT_FILE(INIT_FILE)) u_sram
(
     .CLK (clk_i)
    ,.CEN (~(rd_acc_w | wr_acc_w))
    ,.WEN (~wr_acc_w)
    ,.A   (addr_q)
    ,.D   ((wdata_q & mask_w) | (q_w & ~mask_w))   // merge byte; full strobe -> = wdata_q
    ,.Q   (q_w)
);

//-----------------------------------------------------------------
// Response
//-----------------------------------------------------------------
assign rvalid_o = (state_q == S_RRSP);
assign rdata_o  = q_w;                  // Q giu nguyen khi CEN=1
assign rresp_o  = 2'b00;
assign bvalid_o = (state_q == S_BRSP);
assign bresp_o  = 2'b00;

endmodule
