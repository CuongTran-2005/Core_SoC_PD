library verilog;
use verilog.vl_types.all;
entity RISC_V is
    port(
        CLOCK_50        : in     vl_logic;
        KEY             : in     vl_logic_vector(0 downto 0);
        SW              : in     vl_logic_vector(8 downto 0);
        HEX0            : out    vl_logic_vector(6 downto 0);
        HEX1            : out    vl_logic_vector(6 downto 0);
        HEX2            : out    vl_logic_vector(6 downto 0);
        HEX3            : out    vl_logic_vector(6 downto 0);
        HEX4            : out    vl_logic_vector(6 downto 0);
        HEX5            : out    vl_logic_vector(6 downto 0);
        HEX6            : out    vl_logic_vector(6 downto 0);
        HEX7            : out    vl_logic_vector(6 downto 0);
        IFinst          : out    vl_logic_vector(0 to 31);
        IDinst          : out    vl_logic_vector(0 to 31);
        EXinst          : out    vl_logic_vector(0 to 31);
        MEMinst         : out    vl_logic_vector(0 to 31);
        WBinst          : out    vl_logic_vector(0 to 31)
    );
end RISC_V;
