`timescale 1ns / 1ps
// Testbench: master -> axi4lite_dist -> {outport0: SRAM, outport1: accelerator}
module tb_axi_wrappers;

localparam SRAM_BASE = 32'h0000_0000;   // outport0 (addr[26:24] = 0)
localparam ACC_BASE  = 32'h0100_0000;   // outport1 (addr[26:24] = 1)

reg clk = 0, rst = 1;
always #10 clk = ~clk;                  // 50 MHz

// master side
reg         m_awvalid = 0, m_wvalid = 0, m_bready = 0, m_arvalid = 0, m_rready = 0;
reg  [31:0] m_awaddr = 0, m_wdata = 0, m_araddr = 0;
reg  [3:0]  m_wstrb = 0;
wire        m_awready, m_wready, m_bvalid, m_arready, m_rvalid;
wire [1:0]  m_bresp, m_rresp;
wire [31:0] m_rdata;

// slave 0 / 1 nets
wire s0_awready, s0_wready, s0_bvalid, s0_arready, s0_rvalid;
wire [1:0] s0_bresp, s0_rresp; wire [31:0] s0_rdata;
wire s0_awvalid, s0_wvalid, s0_bready, s0_arvalid, s0_rready;
wire [31:0] s0_awaddr, s0_wdata, s0_araddr; wire [3:0] s0_wstrb;

wire s1_awready, s1_wready, s1_bvalid, s1_arready, s1_rvalid;
wire [1:0] s1_bresp, s1_rresp; wire [31:0] s1_rdata;
wire s1_awvalid, s1_wvalid, s1_bready, s1_arvalid, s1_rready;
wire [31:0] s1_awaddr, s1_wdata, s1_araddr; wire [3:0] s1_wstrb;

axi4lite_dist u_dist (
`include "dist_conn.vh"
);

axi4lite_sram_wrapper u_sram_w (
     .clk_i(clk), .rst_i(rst)
    ,.awvalid_i(s0_awvalid), .awaddr_i(s0_awaddr), .wvalid_i(s0_wvalid)
    ,.wdata_i(s0_wdata), .wstrb_i(s0_wstrb), .bready_i(s0_bready)
    ,.arvalid_i(s0_arvalid), .araddr_i(s0_araddr), .rready_i(s0_rready)
    ,.awready_o(s0_awready), .wready_o(s0_wready), .bvalid_o(s0_bvalid), .bresp_o(s0_bresp)
    ,.arready_o(s0_arready), .rvalid_o(s0_rvalid), .rdata_o(s0_rdata), .rresp_o(s0_rresp)
);

axi4lite_accel_wrapper u_acc_w (
     .clk_i(clk), .rst_i(rst)
    ,.awvalid_i(s1_awvalid), .awaddr_i(s1_awaddr), .wvalid_i(s1_wvalid)
    ,.wdata_i(s1_wdata), .wstrb_i(s1_wstrb), .bready_i(s1_bready)
    ,.arvalid_i(s1_arvalid), .araddr_i(s1_araddr), .rready_i(s1_rready)
    ,.awready_o(s1_awready), .wready_o(s1_wready), .bvalid_o(s1_bvalid), .bresp_o(s1_bresp)
    ,.arready_o(s1_arready), .rvalid_o(s1_rvalid), .rdata_o(s1_rdata), .rresp_o(s1_rresp)
);

//-----------------------------------------------------------------
// AXI master tasks (drive o negedge, sample o posedge)
//-----------------------------------------------------------------
task axi_write(input [31:0] addr, input [31:0] data, input [3:0] strb);
    reg aw_d, w_d, b_d;
