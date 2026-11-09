library verilog;
use verilog.vl_types.all;
entity Register_File is
    port(
        clk             : in     vl_logic;
        rst             : in     vl_logic;
        RegWEn          : in     vl_logic;
        rs1_addr        : in     vl_logic_vector(4 downto 0);
        rs2_addr        : in     vl_logic_vector(4 downto 0);
        rd_addr         : in     vl_logic_vector(4 downto 0);
        wdata           : in     vl_logic_vector(31 downto 0);
        rs1_data        : out    vl_logic_vector(31 downto 0);
        rs2_data        : out    vl_logic_vector(31 downto 0);
        addr            : in     vl_logic_vector(4 downto 0);
        output_rf       : out    vl_logic_vector(31 downto 0)
    );
end Register_File;
