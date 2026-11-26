module IFID(
    input clk,
    input rst,
    input stall,
    input clr,
    input [31:0] PC,
    input [31:0] inst,
    output reg [31:0] PCout,
    output reg [31:0] inst_out    
);

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            PCout <= 32'd0;
            inst_out <= 32'h00000013;
        end 
        // (*) sửa lại "ưu tiên stall trước clr để không xóa mất lệnh khi pipeline đang dừng chờ bộ nhớ AXI" //
        else if (!stall) begin
            if (clr) begin
                PCout <= 32'd0;
                inst_out <= 32'h00000013;
            end 
            else begin
                PCout <= PC;
                inst_out <= inst;
            end
        end
    end
    
endmodule