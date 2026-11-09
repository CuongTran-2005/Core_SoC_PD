library verilog;
use verilog.vl_types.all;
entity WBcontrol is
    port(
        instWB          : in     vl_logic_vector(31 downto 0);
        WBsel           : out    vl_logic_vector(1 downto 0);
        regWEn          : out    vl_logic
    );
end WBcontrol;
