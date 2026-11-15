//-----------------------------------------------------------------
// AXI4-Lite slave wrapper cho accelerator_top (4x4 systolic, C = A x B)
//
// Register map (offset trong cua so cua slave, 32-bit word):
//   0x00 CTRL    W   [0] START (xung 1 chu ky, bo qua neu dang busy)
//                    [1] CLEAR (xung 1 chu ky, xoa accumulator)
//                    Ghi 0x3 = clear + start
//   0x04 STATUS  R   [0] BUSY, [1] DONE (DONE giu den lan START ke tiep)
//   0x10..0x1C   A   RW  word r = hang r cua A, byte k = A[r][k]
//   0x20..0x2C   B   RW  word k = hang k cua B, byte j = B[k][j]
//   0x40..0x7C   C   R   C[r][c] tai 0x40 + r*0x10 + c*4, sign-extend 20->32
//
// Accelerator can du lieu nap theo tung chu ky va da skew
// (hang i tre i chu ky, cot j tre j chu ky) -> wrapper tu skew:
//   a_row_i (t) = A[i][t-i],  b_col_j (t) = B[t-j][j],  ngoai khoang 0..3 -> 0
//
// Reset: rst_i active-high async (giong axi4lite_dist); noi bo dao thanh rst_n.
//-----------------------------------------------------------------
module axi4lite_accel_wrapper
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

//-----------------------------------------------------------------
// AXI write: chot AW va W rieng, du ca hai thi thuc hien 1 chu ky, roi B
//-----------------------------------------------------------------
reg        aw_q, w_q, bvalid_q;
reg [7:0]  waddr_q;
reg [31:0] wdata_q;
reg [3:0]  wstrb_q;

wire do_wr_w = aw_q && w_q;

assign awready_o = !aw_q && !bvalid_q;
assign wready_o  = !w_q  && !bvalid_q;

wire aw_hs_w = awvalid_i && awready_o;
wire w_hs_w  = wvalid_i  && wready_o;

always @ (posedge clk_i or posedge rst_i)
if (rst_i)
begin
    aw_q     <= 1'b0;
    w_q      <= 1'b0;
    bvalid_q <= 1'b0;
    waddr_q  <= 8'b0;
    wdata_q  <= 32'b0;
    wstrb_q  <= 4'b0;
end
else
begin
    if (aw_hs_w) begin aw_q <= 1'b1; waddr_q <= awaddr_i[7:0]; end
    if (w_hs_w)  begin w_q  <= 1'b1; wdata_q <= wdata_i; wstrb_q <= wstrb_i; end

    if (do_wr_w)
    begin
        aw_q     <= 1'b0;
        w_q      <= 1'b0;
        bvalid_q <= 1'b1;
    end
    else if (bvalid_q && bready_i)
        bvalid_q <= 1'b0;
end

assign bvalid_o = bvalid_q;
assign bresp_o  = 2'b00;

