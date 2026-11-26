module RISC_V (
    input wire clk,
    input wire rst,

    //========================================
    // AXI4-Lite Master: Read Address
    //========================================
    output wire [31:0] axi_araddr,
    output wire        axi_arvalid,
    input  wire        axi_arready,

    //========================================
    // AXI4-Lite Master: Read Data
    //========================================
    input  wire [31:0] axi_rdata,
    input  wire [1:0]  axi_rresp,
    input  wire        axi_rvalid,
    output wire        axi_rready,

    //========================================
    // AXI4-Lite Master: Write Address
    //========================================
    output wire [31:0] axi_awaddr,
    output wire        axi_awvalid,
    input  wire        axi_awready,

    //========================================
    // AXI4-Lite Master: Write Data
    //========================================
    output wire [31:0] axi_wdata,
    output wire [3:0]  axi_wstrb,
    output wire        axi_wvalid,
    input  wire        axi_wready,

    //========================================
    // AXI4-Lite Master: Write Response
    //========================================
    input  wire [1:0]  axi_bresp,
    input  wire        axi_bvalid,
    output wire        axi_bready
);

    // =========================================================================
    // 1. KHAI BÁO CÁC DÂY NỐI (WIRES)
    // =========================================================================
	 
	 // Dây nối trong datapath 
    // Tầng IF
    wire [31:0] pc_next, pc_curr, pc_plus4_if, inst_if;
    wire        stall_pc, stall_if;
    
    // Tầng ID
    wire [31:0] pc_id, inst_id, rdata1_id, rdata2_id;
    wire stall_ifid, clr_ifid, clr_idex;
	 wire hazard_stall_pc, hazard_stall_ifid;
    
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
    wire mem_rw, is_load_store;

    // Tầng WB
    wire [31:0] pc_plus4_wb, alu_result_wb, mem_data_wb, inst_wb, wdata_wb;
    wire [1:0] wb_sel;
    wire reg_wen_wb;
	 
	 //Tín hiệu điều khiển BUS, arbiter
	 wire imem_req, imem_ready, imem_busy, pipe_stall;
	 wire [31:0] imem_addr;
	 wire [31:0] imem_rdata;
	 
	 wire dmem_busy, dmem_req, dmem_we, dmem_ready;
	 wire [31:0] dmem_addr, dmem_wdata, dmem_rdata;
	 

    // =========================================================================
    // 2. KẾT NỐI CÁC KHỐI (INSTANTIATION)
    // =========================================================================
		
	 // ---------- TẦNG FETCH (IF) ----------
	 assign pc_plus4_if = pc_curr +4;
	 assign pc_next = (pc_sel)? alu_result_ex: pc_plus4_if;
	 
    PC pc_reg (
        .clk(clk), .rst(rst), .Stall_PC(stall_pc), .PCin(pc_next), .PCout(pc_curr)
    );
	 
	 assign stall_if   = dmem_busy;
	 assign pipe_stall = imem_busy | dmem_busy;
	 assign stall_pc   = hazard_stall_pc | pipe_stall;
    assign stall_ifid = hazard_stall_ifid | pipe_stall;
	 
	 IMEM imem (
        .clk(clk),
        .rst(rst),
        .stall_if(stall_if),
        .pc_in(pc_curr),
        .imem_req(imem_req),
        .imem_addr(imem_addr),
        .imem_rdata(imem_rdata),
        .imem_ready(imem_ready),
        .imem_busy(imem_busy),
        .inst_out(inst_if)
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
        .wdata(wdata_wb), .RegWEn(reg_wen_wb & ~pipe_stall),
        .rs1_data(rdata1_id), .rs2_data(rdata2_id),
        .addr(5'b0)
    );

    Hazard_Detection_Unit hazard_unit (
        .instID(inst_id), .instEX(inst_ex), .PCsel(pc_sel),
        .Stall_PC(hazard_stall_pc), .Stall_IF_ID(hazard_stall_ifid), 
        .CLR_IF_ID(clr_ifid), .CLR_ID_EX(clr_idex)
    );

    IDEX idex (
        .clk(clk), .rst(rst), .stall(pipe_stall), .clr(clr_idex),
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
        .clk(clk), .rst(rst), .stall(pipe_stall),
        .PC(pc_ex), .ALU_result(alu_result_ex), .rdata2(mux_b_fwd), .inst(inst_ex),
        .PCout(pc_mem), .ALU_result_out(alu_result_mem), .rdata2_out(rdata2_mem), .inst_out(inst_mem)
    );
	 
	 // ---------- TẦNG MEMORY (MEM) ----------
		
	 DMEM dmem (
        .clk(clk), 
        .rst(rst),
        .imem_busy(imem_busy),
        .mem_valid(is_load_store),
        .addr(alu_result_mem), 
        .wdata(rdata2_mem), 
        .MemRW(mem_rw), 
        .funct3(inst_mem[14:12]), 
        .rdata(mem_data_mem),
        // Giao tiếp qua các cổng port ra ngoài Core để kết nối Arbiter
        .dmem_busy(dmem_busy),
        .dmem_req(dmem_req),
        .dmem_addr(dmem_addr),
        .dmem_we(dmem_we),
        .dmem_wdata(dmem_wdata),
        .dmem_ready(dmem_ready),
        .dmem_rdata(dmem_rdata)
    );
	 
	 
    MEMcontrol mem_control (
        .instM(inst_mem), .MemRW(mem_rw), .is_load_store(is_load_store)
    );
	 
	 MEMWB memwb (
        .clk(clk), .rst(rst), .stall(pipe_stall),
        .PC_plus_4(pc_mem + 4), .ALU_result(alu_result_mem), .mem(mem_data_mem), .inst(inst_mem),
        .PC_plus_4_out(pc_plus4_wb), .ALU_result_out(alu_result_wb), .mem_out(mem_data_wb), .inst_out(inst_wb)
    );


    // ---------- TẦNG WRITE BACK (WB) ----------
    WBcontrol wb_control (
        .instWB(inst_wb), .WBsel(wb_sel), .regWEn(reg_wen_wb)
    );

    assign wdata_wb = (wb_sel == 2'b00) ? pc_plus4_wb :
                      (wb_sel == 2'b01) ? alu_result_wb : mem_data_wb;

	 //---------------Nối Aarbiter ----------------

	 Arbiter u_arbiter (
		 .clk          (clk),
		 .rst          (rst),

		 //========================================
		 // IMEM
		 //========================================
		 .imem_req     (imem_req),
		 .imem_addr    (imem_addr),
		 .imem_rdata   (imem_rdata),
		 .imem_ready   (imem_ready),

		 //========================================
		 // DMEM
		 //========================================
		 .dmem_req     (dmem_req),
		 .dmem_busy    (dmem_busy),
		 .dmem_addr    (dmem_addr),
		 .dmem_we      (dmem_we),
		 .dmem_wdata   (dmem_wdata),
		 .dmem_rdata   (dmem_rdata),
		 .dmem_ready   (dmem_ready),

		 //========================================
		 // AXI4-Lite Read Address
		 //========================================
		 .axi_araddr   (axi_araddr),
		 .axi_arvalid  (axi_arvalid),
		 .axi_arready  (axi_arready),

		 //========================================
		 // AXI4-Lite Read Data
		 //========================================
		 .axi_rdata    (axi_rdata),
		 .axi_rresp    (axi_rresp),
		 .axi_rvalid   (axi_rvalid),
		 .axi_rready   (axi_rready),

		 //========================================
		 // AXI4-Lite Write Address
		 //========================================
		 .axi_awaddr   (axi_awaddr),
		 .axi_awvalid  (axi_awvalid),
		 .axi_awready  (axi_awready),

		 //========================================
		 // AXI4-Lite Write Data
		 //========================================
		 .axi_wdata    (axi_wdata),
		 .axi_wstrb    (axi_wstrb),
		 .axi_wvalid   (axi_wvalid),
		 .axi_wready   (axi_wready),

		 //========================================
		 // AXI4-Lite Write Response
		 //========================================
		 .axi_bresp    (axi_bresp),
		 .axi_bvalid   (axi_bvalid),
		 .axi_bready   (axi_bready)
	);


	
endmodule
	 
	 