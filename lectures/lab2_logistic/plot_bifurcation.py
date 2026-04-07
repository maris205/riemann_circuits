"""
Lab 2: 画分岔图
从 Vivado 仿真输出文件 bifurcation_data.txt 读取数据并画图。

使用: python plot_bifurcation.py
"""
import numpy as np
import matplotlib.pyplot as plt

# 读取仿真数据
data = np.loadtxt('bifurcation_data.txt')
mu = data[:, 0]
x = data[:, 1]

# 画分岔图
fig, ax = plt.subplots(figsize=(12, 7))
ax.scatter(mu, x, s=0.3, c='black', alpha=0.3)
ax.set_xlabel('μ', fontsize=14)
ax.set_ylabel('x', fontsize=14)
ax.set_title('FPGA Logistic Map: Bifurcation Diagram (Q4.28 Fixed-Point)',
             fontsize=14, fontweight='bold')
ax.grid(True, alpha=0.3)

# 标注关键区域
ax.axvline(x=1.5437, color='red', linestyle='--', alpha=0.5, label='μ_c (Feigenbaum)')
ax.legend(fontsize=11)

plt.tight_layout()
plt.savefig('bifurcation_fpga.png', dpi=200)
plt.show()
print('Saved bifurcation_fpga.png')
