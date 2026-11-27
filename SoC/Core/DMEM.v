module DMEM (
    input         clk,
    input         rst,
	 
    input         imem_busy,

    input         mem_valid,
    input  [31:0] addr,
    input  [31:0] wdata,
    input         MemRW,
    input  [2:0]  funct3,
    output [31:0] rdata,
    output        dmem_busy,

    // Request interface to Arbiter
    output        dmem_req,
    output [31:0] dmem_addr,
    output        dmem_we,
    output [31:0] dmem_wdata,

    // Response interface from Arbiter
    input         dmem_ready,
    input  [31:0] dmem_rdata
);

    localparam READ  = 1'b0;
    localparam WRITE = 1'b1;

    reg STATE;
    reg active;
	 
    reg done;
    reg [31:0] rdata_reg;

    reg [31:0] addr_reg;
    reg [31:0] wdata_reg;
    reg [31:0] temp_word;

    reg [2:0] funct3_reg;
    reg       MemRW_reg;
    reg [1:0] byte_offset;

	// XỬ LÝ SOTRE 
    always @(*) begin
        temp_word = rdata_reg;
        case (funct3_reg)
            3'b000: begin // SB
						 case (byte_offset)
							  2'b00: temp_word[7:0]   = wdata_reg[7:0];
							  2'b01: temp_word[15:8]  = wdata_reg[7:0];
							  2'b10: temp_word[23:16] = wdata_reg[7:0];
							  2'b11: temp_word[31:24] = wdata_reg[7:0];
						 endcase
					end
            3'b001: begin // SH
						 if (byte_offset[1] == 1'b0)
							  temp_word[15:0]  = wdata_reg[15:0];
						 else
							  temp_word[31:16] = wdata_reg[15:0];
					end
            3'b010: begin // SW
						 temp_word = wdata_reg;
					end
            default: ;
        endcase
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            STATE         <= READ;
            active        <= 1'b0;
            done          <= 1'b0;
            rdata_reg     <= 32'b0;

            addr_reg      <= 32'b0;
            wdata_reg     <= 32'b0;
            funct3_reg    <= 3'b0;
            MemRW_reg     <= 1'b0;
            byte_offset   <= 2'b0;
        end
        else begin
            if (done) begin
                if (!imem_busy)
                    done <= 1'b0;
            end
            else if (!active && mem_valid) begin
                active      <= 1'b1;
                STATE       <= READ;
                addr_reg    <= addr;
                wdata_reg   <= wdata;
                funct3_reg  <= funct3;
                MemRW_reg   <= MemRW;
                byte_offset <= addr[1:0];
            end
            else if (active) begin
                case (STATE)
                    READ: begin
                        if (dmem_ready) begin
                            rdata_reg <= dmem_rdata;
                            if (MemRW_reg) begin
                                STATE <= WRITE;
                            end
                            else begin
                                // Load completed
                                active <= 1'b0;
                                done   <= imem_busy;
                            end
                        end
                    end
                    WRITE: begin
                        if (dmem_ready) begin
                            // Store completed
                            active <= 1'b0;
                            STATE  <= READ;
                            done   <= imem_busy;
                        end
                    end
                endcase
            end
        end
    end

    wire dmem_finish = active && dmem_ready && ((STATE == WRITE) || !MemRW_reg);

    assign dmem_req  = active;
    assign dmem_we   = (STATE == WRITE);
    assign dmem_addr = {addr_reg[31:2], 2'b00};
    assign dmem_wdata = temp_word;
    assign dmem_busy = (active || (mem_valid && !done)) && !dmem_finish;
	
    wire [31:0] load_word = (active && dmem_ready) ? dmem_rdata : rdata_reg;

    wire [7:0] selected_byte =
        (byte_offset == 2'b00) ? load_word[7:0]   :
        (byte_offset == 2'b01) ? load_word[15:8]  :
        (byte_offset == 2'b10) ? load_word[23:16] :
                                 load_word[31:24];

    wire [15:0] selected_half =
        (byte_offset[1] == 1'b0) ?
        load_word[15:0] : load_word[31:16];

    assign rdata =
        (funct3_reg == 3'b000) ? {{24{selected_byte[7]}}, selected_byte} :
        (funct3_reg == 3'b001) ? {{16{selected_half[15]}}, selected_half} :
        (funct3_reg == 3'b010) ? load_word :
        (funct3_reg == 3'b100) ? {24'b0, selected_byte} :
        (funct3_reg == 3'b101) ? {16'b0, selected_half} :
                                 32'b0;

endmodule
