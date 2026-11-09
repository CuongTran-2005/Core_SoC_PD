transcript on
if {[file exists rtl_work]} {
	vdel -lib rtl_work -all
}
vlib rtl_work
vmap work rtl_work

vlog -vlog01compat -work work +incdir+E:/HK6/HDL/doan/verilog/verilog/WBcontrol {E:/HK6/HDL/doan/verilog/verilog/WBcontrol/WBcontrol.v}
vlog -vlog01compat -work work +incdir+E:/HK6/HDL/doan/verilog/verilog/RegisterFile {E:/HK6/HDL/doan/verilog/verilog/RegisterFile/Register_File.v}
vlog -vlog01compat -work work +incdir+E:/HK6/HDL/doan/verilog/verilog/PC {E:/HK6/HDL/doan/verilog/verilog/PC/PC.v}
vlog -vlog01compat -work work +incdir+E:/HK6/HDL/doan/verilog/verilog/MEMWB {E:/HK6/HDL/doan/verilog/verilog/MEMWB/MEMWB.v}
vlog -vlog01compat -work work +incdir+E:/HK6/HDL/doan/verilog/verilog/MEMcontrol {E:/HK6/HDL/doan/verilog/verilog/MEMcontrol/MEMcontrol.v}
vlog -vlog01compat -work work +incdir+E:/HK6/HDL/doan/verilog/verilog/ImmGen {E:/HK6/HDL/doan/verilog/verilog/ImmGen/ImmGen.v}
vlog -vlog01compat -work work +incdir+E:/HK6/HDL/doan/verilog/verilog/IFID {E:/HK6/HDL/doan/verilog/verilog/IFID/IFID.v}
vlog -vlog01compat -work work +incdir+E:/HK6/HDL/doan/verilog/verilog/IDEX {E:/HK6/HDL/doan/verilog/verilog/IDEX/IDEX.v}
vlog -vlog01compat -work work +incdir+E:/HK6/HDL/doan/verilog/verilog/Hazard_Detection_Unit {E:/HK6/HDL/doan/verilog/verilog/Hazard_Detection_Unit/Hazard_Detection_Unit.v}
vlog -vlog01compat -work work +incdir+E:/HK6/HDL/doan/verilog/verilog/Fowarding_Unit {E:/HK6/HDL/doan/verilog/verilog/Fowarding_Unit/Fowarding_Unit.v}
vlog -vlog01compat -work work +incdir+E:/HK6/HDL/doan/verilog/verilog/EXMEM {E:/HK6/HDL/doan/verilog/verilog/EXMEM/EXMEM.v}
vlog -vlog01compat -work work +incdir+E:/HK6/HDL/doan/verilog/verilog/EXcontrol {E:/HK6/HDL/doan/verilog/verilog/EXcontrol/EXcontrol.v}
vlog -vlog01compat -work work +incdir+E:/HK6/HDL/doan/verilog/verilog/BranchComp {E:/HK6/HDL/doan/verilog/verilog/BranchComp/BranchComp.v}
vlog -vlog01compat -work work +incdir+E:/HK6/HDL/doan/verilog/verilog/ALU {E:/HK6/HDL/doan/verilog/verilog/ALU/ALU.v}
vlog -vlog01compat -work work +incdir+E:/HK6/HDL/doan/verilog/verilog/RISC_V {E:/HK6/HDL/doan/verilog/verilog/RISC_V/RISC_V.v}
vlog -vlog01compat -work work +incdir+E:/HK6/HDL/doan/verilog/verilog/RISC_V {E:/HK6/HDL/doan/verilog/verilog/RISC_V/HexDigit.v}
vlog -vlog01compat -work work +incdir+E:/HK6/HDL/doan/verilog/verilog/IMEM {E:/HK6/HDL/doan/verilog/verilog/IMEM/IMEM.v}
vlog -vlog01compat -work work +incdir+E:/HK6/HDL/doan/verilog/verilog/DMEM {E:/HK6/HDL/doan/verilog/verilog/DMEM/DMEM.v}

vlog -vlog01compat -work work +incdir+E:/HK6/HDL/doan/verilog/verilog/RISC_V {E:/HK6/HDL/doan/verilog/verilog/RISC_V/pipeline_tb.v}

vsim -t 1ps -L altera_ver -L lpm_ver -L sgate_ver -L altera_mf_ver -L altera_lnsim_ver -L cycloneii_ver -L rtl_work -L work -voptargs="+acc"  pipeline_tb

add wave *
view structure
view signals
run -all
