# Vivado 2022.2。只做功能综合，不布局布线。
set origin [file normalize [file join [file dirname [info script]] ..]]
set proj_dir [file join $origin vivado motor_foc]
create_project motor_foc $proj_dir -part xc7k325tffg900-2 -force
set_property target_language Verilog [current_project]
set_property simulator_language Verilog [current_project]
add_files [glob [file join $origin rtl *.v]]
set_property include_dirs [list [file join $origin rtl]] [current_fileset]
set_property top top_integration [current_fileset]
add_files -fileset constrs_1 [file join $origin constraints motor.xdc]
add_files -fileset sim_1 [glob [file join $origin sim tb_*.v]]
set_property include_dirs [list [file join $origin rtl]] [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1
set status [get_property STATUS [get_runs synth_1]]
puts "SYNTH_STATUS $status"
if {![string match "*Complete*" $status]} {
    exit 1
}
exit 0