//-----------------------------------------------------------------
// Ghi thanh ghi
//-----------------------------------------------------------------
wire wr_ctrl_w = do_wr_w && (waddr_q[7:2] == 6'h00) && wstrb_q[0];
wire wr_a_w    = do_wr_w && (waddr_q[7:4] == 4'h1);
wire wr_b_w    = do_wr_w && (waddr_q[7:4] == 4'h2);

wire busy_w, done_w;
wire start_w = wr_ctrl_w && wdata_q[0] && !busy_w;
wire clear_w = wr_ctrl_w && wdata_q[1];

// Row-major, word r = [32*r +: 32], byte k = [32*r + 8*k +: 8]
reg [127:0] a_q, b_q;
integer k;

always @ (posedge clk_i)
    for (k = 0; k < 4; k = k + 1)
        if (wstrb_q[k])
        begin
            if (wr_a_w) a_q[{waddr_q[3:2], 5'd0} + 8*k +: 8] <= wdata_q[8*k +: 8];
            if (wr_b_w) b_q[{waddr_q[3:2], 5'd0} + 8*k +: 8] <= wdata_q[8*k +: 8];
        end

//-----------------------------------------------------------------
// Bo nap du lieu co skew
// cnt_q = 0 o chu ky busy dau tien (busy len 1 chu ky sau start)
//-----------------------------------------------------------------
reg [3:0] cnt_q;

always @ (posedge clk_i or posedge rst_i)
if (rst_i)
    cnt_q <= 4'd0;
else
    cnt_q <= busy_w ? cnt_q + 4'd1 : 4'd0;

// Khi khong busy ep t=15: (15 - i) >= 12 > 3 -> moi chi so ngoai khoang -> du lieu = 0
wire [3:0] t_w = busy_w ? cnt_q : 4'd15;

// m[row][col] (row/col 4-bit, >3 -> 0)
function [7:0] pick;
    input [127:0] m;
    input [3:0]   row;
    input [3:0]   col;
begin
    pick = (row > 4'd3 || col > 4'd3) ? 8'd0 : m[{row[1:0], col[1:0], 3'b000} +: 8];
end
endfunction

wire [7:0] a_row0_w = pick(a_q, 4'd0, t_w - 4'd0);
wire [7:0] a_row1_w = pick(a_q, 4'd1, t_w - 4'd1);
wire [7:0] a_row2_w = pick(a_q, 4'd2, t_w - 4'd2);
wire [7:0] a_row3_w = pick(a_q, 4'd3, t_w - 4'd3);

wire [7:0] b_col0_w = pick(b_q, t_w - 4'd0, 4'd0);
wire [7:0] b_col1_w = pick(b_q, t_w - 4'd1, 4'd1);
wire [7:0] b_col2_w = pick(b_q, t_w - 4'd2, 4'd2);
wire [7:0] b_col3_w = pick(b_q, t_w - 4'd3, 4'd3);

//-----------------------------------------------------------------
// AXI read: 1 outstanding, rdata la to hop tu raddr_q (on dinh khi giu rvalid)
//-----------------------------------------------------------------
reg        rvalid_q;
reg [7:0]  raddr_q;

assign arready_o = !rvalid_q;

wire ar_hs_w = arvalid_i && arready_o;

always @ (posedge clk_i or posedge rst_i)
if (rst_i)
begin
    rvalid_q <= 1'b0;
    raddr_q  <= 8'b0;
end
else
begin
    if (ar_hs_w)
    begin
        rvalid_q <= 1'b1;
        raddr_q  <= araddr_i[7:0];
    end
    else if (rvalid_q && rready_i)
        rvalid_q <= 1'b0;
end

// Chon hang ket qua theo dia chi doc (one-hot cho row_sel)
wire [3:0] row_sel_w = 4'b0001 << raddr_q[5:4];

wire signed [19:0] res0_w, res1_w, res2_w, res3_w;
reg  signed [19:0] res_sel_r;

always @ *
begin
    case (raddr_q[3:2])
    2'd0:    res_sel_r = res0_w;
    2'd1:    res_sel_r = res1_w;
    2'd2:    res_sel_r = res2_w;
    default: res_sel_r = res3_w;
    endcase
end

reg [31:0] rdata_r;

always @ *
begin
    case (raddr_q[7:4])
    4'h0:    rdata_r = (raddr_q[3:2] == 2'd1) ? {30'd0, done_w, busy_w} : 32'd0;
    4'h1:    rdata_r = a_q[{raddr_q[3:2], 5'd0} +: 32];
    4'h2:    rdata_r = b_q[{raddr_q[3:2], 5'd0} +: 32];
    default: rdata_r = (raddr_q[7:6] == 2'b01) ? {{12{res_sel_r[19]}}, res_sel_r} : 32'd0;
    endcase
end

assign rvalid_o = rvalid_q;
assign rdata_o  = rdata_r;
assign rresp_o  = 2'b00;

//-----------------------------------------------------------------
// Accelerator
//-----------------------------------------------------------------
accelerator_top u_acc
(
     .clk      (clk_i)
    ,.rst_n    (~rst_i)
    ,.start    (start_w)
    ,.clear    (clear_w)
    ,.row_sel  (row_sel_w)
    ,.a_row0   (a_row0_w)
    ,.a_row1   (a_row1_w)
    ,.a_row2   (a_row2_w)
    ,.a_row3   (a_row3_w)
    ,.b_col0   (b_col0_w)
    ,.b_col1   (b_col1_w)
    ,.b_col2   (b_col2_w)
    ,.b_col3   (b_col3_w)
    ,.res_out0 (res0_w)
    ,.res_out1 (res1_w)
    ,.res_out2 (res2_w)
    ,.res_out3 (res3_w)
    ,.busy     (busy_w)
    ,.done     (done_w)
);

endmodule
