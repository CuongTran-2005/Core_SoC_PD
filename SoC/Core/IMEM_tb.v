`timescale 1ns/1ps

module IMEM_tb();
    reg [31:0] addr;
    wire [31:0] inst;

    // Khởi tạo module IMEM
    IMEM dut (
        .addr(addr),
        .inst(inst)
    );

    initial begin
        $display("--- KIEM TRA NAP FILE IMEM ---");
        
        // Kiểm tra địa chỉ 0x0 (Lệnh đầu tiên)
        addr = 32'h00000000; #10;
        $display("Addr: %h | Instruction: %b (Hex: %h)", addr, inst, inst);

        // Kiểm tra địa chỉ 0x4 (Lệnh thứ hai)
        addr = 32'h00000004; #10;
        $display("Addr: %h | Instruction: %b (Hex: %h)", addr, inst, inst);

        // Kiểm tra địa chỉ 0x8 (Lệnh thứ ba)
        addr = 32'h00000008; #10;
        $display("Addr: %h | Instruction: %b (Hex: %h)", addr, inst, inst);

        if (inst === 32'hxxxxxxxx) begin
            $display("LOI: Du lieu IMEM dang bi 'x'. File .bin chua duoc nap dung!");
        end else if (inst === 0) begin
            $display("CANH BAO: Du lieu tra ve bang 0. Hay kiem tra noi dung file .bin");
        end else begin
            $display("THANH CONG: IMEM da doc duoc du lieu.");
        end
        
        $stop;
    end
endmodule