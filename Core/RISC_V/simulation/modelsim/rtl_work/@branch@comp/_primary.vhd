library verilog;
use verilog.vl_types.all;
entity BranchComp is
    port(
        rs1             : in     vl_logic_vector(31 downto 0);
        rs2             : in     vl_logic_vector(31 downto 0);
        BrUn            : in     vl_logic;
        BrEq            : out    vl_logic;
        BrLt            : out    vl_logic
    );
end BranchComp;
