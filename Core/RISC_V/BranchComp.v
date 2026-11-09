module BranchComp (
    input  [31:0] rs1,  
    input  [31:0] rs2,
    input         BrUn,   // Tín hiệu điều khiển: 1 = Không dấu (Unsigned), 0 = Có dấu (Signed)
    output        BrEq,   // Kết quả so sánh bằng (Equal)
    output        BrLt    // Kết quả so sánh bé hơn (Less Than)
);

    assign BrEq = (rs1 == rs2);
    assign BrLt = BrUn ? (rs1 < rs2) : ($signed(rs1) < $signed(rs2));

endmodule