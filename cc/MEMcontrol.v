module MEMcontrol (
	input [31:0] instM,
	output MemRW,
	output is_load_store
);

	wire [6:0] opcode = instM[6:0];

	assign MemRW = (opcode == 7'b0100011);
	
	assign  is_load_store = MemRW || (opcode == 7'b0000011);
	
endmodule

	