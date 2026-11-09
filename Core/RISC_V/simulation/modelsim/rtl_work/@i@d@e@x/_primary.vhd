library verilog;
use verilog.vl_types.all;
entity IDEX is
    port(
        clk             : in     vl_logic;
        rst             : in     vl_logic;
        clr             : in     vl_logic;
        PC              : in     vl_logic_vector(31 downto 0);
        rdata1          : in     vl_logic_vector(31 downto 0);
        rdata2          : in     vl_logic_vector(31 downto 0);
        inst            : in     vl_logic_vector(31 downto 0);
        PCout           : out    vl_logic_vector(31 downto 0);
        rdata1_out      : out    vl_logic_vector(31 downto 0);
        rdata2_out      : out    vl_logic_vector(31 downto 0);
        inst_out        : out    vl_logic_vector(31 downto 0)
    );
end IDEX;
