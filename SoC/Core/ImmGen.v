module ImmGen(
    input  [31:0] inst, 
    input  [2:0]  ImmSel,
    output reg [31:0] imm
);

    parameter IType = 3'b000,
				  SType = 3'b001,
				  BType = 3'b010,
				  UType = 3'b011,
				  JType = 3'b100;

    always @(*) begin
        case (ImmSel)
            IType: imm = { {20{inst[31]}}, inst[31:20] };
            SType: imm = { {20{inst[31]}}, inst[31:25], inst[11:7] };
            BType: imm = { {19{inst[31]}}, inst[31], inst[7], inst[30:25], inst[11:8], 1'b0 };
            UType: imm = { inst[31:12], 12'b0 };
            JType: imm = { {11{inst[31]}}, inst[31], inst[19:12], inst[20], inst[30:21], 1'b0 };
            default: imm = 32'b0;
        endcase
    end

endmodule