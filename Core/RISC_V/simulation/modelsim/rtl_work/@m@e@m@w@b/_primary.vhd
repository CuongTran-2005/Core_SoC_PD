library verilog;
use verilog.vl_types.all;
entity MEMWB is
    port(
        clk             : in     vl_logic;
        rst             : in     vl_logic;
        PC_plus_4       : in     vl_logic_vector(31 downto 0);
        ALU_result      : in     vl_logic_vector(31 downto 0);
        mem             : in     vl_logic_vector(31 downto 0);
        inst            : in     vl_logic_vector(31 downto 0);
        PC_plus_4_out   : out    vl_logic_vector(31 downto 0);
        ALU_result_out  : out    vl_logic_vector(31 downto 0);
        mem_out         : out    vl_logic_vector(31 downto 0);
        inst_out        : out    vl_logic_vector(31 downto 0)
    );
end MEMWB;
