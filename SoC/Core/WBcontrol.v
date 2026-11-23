module WBcontrol (
	input [31:0] instWB,
	output [1:0] WBsel,
	output regWEn
);

	wire [6:0] opcode = instWB[6:0];
	
	assign regWEn = ((opcode == 7'b0100011)||(opcode == 7'b1100011))? 1'b0 : 1'b1;
	
	assign WBsel = (opcode == 7'b0000011)? 2'b10 :
						((opcode == 7'b1101111)||(opcode == 7'b1100111))? 2'b00 :
						2'b01;

endmodule