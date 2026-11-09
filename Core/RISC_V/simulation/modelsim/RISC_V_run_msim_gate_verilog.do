transcript on
if {[file exists gate_work]} {
	vdel -lib gate_work -all
}
vlib gate_work
vmap work gate_work

vlog -vlog01compat -work work +incdir+. {RISC_V.vo}

vlog -vlog01compat -work work +incdir+E:/HK6/HDL/doan/verilog/verilog/RISC_V {E:/HK6/HDL/doan/verilog/verilog/RISC_V/RISC_V_tb.v}

vsim -t 1ps +transport_int_delays +transport_path_delays -L cycloneii_ver -L gate_work -L work -voptargs="+acc"  RISC_V_tb

add wave *
view structure
view signals
run -all