begin
    @(negedge clk);
    m_awvalid = 1; m_awaddr = addr; m_wvalid = 1; m_wdata = data; m_wstrb = strb;
    aw_d = 0; w_d = 0;
    while (!(aw_d && w_d)) begin
        @(posedge clk);
        if (m_awvalid && m_awready) aw_d = 1;
        if (m_wvalid  && m_wready)  w_d  = 1;
        @(negedge clk);
        if (aw_d) m_awvalid = 0;
        if (w_d)  m_wvalid  = 0;
    end
    m_bready = 1; b_d = 0;
    while (!b_d) begin
        @(posedge clk);
        if (m_bvalid && m_bready) begin
            b_d = 1;
            if (m_bresp !== 2'b00) $display("ERR: bresp=%b", m_bresp);
        end
    end
    @(negedge clk); m_bready = 0;
end
endtask


task axi_write_split(input [31:0] addr, input [31:0] data, input [3:0] strb, input integer gap);
    reg aw_d, w_d, b_d;
begin
    @(negedge clk);
    m_awvalid = 1; m_awaddr = addr; aw_d = 0; w_d = 0;
    while (!aw_d) begin
        @(posedge clk); if (m_awvalid && m_awready) aw_d = 1;
        @(negedge clk); if (aw_d) m_awvalid = 0;
    end
    repeat (gap) @(negedge clk);
    m_wvalid = 1; m_wdata = data; m_wstrb = strb;
    while (!w_d) begin
        @(posedge clk); if (m_wvalid && m_wready) w_d = 1;
        @(negedge clk); if (w_d) m_wvalid = 0;
    end
    m_bready = 1; b_d = 0;
    while (!b_d) begin @(posedge clk); if (m_bvalid && m_bready) b_d = 1; end
    @(negedge clk); m_bready = 0;
end
endtask

task axi_read(input [31:0] addr, output [31:0] data);
    reg ar_d, r_d;
begin
    @(negedge clk);
    m_arvalid = 1; m_araddr = addr; ar_d = 0;
    while (!ar_d) begin
        @(posedge clk);
        if (m_arvalid && m_arready) ar_d = 1;
        @(negedge clk);
        if (ar_d) m_arvalid = 0;
    end
    m_rready = 1; r_d = 0;
    while (!r_d) begin
        @(posedge clk);
        if (m_rvalid && m_rready) begin r_d = 1; data = m_rdata; end
    end
    @(negedge clk); m_rready = 0;
end
endtask

//-----------------------------------------------------------------
// Test
//-----------------------------------------------------------------
integer errors = 0;
reg [31:0] rd;

task check(input [31:0] got, input [31:0] exp, input [255:0] what);
begin
    if (got !== exp) begin
        errors = errors + 1;
        $display("FAIL %0s: got %h exp %h", what, got, exp);
    end
end
endtask

integer r, c, kk, i;
reg signed [7:0]  A [0:3][0:3];
reg signed [7:0]  B [0:3][0:3];
integer           C [0:3][0:3];
reg [31:0]        w;
integer           tmo;

initial begin
    repeat (4) @(posedge clk);
    rst = 0;
    repeat (2) @(posedge clk);

    // ---------- SRAM: full word ----------
    axi_write(SRAM_BASE + 32'h10, 32'hDEADBEEF, 4'hF);
    axi_write(SRAM_BASE + 32'h14, 32'h12345678, 4'hF);
    axi_read (SRAM_BASE + 32'h10, rd); check(rd, 32'hDEADBEEF, "sram w0");
    axi_read (SRAM_BASE + 32'h14, rd); check(rd, 32'h12345678, "sram w1");

    // ---------- SRAM: partial strobe (RMW) ----------
    axi_write(SRAM_BASE + 32'h20, 32'hAABBCCDD, 4'hF);
    axi_write(SRAM_BASE + 32'h20, 32'h000000EE, 4'b0001);
    axi_read (SRAM_BASE + 32'h20, rd); check(rd, 32'hAABBCCEE, "sram sb");
    axi_write(SRAM_BASE + 32'h20, 32'h11223344, 4'b1010);
    axi_read (SRAM_BASE + 32'h20, rd); check(rd, 32'h11BB33EE, "sram strb1010");
    axi_write(SRAM_BASE + 32'h20, 32'h0000BEEF, 4'b0011);
    axi_read (SRAM_BASE + 32'h20, rd); check(rd, 32'h11BBBEEF, "sram sh");
    // cac o khac khong bi anh huong
    axi_read (SRAM_BASE + 32'h10, rd); check(rd, 32'hDEADBEEF, "sram w0 intact");

    // ---------- SRAM: top of window (0xFFC) ----------
    axi_write(SRAM_BASE + 32'hFFC, 32'hCAFEF00D, 4'hF);
    axi_read (SRAM_BASE + 32'hFFC, rd); check(rd, 32'hCAFEF00D, "sram last word");

    // ---------- Accelerator ----------
    for (r = 0; r < 4; r = r + 1)
        for (c = 0; c < 4; c = c + 1) begin
            A[r][c] = ($random % 100);       // co ca so am
            B[r][c] = ($random % 100);
        end
    for (r = 0; r < 4; r = r + 1)
        for (c = 0; c < 4; c = c + 1) begin
            C[r][c] = 0;
            for (kk = 0; kk < 4; kk = kk + 1) C[r][c] = C[r][c] + A[r][kk] * B[kk][c];
        end

    for (r = 0; r < 4; r = r + 1) begin
        w = {A[r][3][7:0], A[r][2][7:0], A[r][1][7:0], A[r][0][7:0]};
        axi_write(ACC_BASE + 32'h10 + r*4, w, 4'hF);
        w = {B[r][3][7:0], B[r][2][7:0], B[r][1][7:0], B[r][0][7:0]};
        axi_write(ACC_BASE + 32'h20 + r*4, w, 4'hF);
    end
    // readback A/B
    axi_read(ACC_BASE + 32'h14, rd);
    check(rd, {A[1][3][7:0], A[1][2][7:0], A[1][1][7:0], A[1][0][7:0]}, "A readback");

    axi_write(ACC_BASE + 32'h00, 32'h3, 4'hF);      // clear + start
    tmo = 0; rd = 0;
    while (!rd[1] && tmo < 100) begin
        axi_read(ACC_BASE + 32'h04, rd);
        tmo = tmo + 1;
    end
    if (tmo >= 100) begin errors = errors + 1; $display("FAIL: accelerator timeout"); end

    for (r = 0; r < 4; r = r + 1)
        for (c = 0; c < 4; c = c + 1) begin
            axi_read(ACC_BASE + 32'h40 + r*32'h10 + c*4, rd);
            if ($signed(rd) !== C[r][c]) begin
                errors = errors + 1;
                $display("FAIL C[%0d][%0d]: got %0d exp %0d", r, c, $signed(rd), C[r][c]);
            end
        end

    // ---------- Accelerator lan 2: doi du lieu, khong clear thi cong don; clear+start -> dung ----------
    for (r = 0; r < 4; r = r + 1)
        for (c = 0; c < 4; c = c + 1) A[r][c] = ($random % 120);
    for (r = 0; r < 4; r = r + 1)
        for (c = 0; c < 4; c = c + 1) begin
            C[r][c] = 0;
            for (kk = 0; kk < 4; kk = kk + 1) C[r][c] = C[r][c] + A[r][kk] * B[kk][c];
        end
    for (r = 0; r < 4; r = r + 1) begin
        w = {A[r][3][7:0], A[r][2][7:0], A[r][1][7:0], A[r][0][7:0]};
        axi_write(ACC_BASE + 32'h10 + r*4, w, 4'hF);
    end
    axi_write(ACC_BASE + 32'h00, 32'h3, 4'hF);
    tmo = 0; rd = 0;
    while (!rd[1] && tmo < 100) begin axi_read(ACC_BASE + 32'h04, rd); tmo = tmo + 1; end
    // luu y: DONE cua lan 1 con giu den khi start -> start xoa done, nen day la lan 2
    for (r = 0; r < 4; r = r + 1)
        for (c = 0; c < 4; c = c + 1) begin
            axi_read(ACC_BASE + 32'h40 + r*32'h10 + c*4, rd);
            if ($signed(rd) !== C[r][c]) begin
                errors = errors + 1;
                $display("FAIL run2 C[%0d][%0d]: got %0d exp %0d", r, c, $signed(rd), C[r][c]);
            end
        end


    // ---------- AW truoc, W sau ----------
    axi_write_split(SRAM_BASE + 32'h30, 32'h01020304, 4'hF, 3);
    axi_read(SRAM_BASE + 32'h30, rd); check(rd, 32'h01020304, "split full");
    axi_write_split(SRAM_BASE + 32'h30, 32'h000000AA, 4'b0100 | 4'b0000, 5);
    axi_read(SRAM_BASE + 32'h30, rd); check(rd, 32'h01000304, "split strb byte2");
    axi_write_split(SRAM_BASE + 32'h30, 32'h00BB0000, 4'b0100, 2);
    axi_read(SRAM_BASE + 32'h30, rd); check(rd, 32'h01BB0304, "split rmw");
    axi_write_split(ACC_BASE + 32'h10, 32'h04030201, 4'hF, 4);
    axi_read(ACC_BASE + 32'h10, rd); check(rd, 32'h04030201, "acc split");

    // ---------- Doc SRAM sau khi dung accelerator (kiem tra chon outport) ----------
    axi_read(SRAM_BASE + 32'h10, rd); check(rd, 32'hDEADBEEF, "sram still ok");

    if (errors == 0) $display("ALL TESTS PASSED");
    else             $display("%0d ERRORS", errors);
    $finish;
end

initial begin
    #2000000;
    $display("GLOBAL TIMEOUT");
    $finish;
end

endmodule
