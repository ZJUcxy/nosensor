# 时钟约束。器件 xc7k325tffg900-2，Vivado 2022.2。
# 板级管脚未定时，这里不写 LOC。AXI 与核心同为 clk_in 经 BUFG 后的 100 MHz。
# 19.2 MHz 由 MMCM 从该 100 MHz 导出，不另建 create_clock。

create_clock -name clk_in -period 10.000 [get_ports clk_in_i]

# 硬件复位异步置位、同步释放
set_false_path -from [get_ports rst_hw_n_i]

# S0 翻转从 19.2 MHz 进入 100 MHz，只约束第一级同步器
set_max_delay -datapath_only 10.000 \
    -from [get_cells -hier -filter {NAME =~ *s0_toggle_reg}] \
    -to   [get_cells -hier -filter {NAME =~ *cdc_s0_ff_reg[0]*}]

# FO 为异步低有效输入
set_max_delay -datapath_only 10.000 \
    -from [get_ports ipm_fo_i] \
    -to   [get_cells -hier -filter {NAME =~ *fo_ff_reg[0]*}]

set_property ASYNC_REG TRUE [get_cells -hier -filter {NAME =~ *cdc_s0_ff_reg*}]
set_property ASYNC_REG TRUE [get_cells -hier -filter {NAME =~ *fo_ff_reg*}]
