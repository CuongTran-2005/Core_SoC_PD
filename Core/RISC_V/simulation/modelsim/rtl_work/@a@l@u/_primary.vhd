library verilog;
use verilog.vl_types.all;
entity ALU is
    port(
        A               : in     vl_logic_vector(31 downto 0);
        B               : in     vl_logic_vector(31 downto 0);
        ALU_Control     : in     vl_logic_vector(3 downto 0);
        \out\           : out    vl_logic_vector(31 downto 0)
    );
end ALU;
