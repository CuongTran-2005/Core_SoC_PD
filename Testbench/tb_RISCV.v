`timescale 1ns/1ps
// =============================================================================
// Testbench: RISC_V (RV32I, pipeline 5 tầng, AXI4-Lite master)
//
//  - Mô hình AXI4-Lite slave (bộ nhớ thống nhất 64KB) với độ trễ ngẫu nhiên
//  - Chương trình test được "assemble" ngay trong TB (không cần toolchain/hex)
//  - Chương trình tự ghi kết quả ra RES_BASE + 4*k bằng lệnh sw; TB so sánh
//    với giá trị kỳ vọng -> không phụ thuộc tên tín hiệu bên trong core
//  - Ghi vào DONE_ADDR = báo kết thúc
//  - Monitor giao thức AXI4-Lite (ổn định valid/data, X, wstrb hợp lệ, ...)
//
//  Chạy:  iverilog -g2012 -o sim.vvp tb_RISC_V.v <file RTL của core>
//         vvp sim.vvp                       (không wait-state)
//         vvp sim.vvp +MAXWAIT=6            (slave trễ ngẫu nhiên 0..6 chu kỳ)
//         vvp sim.vvp +MAXWAIT=6 +VERBOSE   (in từng giao dịch AXI)
// =============================================================================
module tb_RISC_V;

    parameter CLK_PERIOD  = 10;
    parameter RST_ACTIVE  = 1'b1;            // mức tích cực của rst
    parameter MEM_WORDS   = 16384;           // 64KB
    parameter RES_BASE    = 32'h0000_2000;   // vùng chương trình ghi kết quả
    parameter DONE_ADDR   = 32'h0000_3000;   // ghi vào đây = kết thúc (bit [11:0] = 0)
    parameter TIMEOUT_CYC = 100000;

    // ------------------------------------------------------------------
    // Clock / reset / DUT
    // ------------------------------------------------------------------
    reg clk, rst;
    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;
    wire in_reset = (rst === RST_ACTIVE);

    wire [31:0] axi_araddr;  wire axi_arvalid; wire axi_arready;
    wire [31:0] axi_rdata;   wire [1:0] axi_rresp; wire axi_rvalid; wire axi_rready;
    wire [31:0] axi_awaddr;  wire axi_awvalid; wire axi_awready;
    wire [31:0] axi_wdata;   wire [3:0] axi_wstrb; wire axi_wvalid; wire axi_wready;
    wire [1:0]  axi_bresp;   wire axi_bvalid;  wire axi_bready;

    RISC_V dut (
        .clk(clk), .rst(rst),
        .axi_araddr(axi_araddr), .axi_arvalid(axi_arvalid), .axi_arready(axi_arready),
        .axi_rdata(axi_rdata), .axi_rresp(axi_rresp), .axi_rvalid(axi_rvalid), .axi_rready(axi_rready),
        .axi_awaddr(axi_awaddr), .axi_awvalid(axi_awvalid), .axi_awready(axi_awready),
        .axi_wdata(axi_wdata), .axi_wstrb(axi_wstrb), .axi_wvalid(axi_wvalid), .axi_wready(axi_wready),
        .axi_bresp(axi_bresp), .axi_bvalid(axi_bvalid), .axi_bready(axi_bready)
    );

    // ------------------------------------------------------------------
    // Biến chung
    // ------------------------------------------------------------------
    reg [31:0] mem [0:MEM_WORDS-1];
    integer    errors, seed, maxwait, verbose, cyc, n_rd, n_wr, dummy;
    reg        done_flag;

    task fail;
        input [8*56-1:0] msg;
        begin
            errors = errors + 1;
            $display("[%0t] ERROR: %0s", $time, msg);
        end
    endtask

    function integer rnd_wait;
        input dummy_in;
        begin
            if (maxwait == 0) rnd_wait = 0;
            else              rnd_wait = {$random(seed)} % (maxwait + 1);
        end
    endfunction

    // ------------------------------------------------------------------
    // AXI4-Lite slave: kênh đọc (AR -> R)
    // ------------------------------------------------------------------
    localparam R_AR = 2'd0, R_LAT = 2'd1, R_RSP = 2'd2;
    reg [1:0]  r_state;
    reg        arready_r, rvalid_r;
    reg [31:0] rdata_r, araddr_q;
    integer    r_cnt;

    assign axi_arready = arready_r;
    assign axi_rvalid  = rvalid_r;
    assign axi_rdata   = rdata_r;
    assign axi_rresp   = 2'b00;

    always @(posedge clk) begin
        if (in_reset) begin
            r_state <= R_AR; arready_r <= 1'b0; rvalid_r <= 1'b0;
            rdata_r <= 32'd0; araddr_q <= 32'd0; r_cnt <= 0;
        end else case (r_state)
            R_AR: begin
                if (axi_arvalid && arready_r) begin
                    arready_r <= 1'b0;
                    araddr_q  <= axi_araddr;
                    r_cnt     <= rnd_wait(0);
                    r_state   <= R_LAT;
                end else if (r_cnt == 0) arready_r <= 1'b1;
                else                     r_cnt    <= r_cnt - 1;
            end
            R_LAT: begin
                if (r_cnt == 0) begin
                    rvalid_r <= 1'b1;
                    rdata_r  <= (araddr_q >= MEM_WORDS*4) ? 32'hxxxx_xxxx : mem[araddr_q >> 2];
                    r_state  <= R_RSP;
                end else r_cnt <= r_cnt - 1;
            end
            R_RSP: begin
                if (axi_rready) begin
                    rvalid_r <= 1'b0;
                    r_cnt    <= rnd_wait(0);
                    r_state  <= R_AR;
                end
            end
        endcase
    end

    // ------------------------------------------------------------------
    // AXI4-Lite slave: kênh ghi (AW + W -> B), AW và W nhận độc lập
    // ------------------------------------------------------------------
    reg        awready_r, wready_r, bvalid_r, aw_got, w_got;
    reg [31:0] awaddr_q, wdata_q;
    reg [3:0]  wstrb_q;
    integer    aw_cnt, w_cnt, b_cnt;

    assign axi_awready = awready_r;
    assign axi_wready  = wready_r;
    assign axi_bvalid  = bvalid_r;
    assign axi_bresp   = 2'b00;

    task mem_wr;
        input [31:0] a, d;
        input [3:0]  s;
        reg   [31:0] t;
        integer      i;
        begin
            t = mem[a >> 2];
            for (i = 0; i < 4; i = i + 1)
                if (s[i]) t[8*i +: 8] = d[8*i +: 8];
            mem[a >> 2] = t;
        end
    endtask

    always @(posedge clk) begin
        if (in_reset) begin
            awready_r <= 1'b0; wready_r <= 1'b0; bvalid_r <= 1'b0;
            aw_got <= 1'b0; w_got <= 1'b0; aw_cnt <= 0; w_cnt <= 0; b_cnt <= 0;
        end else begin
            // ---- AW ----
            if (axi_awvalid && awready_r) begin
                awready_r <= 1'b0; aw_got <= 1'b1; awaddr_q <= axi_awaddr;
            end else if (!aw_got && !bvalid_r) begin
                if (aw_cnt == 0) awready_r <= 1'b1; else aw_cnt <= aw_cnt - 1;
            end
            // ---- W ----
            if (axi_wvalid && wready_r) begin
                wready_r <= 1'b0; w_got <= 1'b1; wdata_q <= axi_wdata; wstrb_q <= axi_wstrb;
            end else if (!w_got && !bvalid_r) begin
                if (w_cnt == 0) wready_r <= 1'b1; else w_cnt <= w_cnt - 1;
            end
            // ---- thực hiện ghi, trả B ----
            if (aw_got && w_got && !bvalid_r) begin
                if (b_cnt == 0) begin
                    if (awaddr_q == DONE_ADDR)         done_flag = 1'b1;
                    else if (awaddr_q >= MEM_WORDS*4)  fail("AW: ghi ngoai vung nho");
                    else                               mem_wr(awaddr_q, wdata_q, wstrb_q);
                    bvalid_r <= 1'b1; aw_got <= 1'b0; w_got <= 1'b0;
                    b_cnt <= rnd_wait(0); aw_cnt <= rnd_wait(0); w_cnt <= rnd_wait(0);
                end else b_cnt <= b_cnt - 1;
            end
            if (bvalid_r && axi_bready) bvalid_r <= 1'b0;
        end
    end

    // ------------------------------------------------------------------
    // Monitor giao thức AXI4-Lite phía master
    // ------------------------------------------------------------------
    reg        ar_hold, aw_hold, w_hold, x_reported;
    reg [31:0] ar_a, aw_a, w_d;
    reg [3:0]  w_s;
    wire       wstrb_ok = (axi_wstrb == 4'b1111) || (axi_wstrb == 4'b0011) || (axi_wstrb == 4'b1100) ||
                          (axi_wstrb == 4'b0001) || (axi_wstrb == 4'b0010) || (axi_wstrb == 4'b0100) ||
                          (axi_wstrb == 4'b1000);

    always @(posedge clk) begin
        if (in_reset) begin
            ar_hold <= 1'b0; aw_hold <= 1'b0; w_hold <= 1'b0; x_reported <= 1'b0;
        end else begin
            // valid đã lên thì phải giữ valid + addr/data đến khi có ready
            if (ar_hold && (axi_arvalid !== 1'b1 || axi_araddr !== ar_a))
                fail("AR: arvalid/araddr thay doi truoc arready");
            if (aw_hold && (axi_awvalid !== 1'b1 || axi_awaddr !== aw_a))
                fail("AW: awvalid/awaddr thay doi truoc awready");
            if (w_hold && (axi_wvalid !== 1'b1 || axi_wdata !== w_d || axi_wstrb !== w_s))
                fail("W: wvalid/wdata/wstrb thay doi truoc wready");
            ar_hold <= (axi_arvalid === 1'b1) && !axi_arready; ar_a <= axi_araddr;
            aw_hold <= (axi_awvalid === 1'b1) && !axi_awready; aw_a <= axi_awaddr;
            w_hold  <= (axi_wvalid  === 1'b1) && !axi_wready;  w_d  <= axi_wdata; w_s <= axi_wstrb;

            // X/Z trên các tín hiệu điều khiển (báo 1 lần)
            if (!x_reported && ((^{axi_arvalid, axi_awvalid, axi_wvalid, axi_rready, axi_bready}) === 1'bx)) begin
                x_reported <= 1'b1;
                fail("X/Z tren arvalid/awvalid/wvalid/rready/bready");
            end
            if (axi_wvalid === 1'b1 && !wstrb_ok) fail("W: wstrb khong hop le");
            if (axi_arvalid === 1'b1 && axi_arready && axi_araddr >= MEM_WORDS*4) fail("AR: doc ngoai vung nho");
            if (axi_arvalid === 1'b1 && axi_araddr[1:0] != 2'b00 && axi_arready) fail("AR: araddr khong can le 4 byte");

            // thống kê + log
            if (axi_arvalid === 1'b1 && axi_arready) begin
                n_rd = n_rd + 1;
                if (verbose) $display("[%0t] AR  addr=%h", $time, axi_araddr);
            end
            if (axi_rvalid && axi_rready && verbose) $display("[%0t] R   data=%h", $time, axi_rdata);
            if (axi_awvalid === 1'b1 && axi_awready && verbose) $display("[%0t] AW  addr=%h", $time, axi_awaddr);
            if (axi_wvalid === 1'b1 && axi_wready) begin
                n_wr = n_wr + 1;
                if (verbose) $display("[%0t] W   data=%h strb=%b", $time, axi_wdata, axi_wstrb);
            end
            if (axi_bvalid && axi_bready && verbose) $display("[%0t] B   resp=%b", $time, axi_bresp);
        end
    end

    // ------------------------------------------------------------------
    // Bộ "assembler" RV32I tối giản
    // ------------------------------------------------------------------
    function [31:0] enc_r;
        input [6:0] f7; input [4:0] rs2, rs1; input [2:0] f3; input [4:0] rd; input [6:0] op;
        begin enc_r = {f7, rs2, rs1, f3, rd, op}; end
    endfunction
    function [31:0] enc_i;
        input [11:0] imm; input [4:0] rs1; input [2:0] f3; input [4:0] rd; input [6:0] op;
        begin enc_i = {imm, rs1, f3, rd, op}; end
    endfunction
    function [31:0] enc_s;
        input [11:0] imm; input [4:0] rs2, rs1; input [2:0] f3;
        begin enc_s = {imm[11:5], rs2, rs1, f3, imm[4:0], 7'b0100011}; end
    endfunction
    function [31:0] enc_b;
        input [12:0] imm; input [4:0] rs2, rs1; input [2:0] f3;
        begin enc_b = {imm[12], imm[10:5], rs2, rs1, f3, imm[4:1], imm[11], 7'b1100011}; end
    endfunction
    function [31:0] enc_j;
        input [20:0] imm; input [4:0] rd;
        begin enc_j = {imm[20], imm[10:1], imm[11], imm[19:12], rd, 7'b1101111}; end
    endfunction

    reg [31:0]      pc_gen;
    integer         ridx;
    reg [31:0]      exp_val [0:63];
    reg [8*32-1:0]  tname   [0:63];

    task emit;      input [31:0] inst; begin mem[pc_gen >> 2] = inst; pc_gen = pc_gen + 4; end endtask
    task rtype;     input [6:0] f7; input [2:0] f3; input [4:0] rd, rs1, rs2;
                    begin emit(enc_r(f7, rs2, rs1, f3, rd, 7'b0110011)); end endtask
    task itype;     input [2:0] f3; input [4:0] rd, rs1; input integer imm;
                    begin emit(enc_i(imm[11:0], rs1, f3, rd, 7'b0010011)); end endtask
    task shifti;    input [6:0] f7; input [2:0] f3; input [4:0] rd, rs1, shamt;
                    begin emit(enc_i({f7, shamt}, rs1, f3, rd, 7'b0010011)); end endtask
    task load;      input [2:0] f3; input [4:0] rd, rs1; input integer imm;
                    begin emit(enc_i(imm[11:0], rs1, f3, rd, 7'b0000011)); end endtask
    task store;     input [2:0] f3; input [4:0] rs2, rs1; input integer imm;
                    begin emit(enc_s(imm[11:0], rs2, rs1, f3)); end endtask
    task branch;    input [2:0] f3; input [4:0] rs1, rs2; input integer off;
                    begin emit(enc_b(off[12:0], rs2, rs1, f3)); end endtask
    task lui;       input [4:0] rd; input [19:0] imm; begin emit({imm, rd, 7'b0110111}); end endtask
    task auipc;     input [4:0] rd; input [19:0] imm; begin emit({imm, rd, 7'b0010111}); end endtask
    task jal;       input [4:0] rd; input integer off; begin emit(enc_j(off[20:0], rd)); end endtask
    task jalr;      input [4:0] rd, rs1; input integer imm;
                    begin emit(enc_i(imm[11:0], rs1, 3'b000, rd, 7'b1100111)); end endtask

    // Ghi thanh ghi rs ra RES_BASE + 4*ridx và nhớ giá trị kỳ vọng
    task res;
        input [4:0] rs; input [31:0] expv; input [8*32-1:0] nm;
        begin
            store(3'b010, rs, 31, ridx*4);
            exp_val[ridx] = expv; tname[ridx] = nm; ridx = ridx + 1;
        end
    endtask

    // ------------------------------------------------------------------
    // Chương trình test
    // ------------------------------------------------------------------
    task build_program;
        reg [31:0] p_auipc, p_jal, p_jalr;
        integer i;
        begin
            for (i = 0; i < MEM_WORDS; i = i + 1)
                mem[i] = (i < 1024) ? 32'h0000_0013 : 32'h0;   // vùng code = NOP
            pc_gen = 0; ridx = 0;

            lui(31, RES_BASE >> 12);                          // x31 = RES_BASE

            // ---- 1. ALU + forwarding (MEM->EX, WB->EX, regfile bypass) ----
            itype(3'b000, 1, 0, 5);                           // x1 = 5
            itype(3'b000, 2, 1, 7);                           // x2 = 12      (fwd MEM, rs1)
            rtype(7'b0000000, 3'b000, 3, 2, 1);               // x3 = 17      (fwd MEM + WB)
            rtype(7'b0100000, 3'b000, 4, 3, 1);               // x4 = 12      (x1 cach 3 lenh -> regfile bypass)
            res(4, 12, "SUB + store fwd MEM->EX");
            res(3, 17, "ADD chain / regfile bypass");

            // ---- 2. Logic ----
            itype(3'b000, 5, 0, 240);                         // x5 = 0xF0
            itype(3'b111, 6, 5, 32'h3C);                      // andi -> 0x30
            itype(3'b110, 7, 5, 15);                          // ori  -> 0xFF
            itype(3'b100, 8, 7, 32'h55);                      // xori -> 0xAA
            res(6, 32'h30, "ANDI");
            res(7, 32'hFF, "ORI");
            res(8, 32'hAA, "XORI");

            // ---- 3. Shift ----
            itype(3'b000, 9, 0, -16);                         // x9 = 0xFFFFFFF0
            shifti(7'b0000000, 3'b101, 10, 9, 4);             // srli
            shifti(7'b0100000, 3'b101, 11, 9, 4);             // srai
            shifti(7'b0000000, 3'b001, 12, 1, 3);             // slli x1(=5) << 3
            res(10, 32'h0FFF_FFFF, "SRLI");
            res(11, 32'hFFFF_FFFF, "SRAI");
            res(12, 40,            "SLLI");

            // ---- 4. So sánh ----
            itype(3'b010, 13, 9, 0);                          // slti  (-16 < 0)        = 1
            itype(3'b011, 14, 9, 1);                          // sltiu (0xFFFFFFF0 < 1) = 0
            rtype(7'b0000000, 3'b011, 15, 0, 9);              // sltu  (0 < 0xFFFFFFF0) = 1
            rtype(7'b0000000, 3'b011, 16, 9, 1);              // sltu  (0xFFFFFFF0 < 5) = 0
            res(13, 1, "SLTI");
            res(14, 0, "SLTIU");
            res(15, 1, "SLTU (x0, neg)");
            res(16, 0, "SLTU (neg, pos)");

            // ---- 5. LUI / AUIPC ----
            lui(17, 20'h12345);
            p_auipc = pc_gen; auipc(18, 1);
            res(17, 32'h1234_5000,      "LUI");
            res(18, p_auipc + 32'h1000, "AUIPC");

            // ---- 6. Load / Store ----
            lui(19, 20'hDEADC);
            itype(3'b000, 19, 19, -273);                      // x19 = 0xDEADBEEF
            store(3'b010, 19, 31, 256);                       // sw x19, 0x100(x31)
            load (3'b010, 20, 31, 256);                       // lw x20
            res(20, 32'hDEAD_BEEF, "SW->LW, LW->SW (load-use)");
            load (3'b000, 21, 31, 256);                       // lb  @+0
            load (3'b100, 22, 31, 257);                       // lbu @+1
            load (3'b001, 23, 31, 258);                       // lh  @+2
            load (3'b101, 24, 31, 256);                       // lhu @+0
            res(21, 32'hFFFF_FFEF, "LB (sign-ext)");
            res(22, 32'h0000_00BE, "LBU");
            res(23, 32'hFFFF_DEAD, "LH (sign-ext)");
            res(24, 32'h0000_BEEF, "LHU");

            itype(3'b000, 25, 0, 32'h55);
            store(3'b000, 25, 31, 257);                       // sb 0x55 @+1 -> 0xDEAD55EF
            itype(3'b000, 26, 0, 32'h234);
            store(3'b001, 26, 31, 258);                       // sh 0x234 @+2 -> 0x023455EF
            load (3'b010, 27, 31, 256);
            res(27, 32'h0234_55EF, "SB/SH wstrb + LW");

            load (3'b010, 28, 31, 256);                       // load-use hazard
            rtype(7'b0000000, 3'b000, 29, 28, 28);            // x29 = x28 + x28
            res(29, 32'h0468_ABDE, "Load-use stall");

            // ---- 7. Branch: taken / not taken / flush ----
            itype(3'b000, 3, 0, 0);                           // x3 = 0  (bộ đếm "lệnh độc")
            itype(3'b000, 4, 0, 0);                           // x4 = 0  (bộ đếm "không nhảy")
            itype(3'b000, 1, 0, 1);
            itype(3'b000, 2, 0, 1);
            itype(3'b000, 5, 0, -1);
            branch(3'b000, 1, 2, 12);                         // beq  taken, bỏ 2 lệnh
            itype(3'b000, 3, 3, 1);                           //   poison
            itype(3'b000, 3, 3, 1);                           //   poison
            branch(3'b001, 1, 2, 8);                          // bne  not taken
            itype(3'b000, 4, 4, 1);                           //   x4 = 1
            branch(3'b100, 5, 0, 8);                          // blt  taken (-1 < 0)
            itype(3'b000, 3, 3, 1);                           //   poison
            branch(3'b110, 5, 0, 8);                          // bltu not taken
            itype(3'b000, 4, 4, 1);                           //   x4 = 2
            branch(3'b101, 0, 5, 8);                          // bge  taken (0 >= -1)
            itype(3'b000, 3, 3, 1);                           //   poison
            branch(3'b111, 0, 5, 8);                          // bgeu not taken
            itype(3'b000, 4, 4, 1);                           //   x4 = 3
            itype(3'b000, 6, 0, 3);
            itype(3'b000, 7, 0, 3);
            branch(3'b000, 6, 7, 8);                          // beq taken, toán hạng forward
            itype(3'b000, 3, 3, 1);                           //   poison
            res(3, 0, "Branch flush (x3 == 0)");
            res(4, 3, "Branch not-taken count");

            // ---- 8. Vòng lặp (nhảy lùi) ----
            itype(3'b000, 10, 0, 0);
            itype(3'b000, 11, 0, 5);
            itype(3'b000, 10, 10, 2);                         // loop:
            itype(3'b000, 11, 11, -1);
            branch(3'b001, 11, 0, -8);                        // bne x11,x0,loop
            res(10, 10, "Loop 5 vong (backward br)");

            // ---- 9. JAL / JALR ----
            itype(3'b000, 3, 0, 0);
            p_jal = pc_gen; jal(1, 12);                       // bỏ 2 lệnh
            itype(3'b000, 3, 3, 1);                           //   poison
            itype(3'b000, 3, 3, 1);                           //   poison
            res(1, p_jal + 4, "JAL link (WB->ID bypass)");    // target dùng x1 ngay
            p_jalr = pc_gen;
            itype(3'b000, 5, 0, p_jalr + 12);                 // x5 = địa chỉ target
            jalr(6, 5, 0);                                    // nhảy ngay sau lệnh addi (fwd)
            itype(3'b000, 3, 3, 1);                           //   poison
            res(6, p_jalr + 8, "JALR link");                  // = target
            res(3, 0, "JAL/JALR flush (x3 == 0)");

            // ---- Kết thúc ----
            lui(30, DONE_ADDR >> 12);
            itype(3'b000, 29, 0, 1);
            store(3'b010, 29, 30, 0);                         // báo DONE
            jal(0, 0);                                        // loop vô hạn
        end
    endtask

    // ------------------------------------------------------------------
    // Kiểm tra kết quả
    // ------------------------------------------------------------------
    task check_results;
        integer k;
        reg [31:0] got;
        begin
            for (k = 0; k < ridx; k = k + 1) begin
                got = mem[(RES_BASE >> 2) + k];
                if (got !== exp_val[k]) begin
                    errors = errors + 1;
                    $display("  FAIL [%2d] %-28s got=%h exp=%h", k, tname[k], got, exp_val[k]);
                end else
                    $display("  PASS [%2d] %-28s %h", k, tname[k], got);
            end
        end
    endtask

    // ------------------------------------------------------------------
    // Điều khiển chính
    // ------------------------------------------------------------------
    initial begin
        errors = 0; seed = 32'h1234_5678; maxwait = 0; verbose = 0;
        cyc = 0; n_rd = 0; n_wr = 0; done_flag = 1'b0;
        dummy = $value$plusargs("MAXWAIT=%d", maxwait);
        if ($test$plusargs("VERBOSE")) verbose = 1;

        $dumpfile("tb_RISC_V.vcd");
        $dumpvars(0, tb_RISC_V);

        build_program;
        $display("== Chuong trinh: %0d lenh, %0d ket qua kiem tra, MAXWAIT=%0d ==", pc_gen/4, ridx, maxwait);

        rst = RST_ACTIVE;
        repeat (5) @(posedge clk);
        @(negedge clk) rst = ~RST_ACTIVE;

        wait (done_flag);
        repeat (10) @(posedge clk);

        check_results;
        $display("== %0d chu ky, %0d lan doc AXI, %0d lan ghi AXI ==", cyc, n_rd, n_wr);
        if (errors == 0) $display("*** TEST PASSED ***");
        else             $display("*** TEST FAILED: %0d loi ***", errors);
        $finish;
    end

    // Watchdog
    always @(posedge clk) begin
        if (!in_reset) cyc <= cyc + 1;
        if (cyc == TIMEOUT_CYC && !done_flag) begin
            $display("*** TIMEOUT: core khong ghi DONE (ket qua den luc treo) ***");
            check_results;
            $display("*** TEST FAILED ***");
            $finish;
        end
    end

endmodule
