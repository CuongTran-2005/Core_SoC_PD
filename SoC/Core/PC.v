module PC (
    input clk,
    input rst,
    input Stall_PC,
    input [31:0] PCin,
    output reg [31:0] PCout
);
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            PCout <= 32'h00400000;
        end
        else if (!Stall_PC) begin
            PCout <= PCin;
        end
    end
endmodule