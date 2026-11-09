library verilog;
use verilog.vl_types.all;
entity Hazard_Detection_Unit is
    port(
        instID          : in     vl_logic_vector(31 downto 0);
        instEX          : in     vl_logic_vector(31 downto 0);
        PCsel           : in     vl_logic;
        Stall_PC        : out    vl_logic;
        Stall_IF_ID     : out    vl_logic;
        CLR_IF_ID       : out    vl_logic;
        CLR_ID_EX       : out    vl_logic
    );
end Hazard_Detection_Unit;
