"""
Lab 5: 画混沌波形 + 对比不同 μ 的行为

读取 Vivado 仿真输出，画时域波形。
学生需要对 6 个不同 μ 值各跑一次仿真，收集截图。
"""
import numpy as np
import matplotlib.pyplot as plt

# 读取仿真数据
data = np.loadtxt('chaos_waveform.txt')
print(f'Loaded {len(data)} samples')

fig, axes = plt.subplots(2, 1, figsize=(14, 8))

# 时域波形
ax = axes[0]
ax.plot(data, 'b-', linewidth=0.5)
ax.set_xlabel('Iteration n', fontsize=12)
ax.set_ylabel('DAC Output (0-255)', fontsize=12)
ax.set_title('Chaos Signal Generator — Time Domain Waveform',
             fontsize=13, fontweight='bold')
ax.axhline(y=128, color='gray', linestyle='--', alpha=0.3, label='Midpoint')
ax.legend()
ax.grid(True, alpha=0.3)

# 回归映射 x[n+1] vs x[n]
ax = axes[1]
ax.scatter(data[:-1], data[1:], s=0.5, c='steelblue', alpha=0.5)
ax.set_xlabel('x[n]', fontsize=12)
ax.set_ylabel('x[n+1]', fontsize=12)
ax.set_title('Return Map (x[n+1] vs x[n])',
             fontsize=13, fontweight='bold')
ax.grid(True, alpha=0.3)

plt.tight_layout()
plt.savefig('chaos_waveform.png', dpi=200)
plt.show()
print('Saved chaos_waveform.png')

# 统计信息
print(f'\nSignal Statistics:')
print(f'  Mean:  {data.mean():.1f}')
print(f'  Std:   {data.std():.1f}')
print(f'  Min:   {data.min():.0f}')
print(f'  Max:   {data.max():.0f}')
print(f'  Range: {data.max()-data.min():.0f}')

if data.std() < 5:
    print('  → Periodic behavior (stable fixed point)')
elif data.std() < 30:
    print('  → Period-2 or Period-4 oscillation')
else:
    print('  → Chaotic behavior!')
