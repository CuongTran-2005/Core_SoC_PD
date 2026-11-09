library verilog;
use verilog.vl_types.all;
entity ImmGen is
    generic(
        IType           : vl_logic_vector(0 to 2) := (Hi0, Hi0, Hi0);
        SType           : vl_logic_vector(0 to 2) := (Hi0, Hi0, Hi1);
        BType           : vl_logic_vector(0 to 2) := (Hi0, Hi1, Hi0);
        UType           : vl_logic_vector(0 to 2) := (Hi0, Hi1, Hi1);
        JType           : vl_logic_vector(0 to 2) := (Hi1, Hi0, Hi0)
    );
    port(
        inst            : in     vl_logic_vector(31 downto 0);
        ImmSel          : in     vl_logic_vector(2 downto 0);
        imm             : out    vl_logic_vector(31 downto 0)
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of IType : constant is 1;
    attribute mti_svvh_generic_type of SType : constant is 1;
    attribute mti_svvh_generic_type of BType : constant is 1;
    attribute mti_svvh_generic_type of UType : constant is 1;
    attribute mti_svvh_generic_type of JType : constant is 1;
end ImmGen;
