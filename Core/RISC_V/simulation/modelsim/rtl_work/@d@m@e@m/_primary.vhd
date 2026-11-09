library verilog;
use verilog.vl_types.all;
entity DMEM is
    generic(
        BASE_ADDRESS    : integer := 268500992;
        RAM_SIZE        : integer := 1024
    );
    port(
        clk             : in     vl_logic;
        addr            : in     vl_logic_vector(31 downto 0);
        wdata           : in     vl_logic_vector(31 downto 0);
        MemRW           : in     vl_logic;
        funct3          : in     vl_logic_vector(2 downto 0);
        rdata           : out    vl_logic_vector(31 downto 0);
        addr_output     : in     vl_logic_vector(7 downto 0);
        output_dmem     : out    vl_logic_vector(31 downto 0)
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of BASE_ADDRESS : constant is 1;
    attribute mti_svvh_generic_type of RAM_SIZE : constant is 1;
end DMEM;
