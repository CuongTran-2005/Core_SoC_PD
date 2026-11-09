library verilog;
use verilog.vl_types.all;
entity PC is
    port(
        clk             : in     vl_logic;
        rst             : in     vl_logic;
        Stall_PC        : in     vl_logic;
        PCin            : in     vl_logic_vector(31 downto 0);
        PCout           : out    vl_logic_vector(31 downto 0)
    );
end PC;
