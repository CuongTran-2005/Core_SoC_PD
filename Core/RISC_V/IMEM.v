module IMEM (
    input [31:0] addr,
    output [31:0] inst
);
    reg [31:0] mem [0:255]; 

    initial begin
        $readmemb("D:/ChuyendeViMach_1/RTL/23520049_Bao _cao_do_an_CE213/verilog/TESTRARS/test_1_instruction.bin", mem); 
    end
    
    wire [31:0] relative_addr = addr - 32'h00400000;
    assign inst = mem[relative_addr[31:2]]; 

endmodule