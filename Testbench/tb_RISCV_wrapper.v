`timescale 1ns/1ps

module tb_RISCV_wrapper;

    // =========================================================================
    // 1. TÍN HIỆU KẾT NỐI DUT (RISC_V_WRAPPER)
    // =========================================================================
    reg         clk;
    reg         rst; // Nối vào KEY[0] (active-high theo RISC_V_WRAPPER hiện tại)

    // AXI4-Lite Read Address
    wire [31:0] axi_araddr;
    wire        axi_arvalid;
    reg         axi_arready;

    // AXI4-Lite Read Data
    reg  [31:0] axi_rdata;
    reg  [1:0]  axi_rresp;
    reg         axi_rvalid;
    wire        axi_rready;

    // AXI4-Lite Write Address
    wire [31:0] axi_awaddr;
    wire        axi_awvalid;
    reg         axi_awready;

    // AXI4-Lite Write Data
    wire [31:0] axi_wdata;
    wire [3:0]  axi_wstrb;
    wire        axi_wvalid;
    reg         axi_wready;

    // AXI4-Lite Write Response
    reg  [1:0]  axi_bresp;
    reg         axi_bvalid;
    wire        axi_bready;

    RISC_V_WRAPPER dut (
        .CLOCK_50    (clk),
        .KEY         (rst),

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

    // Clock 50 MHz (chu kỳ 20 ns)
    initial clk = 1'b0;
    always #10 clk = ~clk;

    // =========================================================================
    // 2. BỘ NHỚ HÀNH VI AXI4-LITE SLAVE (TÁCH VÙNG IMEM VÀ DMEM)
    // =========================================================================
    // IMEM: 0x0040_0000 .. 0x0040_03FF (256 words)
    // DMEM: 0x1001_0000 .. 0x1001_03FF (256 words)
    reg [31:0] imem_mem [0:255];
    reg [31:0] dmem_mem [0:255];

    function [31:0] read_slave_mem;
        input [31:0] addr;
        begin
            if (addr[31:12] == 20'h00400)
                read_slave_mem = imem_mem[addr[9:2]];
            else if (addr[31:12] == 20'h10010)
                read_slave_mem = dmem_mem[addr[9:2]];
            else
                read_slave_mem = 32'hDEAD_BEEF;
        end
    endfunction

    // Trạng thái kênh Read Slave (AR/R)
    localparam RD_IDLE      = 2'd0;
    localparam RD_WAIT_DATA = 2'd1;
    localparam RD_RESP      = 2'd2;

    reg [1:0]  rd_state;
    reg [31:0] rd_addr_lat;
    reg [1:0]  ar_wait_cnt;
    reg        r_wait_cnt;
    integer    rd_txn_cnt;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            rd_state    <= RD_IDLE;
            axi_arready <= 1'b1;
            axi_rvalid  <= 1'b0;
            axi_rdata   <= 32'b0;
            axi_rresp   <= 2'b00;
            rd_addr_lat <= 32'b0;
            ar_wait_cnt <= 2'd0;
            r_wait_cnt  <= 1'b0;
            rd_txn_cnt  <= 0;
        end
        else begin
            case (rd_state)
                RD_IDLE: begin
                    if (axi_arvalid && axi_arready) begin
                        rd_addr_lat <= axi_araddr;
                        axi_arready <= 1'b0;
                        if ((rd_txn_cnt % 2) == 0) begin
                            axi_rvalid <= 1'b1;
                            axi_rdata  <= read_slave_mem(axi_araddr);
                            axi_rresp  <= ((axi_araddr[31:12] == 20'h00400) ||
                                           (axi_araddr[31:12] == 20'h10010)) ? 2'b00 : 2'b10;
                            rd_state   <= RD_RESP;
                        end
                        else begin
                            r_wait_cnt <= 1'b1;
                            rd_state   <= RD_WAIT_DATA;
                        end
                    end
                    else if (axi_arvalid && !axi_arready) begin
                        if (ar_wait_cnt == 2'd0)
                            axi_arready <= 1'b1;
                        else
                            ar_wait_cnt <= ar_wait_cnt - 2'd1;
                    end
                end

                RD_WAIT_DATA: begin
                    axi_rvalid <= 1'b1;
                    axi_rdata  <= read_slave_mem(rd_addr_lat);
                    axi_rresp  <= ((rd_addr_lat[31:12] == 20'h00400) ||
                                   (rd_addr_lat[31:12] == 20'h10010)) ? 2'b00 : 2'b10;
                    rd_state   <= RD_RESP;
                end

                RD_RESP: begin
                    if (axi_rvalid && axi_rready) begin
                        axi_rvalid <= 1'b0;
                        rd_txn_cnt <= rd_txn_cnt + 1;
                        if (rd_addr_lat[31:12] == 20'h00400)
                            $display("[AXI-RD][IMEM] t=%0t addr=%h data=%h", $time, rd_addr_lat, axi_rdata);
                        else
                            $display("[AXI-RD][DMEM] t=%0t addr=%h data=%h", $time, rd_addr_lat, axi_rdata);

                        // Chuẩn bị độ trễ ARREADY cho giao dịch kế tiếp (0, 1 hoặc 2 chu kỳ)
                        if (((rd_txn_cnt + 1) % 3) == 0) begin
                            axi_arready <= 1'b1;
                            ar_wait_cnt <= 2'd0;
                        end
                        else begin
                            axi_arready <= 1'b0;
                            ar_wait_cnt <= ((rd_txn_cnt + 1) % 3) - 1;
                        end
                        rd_state <= RD_IDLE;
                    end
                end

                default: rd_state <= RD_IDLE;
            endcase
        end
    end

    // Trạng thái kênh Write Slave (AW/W/B) - kiểm tra AW và W độc lập
    localparam WR_IDLE   = 2'd0;
    localparam WR_WAIT_B = 2'd1;
    localparam WR_RESP   = 2'd2;

    reg [1:0]  wr_state;
    reg        aw_captured;
    reg        w_captured;
    reg [31:0] aw_addr_lat;
    reg [31:0] w_data_lat;
    reg [3:0]  w_strb_lat;
    reg [1:0]  aw_wait_cnt;
    reg [1:0]  w_wait_cnt;
    reg [1:0]  b_wait_cnt;
    integer    wr_txn_cnt;

    wire aw_hs_now   = axi_awvalid && axi_awready;
    wire w_hs_now    = axi_wvalid  && axi_wready;
    wire aw_done_now = aw_captured || aw_hs_now;
    wire w_done_now  = w_captured  || w_hs_now;

    reg [31:0] wr_eff_addr;
    reg [31:0] wr_eff_data;
    reg [3:0]  wr_eff_strb;
    reg [31:0] wr_old_word;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            wr_state    <= WR_IDLE;
            aw_captured <= 1'b0;
            w_captured  <= 1'b0;
            aw_addr_lat <= 32'b0;
            w_data_lat  <= 32'b0;
            w_strb_lat  <= 4'b0;
            // Mẫu 0: AW và W sẵn sàng cùng chu kỳ
            axi_awready <= 1'b1;
            axi_wready  <= 1'b1;
            aw_wait_cnt <= 2'd0;
            w_wait_cnt  <= 2'd0;
            b_wait_cnt  <= 2'd0;
            axi_bvalid  <= 1'b0;
            axi_bresp   <= 2'b00;
            wr_txn_cnt  <= 0;
        end
        else begin
            case (wr_state)
                WR_IDLE: begin
                    // Kênh AW
                    if (aw_hs_now) begin
                        aw_captured <= 1'b1;
                        aw_addr_lat <= axi_awaddr;
                        axi_awready <= 1'b0;
                    end
                    else if (!aw_captured && axi_awvalid && !axi_awready) begin
                        if (aw_wait_cnt == 2'd0)
                            axi_awready <= 1'b1;
                        else
                            aw_wait_cnt <= aw_wait_cnt - 2'd1;
                    end

                    // Kênh W
                    if (w_hs_now) begin
                        w_captured <= 1'b1;
                        w_data_lat <= axi_wdata;
                        w_strb_lat <= axi_wstrb;
                        axi_wready <= 1'b0;
                    end
                    else if (!w_captured && axi_wvalid && !axi_wready) begin
                        if (w_wait_cnt == 2'd0)
                            axi_wready <= 1'b1;
                        else
                            w_wait_cnt <= w_wait_cnt - 2'd1;
                    end

                    // Khi cả AW và W đã handshake xong (cùng nhịp hoặc lệch nhịp)
                    if (aw_done_now && w_done_now) begin
                        wr_eff_addr = aw_hs_now ? axi_awaddr : aw_addr_lat;
                        wr_eff_data = w_hs_now  ? axi_wdata  : w_data_lat;
                        wr_eff_strb = w_hs_now  ? axi_wstrb  : w_strb_lat;

                        if (wr_eff_addr[31:12] == 20'h10010) begin
                            wr_old_word = dmem_mem[wr_eff_addr[9:2]];
                            if (wr_eff_strb[0]) wr_old_word[7:0]   = wr_eff_data[7:0];
                            if (wr_eff_strb[1]) wr_old_word[15:8]  = wr_eff_data[15:8];
                            if (wr_eff_strb[2]) wr_old_word[23:16] = wr_eff_data[23:16];
                            if (wr_eff_strb[3]) wr_old_word[31:24] = wr_eff_data[31:24];
                            dmem_mem[wr_eff_addr[9:2]] <= wr_old_word;
                            axi_bresp <= 2'b00;
                        end
                        else begin
                            axi_bresp <= 2'b10;
                        end

                        $display("[AXI-WR][DMEM] t=%0t addr=%h data=%h strb=%b (pattern=%0d)",
                                 $time, wr_eff_addr, wr_eff_data, wr_eff_strb, (wr_txn_cnt % 4));

                        aw_captured <= 1'b0;
                        w_captured  <= 1'b0;
                        aw_addr_lat <= wr_eff_addr; // Giữ lại để log nếu cần

                        if (b_wait_cnt == 2'd0) begin
                            axi_bvalid <= 1'b1;
                            wr_state   <= WR_RESP;
                        end
                        else begin
                            wr_state <= WR_WAIT_B;
                        end
                    end
                end

                WR_WAIT_B: begin
                    if (b_wait_cnt <= 2'd1) begin
                        axi_bvalid <= 1'b1;
                        wr_state   <= WR_RESP;
                    end
                    else begin
                        b_wait_cnt <= b_wait_cnt - 2'd1;
                    end
                end

                WR_RESP: begin
                    if (axi_bvalid && axi_bready) begin
                        axi_bvalid <= 1'b0;
                        wr_txn_cnt <= wr_txn_cnt + 1;

                        // Chọn mẫu handshake cho giao dịch ghi kế tiếp
                        case ((wr_txn_cnt + 1) % 4)
                            0: begin // Mẫu 0: AW và W cùng nhịp
                                axi_awready <= 1'b1;
                                axi_wready  <= 1'b1;
                                aw_wait_cnt <= 2'd0;
                                w_wait_cnt  <= 2'd0;
                                b_wait_cnt  <= 2'd0;
                            end
                            1: begin // Mẫu 1: AW trước, W trễ 2 chu kỳ
                                axi_awready <= 1'b1;
                                axi_wready  <= 1'b0;
                                aw_wait_cnt <= 2'd0;
                                w_wait_cnt  <= 2'd1;
                                b_wait_cnt  <= 2'd0;
                            end
                            2: begin // Mẫu 2: W trước, AW trễ 2 chu kỳ
                                axi_awready <= 1'b0;
                                axi_wready  <= 1'b1;
                                aw_wait_cnt <= 2'd1;
                                w_wait_cnt  <= 2'd0;
                                b_wait_cnt  <= 2'd0;
                            end
                            default: begin // Mẫu 3: Trễ cả AW, W và B
                                axi_awready <= 1'b0;
                                axi_wready  <= 1'b0;
                                aw_wait_cnt <= 2'd1;
                                w_wait_cnt  <= 2'd2;
                                b_wait_cnt  <= 2'd1;
                            end
                        endcase
                        wr_state <= WR_IDLE;
                    end
                end

                default: wr_state <= WR_IDLE;
            endcase
        end
    end

    // =========================================================================
    // 3. BỘ KIỂM TRA GIAO THỨC AXI4-LITE & KHÓA ARBITER RMW
    // =========================================================================
    reg        prev_ar_wait, prev_aw_wait, prev_w_wait;
    reg [31:0] prev_araddr,  prev_awaddr,  prev_wdata;
    reg [3:0]  prev_wstrb;
    integer    proto_err_cnt;
    integer    rmw_err_cnt;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            prev_ar_wait  <= 1'b0;
            prev_aw_wait  <= 1'b0;
            prev_w_wait   <= 1'b0;
            prev_araddr   <= 32'b0;
            prev_awaddr   <= 32'b0;
            prev_wdata    <= 32'b0;
            prev_wstrb    <= 4'b0;
            proto_err_cnt <= 0;
            rmw_err_cnt   <= 0;
        end
        else begin
            // Kiểm tra giữ ổn định kênh AR khi chưa có ARREADY
            if (prev_ar_wait) begin
                if (!axi_arvalid || (axi_araddr !== prev_araddr)) begin
                    $display("[ERROR][AXI-AR] t=%0t ARVALID/ARADDR thay doi truoc khi handshake!", $time);
                    proto_err_cnt <= proto_err_cnt + 1;
                end
            end

            // Kiểm tra giữ ổn định kênh AW khi chưa có AWREADY
            if (prev_aw_wait) begin
                if (!axi_awvalid || (axi_awaddr !== prev_awaddr)) begin
                    $display("[ERROR][AXI-AW] t=%0t AWVALID/AWADDR thay doi truoc khi handshake!", $time);
                    proto_err_cnt <= proto_err_cnt + 1;
                end
            end

            // Kiểm tra giữ ổn định kênh W khi chưa có WREADY
            if (prev_w_wait) begin
                if (!axi_wvalid || (axi_wdata !== prev_wdata) || (axi_wstrb !== prev_wstrb)) begin
                    $display("[ERROR][AXI-W] t=%0t WVALID/WDATA/WSTRB thay doi truoc khi handshake!", $time);
                    proto_err_cnt <= proto_err_cnt + 1;
                end
            end

            // Kiểm tra phản hồi RRESP/BRESP
            if (axi_rvalid && axi_rready && (axi_rresp !== 2'b00)) begin
                $display("[ERROR][AXI-R] t=%0t RRESP != OKAY (%b) tai addr=%h", $time, axi_rresp, rd_addr_lat);
                proto_err_cnt <= proto_err_cnt + 1;
            end
            if (axi_bvalid && axi_bready && (axi_bresp !== 2'b00)) begin
                $display("[ERROR][AXI-B] t=%0t BRESP != OKAY (%b)", $time, axi_bresp);
                proto_err_cnt <= proto_err_cnt + 1;
            end

            // Kiểm tra IMEM không được chen ngang khi DMEM đang thực hiện Store RMW
            if (dut.u_risc_v.dmem.active && dut.u_risc_v.dmem.MemRW_reg) begin
                if (axi_arvalid && axi_arready && (axi_araddr[31:12] == 20'h00400)) begin
                    $display("[ERROR][RMW] t=%0t IMEM chen ngang trong luc DMEM dang Store RMW!", $time);
                    rmw_err_cnt <= rmw_err_cnt + 1;
                end
            end
            
            
//            `ifndef POST_SYNTH
//            if (dut.u_risc_v.dmem.active && dut.u_risc_v.dmem.MemRW_reg) begin
//                if (axi_arvalid && axi_arready && (axi_araddr[31:12] == 20'h00400)) begin
//                    $display("[ERROR][RMW] t=%0t IMEM chen ngang trong luc DMEM dang Store RMW!", $time);
//                    rmw_err_cnt <= rmw_err_cnt + 1;
//                end
//            end
//            `endif
            prev_ar_wait <= axi_arvalid && !axi_arready;
            prev_araddr  <= axi_araddr;
            prev_aw_wait <= axi_awvalid && !axi_awready;
            prev_awaddr  <= axi_awaddr;
            prev_w_wait  <= axi_wvalid && !axi_wready;
            prev_wdata   <= axi_wdata;
            prev_wstrb   <= axi_wstrb;
        end
    end

    // =========================================================================
    // 4. TASK KIỂM TRA KẾT QUẢ & KỊCH BẢN CHẠY TESTBENCH
    // =========================================================================
    integer i;
    integer cyc;
    integer fail_cnt;

    task check_reg;
        input [4:0]  idx;
        input [31:0] expected;
        input [127:0] label;
        reg   [31:0] actual;
        begin
            actual = dut.u_risc_v.reg_file.rf[idx];
            if (actual === expected) begin
                $display("  [PASS] x%02d (%0s) = 0x%08h", idx, label, actual);
            end
            else begin
                $display("  [FAIL] x%02d (%0s) = 0x%08h (expected 0x%08h)", idx, label, actual, expected);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    task check_dmem;
        input integer word_idx;
        input [31:0]  expected;
        input [127:0] label;
        reg   [31:0]  actual;
        begin
            actual = dmem_mem[word_idx];
            if (actual === expected) begin
                $display("  [PASS] dmem[%0d] (%0s) = 0x%08h", word_idx, label, actual);
            end
            else begin
                $display("  [FAIL] dmem[%0d] (%0s) = 0x%08h (expected 0x%08h)", word_idx, label, actual, expected);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    // Tuỳ chọn xuất VCD nếu biên dịch với -DDUMP_VCD
    `ifdef DUMP_VCD
    initial begin
        $dumpfile("tb_RISCV_wrapper.vcd");
        $dumpvars(0, tb_RISCV_wrapper);
    end
    `endif

    initial begin
        fail_cnt = 0;

        // Khởi tạo bộ nhớ
        for (i = 0; i < 256; i = i + 1) begin
            imem_mem[i] = 32'h0000_0013; // NOP
            dmem_mem[i] = 32'h0000_0000;
        end

        // Dữ liệu ban đầu trong DMEM (0x1001_0000 .. 0x1001_0010)
        dmem_mem[0] = 32'h1234_5678; // 0x1001_0000
        dmem_mem[1] = 32'h80FF_7F01; // 0x1001_0004
        dmem_mem[2] = 32'hAABB_CCDD; // 0x1001_0008
        dmem_mem[3] = 32'h0000_0000; // 0x1001_000C
        dmem_mem[4] = 32'h0000_0000; // 0x1001_0010

        // Chương trình RV32I tại 0x0040_0000
        // --- Kịch bản 1: Instruction Fetch + ALU + Forwarding ---
        imem_mem[0]  = 32'h1001_00B7; // lui  x1, 0x10010      -> x1 = 0x1001_0000
        imem_mem[1]  = 32'h00A0_0113; // addi x2, x0, 10       -> x2 = 10
        imem_mem[2]  = 32'h0051_0193; // addi x3, x2, 5        -> x3 = 15 (EX->EX fwd)
        imem_mem[3]  = 32'h0031_0233; // add  x4, x2, x3       -> x4 = 25 (MEM->EX + EX->EX fwd)

        // --- Kịch bản 2: Load LW/LB/LBU/LH/LHU + Load-Use Hazard ---
        imem_mem[4]  = 32'h0000_A283; // lw   x5, 0(x1)        -> x5 = 0x1234_5678
        imem_mem[5]  = 32'h0012_8313; // addi x6, x5, 1        -> x6 = 0x1234_5679 (Load-Use)
        imem_mem[6]  = 32'h0060_8383; // lb   x7, 6(x1)        -> x7 = 0xFFFF_FFFF (sign-ext 0xFF)
        imem_mem[7]  = 32'h0070_C403; // lbu  x8, 7(x1)        -> x8 = 0x0000_0080 (zero-ext 0x80)
        imem_mem[8]  = 32'h0060_9483; // lh   x9, 6(x1)        -> x9 = 0xFFFF_80FF (sign-ext 0x80FF)
        imem_mem[9]  = 32'h0060_D503; // lhu  x10, 6(x1)       -> x10 = 0x0000_80FF (zero-ext 0x80FF)
        imem_mem[10] = 32'h0050_8583; // lb   x11, 5(x1)       -> x11 = 0x0000_007F (dương)

        // --- Kịch bản 3: Store RMW SW/SB/SH + AW/W độc lập + đọc kiểm chứng lại ---
        imem_mem[11] = 32'h0050_A623; // sw   x5, 12(x1)       -> dmem[3] = 0x1234_5678
        imem_mem[12] = 32'h0550_0613; // addi x12, x0, 0x55    -> x12 = 0x0000_0055
        imem_mem[13] = 32'h00C0_84A3; // sb   x12, 9(x1)       -> dmem[2] = 0xAABB_55DD (RMW)
        imem_mem[14] = 32'h0000_16B7; // lui  x13, 0x00001     -> x13 = 0x0000_1000
        imem_mem[15] = 32'h2346_8693; // addi x13, x13, 0x234  -> x13 = 0x0000_1234
        imem_mem[16] = 32'h00D0_9523; // sh   x13, 10(x1)      -> dmem[2] = 0x1234_55DD (RMW)
        imem_mem[17] = 32'h0080_A703; // lw   x14, 8(x1)       -> x14 = 0x1234_55DD
        imem_mem[18] = 32'h00C0_A783; // lw   x15, 12(x1)      -> x15 = 0x1234_5678

        // --- Kịch bản 4: Branch Taken + Flush khi có stall AXI ---
        imem_mem[19] = 32'h00F2_8463; // beq  x5, x15, +8      -> nhảy tới [21]
        imem_mem[20] = 32'h1EE0_0813; // addi x16, x0, 0x1EE   -> PHẢI bị flush (x16 == 0)
        imem_mem[21] = 32'h0770_0893; // addi x17, x0, 0x77    -> x17 = 0x0000_0077
        imem_mem[22] = 32'h0110_A823; // sw   x17, 16(x1)      -> dmem[4] = 0x0000_0077
        imem_mem[23] = 32'h0000_006F; // jal  x0, 0            -> dừng tại chỗ

        // Giữ Reset trong 3 chu kỳ
        $display("================================================================");
        $display(" BAT DAU MO PHONG tb_RISCV_wrapper (AXI4-Lite Core Test)");
        $display("================================================================");
        rst = 1'b1;
        repeat (3) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        // Chờ lệnh Store cuối ghi dmem_mem[4] == 0x0000_0077 hoặc timeout 800 chu kỳ
        cyc = 0;
        while ((dmem_mem[4] !== 32'h0000_0077) && (cyc < 800)) begin
            @(posedge clk);
            cyc = cyc + 1;
        end

        if (cyc >= 800) begin
            $display("[FAIL] TIMEOUT sau 800 chu ky! Core khong hoan thanh chuong trinh.");
            fail_cnt = fail_cnt + 1;
        end
        else begin
            $display("-> Hoan thanh chuong trinh tai chu ky thu %0d (t=%0t)", cyc, $time);
            // Chạy thêm 15 chu kỳ để kiểm tra vòng lặp jal x0, 0 và không có ghi sai nào thêm
            repeat (15) @(posedge clk);
        end

        $display("\n--- KIEM TRA THANH GHI (REGISTER FILE) ---");
        check_reg(5'd1,  32'h1001_0000, "lui base");
        check_reg(5'd2,  32'h0000_000A, "addi 10");
        check_reg(5'd3,  32'h0000_000F, "EX fwd");
        check_reg(5'd4,  32'h0000_0019, "MEM+EX fwd");
        check_reg(5'd5,  32'h1234_5678, "lw dmem[0]");
        check_reg(5'd6,  32'h1234_5679, "load-use");
        check_reg(5'd7,  32'hFFFF_FFFF, "lb sign");
        check_reg(5'd8,  32'h0000_0080, "lbu zero");
        check_reg(5'd9,  32'hFFFF_80FF, "lh sign");
        check_reg(5'd10, 32'h0000_80FF, "lhu zero");
        check_reg(5'd11, 32'h0000_007F, "lb pos");
        check_reg(5'd12, 32'h0000_0055, "addi 0x55");
        check_reg(5'd13, 32'h0000_1234, "lui+addi");
        check_reg(5'd14, 32'h1234_55DD, "lw after RMW");
        check_reg(5'd15, 32'h1234_5678, "lw dmem[3]");
        check_reg(5'd16, 32'h0000_0000, "branch flush");
        check_reg(5'd17, 32'h0000_0077, "branch target");

        $display("\n--- KIEM TRA BO NHO DU LIEU (DMEM) ---");
        check_dmem(0, 32'h1234_5678, "init word 0");
        check_dmem(1, 32'h80FF_7F01, "init word 1");
        check_dmem(2, 32'h1234_55DD, "after SB+SH RMW");
        check_dmem(3, 32'h1234_5678, "after SW");
        check_dmem(4, 32'h0000_0077, "final SW");

        $display("\n--- KIEM TRA GIAO THUC AXI4-LITE & ARBITER ---");
        $display("  So giao dich AXI Read  hoan tat : %0d", rd_txn_cnt);
        $display("  So giao dich AXI Write hoan tat : %0d", wr_txn_cnt);
        $display("  Loi giao thuc AXI4-Lite         : %0d", proto_err_cnt);
        $display("  Loi IMEM chen ngang Store RMW   : %0d", rmw_err_cnt);

        $display("================================================================");
        if ((fail_cnt == 0) && (proto_err_cnt == 0) && (rmw_err_cnt == 0))
            $display(" KET QUA CHUNG: PASS (Tat ca kiem tra thanh cong!)");
        else
            $display(" KET QUA CHUNG: FAIL (fail=%0d, proto=%0d, rmw=%0d)", fail_cnt, proto_err_cnt, rmw_err_cnt);
        $display("================================================================");

        $finish;
    end

endmodule
