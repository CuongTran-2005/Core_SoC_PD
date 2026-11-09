library verilog;
use verilog.vl_types.all;
entity EXcontrol is
    port(
        instEX          : in     vl_logic_vector(31 downto 0);
        BrEQ            : in     vl_logic;
        BrLT            : in     vl_logic;
        ImmSel          : out    vl_logic_vector(2 downto 0);
        BrUn            : out    vl_logic;
        Bsel            : out    vl_logic;
        Asel            : out    vl_logic;
        ALUsel          : out    vl_logic_vector(3 downto 0);
        PCSel           : out    vl_logic
    );
end EXcontrol;
