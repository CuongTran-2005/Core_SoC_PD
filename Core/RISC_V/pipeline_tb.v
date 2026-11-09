`timescale 1ns/1ps

module pipeline_tb();
    reg clk;
    reg rst;
    reg [8:0] sw;
    wire [6:0] hex0, hex1, hex2, hex3, hex4, hex5, hex6, hex7;
	 wire [31:0] IF, ID, EX, MEM, WB;

    integer rf_file;
    integer dmem_file;
    integer i;

    RISC_V dut (
        .CLOCK_50(clk),
        .KEY (!rst),
        .SW (sw),
        .HEX0(hex0), 
        .HEX1(hex1), 
        .HEX2(hex2), 
        .HEX3(hex3), 
        .HEX4(hex4), 
        .HEX5(hex5), 
        .HEX6(hex6), 
        .HEX7(hex7),
		  .IFinst(IF),
		  .IDinst(ID),
		  .EXinst(EX),
		  .MEMinst(MEM),
		  .WBinst(WB)
    );

    always #10 clk = ~clk;

    initial begin
        clk = 0;
        rst = 1;
        sw = 9'b0;
        
        #40;
        rst = 0;

        #5000;
        $display("================ KET QUA KIEM TRA CUOI CUNG ================");
        $display("Register x10 (val): %d", dut.reg_file.rf[10]);
        $display("Register x11 (val): %d", dut.reg_file.rf[11]);
        $display("============================================================\n");
        
        $stop; 
    end

    initial begin
        $timeformat(-9, 1, " ns", 10);
        $monitor("Time: %t | PC: %h | Inst: %h", $time, dut.pc_curr, dut.inst_if);
    end

endmodule