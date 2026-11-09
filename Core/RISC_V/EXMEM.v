module EXMEM(
    input clk,
    input rst,
    input [31:0] PC,
    input [31:0] ALU_result,
    input [31:0] rdata2,
    input [31:0] inst,
    output reg [31:0] PCout,
    output reg [31:0] ALU_result_out,
    output reg [31:0] rdata2_out,
    output reg [31:0] inst_out
);

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            PCout <= 32'd0;
            ALU_result_out <= 32'd0;
            rdata2_out <= 32'd0;
            inst_out <= 32'h00000013;
        end else begin
            PCout <= PC;
            ALU_result_out <= ALU_result;
            rdata2_out <= rdata2;
            inst_out <= inst;
        end
    end
    
endmodule