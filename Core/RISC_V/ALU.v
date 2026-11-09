module ALU (
    input  [31:0] A,         
    input  [31:0] B,           
    input  [3:0]  ALU_Control,
    output [31:0] out   
);

    assign out = (ALU_Control == 4'b0000) ? (A + B): // ADD
                 (ALU_Control == 4'b1000) ? (A - B): // SUB
                 (ALU_Control == 4'b0001) ? (A << B[4:0]): // SLL
                 (ALU_Control == 4'b0010) ? ($signed(A) < $signed(B) ? 32'd1 : 32'd0): // SLT
                 (ALU_Control == 4'b0011) ? (A < B ? 32'd1 : 32'd0): // SLTU
                 (ALU_Control == 4'b0100) ? (A ^ B): // XOR
                 (ALU_Control == 4'b0101) ? (A >> B[4:0]): // SRL (Logical)
                 (ALU_Control == 4'b1101) ? ($signed(A) >>> B[4:0]): // SRA (Arithmetic)
                 (ALU_Control == 4'b0110) ? (A | B):// OR
                 (ALU_Control == 4'b0111) ? (A & B):// AND
                 (ALU_Control == 4'b1111) ? B:// LUI (Pass B)
                  32'b0;

endmodule