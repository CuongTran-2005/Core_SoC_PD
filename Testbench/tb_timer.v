`timescale 1ns / 1ps
`include "timer_defs.v"

module tb_timer;

    // Tham so he thong: Tan so 50 MHz -> Chu ky clock = 20 ns
    localparam CLK_PERIOD = 20;

    reg          clk_i;
    reg          rst_i;

    // Tin hieu giao tiep AXI4-Lite
    reg          cfg_awvalid_i;
    reg  [31:0]  cfg_awaddr_i;
    reg          cfg_wvalid_i;
    reg  [31:0]  cfg_wdata_i;
    reg  [3:0]   cfg_wstrb_i;
    reg          cfg_bready_i;
    reg          cfg_arvalid_i;
    reg  [31:0]  cfg_araddr_i;
    reg          cfg_rready_i;

    wire         cfg_awready_o;
    wire         cfg_wready_o;
    wire         cfg_bvalid_o;
    wire [1:0]   cfg_bresp_o;
    wire         cfg_arready_o;
    wire         cfg_rvalid_o;
    wire [31:0]  cfg_rdata_o;
    wire [1:0]   cfg_rresp_o;
    wire         intr_o;

    // Bien thong kê và ho tro kiem tra
    integer      pass_count = 0;
    integer      fail_count = 0;
    reg  [31:0]  rd_val;
    reg  [31:0]  snap_val;
    integer      i;
    integer      irq_count;

    //-----------------------------------------------------------------
    // Khoi tao DUT (Device Under Test)
    //-----------------------------------------------------------------
    timer dut (
        .clk_i          (clk_i),
        .rst_i          (rst_i),
        .cfg_awvalid_i  (cfg_awvalid_i),
        .cfg_awaddr_i   (cfg_awaddr_i),
        .cfg_wvalid_i   (cfg_wvalid_i),
        .cfg_wdata_i    (cfg_wdata_i),
        .cfg_wstrb_i    (cfg_wstrb_i),
        .cfg_bready_i   (cfg_bready_i),
        .cfg_arvalid_i  (cfg_arvalid_i),
        .cfg_araddr_i   (cfg_araddr_i),
        .cfg_rready_i   (cfg_rready_i),

        .cfg_awready_o  (cfg_awready_o),
        .cfg_wready_o   (cfg_wready_o),
        .cfg_bvalid_o   (cfg_bvalid_o),
        .cfg_bresp_o    (cfg_bresp_o),
        .cfg_arready_o  (cfg_arready_o),
        .cfg_rvalid_o   (cfg_rvalid_o),
        .cfg_rdata_o    (cfg_rdata_o),
        .cfg_rresp_o    (cfg_rresp_o),
        .intr_o         (intr_o)
    );

    // Tao xung Clock 50 MHz
    initial begin
        clk_i = 1'b0;
        forever #(CLK_PERIOD / 2) clk_i = ~clk_i;
    end

    // Watchdog chong treo mô phong
    initial begin
        #500000;
        $display("[TIMEOUT] Mo phong vuot qua thoi gian gioi han!");
        $finish;
    end

    // Task check: tu dong kiem tra ket qua (self-checking)
    task check;
        input condition;
        input [8*80-1:0] msg;
        begin
            if (condition) begin
                pass_count = pass_count + 1;
                $display("[PASS] %0t ns | %0s", $time, msg);
            end else begin
                fail_count = fail_count + 1;
                $display("[FAIL] %0t ns | %0s", $time, msg);
            end
        end
    endtask

    // reset he thong.
    task reset_dut;
        begin
            rst_i         = 1'b1;
            cfg_awvalid_i = 1'b0;
            cfg_awaddr_i  = 32'h0;
            cfg_wvalid_i  = 1'b0;
            cfg_wdata_i   = 32'h0;
            cfg_wstrb_i   = 4'hF;
            cfg_bready_i  = 1'b0;
            cfg_arvalid_i = 1'b0;
            cfg_araddr_i  = 32'h0;
            cfg_rready_i  = 1'b0;
            repeat (4) @(posedge clk_i);
            #1;
            rst_i = 1'b0;
            repeat (2) @(posedge clk_i);
        end
    endtask

    // Task axi_write: ghi AXI4-Lite, gui dong thoi AW va W.
    task axi_write;
        input [31:0] addr;
        input [31:0] data;
        input [3:0]  strb;
        reg aw_done, w_done;
        begin
            @(posedge clk_i);
            cfg_awvalid_i <= 1'b1;
            cfg_awaddr_i  <= addr;
            cfg_wvalid_i  <= 1'b1;
            cfg_wdata_i   <= data;
            cfg_wstrb_i   <= strb;
            cfg_bready_i  <= 1'b1;

            aw_done = 1'b0;
            w_done  = 1'b0;

            while (!aw_done || !w_done) begin
                @(posedge clk_i);
                if (cfg_awvalid_i && cfg_awready_o) begin
                    aw_done = 1'b1;
                    cfg_awvalid_i <= 1'b0;
                end
                if (cfg_wvalid_i && cfg_wready_o) begin
                    w_done = 1'b1;
                    cfg_wvalid_i <= 1'b0;
                end
            end

            while (!cfg_bvalid_o) @(posedge clk_i);
            @(posedge clk_i);
            cfg_bready_i <= 1'b0;
            cfg_wstrb_i  <= 4'hF;
        end
    endtask

   // Task axi_write_addr_first: split write, dia chi (AW) den truoc du lieu (W).
    task axi_write_addr_first;
        input [31:0] addr;
        input [31:0] data;
        input integer delay_cycles;
        begin
            @(posedge clk_i);
            cfg_awvalid_i <= 1'b1;
            cfg_awaddr_i  <= addr;
            cfg_bready_i  <= 1'b1;

            @(posedge clk_i);
            while (!cfg_awready_o) @(posedge clk_i);
            cfg_awvalid_i <= 1'b0;

            repeat (delay_cycles) @(posedge clk_i);
            cfg_wvalid_i <= 1'b1;
            cfg_wdata_i  <= data;
            cfg_wstrb_i  <= 4'hF;

            @(posedge clk_i);
            while (!cfg_wready_o) @(posedge clk_i);
            cfg_wvalid_i <= 1'b0;

            while (!cfg_bvalid_o) @(posedge clk_i);
            @(posedge clk_i);
            cfg_bready_i <= 1'b0;
        end
    endtask

    // Task axi_write_data_first: split write, du lieu (W) den truoc dia chi (AW).
    task axi_write_data_first;
        input [31:0] addr;
        input [31:0] data;
        input integer delay_cycles;
        begin
            @(posedge clk_i);
            cfg_wvalid_i <= 1'b1;
            cfg_wdata_i  <= data;
            cfg_wstrb_i  <= 4'hF;
            cfg_bready_i <= 1'b1;

            @(posedge clk_i);
            while (!cfg_wready_o) @(posedge clk_i);
            cfg_wvalid_i <= 1'b0;

            repeat (delay_cycles) @(posedge clk_i);
            cfg_awvalid_i <= 1'b1;
            cfg_awaddr_i  <= addr;

            @(posedge clk_i);
            while (!cfg_awready_o) @(posedge clk_i);
            cfg_awvalid_i <= 1'b0;

            while (!cfg_bvalid_o) @(posedge clk_i);
            @(posedge clk_i);
            cfg_bready_i <= 1'b0;
        end
    endtask

    // Task axi_read: doc AXI4-Lite, ho tro chen tre RREADY de test backpressure.
    task axi_read;
        input  [31:0]  addr;
        output [31:0]  data_out;
        input  integer rready_delay;
        begin
            @(posedge clk_i);
            cfg_arvalid_i <= 1'b1;
            cfg_araddr_i  <= addr;
            cfg_rready_i  <= (rready_delay == 0) ? 1'b1 : 1'b0;

            @(posedge clk_i);
            while (!cfg_arready_o) @(posedge clk_i);
            cfg_arvalid_i <= 1'b0;

            if (rready_delay > 0) begin
                repeat (rready_delay) @(posedge clk_i);
                cfg_rready_i <= 1'b1;
            end

            while (!cfg_rvalid_o) @(posedge clk_i);
            data_out = cfg_rdata_o;
            @(posedge clk_i);
            cfg_rready_i <= 1'b0;
        end
    endtask

    initial begin
        $dumpfile("tb_timer.vcd");
        $dumpvars(0, tb_timer);

        $display("==================================================================");
        $display("      BAT DAU VERIFY MODULE TIMER (AXI4-LITE) - 50 MHz");
        $display("==================================================================");

        // TC1: Kiem tra gia tri mac dinh sau reset
        $display("\n--- TC1: Kiem tra gia tri mac dinh sau Reset ---");
        reset_dut();
        check(intr_o === 1'b0, "TC1.1: intr_o == 0 sau reset");

        axi_read({24'h0, `TIMER_CTRL0}, rd_val, 0);
        check(rd_val === 32'h0, "TC1.2: TIMER_CTRL0 == 0 sau reset");

        axi_read({24'h0, `TIMER_CMP0}, rd_val, 0);
        check(rd_val === 32'h0, "TC1.3: TIMER_CMP0 == 0 sau reset");

        axi_read({24'h0, `TIMER_VAL0}, rd_val, 0);
        check(rd_val === 32'h0, "TC1.4: TIMER_VAL0 == 0 sau reset");

        axi_read({24'h0, `TIMER_CTRL1}, rd_val, 0);
        check(rd_val === 32'h0, "TC1.5: TIMER_CTRL1 == 0 sau reset");

        axi_read({24'h0, `TIMER_CMP1}, rd_val, 0);
        check(rd_val === 32'h0, "TC1.6: TIMER_CMP1 == 0 sau reset");

        axi_read({24'h0, `TIMER_VAL1}, rd_val, 0);
        check(rd_val === 32'h0, "TC1.7: TIMER_VAL1 == 0 sau reset");

        // TC2: Doc/ghi thanh ghi, bit masking va dia chi khong hop le
        $display("\n--- TC2: Doc/Ghi thanh ghi, Bit Masking & Unmapped Address ---");
        axi_write({24'h0, `TIMER_CMP0}, 32'hDEAD_BEEF, 4'hF);
        axi_read({24'h0, `TIMER_CMP0}, rd_val, 0);
        check(rd_val === 32'hDEAD_BEEF && cfg_bresp_o === 2'b00, "TC2.1: Ghi/Doc TIMER_CMP0 = 0xDEADBEEF");

        // Kiem tra ghi voi wstrb khac 0xF: RTL van ghi nguyen word 32-bit
        axi_write({24'h0, `TIMER_CMP1}, 32'h1234_5678, 4'h1);
        axi_read({24'h0, `TIMER_CMP1}, rd_val, 0);
        check(rd_val === 32'h1234_5678, "TC2.2: Ghi/Doc TIMER_CMP1 = 0x12345678 (wstrb=4'h1)");

        // Ghi toan 1 vao CTRL0 va CTRL1: chi bit [2:1] (0x6) duoc giu lai
        axi_write({24'h0, `TIMER_CTRL0}, 32'hFFFF_FFFF, 4'hF);
        axi_read({24'h0, `TIMER_CTRL0}, rd_val, 0);
        check(rd_val === 32'h0000_0006, "TC2.3: TIMER_CTRL0 chi luu bit [2:1] = 0x6");
        axi_write({24'h0, `TIMER_CTRL0}, 32'h0, 4'hF);

        axi_write({24'h0, `TIMER_CTRL1}, 32'hFFFF_FFFF, 4'hF);
        axi_read({24'h0, `TIMER_CTRL1}, rd_val, 0);
        check(rd_val === 32'h0000_0006, "TC2.4: TIMER_CTRL1 chi luu bit [2:1] = 0x6");
        axi_write({24'h0, `TIMER_CTRL1}, 32'h0, 4'hF);

        // Doc cac dia chi trong (0x00, 0x04, 0x20) phai tra ve 0
        axi_read(32'h00, rd_val, 0);
        check(rd_val === 32'h0 && cfg_rresp_o === 2'b00, "TC2.5: Doc dia chi unmapped 0x00 tra ve 0");
        axi_read(32'h04, rd_val, 0);
        check(rd_val === 32'h0 && cfg_rresp_o === 2'b00, "TC2.6: Doc dia chi unmapped 0x04 tra ve 0");
        axi_read(32'h20, rd_val, 0);
        check(rd_val === 32'h0 && cfg_rresp_o === 2'b00, "TC2.7: Doc dia chi unmapped 0x20 tra ve 0");

        // TC3: Cac truong hop dac biet cua AXI4-Lite (split write, backpressure, tranh chap R/W)
        $display("\n--- TC3: AXI4-Lite Split Transactions & Arbitration ---");
        // 3a: AWVALID den truoc WVALID 3 chu ky
        axi_write_addr_first({24'h0, `TIMER_CMP0}, 32'hCAFE_BABE, 3);
        axi_read({24'h0, `TIMER_CMP0}, rd_val, 0);
        check(rd_val === 32'hCAFE_BABE, "TC3.1: AXI Split Write (AW truoc W): CMP0 = 0xCAFEBABE");

        // 3b: WVALID den truoc AWVALID 3 chu ky, cong tre RREADY 4 chu ky
        axi_write_data_first({24'h0, `TIMER_CMP1}, 32'hA5A5_5A5A, 3);
        axi_read({24'h0, `TIMER_CMP1}, rd_val, 4);
        check(rd_val === 32'hA5A5_5A5A, "TC3.2: AXI Split Write (W truoc AW) + RREADY delay: CMP1 = 0xA5A55A5A");

        // 3c. Tranh chap Read va Write cung chu ky, Read phai duoc uu tien truoc
        @(posedge clk_i);
        cfg_arvalid_i <= 1'b1;
        cfg_araddr_i  <= {24'h0, `TIMER_CMP0};
        cfg_rready_i  <= 1'b1;
        cfg_awvalid_i <= 1'b1;
        cfg_awaddr_i  <= {24'h0, `TIMER_CMP0};
        cfg_wvalid_i  <= 1'b1;
        cfg_wdata_i   <= 32'h1111_2222;
        cfg_bready_i  <= 1'b1;

        #1;
        check(cfg_arready_o === 1'b1 && cfg_awready_o === 1'b0 && cfg_wready_o === 1'b0,
              "TC3.3: Uu tien Read khi ARVALID & AWVALID cung len 1");

        @(posedge clk_i);
        cfg_arvalid_i <= 1'b0; // Doc xong thi Write nhuong bus va hoan tat

        while (!(cfg_awvalid_i && cfg_awready_o)) @(posedge clk_i);
        cfg_awvalid_i <= 1'b0;
        cfg_wvalid_i  <= 1'b0;
        while (!cfg_bvalid_o) @(posedge clk_i);
        @(posedge clk_i);
        cfg_bready_i <= 1'b0;
        cfg_rready_i <= 1'b0;

        axi_read({24'h0, `TIMER_CMP0}, rd_val, 0);
        check(rd_val === 32'h1111_2222, "TC3.4: Write hoan tat dung sau khi Read xong: CMP0 = 0x11112222");

        // TC4: Preload VAL0/VAL1, dem tien, tam dung (Pause) va tiep tuc (Resume)
        $display("\n--- TC4: Preload VAL0/VAL1, Dem tien, Pause & Resume ---");
        reset_dut();
        axi_write({24'h0, `TIMER_VAL0}, 32'd100, 4'hF);
        axi_write({24'h0, `TIMER_VAL1}, 32'd500, 4'hF);
        repeat (2) @(posedge clk_i);

        axi_read({24'h0, `TIMER_VAL0}, rd_val, 0);
        check(rd_val === 32'd100, "TC4.1: Preload VAL0 = 100 khi ENABLE=0");
        axi_read({24'h0, `TIMER_VAL1}, rd_val, 0);
        check(rd_val === 32'd500, "TC4.2: Preload VAL1 = 500 khi ENABLE=0");

        // Bat ca 2 kenh dem (ENABLE=1, INTR=0 -> 32'h4)
        axi_write({24'h0, `TIMER_CTRL0}, 32'h4, 4'hF);
        axi_write({24'h0, `TIMER_CTRL1}, 32'h4, 4'hF);
        repeat (10) @(posedge clk_i);

        // Tam dung ca 2 kenh (Pause)
        axi_write({24'h0, `TIMER_CTRL0}, 32'h0, 4'hF);
        axi_write({24'h0, `TIMER_CTRL1}, 32'h0, 4'hF);
        repeat (3) @(posedge clk_i);

        axi_read({24'h0, `TIMER_VAL0}, snap_val, 0);
        check(snap_val > 32'd100, "TC4.3: Timer 0 da dem tang khi ENABLE=1");
        repeat (5) @(posedge clk_i);
        axi_read({24'h0, `TIMER_VAL0}, rd_val, 0);
        check(rd_val === snap_val, "TC4.4: Timer 0 dung yen gia tri khi Pause (ENABLE=0)");

        axi_read({24'h0, `TIMER_VAL1}, snap_val, 0);
        check(snap_val > 32'd500, "TC4.5: Timer 1 da dem tang khi ENABLE=1");
        repeat (5) @(posedge clk_i);
        axi_read({24'h0, `TIMER_VAL1}, rd_val, 0);
        check(rd_val === snap_val, "TC4.6: Timer 1 dung yen gia tri khi Pause (ENABLE=0)");

        // =============================================================
        // TC5: Compare match va tao xung ngat intr_o
        // =============================================================
        $display("\n--- TC5: Compare Match & Xung ngat intr_o (Timer 0 & Timer 1) ---");
        // 5a. Timer 0
        reset_dut();
        axi_write({24'h0, `TIMER_CMP0}, 32'd10, 4'hF);
        axi_write({24'h0, `TIMER_VAL0}, 32'd0,  4'hF);
        repeat (2) @(posedge clk_i);
        axi_write({24'h0, `TIMER_CTRL0}, 32'h6, 4'hF); // ENABLE=1, INTR=1

        irq_count = 0;
        for (i = 0; i < 20; i = i + 1) begin
            @(posedge clk_i);
            #1;
            if (intr_o === 1'b1) begin
                irq_count = irq_count + 1;
                check(dut.timer0_value_q === 32'd11, "TC5.1: Timer 0 kich ngat dung thoi diem VAL0 == CMP0 (10)");
            end
        end
        check(irq_count === 1, "TC5.2: Timer 0 phat dung 1 xung don intr_o");

        // 5b. Timer 1
        reset_dut();
        axi_write({24'h0, `TIMER_CMP1}, 32'd12, 4'hF);
        axi_write({24'h0, `TIMER_VAL1}, 32'd0,  4'hF);
        repeat (2) @(posedge clk_i);
        axi_write({24'h0, `TIMER_CTRL1}, 32'h6, 4'hF); // ENABLE=1, INTR=1

        irq_count = 0;
        for (i = 0; i < 22; i = i + 1) begin
            @(posedge clk_i);
            #1;
            if (intr_o === 1'b1) begin
                irq_count = irq_count + 1;
                check(dut.timer1_value_q === 32'd13, "TC5.3: Timer 1 kich ngat dung thoi diem VAL1 == CMP1 (12)");
            end
        end
        check(irq_count === 1, "TC5.4: Timer 1 phat dung 1 xung don intr_o");

        // TC6: Che ngat (INTR=0) va dung tai diem compare (ENABLE=0)
        $display("\n--- TC6: Che ngat (INTR=0) & Dung tai Compare (ENABLE=0) ---");
        reset_dut();
        // 6a. ENABLE=1 nhung INTR=0 thi khong duoc phat ngat
        axi_write({24'h0, `TIMER_CMP0}, 32'd5, 4'hF);
        axi_write({24'h0, `TIMER_CTRL0}, 32'h4, 4'hF);
        irq_count = 0;
        for (i = 0; i < 12; i = i + 1) begin
            @(posedge clk_i);
            #1;
            if (intr_o === 1'b1) irq_count = irq_count + 1;
        end
        check(irq_count === 0, "TC6.1: Khong phat ngat khi INTR=0 du VAL0 da vuot qua CMP0");

        // 6b. VAL0 == CMP0, INTR=1 nhung ENABLE=0 thi khong duoc phat ngat
        axi_write({24'h0, `TIMER_CTRL0}, 32'h0, 4'hF);
        axi_write({24'h0, `TIMER_VAL0}, 32'd20, 4'hF);
        axi_write({24'h0, `TIMER_CMP0}, 32'd20, 4'hF);
        repeat (2) @(posedge clk_i);
        axi_write({24'h0, `TIMER_CTRL0}, 32'h2, 4'hF); // ENABLE=0, INTR=1
        irq_count = 0;
        for (i = 0; i < 10; i = i + 1) begin
            @(posedge clk_i);
            #1;
            if (intr_o === 1'b1) irq_count = irq_count + 1;
        end
        check(irq_count === 0, "TC6.2: Khong phat ngat khi VAL0 == CMP0 nhung Timer dang tat");

        // TC7: Cap nhat VAL0 va CMP0 ngay trong luc timer dang chay
        $display("\n--- TC7: Cap nhat VAL0 & CMP0 On-the-Fly khi dang chay ---");
        reset_dut();
        axi_write({24'h0, `TIMER_CMP0}, 32'd100, 4'hF);
        axi_write({24'h0, `TIMER_CTRL0}, 32'h6,  4'hF); 
        repeat (5) @(posedge clk_i);

        // Ghi de VAL0 = 85 va ha CMP0 = 98 ngay luc dang dem
        axi_write({24'h0, `TIMER_VAL0}, 32'd85, 4'hF);
        axi_write({24'h0, `TIMER_CMP0}, 32'd98, 4'hF);

        irq_count = 0;
        for (i = 0; i < 20; i = i + 1) begin
            @(posedge clk_i);
            #1;
            if (intr_o === 1'b1) irq_count = irq_count + 1;
        end
        check(irq_count === 1, "TC7.1: Ghi de VAL0/CMP0 luc dang chay van kich ngat chinh xac");

        // TC8: Tran bo dem 32-bit (0xFFFFFFFF -> 0x00000000)
        $display("\n--- TC8: Tran bo dem 32-bit (Rollover) ---");
        reset_dut();
        axi_write({24'h0, `TIMER_VAL0}, 32'hFFFF_FFFC, 4'hF);
        axi_write({24'h0, `TIMER_CMP0}, 32'h0000_0001, 4'hF);
        repeat (2) @(posedge clk_i);
        axi_write({24'h0, `TIMER_CTRL0}, 32'h6, 4'hF);

        irq_count = 0;
        for (i = 0; i < 12; i = i + 1) begin
            @(posedge clk_i);
            #1;
            if (intr_o === 1'b1) irq_count = irq_count + 1;
        end
        check(irq_count === 1, "TC8.1: Timer 0 tran qua 0xFFFFFFFF ve 0 va kich ngat tai 0x1");

        // TC9: Chay dong thoi ca 2 kenh va ngat trung chu ky clock
        $display("\n--- TC9: Chay song song Timer 0 & Timer 1 + Ngat dong thoi ---");
        // 9a. Hai kenh cham nguong o 2 thoi diem khac nhau
        reset_dut();
        axi_write({24'h0, `TIMER_CMP0}, 32'd6,  4'hF);
        axi_write({24'h0, `TIMER_CMP1}, 32'd14, 4'hF);
        axi_write({24'h0, `TIMER_CTRL0}, 32'h6, 4'hF);
        axi_write({24'h0, `TIMER_CTRL1}, 32'h6, 4'hF);

        irq_count = 0;
        for (i = 0; i < 25; i = i + 1) begin
            @(posedge clk_i);
            #1;
            if (intr_o === 1'b1) irq_count = irq_count + 1;
        end
        check(irq_count === 2, "TC9.1: Timer 0 & Timer 1 chay song song phat du 2 xung IRQ doc lap");

        // 9b. Hai kenh cham nguong tai cung 1 chu ky clock (OR-gate IRQ)
        reset_dut();
        axi_write({24'h0, `TIMER_CMP0}, 32'd15, 4'hF);
        axi_write({24'h0, `TIMER_CMP1}, 32'd15, 4'hF);
        axi_write({24'h0, `TIMER_VAL0}, 32'd10, 4'hF);
        axi_write({24'h0, `TIMER_VAL1}, 32'd10, 4'hF);
        repeat (2) @(posedge clk_i);
        axi_write({24'h0, `TIMER_CTRL0}, 32'h6, 4'hF);
        axi_write({24'h0, `TIMER_CTRL1}, 32'h6, 4'hF);

        irq_count = 0;
        for (i = 0; i < 12; i = i + 1) begin
            @(posedge clk_i);
            #1;
            if (intr_o === 1'b1) irq_count = irq_count + 1;
        end
        check(irq_count === 1, "TC9.2: Hai kenh cham nguong cung luc van xuat xung intr_o sach");

        // TC10: Reset dot ngot khi ca 2 timer dang chay (mid-operation reset)
        $display("\n--- TC10: Mid-operation Reset ---");
        reset_dut();
        check(intr_o === 1'b0, "TC10.1: intr_o == 0 sau mid-operation reset");
        axi_read({24'h0, `TIMER_VAL0}, rd_val, 0);
        check(rd_val === 32'h0, "TC10.2: VAL0 ve 0 ngay lap tuc khi reset giua chung");
        axi_read({24'h0, `TIMER_VAL1}, rd_val, 0);
        check(rd_val === 32'h0, "TC10.3: VAL1 ve 0 ngay lap tuc khi reset giua chung");

       
        $display("\n==================================================================");
        $display("      KET QUA VERIFY TIMER: PASS = %0d | FAIL = %0d", pass_count, fail_count);
        $display("==================================================================");
        if (fail_count == 0)
            $display("      >>> TAT CA 37 KIEM TRA DEU PASS 100%%! <<<");
        else
            $display("      >>> CO LOI XAY RA, KIEM TRA LAI WAVEFORM! <<<");

        $finish;
    end

endmodule