module IMEM (
    input  wire        clk,
    input  wire        rst,
    input  wire        stall_if,
    input  wire [31:0] pc_in,

    // Arbiter interface
    output wire        imem_req,
    output wire [31:0] imem_addr,
    input  wire [31:0] imem_rdata,
    input  wire        imem_ready,

    output wire        imem_busy,
    output wire [31:0] inst_out
);

    reg        busy;
    reg [31:0] inst_reg;

    assign imem_req  = busy && !stall_if;
    assign imem_addr = {pc_in[31:2], 2'b00};
    assign imem_busy = busy && !imem_ready;
    assign inst_out  = imem_ready ? imem_rdata : inst_reg;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            busy     <= 1'b1;
            inst_reg <= 32'h00000013; //lệnh NOP addi x0,0,0
        end
        else begin
            if (busy && imem_ready) begin
                inst_reg <= imem_rdata;
                if (stall_if)
                    busy <= 1'b0;
            end
            else if (!busy && !stall_if) begin
                busy <= 1'b1;
            end
        end
    end

endmodule
