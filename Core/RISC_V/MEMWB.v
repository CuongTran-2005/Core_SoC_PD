module MEMWB(
    input clk,
    input rst,
    input [31:0] PC_plus_4,
    input [31:0] ALU_result,
    input [31:0] mem,
    input [31:0] inst,
    output reg [31:0] PC_plus_4_out,
    output reg [31:0] ALU_result_out,
    output reg [31:0] mem_out,
    output reg [31:0] inst_out
);

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            PC_plus_4_out <= 32'd0;
            ALU_result_out <= 32'd0;
            mem_out <= 32'd0;
            inst_out <= 32'h00000013;
        end else begin
            PC_plus_4_out <= PC_plus_4;
            ALU_result_out <= ALU_result;
            mem_out <= mem;
            inst_out <= inst;
        end
    end
    
endmodule