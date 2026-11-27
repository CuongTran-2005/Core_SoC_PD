module MEMcontrol (
	input [31:0] instM,
	output MemRW
);

	wire [6:0] opcode = instM[6:0];

	assign MemRW = (opcode == 7'b0100011);
endmodule

	