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
        else if (clr) begin
            PCout <= 32'd0;
            inst_out <= 32'h00000013;
        end 
        else if (!stall) begin
            PCout <= PC;
            inst_out <= inst;
        end
    end
    
endmodule