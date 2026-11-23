`timescale 1ns/1ps
// =============================================================================
// Testbench: core_soc  (AXI4-Lite dist + IRQ ctrl / Timer / UART / SPI / GPIO /
//                       SRAM / Accelerator / EXT3)
//
//  TB đóng vai "core": một AXI4-Lite master BFM nối vào cổng inport_*.
//  - Kiểm tra từng ngoại vi qua thanh ghi + chân ngoài (uart/spi/gpio/ext3/irq)
//  - Mô hình slave ngoài cho cổng ext3_cfg_* (có SLVERR, độ trễ thay đổi)
//  - Mô hình SPI slave, UART monitor/transmitter, GPIO driver
//  - Kiểm tra AW/W đến lệch thứ tự, backpressure ở B/R, xen kẽ ngoại vi (random)
//  - Monitor giao thức ở inport_* và ext3_cfg_*
//
//  Chạy:  iverilog -g2012 -o sim.vvp tb_core_soc.v core_soc.v axi4lite_dist.v \
//             irq_ctrl.v timer.v uart_lite.v spi_lite.v gpio.v \
//             axi4lite_sram_wrapper.v axi4lite_accel_wrapper.v   (+ file con của chúng)
//         vvp sim.vvp [+VERBOSE]
// =============================================================================
module tb_core_soc;

    // ---------------- Tham số (khớp với axi4lite_dist: chọn cổng bằng addr[26:24]) --------
    parameter CLK_FREQ    = 50000000;
    parameter BAUDRATE    = 1000000;
    parameter C_SCK_RATIO = 50;

    parameter IRQ_BASE   = 32'h0000_0000;
    parameter TMR_BASE   = 32'h0100_0000;
    parameter UART_BASE  = 32'h0200_0000;
    parameter SPI_BASE   = 32'h0300_0000;
    parameter GPIO_BASE  = 32'h0400_0000;
    parameter SRAM_BASE  = 32'h0500_0000;
    parameter ACCEL_BASE = 32'h0600_0000;
    parameter EXT3_BASE  = 32'h0700_0000;

    parameter SRAM_WORDS     = 64;   // số từ SRAM đem ra test (<= dung lượng SRAM thật)
    parameter ACCEL_RW_CHECK = 0;    // 1: accel có thanh ghi R/W tại ACCEL_REG_OFS -> kiểm tra readback
    parameter ACCEL_REG_OFS  = 32'h0;
    parameter TIMEOUT_CYC    = 2000000;

    // ---------------- Clock / reset ----------------
    reg clk_i, rst_i;
    initial clk_i = 1'b0;
    always #(1000000000/CLK_FREQ/2) clk_i = ~clk_i;
    wire clk = clk_i;

    // ---------------- Tín hiệu DUT ----------------
    reg         inport_awvalid, inport_wvalid, inport_bready, inport_arvalid, inport_rready;
    reg  [31:0] inport_awaddr, inport_wdata, inport_araddr;
    reg  [3:0]  inport_wstrb;
    wire        inport_awready, inport_wready, inport_bvalid, inport_arready, inport_rvalid;
    wire [1:0]  inport_bresp, inport_rresp;
    wire [31:0] inport_rdata;

    reg         spi_miso;
    wire        spi_clk, spi_mosi;  wire [7:0] spi_cs;
    reg         uart_rx_drv, uart_lb;
    wire        uart_tx;
    wire        uart_rx = uart_lb ? uart_tx : uart_rx_drv;
    reg  [31:0] gpio_input;
    wire [31:0] gpio_output, gpio_oe;
    wire        intr;

    reg         ext3_awready, ext3_wready, ext3_bvalid, ext3_arready, ext3_rvalid, ext3_irq;
    reg  [1:0]  ext3_bresp, ext3_rresp;
    reg  [31:0] ext3_rdata;
    wire        ext3_awvalid, ext3_wvalid, ext3_bready, ext3_arvalid, ext3_rready;
    wire [31:0] ext3_awaddr, ext3_wdata, ext3_araddr;
    wire [3:0]  ext3_wstrb;

    core_soc #(.CLK_FREQ(CLK_FREQ), .BAUDRATE(BAUDRATE), .C_SCK_RATIO(C_SCK_RATIO)) dut (
        .clk_i(clk_i), .rst_i(rst_i),
        .inport_awvalid_i(inport_awvalid), .inport_awaddr_i(inport_awaddr),
        .inport_wvalid_i(inport_wvalid),   .inport_wdata_i(inport_wdata), .inport_wstrb_i(inport_wstrb),
        .inport_bready_i(inport_bready),
        .inport_arvalid_i(inport_arvalid), .inport_araddr_i(inport_araddr), .inport_rready_i(inport_rready),
        .spi_miso_i(spi_miso), .uart_rx_i(uart_rx), .gpio_input_i(gpio_input),
        .ext3_cfg_awready_i(ext3_awready), .ext3_cfg_wready_i(ext3_wready),
        .ext3_cfg_bvalid_i(ext3_bvalid),   .ext3_cfg_bresp_i(ext3_bresp),
        .ext3_cfg_arready_i(ext3_arready), .ext3_cfg_rvalid_i(ext3_rvalid),
        .ext3_cfg_rdata_i(ext3_rdata),     .ext3_cfg_rresp_i(ext3_rresp),
        .ext3_irq_i(ext3_irq),
        .intr_o(intr),
        .inport_awready_o(inport_awready), .inport_wready_o(inport_wready),
        .inport_bvalid_o(inport_bvalid),   .inport_bresp_o(inport_bresp),
        .inport_arready_o(inport_arready), .inport_rvalid_o(inport_rvalid),
        .inport_rdata_o(inport_rdata),     .inport_rresp_o(inport_rresp),
        .spi_clk_o(spi_clk), .spi_mosi_o(spi_mosi), .spi_cs_o(spi_cs),
        .uart_tx_o(uart_tx),
        .gpio_output_o(gpio_output), .gpio_output_enable_o(gpio_oe),
        .ext3_cfg_awvalid_o(ext3_awvalid), .ext3_cfg_awaddr_o(ext3_awaddr),
        .ext3_cfg_wvalid_o(ext3_wvalid),   .ext3_cfg_wdata_o(ext3_wdata), .ext3_cfg_wstrb_o(ext3_wstrb),
        .ext3_cfg_bready_o(ext3_bready),
        .ext3_cfg_arvalid_o(ext3_arvalid), .ext3_cfg_araddr_o(ext3_araddr), .ext3_cfg_rready_o(ext3_rready)
    );

    // ---------------- Biến chung ----------------
    integer errors, checks, verbose, cyc, seed, dummy;
    reg     finished;

    task fail;
        input [8*56-1:0] msg;
        begin errors = errors + 1; $display("[%0t] ERROR: %0s", $time, msg); end
    endtask
    task fail_a;
        input [8*40-1:0] msg; input [31:0] a;
        begin errors = errors + 1; $display("[%0t] ERROR: %0s (addr=%h)", $time, msg, a); end
    endtask
    task summary;
        begin
            $display("== %0d chu ky, %0d phep kiem tra ==", cyc, checks);
            if (errors == 0) $display("*** TEST PASSED ***");
            else             $display("*** TEST FAILED: %0d loi ***", errors);
        end
    endtask
    task fatal;
        input [8*56-1:0] msg;
        begin fail(msg); summary; $finish; end
    endtask
    task tstart; input [8*48-1:0] nm; begin $display("--- %0s", nm); end endtask

    // =========================================================================
    // AXI4-Lite master BFM
    //   mode: 0 = AW và W cùng lúc, 1 = AW trước (W trễ 4 clk), 2 = W trước (AW trễ 4 clk)
    //   b_delay / rd_delay: số clk trễ trước khi bật bready / rready (tạo backpressure)
    // =========================================================================
    integer b_delay, rd_delay;
    localparam BUS_LIM = 3000;

    task axi_wr;
        input [31:0] a, d; input [3:0] s; input integer mode; output [1:0] resp;
        integer ta, tw, tb;
        begin
            ta = 0; tw = 0; tb = 0;
            if (mode == 2) mode =1;
            fork
                begin : AW_P
                    if (mode == 2) repeat (4) @(posedge clk);
                    inport_awaddr <= a; inport_awvalid <= 1'b1;
                    @(posedge clk);
                    while (!inport_awready && ta < BUS_LIM) begin @(posedge clk); ta = ta + 1; end
                    inport_awvalid <= 1'b0;
                    // inport_wdata <= d; inport_wstrb <= s; inport_wvalid <= 1'b1;
                    // @(posedge clk);
                    // while (!inport_wready && tw < BUS_LIM) begin @(posedge clk); tw = tw + 1; end
                    // inport_wvalid <= 1'b0;
                end
                begin : W_P
                    if (mode == 1) repeat (4) @(posedge clk);
                    inport_wdata <= d; inport_wstrb <= s; inport_wvalid <= 1'b1;
                    @(posedge clk);
                    while (!inport_wready && tw < BUS_LIM) begin @(posedge clk); tw = tw + 1; end
                    inport_wvalid <= 1'b0;
                end
            join
            if (ta >= BUS_LIM || tw >= BUS_LIM) fatal("TIMEOUT: awready/wready khong len");
            repeat (b_delay) @(posedge clk);
            inport_bready <= 1'b1;
            @(posedge clk);
            while (!inport_bvalid && tb < BUS_LIM) begin @(posedge clk); tb = tb + 1; end
            if (tb >= BUS_LIM) fatal("TIMEOUT: bvalid khong len");
            resp = inport_bresp;
            inport_bready <= 1'b0;
        end
    endtask

    task axi_rd;
        input [31:0] a; output [31:0] d; output [1:0] resp;
        integer ta, tr;
        begin
            ta = 0; tr = 0;
            inport_araddr <= a; inport_arvalid <= 1'b1;
            @(posedge clk);
            while (!inport_arready && ta < BUS_LIM) begin @(posedge clk); ta = ta + 1; end
            if (ta >= BUS_LIM) fatal("TIMEOUT: arready khong len");
            inport_arvalid <= 1'b0;
            repeat (rd_delay) @(posedge clk);
            inport_rready <= 1'b1;
            @(posedge clk);
            while (!inport_rvalid && tr < BUS_LIM) begin @(posedge clk); tr = tr + 1; end
            if (tr >= BUS_LIM) fatal("TIMEOUT: rvalid khong len");
            d = inport_rdata; resp = inport_rresp;
            inport_rready <= 1'b0;
        end
    endtask

    // ---- tác vụ mức cao: kiểm tra response = OKAY ----
    task wr;   input [31:0] a, d; reg [1:0] r;
        begin axi_wr(a, d, 4'hF, 0, r); if (r !== 2'b00) fail_a("BRESP != OKAY", a); end endtask
    task wrs;  input [31:0] a, d; input [3:0] s; input integer mode; reg [1:0] r;
        begin axi_wr(a, d, s, mode, r); if (r !== 2'b00) fail_a("BRESP != OKAY", a); end endtask
    task rd;   input [31:0] a; output [31:0] d; reg [1:0] r;
        begin axi_rd(a, d, r); if (r !== 2'b00) fail_a("RRESP != OKAY", a); end endtask
    task chk;  input [31:0] a, e; input [8*40-1:0] nm; reg [31:0] d;
        begin
            rd(a, d); checks = checks + 1;
            if (d !== e) begin errors = errors + 1;
                $display("[%0t] FAIL %0s @%h: got=%h exp=%h", $time, nm, a, d, e); end
        end endtask
    task chkm; input [31:0] a, e, m; input [8*40-1:0] nm; reg [31:0] d;
        begin
            rd(a, d); checks = checks + 1;
            if ((d & m) !== (e & m)) begin errors = errors + 1;
                $display("[%0t] FAIL %0s @%h: got=%h exp=%h mask=%h", $time, nm, a, d, e, m); end
        end endtask
    task chk_sig; input cond; input [8*56-1:0] nm;
        begin checks = checks + 1; if (cond !== 1'b1) fail(nm); end endtask

    // =========================================================================
    // Monitor giao thức: inport_*  (đầu ra của dist) và ext3_cfg_* (đầu ra của dist)
    // =========================================================================
    reg        rv_hold, bv_hold, x_rep, ea_hold, ew_hold, er_hold, ex_rep;
    reg [31:0] rd_prev, ea_a, ew_d, er_a; reg [1:0] rr_prev, br_prev; reg [3:0] ew_s;
    integer    aw_hs, w_hs, b_hs, ar_hs, r_hs;

    always @(posedge clk) begin
        if (rst_i) begin
            rv_hold <= 0; bv_hold <= 0; x_rep <= 0; ea_hold <= 0; ew_hold <= 0; er_hold <= 0; ex_rep <= 0;
            aw_hs = 0; w_hs = 0; b_hs = 0; ar_hs = 0; r_hs = 0;
        end else begin
            // R/B: giữ ổn định cho đến khi master nhận
            if (rv_hold && (inport_rvalid !== 1'b1 || inport_rdata !== rd_prev || inport_rresp !== rr_prev))
                fail("inport R: rvalid/rdata/rresp doi khi rready=0");
            if (bv_hold && (inport_bvalid !== 1'b1 || inport_bresp !== br_prev))
                fail("inport B: bvalid/bresp doi khi bready=0");
            rv_hold <= (inport_rvalid === 1'b1) && !inport_rready;
            bv_hold <= (inport_bvalid === 1'b1) && !inport_bready;
            rd_prev <= inport_rdata; rr_prev <= inport_rresp; br_prev <= inport_bresp;
            // X trên các tín hiệu handshake (báo 1 lần)
            if (!x_rep && ((^{inport_awready, inport_wready, inport_bvalid, inport_arready, inport_rvalid}) === 1'bx)) begin
                x_rep <= 1; fail("X/Z tren inport awready/wready/bvalid/arready/rvalid");
            end
            // đếm handshake, bvalid/rvalid chỉ được lên sau yêu cầu tương ứng
            if (inport_awvalid && inport_awready === 1'b1) aw_hs = aw_hs + 1;
            if (inport_wvalid  && inport_wready  === 1'b1) w_hs  = w_hs  + 1;
            if (inport_arvalid && inport_arready === 1'b1) ar_hs = ar_hs + 1;
            if (inport_bvalid === 1'b1 && (aw_hs <= b_hs || w_hs <= b_hs)) fail("inport: bvalid khi chua nhan du AW+W");
            if (inport_rvalid === 1'b1 && ar_hs <= r_hs)                   fail("inport: rvalid khi chua nhan AR");
            if (inport_bvalid === 1'b1 && inport_bready) b_hs = b_hs + 1;
            if (inport_rvalid === 1'b1 && inport_rready) r_hs = r_hs + 1;
            if (verbose) begin
                if (inport_awvalid && inport_awready) $display("[%0t] AW %h", $time, inport_awaddr);
                if (inport_wvalid && inport_wready)   $display("[%0t] W  %h strb=%b", $time, inport_wdata, inport_wstrb);
                if (inport_arvalid && inport_arready) $display("[%0t] AR %h", $time, inport_araddr);
            end
            // ext3: master-side stability
            if (ea_hold && (ext3_awvalid !== 1'b1 || ext3_awaddr !== ea_a)) fail("ext3 AW: valid/addr doi truoc ready");
            if (ew_hold && (ext3_wvalid !== 1'b1 || ext3_wdata !== ew_d || ext3_wstrb !== ew_s)) fail("ext3 W: valid/data doi truoc ready");
            if (er_hold && (ext3_arvalid !== 1'b1 || ext3_araddr !== er_a)) fail("ext3 AR: valid/addr doi truoc ready");
            ea_hold <= (ext3_awvalid === 1'b1) && !ext3_awready; ea_a <= ext3_awaddr;
            ew_hold <= (ext3_wvalid  === 1'b1) && !ext3_wready;  ew_d <= ext3_wdata; ew_s <= ext3_wstrb;
            er_hold <= (ext3_arvalid === 1'b1) && !ext3_arready; er_a <= ext3_araddr;
            if (!ex_rep && ((^{ext3_awvalid, ext3_wvalid, ext3_arvalid, ext3_bready, ext3_rready}) === 1'bx)) begin
                ex_rep <= 1; fail("X/Z tren ext3 awvalid/wvalid/arvalid/bready/rready");
            end
        end
    end

    // =========================================================================
    // Mô hình slave ngoài cho ext3 (AXI4-Lite). Địa chỉ cuối 0x...F0 -> SLVERR
    // =========================================================================
    reg [31:0] e3_mem [0:63];
    integer    e3_lat, e3_ca, e3_cw, e3_cb, e3_cr, e3_i;
    reg        e3_aw_got, e3_w_got, e3_ar_got;
    reg [31:0] e3_aw_q, e3_wd_q, e3_ar_q, e3_last_aw, e3_last_ar;
    reg [3:0]  e3_ws_q;
    reg [31:0] e3_t;

    initial for (e3_i = 0; e3_i < 64; e3_i = e3_i + 1) e3_mem[e3_i] = 32'h0;

    always @(posedge clk) begin
        if (rst_i) begin
            ext3_awready <= 0; ext3_wready <= 0; ext3_bvalid <= 0; ext3_bresp <= 0;
            ext3_arready <= 0; ext3_rvalid <= 0; ext3_rresp <= 0; ext3_rdata <= 0;
            e3_aw_got <= 0; e3_w_got <= 0; e3_ar_got <= 0; e3_ca = 0; e3_cw = 0; e3_cb = 0; e3_cr = 0;
        end else begin
            // ---- ghi ----
            if (ext3_awvalid && ext3_awready) begin ext3_awready <= 0; e3_aw_got <= 1; e3_aw_q <= ext3_awaddr; end
            else if (!e3_aw_got && !ext3_bvalid) begin if (e3_ca == 0) ext3_awready <= 1; else e3_ca = e3_ca - 1; end
            if (ext3_wvalid && ext3_wready) begin ext3_wready <= 0; e3_w_got <= 1; e3_wd_q <= ext3_wdata; e3_ws_q <= ext3_wstrb; end
            else if (!e3_w_got && !ext3_bvalid) begin if (e3_cw == 0) ext3_wready <= 1; else e3_cw = e3_cw - 1; end
            if (e3_aw_got && e3_w_got && !ext3_bvalid) begin
                if (e3_cb == 0) begin
                    e3_last_aw = e3_aw_q;
                    if (e3_aw_q[7:0] == 8'hF0) ext3_bresp <= 2'b10;
                    else begin
                        ext3_bresp <= 2'b00;
                        e3_t = e3_mem[e3_aw_q[7:2]];
                        for (e3_i = 0; e3_i < 4; e3_i = e3_i + 1) if (e3_ws_q[e3_i]) e3_t[8*e3_i +: 8] = e3_wd_q[8*e3_i +: 8];
                        e3_mem[e3_aw_q[7:2]] = e3_t;
                    end
                    ext3_bvalid <= 1; e3_aw_got <= 0; e3_w_got <= 0;
                    e3_cb = e3_lat; e3_ca = e3_lat; e3_cw = e3_lat;
                end else e3_cb = e3_cb - 1;
            end
            if (ext3_bvalid && ext3_bready) ext3_bvalid <= 0;
            // ---- đọc ----
            if (ext3_arvalid && ext3_arready) begin ext3_arready <= 0; e3_ar_got <= 1; e3_ar_q <= ext3_araddr; end
            else if (!e3_ar_got && !ext3_rvalid) begin if (e3_cr == 0) ext3_arready <= 1; else e3_cr = e3_cr - 1; end
            if (e3_ar_got && !ext3_rvalid) begin
                e3_last_ar = e3_ar_q;
                if (e3_ar_q[7:0] == 8'hF0) begin ext3_rresp <= 2'b10; ext3_rdata <= 32'hBAD0_BAD0; end
                else begin ext3_rresp <= 2'b00; ext3_rdata <= e3_mem[e3_ar_q[7:2]]; end
                ext3_rvalid <= 1; e3_ar_got <= 0; e3_cr = e3_lat;
            end
            if (ext3_rvalid && ext3_rready) ext3_rvalid <= 0;
        end
    end

    // =========================================================================
    // UART: monitor chân tx + bộ phát vào rx
    // =========================================================================
    // localparam BITC = CLK_FREQ / BAUDRATE;
    // reg [7:0] u_mon_byte; integer u_mon_cnt, u_i; reg u_ferr;

    // always begin : UART_MON
    //     @(negedge uart_tx);
    //     repeat (BITC/2) @(posedge clk);
    //     if (uart_tx !== 1'b0) u_ferr = 1;
    //     for (u_i = 0; u_i < 8; u_i = u_i + 1) begin
    //         repeat (BITC) @(posedge clk);
    //         u_mon_byte[u_i] = uart_tx;
    //     end
    //     repeat (BITC) @(posedge clk);
    //     if (uart_tx !== 1'b1) u_ferr = 1;
    //     u_mon_cnt = u_mon_cnt + 1;
    // end

    // task uart_send;
    //     input [7:0] b; integer k;
    //     begin
    //         uart_rx_drv = 1'b0; repeat (BITC) @(posedge clk);
    //         for (k = 0; k < 8; k = k + 1) begin uart_rx_drv = b[k]; repeat (BITC) @(posedge clk); end
    //         uart_rx_drv = 1'b1; repeat (BITC) @(posedge clk);
    //     end
    // endtask
    localparam BITC = CLK_FREQ / BAUDRATE;

    reg [7:0] u_mon_byte;
    integer   u_mon_cnt;
    integer   u_i;
    reg       u_ferr;

    always begin : UART_MON

        @(negedge uart_tx);

        // Sample middle of start bit
        repeat (BITC/2) @(posedge clk);
        #1;

        if (uart_tx !== 1'b0)
            u_ferr = 1'b1;

        // Sample 8 data bits, LSB first
        for (u_i = 0; u_i < 8; u_i = u_i + 1) begin
            repeat (BITC) @(posedge clk);
            #1;
            u_mon_byte[u_i] = uart_tx;
        end

        // Sample stop bit
        repeat (BITC) @(posedge clk);
        #1;

        if (uart_tx !== 1'b1)
            u_ferr = 1'b1;

        // One complete UART frame detected
        u_mon_cnt = u_mon_cnt + 1;

    end

    task uart_send;
        input [7:0] b;
        integer k;

        begin
            // Idle -> Start bit
            @(negedge clk);
            uart_rx_drv = 1'b0;
            repeat (BITC) @(negedge clk);

            // 8 data bits, LSB first
            for (k = 0; k < 8; k = k + 1) begin
                uart_rx_drv = b[k];
                repeat (BITC) @(negedge clk);
            end

            // Stop bit
            uart_rx_drv = 1'b1;
            repeat (BITC) @(negedge clk);
        end
    endtask

    // =========================================================================
    // SPI slave (mode 0): lấy mẫu mosi ở cạnh lên, đổi miso ở cạnh xuống
    // =========================================================================
    reg [7:0] spi_resp, spi_cap; integer spi_bits, spi_nbytes;
    initial begin spi_miso = 1'b1; spi_resp = 8'hFF; spi_cap = 0; spi_bits = 0; spi_nbytes = 0; end
    always @(negedge spi_cs[0]) begin spi_bits = 0; spi_miso = spi_resp[7]; end
    always @(posedge spi_clk) if (spi_cs[0] === 1'b0) begin
        spi_cap  = {spi_cap[6:0], spi_mosi};
        spi_bits = spi_bits + 1;
        if (spi_bits % 8 == 0) spi_nbytes = spi_nbytes + 1;
    end
    always @(negedge spi_clk) if (spi_cs[0] === 1'b0) spi_miso = spi_resp[7 - (spi_bits % 8)];

    task spi_xfer;   // gửi tx, nhận về rx (đợi RX không rỗng)
        input [7:0] tx; input [7:0] slave_resp; output [31:0] rx; integer n; reg [31:0] sr;
        begin
            spi_resp = slave_resp;
            wr(SPI_BASE + 32'h68, {24'h0, tx});
            n = 0; sr = 32'h1;
            while ((sr & 1) && n < 2000) begin rd(SPI_BASE + 32'h64, sr); n = n + 1; end
            if (n >= 2000) fail("SPI: RX khong co du lieu (timeout)");
            rd(SPI_BASE + 32'h6c, rx);
        end
    endtask

    // =========================================================================
    // Các nhóm test
    // =========================================================================
    reg [31:0] d0, d1;
    integer i, n;

    task t_reset;
        begin
            tstart("T0: gia tri sau reset");
            chk(IRQ_BASE + 32'h00, 32'h0, "IRQ_ISR");
            chk(IRQ_BASE + 32'h04, 32'h0, "IRQ_IPR");
            chk(IRQ_BASE + 32'h08, 32'h0, "IRQ_IER");
            chk(IRQ_BASE + 32'h18, 32'hFFFF_FFFF, "IRQ_IVR");
            chk(IRQ_BASE + 32'h1c, 32'h0, "IRQ_MER");
            chk(TMR_BASE + 32'h08, 32'h0, "TIMER_CTRL0");
            chk(TMR_BASE + 32'h10, 32'h0, "TIMER_VAL0");
            chkm(UART_BASE + 32'h08, 32'h4, 32'h1F, "UART_STATUS (txempty)");
            chk(GPIO_BASE + 32'h00, 32'h0, "GPIO_DIRECTION");
            chk(GPIO_BASE + 32'h08, 32'h0, "GPIO_OUTPUT");
            chkm(SPI_BASE + 32'h64, 32'h5, 32'hF, "SPI_SR (rx/tx empty)");
            chk_sig(intr === 1'b0,                 "intr_o != 0 sau reset");
            chk_sig(uart_tx === 1'b1,              "uart_tx_o != 1 (idle)");
            chk_sig(gpio_output === 32'h0,         "gpio_output_o != 0");
            chk_sig(gpio_oe === 32'h0,             "gpio_output_enable_o != 0");
            chk_sig(ext3_awvalid === 1'b0 && ext3_wvalid === 1'b0 && ext3_arvalid === 1'b0, "ext3 valid != 0 luc idle");
        end
    endtask

    task t_irq;
        begin
            tstart("T1: IRQ controller");
            wr(IRQ_BASE + 32'h08, 32'h7F);  chk(IRQ_BASE + 32'h08, 32'h7F, "IER rw");
            wr(IRQ_BASE + 32'h1c, 32'h1);   chk(IRQ_BASE + 32'h1c, 32'h1,  "MER rw");
            // ngắt ngoài ext3 -> bit 6
            ext3_irq = 1'b1; repeat (6) @(posedge clk); ext3_irq = 1'b0; repeat (4) @(posedge clk);
            chk(IRQ_BASE + 32'h00, 32'h40, "ISR bit6 (ext3_irq)");
            chk(IRQ_BASE + 32'h04, 32'h40, "IPR bit6");
            chk(IRQ_BASE + 32'h18, 32'h6,  "IVR = 6");
            chk_sig(intr === 1'b1, "intr_o phai =1 khi co ngat enable");
            wr(IRQ_BASE + 32'h0c, 32'h40);  repeat (2) @(posedge clk);
            chk(IRQ_BASE + 32'h00, 32'h0, "ISR sau IAR");
            chk(IRQ_BASE + 32'h18, 32'hFFFF_FFFF, "IVR sau IAR");
            chk_sig(intr === 1'b0, "intr_o phai =0 sau IAR");
            // ngắt phần mềm + ưu tiên (chỉ số thấp thắng)
            wr(IRQ_BASE + 32'h00, 32'h24);  chk(IRQ_BASE + 32'h00, 32'h24, "ISR sw-set bit5,2");
            chk(IRQ_BASE + 32'h18, 32'h2, "IVR uu tien bit thap (2)");
            // mặt nạ: IER / CIE / SIE
            wr(IRQ_BASE + 32'h08, 32'h04);  chk(IRQ_BASE + 32'h04, 32'h04, "IPR bi mask boi IER");
            wr(IRQ_BASE + 32'h14, 32'h04);  chk(IRQ_BASE + 32'h08, 32'h00, "CIE xoa bit IER");
            repeat (2) @(posedge clk); chk_sig(intr === 1'b0, "intr_o=0 khi IER=0");
            wr(IRQ_BASE + 32'h10, 32'h20);  chk(IRQ_BASE + 32'h08, 32'h20, "SIE set bit IER");
            chk(IRQ_BASE + 32'h18, 32'h5, "IVR = 5");
            wr(IRQ_BASE + 32'h0c, 32'h24);  chk(IRQ_BASE + 32'h00, 32'h0, "ISR sau IAR 0x24");
            // MER = 0 chặn intr_o
            wr(IRQ_BASE + 32'h08, 32'h7F);  wr(IRQ_BASE + 32'h1c, 32'h0);
            wr(IRQ_BASE + 32'h00, 32'h01);  repeat (4) @(posedge clk);
            chk_sig(intr === 1'b0, "intr_o=0 khi MER=0");
            wr(IRQ_BASE + 32'h1c, 32'h1);   repeat (3) @(posedge clk);
            chk_sig(intr === 1'b1, "intr_o=1 khi MER=1");
            wr(IRQ_BASE + 32'h0c, 32'h01);  repeat (2) @(posedge clk);
            chk(IRQ_BASE + 32'h00, 32'h0, "ISR sach");
        end
    endtask

    task t_timer;
        begin
            tstart("T2: Timer");
            wr(IRQ_BASE + 32'h08, 32'h7F);
            wr(TMR_BASE + 32'h0c, 32'd40);      // CMP0
            wr(TMR_BASE + 32'h10, 32'd0);       // VAL0
            chk(TMR_BASE + 32'h0c, 32'd40, "TIMER_CMP0 rw");
            wr(TMR_BASE + 32'h08, 32'h6);       // interrupt + enable
            repeat (80) @(posedge clk);
            chkm(IRQ_BASE + 32'h00, 32'h1, 32'h1, "ISR bit0 (timer0 match)");
            chk_sig(intr === 1'b1, "intr_o khi timer0 match");
            wr(TMR_BASE + 32'h08, 32'h0);       // dừng
            rd(TMR_BASE + 32'h10, d0); repeat (10) @(posedge clk); rd(TMR_BASE + 32'h10, d1);
            checks = checks + 1; if (d0 !== d1) fail("Timer0 van dem khi enable=0");
            wr(IRQ_BASE + 32'h0c, 32'h01);      repeat (2) @(posedge clk);
            chk(IRQ_BASE + 32'h00, 32'h0, "ISR sach sau IAR timer");
            wr(TMR_BASE + 32'h10, 32'd1000);    // ghi VAL
            chk(TMR_BASE + 32'h10, 32'd1000, "TIMER_VAL0 ghi duoc khi dung");
            wr(TMR_BASE + 32'h08, 32'h4);       // enable, khong ngat
            repeat (20) @(posedge clk); rd(TMR_BASE + 32'h10, d0);
            checks = checks + 1; if (!(d0 > 32'd1000 && d0 < 32'd1100)) fail("Timer0 khong dem dung sau khi enable");
            wr(TMR_BASE + 32'h08, 32'h0);
            chkm(IRQ_BASE + 32'h00, 32'h0, 32'h1, "Khong ngat khi interrupt=0");
            // Timer1 độc lập
            wr(TMR_BASE + 32'h18, 32'd1010);  wr(TMR_BASE + 32'h1c, 32'd1000);
            wr(TMR_BASE + 32'h14, 32'h6);     repeat (40) @(posedge clk);
            chkm(IRQ_BASE + 32'h00, 32'h1, 32'h1, "ISR bit0 (timer1 match)");
            wr(TMR_BASE + 32'h14, 32'h0);     wr(IRQ_BASE + 32'h0c, 32'h01);
            repeat (2) @(posedge clk);        chk(IRQ_BASE + 32'h00, 32'h0, "ISR sach");
        end
    endtask

    task t_gpio;
        begin
            tstart("T3: GPIO");
            wr(GPIO_BASE + 32'h00, 32'hFFFF_0000); chk(GPIO_BASE + 32'h00, 32'hFFFF_0000, "GPIO_DIRECTION");
            chk_sig(gpio_oe === 32'hFFFF_0000, "gpio_output_enable_o = DIRECTION");
            wr(GPIO_BASE + 32'h08, 32'h1234_5678); repeat (2) @(posedge clk);
            chk_sig(gpio_output === 32'h1234_5678, "gpio_output_o = OUTPUT");
            chk(GPIO_BASE + 32'h08, 32'h1234_5678, "GPIO_OUTPUT readback");
            wr(GPIO_BASE + 32'h0c, 32'h0000_0F00); chk(GPIO_BASE + 32'h08, 32'h1234_5F78, "GPIO_OUTPUT_SET");
            wr(GPIO_BASE + 32'h10, 32'h0000_00FF); chk(GPIO_BASE + 32'h08, 32'h1234_5F00, "GPIO_OUTPUT_CLR");
            chk_sig(gpio_output === 32'h1234_5F00, "gpio_output_o sau SET/CLR");
            gpio_input = 32'hCAFE_F00D; repeat (4) @(posedge clk);
            chk(GPIO_BASE + 32'h04, 32'hCAFE_F00D, "GPIO_INPUT");
            // ngắt cạnh lên bit0
            gpio_input = 32'h0; repeat (4) @(posedge clk);
            wr(GPIO_BASE + 32'h14, 32'hFFFF_FFFF);   // mask
            wr(GPIO_BASE + 32'h24, 32'hFFFF_FFFF);   // active high / rising
            wr(GPIO_BASE + 32'h28, 32'hFFFF_FFFF);   // edge
            wr(GPIO_BASE + 32'h1c, 32'hFFFF_FFFF);   // clear
            chk(GPIO_BASE + 32'h20, 32'h0, "GPIO_INT_STATUS sach");
            wr(IRQ_BASE + 32'h08, 32'h7F);
            gpio_input = 32'h1; repeat (6) @(posedge clk);
            chk(GPIO_BASE + 32'h20, 32'h1, "GPIO_INT_STATUS bit0 (rising)");
            chkm(IRQ_BASE + 32'h00, 32'h8, 32'h8, "ISR bit3 (gpio)");
            wr(GPIO_BASE + 32'h1c, 32'h1);           // clear: không tái kích (edge)
            repeat (2) @(posedge clk);
            chk(GPIO_BASE + 32'h20, 32'h0, "GPIO_INT_CLR (edge)");
            wr(IRQ_BASE + 32'h0c, 32'h08);
            // ngắt SW
            wr(GPIO_BASE + 32'h18, 32'h2);  repeat (2) @(posedge clk);
            chk(GPIO_BASE + 32'h20, 32'h2, "GPIO_INT_SET (sw irq)");
            wr(GPIO_BASE + 32'h1c, 32'h2);  repeat (2) @(posedge clk);
            chk(GPIO_BASE + 32'h20, 32'h0, "GPIO_INT_CLR (sw irq)");
            // ngắt mức: clear không có tác dụng khi chân còn tích cực
            wr(GPIO_BASE + 32'h28, 32'h0);           // level mode
            wr(GPIO_BASE + 32'h1c, 32'h1);  repeat (3) @(posedge clk);
            chk(GPIO_BASE + 32'h20, 32'h1, "Level irq giu khi chan con active");
            gpio_input = 32'h0; repeat (4) @(posedge clk);
            wr(GPIO_BASE + 32'h1c, 32'h1);  repeat (2) @(posedge clk);
            chk(GPIO_BASE + 32'h20, 32'h0, "Level irq xoa duoc khi chan ve 0");
            wr(IRQ_BASE + 32'h0c, 32'h7F);  repeat (2) @(posedge clk);
            wr(GPIO_BASE + 32'h14, 32'h0);  wr(GPIO_BASE + 32'h00, 32'h0);
        end
    endtask

    // task t_uart;
    //     reg [7:0] tb [0:3];
    //     begin
    //         tstart("T4: UART");
    //         uart_lb = 1'b1;
    //         tb[0] = 8'h55; tb[1] = 8'h00; tb[2] = 8'hFF; tb[3] = 8'hA3;
    //         for (i = 0; i < 4; i = i + 1) begin
    //             u_mon_cnt = 0; u_ferr = 0;
    //             wr(UART_BASE + 32'h04, {24'h0, tb[i]});
    //             if (i == 0) chkm(UART_BASE + 32'h08, 32'h8, 32'hC, "UART txfull=1, txempty=0 khi dang phat");
    //             n = 0; d0 = 0;
    //             while (!(d0 & 1) && n < 2000) begin rd(UART_BASE + 32'h08, d0); n = n + 1; end
    //             if (n >= 2000) fail("UART: RXVALID khong len (loopback)");
    //             chk(UART_BASE + 32'h00, {24'h0, tb[i]}, "UART RX loopback");
    //             chkm(UART_BASE + 32'h08, 32'h0, 32'h1, "UART rxvalid xoa sau khi doc");
    //             checks = checks + 1;
    //             if (u_mon_cnt != 1 || u_mon_byte !== tb[i]) begin errors = errors + 1;
    //                 $display("[%0t] FAIL UART tx tren chan: byte=%h (exp %h) so khung=%0d", $time, u_mon_byte, tb[i], u_mon_cnt); end
    //             if (u_ferr) fail("UART tx: khung start/stop sai");
    //             chkm(UART_BASE + 32'h08, 32'h4, 32'h4, "UART txempty sau khi xong");
    //         end
    //         // nhận từ chân ngoài
    //         uart_lb = 1'b0; uart_rx_drv = 1'b1; repeat (BITC) @(posedge clk);
    //         uart_send(8'h3D);
    //         n = 0; d0 = 0;
    //         while (!(d0 & 1) && n < 200) begin rd(UART_BASE + 32'h08, d0); n = n + 1; end
    //         chk(UART_BASE + 32'h00, 32'h3D, "UART RX tu chan ngoai");
    //         uart_send(8'hC2);
    //         n = 0; d0 = 0;
    //         while (!(d0 & 1) && n < 200) begin rd(UART_BASE + 32'h08, d0); n = n + 1; end
    //         chk(UART_BASE + 32'h00, 32'hC2, "UART RX byte 2");
    //     end
    // endtask
    task t_uart;

        reg [7:0] tb [0:3];
        integer i;
        integer n;
        integer expected_frames;
        begin
            tstart("T4: UART");
            // Initialize UART test signals
            uart_lb      = 1'b1;
            uart_rx_drv  = 1'b1;
            u_mon_cnt  = 0;
            u_mon_byte = 8'h00;
            u_ferr     = 1'b0;

            tb[0] = 8'h55;
            tb[1] = 8'h00;
            tb[2] = 8'hFF;
            tb[3] = 8'hA3;

            //-----------------------------------------------------------------
            // TEST 1: TX -> Loopback -> RX
            //-----------------------------------------------------------------

            for (i = 0; i < 4; i = i + 1) begin

                u_ferr = 1'b0;

                // Write TX register
                wr(UART_BASE + 32'h04, {24'h0, tb[i]});

                //-----------------------------------------------------------------
                // Check TX status while transmitting
                //-----------------------------------------------------------------

                if (i == 0) begin
                    chkm(
                        UART_BASE + 32'h08,
                        32'h8,
                        32'hC,
                        "UART TXFULL=1 TXEMPTY=0"
                    );
                end

                //-----------------------------------------------------------------
                // Wait for RXVALID
                //-----------------------------------------------------------------

                n  = 0;
                d0 = 0;

                while (!(d0 & 32'h1) && n < 2000) begin
                    rd(UART_BASE + 32'h08, d0);
                    n = n + 1;
                end

                if (n >= 2000) begin
                    fail("UART: RXVALID khong len (loopback)");
                end

                //-----------------------------------------------------------------
                // Read RX register
                //-----------------------------------------------------------------

                chk(
                    UART_BASE + 32'h00,
                    {24'h0, tb[i]},
                    "UART RX loopback"
                );

                //-----------------------------------------------------------------
                // Check RXVALID cleared after reading RX
                //-----------------------------------------------------------------

                chkm(
                    UART_BASE + 32'h08,
                    32'h0,
                    32'h1,
                    "UART RXVALID xoa sau khi doc"
                );

                //-----------------------------------------------------------------
                // Wait for TX monitor to finish current frame
                //-----------------------------------------------------------------

                expected_frames = i + 1;
                n = 0;

                while ((u_mon_cnt < expected_frames) && n < 200) begin
                    @(posedge clk);
                    n = n + 1;
                end

                if (u_mon_cnt != expected_frames) begin
                    fail("UART TX monitor: sai so frame");
                end
                else begin
                    checks = checks + 1;

                    if (u_mon_byte !== tb[i]) begin
                        errors = errors + 1;
                        $display(
                            "[%0t] FAIL UART TX DATA: got=%h exp=%h",
                            $time, u_mon_byte, tb[i]
                        );
                    end
                end

                if (u_ferr)
                    fail("UART TX: start/stop bit sai");

                //-----------------------------------------------------------------
                // Check TXEMPTY after transmission
                //-----------------------------------------------------------------

                chkm(
                    UART_BASE + 32'h08,
                    32'h4,
                    32'h4,
                    "UART TXEMPTY sau khi truyen"
                );

            end

            //-----------------------------------------------------------------
            // TEST 2: RX from external pin
            //-----------------------------------------------------------------

            uart_lb     = 1'b0;
            uart_rx_drv = 1'b1;

            // Wait for RX input to become idle
            repeat (BITC) @(posedge clk);

            //-----------------------------------------------------------------
            // Receive byte 0x3D
            //-----------------------------------------------------------------

            uart_send(8'h3D);

            n  = 0;
            d0 = 0;

            while (!(d0 & 32'h1) && n < 200) begin
                rd(UART_BASE + 32'h08, d0);
                n = n + 1;
            end

            if (n >= 200)
                fail("UART RX: timeout byte 3D");

            chk(
                UART_BASE + 32'h00,
                32'h0000003D,
                "UART RX external byte 3D"
            );

            chkm(
                UART_BASE + 32'h08,
                32'h0,
                32'h1,
                "UART RXVALID clear after byte 3D"
            );

            //-----------------------------------------------------------------
            // Receive byte 0xC2
            //-----------------------------------------------------------------

            uart_send(8'hC2);

            n  = 0;
            d0 = 0;

            while (!(d0 & 32'h1) && n < 200) begin
                rd(UART_BASE + 32'h08, d0);
                n = n + 1;
            end

            if (n >= 200)
                fail("UART RX: timeout byte C2");

            chk(
                UART_BASE + 32'h00,
                32'h000000C2,
                "UART RX external byte C2"
            );

            chkm(
                UART_BASE + 32'h08,
                32'h0,
                32'h1,
                "UART RXVALID clear after byte C2"
            );

        end
    endtask

    task t_spi;
        begin
            tstart("T5: SPI");
            wr(SPI_BASE + 32'h60, 32'h86);          // SPE | MASTER | MANUAL_SS
            wr(SPI_BASE + 32'h70, 32'hFFFF_FFFF);
            wr(SPI_BASE + 32'h40, 32'h0A);          // soft reset
            repeat (4) @(posedge clk);
            wr(SPI_BASE + 32'h60, 32'h86);
            chk_sig(spi_cs === 8'hFF, "spi_cs_o = 0xFF khi chua chon");
            wr(SPI_BASE + 32'h70, 32'hFFFF_FFFE);   repeat (2) @(posedge clk);
            chk_sig(spi_cs === 8'hFE, "spi_cs_o[0]=0 theo SSR");
            spi_xfer(8'hA5, 8'h3C, d0);
            chk_sig(spi_cap === 8'hA5, "SPI mosi gui 0xA5 (MSB truoc)");
            checks = checks + 1; if (d0[7:0] !== 8'h3C) begin errors = errors + 1;
                $display("[%0t] FAIL SPI DRR: got=%h exp=3C", $time, d0); end
            spi_xfer(8'h00, 8'hFF, d0);
            chk_sig(spi_cap === 8'h00, "SPI mosi gui 0x00");
            checks = checks + 1; if (d0[7:0] !== 8'hFF) fail("SPI DRR != 0xFF");
            spi_xfer(8'h81, 8'h18, d0);
            chk_sig(spi_cap === 8'h81, "SPI mosi gui 0x81");
            checks = checks + 1; if (d0[7:0] !== 8'h18) fail("SPI DRR != 0x18");
            // LSB first
            wr(SPI_BASE + 32'h60, 32'h286);         // + LSB_FIRST (bit 9)
            spi_xfer(8'h01, 8'h1E, d0);
            chk_sig(spi_cap === 8'h80, "SPI LSB-first: 0x01 -> 0x80 tren day");
            checks = checks + 1; if (d0[7:0] !== 8'h78) begin errors = errors + 1;
                $display("[%0t] FAIL SPI LSB-first DRR: got=%h exp=78", $time, d0); end
            wr(SPI_BASE + 32'h60, 32'h86);
            wr(SPI_BASE + 32'h70, 32'hFFFF_FFFF);   repeat (2) @(posedge clk);
            chk_sig(spi_cs === 8'hFF, "spi_cs_o tra ve 0xFF");
        end
    endtask

    task t_sram;
        reg [1:0] r; reg [31:0] pat;
        begin
            tstart("T6: SRAM");
            for (i = 0; i < SRAM_WORDS; i = i + 1) wr(SRAM_BASE + 4*i, 32'hA5A5_0000 ^ (i * 32'h0101_0101) ^ i);
            for (i = 0; i < SRAM_WORDS; i = i + 1) chk(SRAM_BASE + 4*i, 32'hA5A5_0000 ^ (i * 32'h0101_0101) ^ i, "SRAM word");
            for (i = SRAM_WORDS-1; i >= 0; i = i - 1) chk(SRAM_BASE + 4*i, 32'hA5A5_0000 ^ (i * 32'h0101_0101) ^ i, "SRAM word (nguoc)");
            // byte strobe
            wr (SRAM_BASE + 32'h0C, 32'hAABB_CCDD);
            wrs(SRAM_BASE + 32'h0C, 32'h0000_0011, 4'b0001, 0); chk(SRAM_BASE + 32'h0C, 32'hAABB_CC11, "SRAM wstrb 0001");
            wrs(SRAM_BASE + 32'h0C, 32'h5566_0000, 4'b1100, 0); chk(SRAM_BASE + 32'h0C, 32'h5566_CC11, "SRAM wstrb 1100");
            wrs(SRAM_BASE + 32'h0C, 32'h0000_7700, 4'b0010, 0); chk(SRAM_BASE + 32'h0C, 32'h5566_7711, "SRAM wstrb 0010");
            wrs(SRAM_BASE + 32'h0C, 32'h9900_0000, 4'b1000, 0); chk(SRAM_BASE + 32'h0C, 32'h9966_7711, "SRAM wstrb 1000");
            chk(SRAM_BASE + 32'h08, 32'hA5A5_0000 ^ (2 * 32'h0101_0101) ^ 2, "SRAM lan can khong bi ghi de");
            // ghi liên tiếp rồi đọc ngay
            wr(SRAM_BASE + 32'h40, 32'h1111_1111); chk(SRAM_BASE + 32'h40, 32'h1111_1111, "SRAM ghi roi doc ngay");
            wr(SRAM_BASE + 32'h40, 32'h2222_2222); wr(SRAM_BASE + 32'h44, 32'h3333_3333);
            chk(SRAM_BASE + 32'h40, 32'h2222_2222, "SRAM ghi lien tiep 1");
            chk(SRAM_BASE + 32'h44, 32'h3333_3333, "SRAM ghi lien tiep 2");
        end
    endtask

    task t_accel;
        reg [1:0] r;
        begin
            tstart("T7: Accelerator (smoke)");
            wr(ACCEL_BASE + ACCEL_REG_OFS, 32'hC0DE_0001);
            rd(ACCEL_BASE + ACCEL_REG_OFS, d0);
            $display("  info: accel[%h] doc lai = %h (BRESP/RRESP = OKAY)", ACCEL_REG_OFS, d0);
            if (ACCEL_RW_CHECK) chk(ACCEL_BASE + ACCEL_REG_OFS, 32'hC0DE_0001, "ACCEL reg rw");
        end
    endtask

    task t_ext3;
        reg [1:0] r;
        begin
            tstart("T8: EXT3 (slave ngoai, SLVERR, AW/W lech)");
            e3_lat = 0;
            for (i = 0; i < 8; i = i + 1) wr(EXT3_BASE + 4*i, 32'hE300_0000 + i);
            chk_sig(e3_last_aw === EXT3_BASE + 32'h1C, "ext3 thay dia chi ghi day du (dist khong cat dia chi)");
            for (i = 0; i < 8; i = i + 1) chk(EXT3_BASE + 4*i, 32'hE300_0000 + i, "EXT3 word");
            chk_sig(e3_last_ar === EXT3_BASE + 32'h1C, "ext3 thay dia chi doc day du");
            wrs(EXT3_BASE + 32'h04, 32'h0000_00EE, 4'b0001, 0); chk(EXT3_BASE + 32'h04, 32'hE300_00EE, "EXT3 wstrb den slave");
            // SLVERR lan truyền
            axi_wr(EXT3_BASE + 32'hF0, 32'h1, 4'hF, 0, r);
            checks = checks + 1; if (r !== 2'b10) begin errors = errors + 1; $display("[%0t] FAIL EXT3 BRESP: got=%b exp=10", $time, r); end
            axi_rd(EXT3_BASE + 32'hF0, d0, r);
            checks = checks + 1; if (r !== 2'b10) begin errors = errors + 1; $display("[%0t] FAIL EXT3 RRESP: got=%b exp=10", $time, r); end
            // sau SLVERR bus còn dùng được
            chk(EXT3_BASE + 32'h00, 32'hE300_0000, "EXT3 doc sau SLVERR");
            // AW/W đến lệch thứ tự
            wrs(EXT3_BASE + 32'h10, 32'h0A0A_0A0A, 4'hF, 1); chk(EXT3_BASE + 32'h10, 32'h0A0A_0A0A, "EXT3 AW truoc W");
            wrs(EXT3_BASE + 32'h14, 32'h0B0B_0B0B, 4'hF, 2); chk(EXT3_BASE + 32'h14, 32'h0B0B_0B0B, "EXT3 W truoc AW");
            // độ trễ + backpressure
            e3_lat = 5; b_delay = 6; rd_delay = 6;
            for (i = 0; i < 4; i = i + 1) wr(EXT3_BASE + 4*i, 32'hD00D_0000 + i);
            for (i = 0; i < 4; i = i + 1) chk(EXT3_BASE + 4*i, 32'hD00D_0000 + i, "EXT3 word (tre 5, bp 6)");
            e3_lat = 0; b_delay = 0; rd_delay = 0;
        end
    endtask

    task t_order;   // AW/W lệch thứ tự + backpressure trên ngoại vi nội bộ
        begin
            tstart("T9: AW/W lech thu tu, backpressure (ngoai vi noi bo)");
            wrs(GPIO_BASE + 32'h08, 32'h1111_0000, 4'hF, 1); chk(GPIO_BASE + 32'h08, 32'h1111_0000, "GPIO AW truoc W");
            wrs(GPIO_BASE + 32'h08, 32'h2222_0000, 4'hF, 2); chk(GPIO_BASE + 32'h08, 32'h2222_0000, "GPIO W truoc AW");
            wrs(SRAM_BASE + 32'h20, 32'h3333_0000, 4'hF, 1); chk(SRAM_BASE + 32'h20, 32'h3333_0000, "SRAM AW truoc W");
            wrs(SRAM_BASE + 32'h24, 32'h4444_0000, 4'hF, 2); chk(SRAM_BASE + 32'h24, 32'h4444_0000, "SRAM W truoc AW");
            b_delay = 7; rd_delay = 7;
            wr(SRAM_BASE + 32'h28, 32'h5555_5555); chk(SRAM_BASE + 32'h28, 32'h5555_5555, "SRAM bp B/R");
            wr(TMR_BASE + 32'h0c, 32'h0000_0123);  chk(TMR_BASE + 32'h0c, 32'h0000_0123, "TIMER bp B/R");
            b_delay = 0; rd_delay = 0;
            wr(GPIO_BASE + 32'h08, 32'h0);
        end
    endtask

    // ---- trộn ngẫu nhiên các ngoại vi, đối chiếu bằng shadow model ----
    reg [31:0] sh_gpio, sh_cmp1; reg [31:0] sh_sram [0:15]; reg [31:0] sh_e3 [0:7];
    task t_random;
        integer k, kind, idx, mode; reg [31:0] rnd, a, exp_v, got; reg [3:0] st; reg [1:0] rs; reg is_wr;
        begin
            tstart("T10: xen ke ngau nhien nhieu ngoai vi (shadow model)");
            sh_gpio = 0; sh_cmp1 = 0;
            wr(GPIO_BASE + 32'h08, 0); wr(TMR_BASE + 32'h18, 0);
            for (k = 0; k < 16; k = k + 1) begin sh_sram[k] = 0; wr(SRAM_BASE + 32'h100 + 4*k, 0); end
            for (k = 0; k < 8;  k = k + 1) begin sh_e3[k]   = 0; wr(EXT3_BASE + 32'h40 + 4*k, 0); end
            for (k = 0; k < 400; k = k + 1) begin
                rnd = $random(seed); kind = {$random(seed)} % 4; idx = {$random(seed)} % 16;
                is_wr = $random(seed); mode = {$random(seed)} % 3;
                b_delay = {$random(seed)} % 5; rd_delay = {$random(seed)} % 5; e3_lat = {$random(seed)} % 4;
                st = $random(seed); if (st == 0) st = 4'hF;
                case (kind)
                0: begin a = GPIO_BASE + 32'h08;
                       if (is_wr) begin axi_wr(a, rnd, 4'hF, mode, rs); sh_gpio = rnd; if (rs !== 0) fail_a("BRESP", a); end
                       else begin axi_rd(a, got, rs); checks = checks + 1;
                            if (got !== sh_gpio) begin errors = errors + 1; $display("[%0t] FAIL rnd GPIO got=%h exp=%h", $time, got, sh_gpio); end end end
                1: begin a = TMR_BASE + 32'h18;
                       if (is_wr) begin axi_wr(a, rnd, 4'hF, mode, rs); sh_cmp1 = rnd; if (rs !== 0) fail_a("BRESP", a); end
                       else begin axi_rd(a, got, rs); checks = checks + 1;
                            if (got !== sh_cmp1) begin errors = errors + 1; $display("[%0t] FAIL rnd TMR_CMP1 got=%h exp=%h", $time, got, sh_cmp1); end end end
                2: begin a = SRAM_BASE + 32'h100 + 4*idx;
                       if (is_wr) begin axi_wr(a, rnd, st, mode, rs); if (rs !== 0) fail_a("BRESP", a);
                            exp_v = sh_sram[idx];
                            if (st[0]) exp_v[7:0]   = rnd[7:0];   if (st[1]) exp_v[15:8]  = rnd[15:8];
                            if (st[2]) exp_v[23:16] = rnd[23:16]; if (st[3]) exp_v[31:24] = rnd[31:24];
                            sh_sram[idx] = exp_v; end
                       else begin axi_rd(a, got, rs); checks = checks + 1;
                            if (got !== sh_sram[idx]) begin errors = errors + 1; $display("[%0t] FAIL rnd SRAM[%0d] got=%h exp=%h", $time, idx, got, sh_sram[idx]); end end end
                3: begin idx = idx % 8; a = EXT3_BASE + 32'h40 + 4*idx;
                       if (is_wr) begin axi_wr(a, rnd, st, mode, rs); if (rs !== 0) fail_a("BRESP", a);
                            exp_v = sh_e3[idx];
                            if (st[0]) exp_v[7:0]   = rnd[7:0];   if (st[1]) exp_v[15:8]  = rnd[15:8];
                            if (st[2]) exp_v[23:16] = rnd[23:16]; if (st[3]) exp_v[31:24] = rnd[31:24];
                            sh_e3[idx] = exp_v; end
                       else begin axi_rd(a, got, rs); checks = checks + 1;
                            if (got !== sh_e3[idx]) begin errors = errors + 1; $display("[%0t] FAIL rnd EXT3[%0d] got=%h exp=%h", $time, idx, got, sh_e3[idx]); end end end
                endcase
            end
            b_delay = 0; rd_delay = 0; e3_lat = 0;
        end
    endtask

    // =========================================================================
    // Điều khiển chính + watchdog
    // =========================================================================
    initial begin
        errors = 0; checks = 0; cyc = 0; seed = 32'hC0FFEE; finished = 0; verbose = 0;
        b_delay = 0; rd_delay = 0; e3_lat = 0; u_mon_cnt = 0; u_ferr = 0; u_mon_byte = 0;

        if ($test$plusargs("VERBOSE")) verbose = 1;
        $dumpfile("tb_core_soc.vcd"); $dumpvars(0, tb_core_soc);

        inport_awvalid = 0; inport_wvalid = 0; inport_bready = 0; inport_arvalid = 0; inport_rready = 0;
        inport_awaddr = 0; inport_wdata = 0; inport_araddr = 0; inport_wstrb = 0;
        uart_rx_drv = 1; uart_lb = 1; gpio_input = 0; ext3_irq = 0;

        rst_i = 1'b1; repeat (8) @(posedge clk); @(negedge clk) rst_i = 1'b0;
        repeat (4) @(posedge clk);

        t_reset;
        t_irq;
        t_timer;
        t_gpio;
        t_uart;
        t_spi;
        t_sram;
        t_accel;
        t_ext3;
        t_order;
        t_random;

        repeat (20) @(posedge clk);
        finished = 1;
        summary;
        $finish;
    end

    always @(posedge clk) begin
        if (!rst_i) cyc <= cyc + 1;
        if (cyc == TIMEOUT_CYC && !finished) begin
            $display("*** TIMEOUT toan cuc ***"); errors = errors + 1; summary; $finish;
        end
    end

endmodule
