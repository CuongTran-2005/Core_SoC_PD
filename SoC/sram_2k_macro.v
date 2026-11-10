// ==============================================================================
// Behavioral Verilog Simulation Model for Embedded SRAM Hard Macro
// Model: sram_2k_macro (Industrial Grade Model)
// Organization: 1024 Words x 32-bit (4 KByte Synchronous Single-Port SRAM)
// Technology: GPDK 45nm
// ==============================================================================

`timescale 1ns / 1ps

module sram_2k_macro #(
    parameter real T_ACCESS = 1.2,      // Access Time: Trễ đọc Clock-to-Q (1.2 ns)
    parameter      INIT_FILE = ""       // Đường dẫn file Hex nạp trước (Bootcode / Firmware)
)(
    input  wire        CLK,  // Xung nhịp đồng bộ (Clock)
    input  wire        CEN,  // Chip Enable (Active Low: 0 = Hoạt động, 1 = Nghỉ)
    input  wire        WEN,  // Write Enable (Active Low: 0 = Ghi, 1 = Đọc)
    input  wire [9:0]  A,    // Bus địa chỉ 10-bit (1024 từ nhớ)
    input  wire [31:0] D,    // Bus dữ liệu ghi vào (Data Input)
    output reg  [31:0] Q     // Bus dữ liệu đọc ra (Data Output)
);

    // Mảng nhớ 1024 từ x 32-bit (Tổng cộng 4096 Bytes)
    reg [31:0] mem [0:1023];

    // Khởi tạo bộ nhớ ban đầu (tránh giá trị X và hỗ trợ nạp firmware)
    integer i;
    initial begin
        for (i = 0; i < 1024; i = i + 1) begin
            mem[i] = 32'h0000_0000;
        end
        Q = 32'h0000_0000;

        // Nếu có truyền file hex ban đầu, nạp trực tiếp vào RAM
        if (INIT_FILE != "") begin
            $readmemh(INIT_FILE, mem);
        end
    end

    // Xử lý Đọc / Ghi đồng bộ và lan truyền trạng thái bất định (X-Propagation)
    always @(posedge CLK) begin
        if (CEN === 1'bx || WEN === 1'bx) begin
            // Trạng thái điều khiển không xác định -> Ngõ ra bị X
            Q <= #(T_ACCESS) 32'hxxxx_xxxx;
        end else if (!CEN) begin
            if (!WEN) begin
                // Chu kỳ GHI (Write): Ghi dữ liệu D vào ô nhớ địa chỉ A
                mem[A] <= D;
            end else begin
                // Chu kỳ ĐỌC (Read): Dữ liệu xuất hiện sau thời gian trễ T_ACCESS
                Q <= #(T_ACCESS) mem[A];
            end
        end
    end

    // ==========================================================================
    // Timing Checks & SDF Back-Annotation Support (Chuẩn công nghiệp Foundry)
    // ==========================================================================
    `ifdef TIMING_CHECK
    specify
        // Access Time: Trễ từ sườn dương CLK đến ngõ ra Q
        (posedge CLK => (Q : mem[A])) = (1.2, 1.2);

        // Ràng buộc Setup và Hold cho các tín hiệu điều khiển và địa chỉ
        $setup(A, posedge CLK, 0.35);
        $hold(posedge CLK, A, 0.20);
        $setup(D, posedge CLK, 0.30);
        $hold(posedge CLK, D, 0.20);
        $setup(CEN, posedge CLK, 0.40);
        $hold(posedge CLK, CEN, 0.20);
        $setup(WEN, posedge CLK, 0.40);
        $hold(posedge CLK, WEN, 0.20);

        // Ràng buộc độ rộng xung xung nhịp và chu kỳ Clock tối thiểu (Fmax ~ 1GHz)
        $width(posedge CLK, 0.45);
        $width(negedge CLK, 0.45);
        $period(posedge CLK, 1.00);
    endspecify
    `endif

endmodule
