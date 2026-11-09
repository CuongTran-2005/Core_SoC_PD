library verilog;
use verilog.vl_types.all;
entity Fowarding_Unit is
    port(
        instEX          : in     vl_logic_vector(31 downto 0);
        instMEM         : in     vl_logic_vector(31 downto 0);
        instWB          : in     vl_logic_vector(31 downto 0);
        fwAsel          : out    vl_logic_vector(1 downto 0);
        fwBsel          : out    vl_logic_vector(1 downto 0)
    );
end Fowarding_Unit;
