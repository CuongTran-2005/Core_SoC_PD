module Fowarding_Unit (
    input [31:0] instEX,
    input [31:0] instMEM,
    input [31:0] instWB,
    
    output [1:0] fwAsel,
    output [1:0] fwBsel
);

    wire [4:0] rs1EX = instEX[19:15];
    wire [4:0] rs2EX = instEX[24:20];
    
    wire [4:0] rdMEM = instMEM[11:7];
    wire [4:0] rdWB  = instWB[11:7];

    // Xác định lệnh có ghi vào thanh ghi hay không (Loại trừ Store và Branch)
    wire regWriteMEM = (instMEM[6:0] != 7'b0100011) && (instMEM[6:0] != 7'b1100011);
    wire regWriteWB  = (instWB[6:0]  != 7'b0100011) && (instWB[6:0]  != 7'b1100011);

    // Kiểm tra xem lệnh ở tầng MEM có phải là Load không
    wire isLoadMEM = (instMEM[6:0] == 7'b0000011);

    // Logic chọn nguồn dữ liệu cho Operand A
    assign fwAsel = (regWriteMEM && (rdMEM != 5'd0) && (rdMEM == rs1EX) && !isLoadMEM) ? 2'b10 : 
                    (regWriteWB  && (rdWB  != 5'd0) && (rdWB  == rs1EX)) ? 2'b01 : 
                     2'b00;

    // Logic chọn nguồn dữ liệu cho Operand B
    assign fwBsel = (regWriteMEM && (rdMEM != 5'd0) && (rdMEM == rs2EX) && !isLoadMEM) ? 2'b10 : 
                    (regWriteWB  && (rdWB  != 5'd0) && (rdWB  == rs2EX)) ? 2'b01 : 
                     2'b00;

endmodule