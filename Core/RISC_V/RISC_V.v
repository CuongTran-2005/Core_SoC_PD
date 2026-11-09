module RISC_V (
    input CLOCK_50,
    input [0:0] KEY,
	 input [8:0] SW,
	 output [6:0] HEX0, HEX1, HEX2, HEX3, HEX4, HEX5, HEX6, HEX7,
	 output [0:31] IFinst, IDinst, EXinst, MEMinst, WBinst
);

    // =========================================================================
    // 1. KHAI BÁO CÁC DÂY NỐI (WIRES)
    // =========================================================================
	 
	 wire clk = CLOCK_50;
	 wire rst = !KEY[0]; 

    // Dây nối dùng để kiểm tra
	 
	 wire [31:0] rf_output_wire, dmem_output_wire, output_wire; 
	 
	 
	 // Dây nối trong datapath 
    // Tầng IF
    wire [31:0] pc_next, pc_curr, pc_plus4_if, inst_if;
    
    // Tầng ID
    wire [31:0] pc_id, inst_id, rdata1_id, rdata2_id;
    wire stall_pc, stall_ifid, clr_ifid, clr_idex;
    
    // Tầng EX
    wire [31:0] pc_ex, rdata1_ex, rdata2_ex, inst_ex, imm_ex;
    wire [31:0] mux_a_fwd, mux_b_fwd, alu_a, alu_b, alu_result_ex;
    wire [1:0] fwAsel, fwBsel;
    wire br_eq, br_lt;
    // Tín hiệu từ EXcontrol
    wire [3:0] alu_sel;
    wire asel, bsel, brun, pc_sel;
    wire [2:0] imm_sel;

    // Tầng MEM
    wire [31:0] pc_mem, alu_result_mem, rdata2_mem, inst_mem, mem_data_mem;
    wire mem_rw;

    // Tầng WB
    wire [31:0] pc_plus4_wb, alu_result_wb, mem_data_wb, inst_wb, wdata_wb;
    wire [1:0] wb_sel;
    wire reg_wen_wb;

    // =========================================================================
    // 2. KẾT NỐI CÁC KHỐI (INSTANTIATION)
    // =========================================================================
		
	 // ---------- TẦNG FETCH (IF) ----------
	 assign pc_plus4_if = pc_curr +4;
	 assign pc_next = (pc_sel)? alu_result_ex: pc_plus4_if;
	 
    PC pc_reg (
        .clk(clk), .rst(rst), .Stall_PC(stall_pc), .PCin(pc_next), .PCout(pc_curr)
    );
	 
	 IMEM imem (
        .addr(pc_curr), .inst(inst_if)
    );
	 
	 IFID ifid (
        .clk(clk), .rst(rst), .stall(stall_ifid), .clr(clr_ifid),
        .PC(pc_curr), .inst(inst_if),
        .PCout(pc_id), .inst_out(inst_id)
    );
	 
	 // ---------- TẦNG DECODE (ID) ----------
    Register_File reg_file (
        .clk(clk), .rst(rst),
        .rs1_addr(inst_id[19:15]), .rs2_addr(inst_id[24:20]), .rd_addr(inst_wb[11:7]),
        .wdata(wdata_wb), .RegWEn(reg_wen_wb),
        .rs1_data(rdata1_id), .rs2_data(rdata2_id),
		  //kiem tra output
		  .addr(SW[4:0]),
		  .output_rf(rf_output_wire)
    );

    Hazard_Detection_Unit hazard_unit (
        .instID(inst_id), .instEX(inst_ex), .PCsel(pc_sel),
        .Stall_PC(stall_pc), .Stall_IF_ID(stall_ifid), 
        .CLR_IF_ID(clr_ifid), .CLR_ID_EX(clr_idex)
    );

    IDEX idex (
        .clk(clk), .rst(rst), .clr(clr_idex),
        .PC(pc_id), .rdata1(rdata1_id), .rdata2(rdata2_id), .inst(inst_id),
        .PCout(pc_ex), .rdata1_out(rdata1_ex), .rdata2_out(rdata2_ex), .inst_out(inst_ex)
    );
	 
	 
	  // ---------- TẦNG EXECUTE (EX) ----------

    assign mux_a_fwd = (fwAsel == 2'b00) ? rdata1_ex : 
                       (fwAsel == 2'b01) ? wdata_wb: alu_result_mem;
    assign mux_b_fwd = (fwBsel == 2'b00) ? rdata2_ex : 
                       (fwBsel == 2'b01) ? wdata_wb: alu_result_mem;

    ImmGen imm_gen (
        .inst(inst_ex), .ImmSel(imm_sel), .imm(imm_ex)
    );

    // Bộ chọn toán hạng ALU (Asel, Bsel)
    assign alu_a = (asel) ? pc_ex : mux_a_fwd;
    assign alu_b = (bsel) ? imm_ex : mux_b_fwd;

    ALU alu (
        .A(alu_a), .B(alu_b), .ALU_Control(alu_sel), .out(alu_result_ex)
    );

    BranchComp branch_comp (
        .rs1(mux_a_fwd), .rs2(mux_b_fwd), .BrUn(brun), .BrEq(br_eq), .BrLt(br_lt)
    );

    EXcontrol ex_control (
        .instEX(inst_ex), .BrEQ(br_eq), .BrLT(br_lt),
        .ImmSel(imm_sel), .BrUn(brun), .Bsel(bsel), .Asel(asel), 
        .ALUsel(alu_sel), .PCSel(pc_sel)
    );

    Fowarding_Unit fwd_unit (
        .instEX(inst_ex), .instMEM(inst_mem), .instWB(inst_wb),
        .fwAsel(fwAsel), .fwBsel(fwBsel)
    );

    EXMEM exmem (
        .clk(clk), .rst(rst),
        .PC(pc_ex), .ALU_result(alu_result_ex), .rdata2(mux_b_fwd), .inst(inst_ex),
        .PCout(pc_mem), .ALU_result_out(alu_result_mem), .rdata2_out(rdata2_mem), .inst_out(inst_mem)
    );
	 
	 // ---------- TẦNG MEMORY (MEM) ----------
    DMEM dmem (
        .clk(clk), .addr(alu_result_mem), .wdata(rdata2_mem), 
        .MemRW(mem_rw), .funct3(inst_mem[14:12]), .rdata(mem_data_mem),
		  //kiem tra output
		  .addr_output(SW[7:0]),
		  .output_dmem(dmem_output_wire)
    );

    MEMcontrol mem_control (
        .instM(inst_mem), .MemRW(mem_rw)
    );
	 
	 MEMWB memwb (
        .clk(clk), .rst(rst),
        .PC_plus_4(pc_mem + 4), .ALU_result(alu_result_mem), .mem(mem_data_mem), .inst(inst_mem),
        .PC_plus_4_out(pc_plus4_wb), .ALU_result_out(alu_result_wb), .mem_out(mem_data_wb), .inst_out(inst_wb)
    );


    // ---------- TẦNG WRITE BACK (WB) ----------
    WBcontrol wb_control (
        .instWB(inst_wb), .WBsel(wb_sel), .regWEn(reg_wen_wb)
    );

    assign wdata_wb = (wb_sel == 2'b00) ? pc_plus4_wb :
                      (wb_sel == 2'b01) ? alu_result_wb : mem_data_wb;
							 
	
	 // ----------- Kiểm tra output ---------------
	 assign output_wire = (SW[8])? dmem_output_wire: rf_output_wire;
	 
	 HexDigit h0(output_wire[3:0],   HEX0);
    HexDigit h1(output_wire[7:4],   HEX1);
    HexDigit h2(output_wire[11:8],  HEX2);
    HexDigit h3(output_wire[15:12], HEX3);
	 HexDigit h4(output_wire[19:16], HEX4);
    HexDigit h5(output_wire[23:20], HEX5);
    HexDigit h6(output_wire[27:24], HEX6);
    HexDigit h7(output_wire[31:28], HEX7);
	
	 assign IFinst = inst_if;
	 assign IDinst = inst_id;
	 assign EXinst = inst_ex;
	 assign MEMinst = inst_mem;
	 assign WBinst = inst_wb;
	 
endmodule
	 
	 