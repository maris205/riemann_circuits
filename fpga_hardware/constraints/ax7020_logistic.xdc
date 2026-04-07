# ============================================================
# AX7020 + AN108 引脚约束 — 基于官方管脚表 (AX7010_AX7020管脚.xlsx)
# AN108 接 J10 扩展口
# ============================================================

# 系统时钟 50MHz
set_property PACKAGE_PIN U18 [get_ports sys_clk]
set_property IOSTANDARD LVCMOS33 [get_ports sys_clk]
create_clock -period 20.000 -name sys_clk [get_ports sys_clk]

# ============================================================
# AN108 DA 接口 — J10 扩展口
# 从 AX7010_AX7020管脚.xlsx 读取的正确引脚
#
# AN108 pin   J10 net     FPGA ball
# DA_D7       IO1_1P      W18
# DA_D6       IO1_1N      W19
# DA_D5       IO1_2P      P14
# DA_D4       IO1_2N      R14
# DA_D3       IO1_3P      Y16
# DA_D2       IO1_3N      Y17
# DA_D1       IO1_4P      V15
# DA_D0       IO1_4N      W15
# DA_CLK      IO1_5P      W14
# DA_WRT      IO1_5N      Y14
# ============================================================

set_property PACKAGE_PIN W18 [get_ports {DA_DATA[7]}]
set_property PACKAGE_PIN W19 [get_ports {DA_DATA[6]}]
set_property PACKAGE_PIN P14 [get_ports {DA_DATA[5]}]
set_property PACKAGE_PIN R14 [get_ports {DA_DATA[4]}]
set_property PACKAGE_PIN Y16 [get_ports {DA_DATA[3]}]
set_property PACKAGE_PIN Y17 [get_ports {DA_DATA[2]}]
set_property PACKAGE_PIN V15 [get_ports {DA_DATA[1]}]
set_property PACKAGE_PIN W15 [get_ports {DA_DATA[0]}]
set_property PACKAGE_PIN W14 [get_ports DA_CLK]
set_property PACKAGE_PIN Y14 [get_ports DA_WRT]

set_property IOSTANDARD LVCMOS33 [get_ports {DA_DATA[*]}]
set_property IOSTANDARD LVCMOS33 [get_ports DA_CLK]
set_property IOSTANDARD LVCMOS33 [get_ports DA_WRT]
set_property SLEW FAST [get_ports {DA_DATA[*]}]
set_property SLEW FAST [get_ports DA_CLK]
set_property SLEW FAST [get_ports DA_WRT]
