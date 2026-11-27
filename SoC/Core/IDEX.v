module IDEX(
    input clk,
    input rst,
    // (*) sửa lại "thêm cổng stall để đóng băng tầng ID/EX khi pipeline chờ IMEM/DMEM" //
    input stall,
    input clr,
    input [31:0] PC,
    input [31:0] rdata1,
    input [31:0] rdata2,
    input [31:0] inst,
    output reg [31:0] PCout,
    output reg [31:0] rdata1_out,
    output reg [31:0] rdata2_out,
    output reg [31:0] inst_out
);

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            PCout      <= 32'd0;
            rdata1_out <= 32'd0;
            rdata2_out <= 32'd0;
            inst_out   <= 32'h00000013;
        // (*) sửa lại "ưu tiên stall trước clr để giữ nguyên trạng thái tầng ID/EX khi chờ bộ nhớ AXI" //
        end else if (!stall) begin
            if (clr) begin
                PCout      <= 32'd0;
                rdata1_out <= 32'd0;
                rdata2_out <= 32'd0;
                inst_out   <= 32'h00000013;
            end else begin
                PCout      <= PC;
                rdata1_out <= rdata1;
                rdata2_out <= rdata2;
                inst_out   <= inst;
            end
        end
    end
    
endmodule