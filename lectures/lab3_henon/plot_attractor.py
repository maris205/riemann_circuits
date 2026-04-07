"""Lab 3: 画 Hénon 奇异吸引子"""
import numpy as np
import matplotlib.pyplot as plt

data = np.loadtxt('henon_attractor.txt')
x, y = data[:, 0], data[:, 1]

fig, ax = plt.subplots(figsize=(8, 6))
ax.scatter(x, y, s=0.3, c='steelblue', alpha=0.5)
ax.set_xlabel('x', fontsize=12)
ax.set_ylabel('y', fontsize=12)
ax.set_title('FPGA Hénon Map: Strange Attractor (Q4.28)', fontsize=13, fontweight='bold')
ax.grid(True, alpha=0.3)
plt.tight_layout()
plt.savefig('henon_attractor_fpga.png', dpi=200)
plt.show()
print('Saved henon_attractor_fpga.png')
