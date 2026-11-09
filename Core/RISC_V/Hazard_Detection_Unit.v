module Hazard_Detection_Unit (
    input [31:0] instID,
    input [31:0] instEX,
    input PCsel,

    output reg Stall_PC,
    output reg Stall_IF_ID,
    output reg CLR_IF_ID,
    output reg CLR_ID_EX
);

    // Giải mã lệnh ở tầng ID
    wire [4:0] rs1_id = instID[19:15];
    wire [4:0] rs2_id = instID[24:20];
    wire [6:0] op_id  = instID[6:0];

    // Giải mã lệnh ở tầng EX
    wire [4:0] rd_ex  = instEX[11:7];
    wire [6:0] op_ex  = instEX[6:0];
    
    // RS2 chỉ được dùng trong: R-type, Branch, Store
    wire uses_rs2 = (op_id == 7'b0110011) || // R-type
                    (op_id == 7'b1100011)   || // Branch
                    (op_id == 7'b0100011);     // Store

    wire is_load_ex = (op_ex == 7'b0000011);

    always @(*) begin
        Stall_PC    = 1'b0;
        Stall_IF_ID = 1'b0;
        CLR_IF_ID   = 1'b0;
        CLR_ID_EX   = 1'b0;

        // 1. Xử lý Load-Use Hazard
        // Stall nếu: Lệnh EX là Load AND (rd_ex trùng rs1 HOẶC (rd_ex trùng rs2 VÀ lệnh ID có dùng rs2))
        if (is_load_ex && (rd_ex != 5'd0) && 
           ((rd_ex == rs1_id) || (uses_rs2 && (rd_ex == rs2_id)))) begin
            Stall_PC    = 1'b1;
            Stall_IF_ID = 1'b1;
            CLR_ID_EX   = 1'b1;
        end

        // 2. Xử lý Control Hazard (PCsel)
        else if (PCsel) begin
            CLR_IF_ID = 1'b1;
            CLR_ID_EX = 1'b1;
        end
    end

endmodule