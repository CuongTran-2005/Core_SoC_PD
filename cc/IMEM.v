module IMEM (
    input  wire        clk,
    input  wire        rst,
    input  wire        stall_if,
    input  wire [31:0] pc_in,

    // Arbiter interface
    output wire        imem_req,
    output wire [9:0]  imem_addr,
    input  wire [31:0] imem_rdata,
    input  wire        imem_ready,

    output reg  [31:0] inst_out
);

    assign imem_req  = ~stall_if;
    assign imem_addr = pc_in[11:2];

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            inst_out   <= 32'h00000013; //lệnh NOP addi x0,0,0
        end
        else begin
            if (imem_ready && !stall_if) begin
                inst_out   <= imem_rdata;
            end
        end
    end

endmodule
