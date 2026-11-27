module EXcontrol (
    input[31:0] instEX,
    input BrEQ,
    input BrLT,
    
    output[2:0]  ImmSel, 
    output BrUn,   
    output Bsel,   
    output Asel,   
    output[3:0]  ALUsel, 
    output PCSel   
);

    wire [6:0] opcode = instEX[6:0];
    wire [2:0] funct3 = instEX[14:12];
    wire [6:0] funct7 = instEX[31:25];
    wire f7_bit5      = instEX[30]; // Bit phân biệt ADD/SUB, SRL/SRA

    // Logic ImmSel
    assign ImmSel = (opcode == 7'b0100011) ? 3'b001 : // S-type
                    (opcode == 7'b1100011) ? 3'b010 : // B-type
                    (opcode == 7'b0110111 || opcode == 7'b0010111) ? 3'b011 : // U-type
                    (opcode == 7'b1101111) ? 3'b100 : // J-type
                     3'b000;  // I-type 

    assign BrUn = (opcode == 7'b1100011) && (funct3[2:1] == 2'b11);
    assign Bsel = (opcode != 7'b0110011);
    assign Asel = (opcode == 7'b1100011) || (opcode == 7'b1101111) || (opcode == 7'b0010111);

   
    assign ALUsel = (opcode == 7'b0110011) ? {f7_bit5, funct3} :
                    (opcode == 7'b0010011) ? ( (funct3 == 3'b101 || funct3 == 3'b001) ? {f7_bit5, funct3} : {1'b0, funct3} ) : // I-type (SLLI, SRLI, SRAI)
                    (opcode == 7'b0110111) ? 4'b1111 : // LUI
                     4'b0000;

    // Logic PCSel
    wire branch_hit = (funct3 == 3'b000) ? BrEQ :          
                      (funct3 == 3'b001) ? !BrEQ :         
                      (funct3 == 3'b100) ? BrLT :          
                      (funct3 == 3'b101) ? !BrLT :         
                      (funct3 == 3'b110) ? BrLT :          
                      (funct3 == 3'b111) ? !BrLT :         
                       1'b0;

    assign PCSel = (opcode == 7'b1101111) || (opcode == 7'b1100111) || (opcode == 7'b1100011 && branch_hit);

endmodule