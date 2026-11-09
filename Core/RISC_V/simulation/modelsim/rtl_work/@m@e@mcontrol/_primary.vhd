library verilog;
use verilog.vl_types.all;
entity MEMcontrol is
    port(
        instM           : in     vl_logic_vector(31 downto 0);
        MemRW           : out    vl_logic
    );
end MEMcontrol;
