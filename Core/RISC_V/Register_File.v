module Register_File (
    input         clk,
    input         rst,
    input         RegWEn,
    input  [4:0]  rs1_addr,
    input  [4:0]  rs2_addr,
    input  [4:0]  rd_addr,
    input  [31:0] wdata,
    output [31:0] rs1_data,
    output [31:0] rs2_data,
	 input  [4:0]  addr,
	 output [31:0] output_rf 
);

    reg [31:0] rf [31:0];

    assign rs1_data = (rs1_addr == 5'b0) ? 32'b0 : 
                     ((rs1_addr == rd_addr) && RegWEn) ? wdata : rf[rs1_addr];

    assign rs2_data = (rs2_addr == 5'b0) ? 32'b0 : 
                     ((rs2_addr == rd_addr) && RegWEn) ? wdata : rf[rs2_addr];

    integer i;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (i = 0; i < 32; i = i + 1) begin
                rf[i] <= 32'b0;
            end
				
				rf[2] <= 32'h7fffeffc;
				rf[3] <= 32'h10008000;
        end 
        else if (RegWEn && (rd_addr != 5'b0)) begin
            rf[rd_addr] <= wdata;
        end
    end
	 
	 assign output_rf = rf[addr];

endmodule