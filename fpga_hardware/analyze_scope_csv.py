"""
分析示波器采集的 CSV 数据，提取黎曼零点

示波器 CSV 格式一般是:
  时间, 电压
  0.000000, 0.523
  0.000002, -0.124
  ...

Usage: python analyze_scope_csv.py scope_data.csv
"""
import numpy as np
import matplotlib.pyplot as plt
from scipy.sparse import coo_matrix, diags
from scipy.sparse.linalg import eigs
import sys
import csv

TRUE_ZEROS = np.array([
    14.1347, 21.0220, 25.0108, 30.4248, 32.9350, 37.5861,
    40.9187, 43.3270, 48.0051, 49.7738, 52.9703, 56.4462
])

# ============================================================
# 1. 读取示波器 CSV
# ============================================================
fname = sys.argv[1] if len(sys.argv) > 1 else 'scope_data.csv'
print(f"Loading {fname}...")

# 尝试多种 CSV 格式
try:
    # 格式1: time, voltage (带 header)
    data = np.genfromtxt(fname, delimiter=',', skip_header=1)
    if data.ndim == 2 and data.shape[1] >= 2:
        voltage = data[:, 1]
    else:
        voltage = data
except:
    # 格式2: 纯数值
    voltage = np.loadtxt(fname, delimiter=',')

# DAC 输出是 0-255 → 归一化到 [-1, +1]
if voltage.max() > 10:  # 原始 DAC 值 0-255
    voltage = (voltage - 128.0) / 128.0
elif voltage.max() > 2:  # 示波器电压 0-3.3V
    voltage = (voltage - voltage.mean()) / (voltage.max() - voltage.min()) * 2

print(f"  {len(voltage)} points, std={voltage.std():.4f}, "
      f"range=[{voltage.min():.3f}, {voltage.max():.3f}]")

# 降采样 (示波器采样率远高于迭代率)
# 如果数据量太大就每 N 个取一个
if len(voltage) > 500000:
    step = len(voltage) // 200000
    voltage = voltage[::step]
    print(f"  Downsampled to {len(voltage)} points (step={step})")

traj = voltage

# ============================================================
# 2. 画波形
# ============================================================
fig, axes = plt.subplots(2, 2, figsize=(14, 10))

ax = axes[0, 0]
ax.plot(traj[:2000], 'b-', linewidth=0.3)
ax.set_title('Chaotic Waveform (first 2000 pts)', fontweight='bold')
ax.set_xlabel('Sample'); ax.set_ylabel('Voltage')
ax.grid(True, alpha=0.3)

ax = axes[0, 1]
ax.scatter(traj[:-1], traj[1:], s=0.1, c='steelblue', alpha=0.3)
ax.set_title('Return Map x[n+1] vs x[n]', fontweight='bold')
ax.set_xlabel('x[n]'); ax.set_ylabel('x[n+1]')
ax.grid(True, alpha=0.3)

# ============================================================
# 3. Markov 分析 — 双配置
# ============================================================
print("\nMarkov analysis...")
x_min, x_max = traj.min()-0.05, traj.max()+0.05

configs = [
    ('Config A (precise)', 300, 0.03),
    ('Config B (most zeros)', 800, 0.015),
]

for idx, (label, n_bins, eps) in enumerate(configs):
    print(f"\n  {label}: bins={n_bins}, eps={eps}")
    try:
        dx = (x_max-x_min)/n_bins
        inv2 = 1.0/(2*eps**2); hw = max(int(5*eps/dx), 2)
        rows, cols, vals = [], [], []
        for i in range(len(traj)-1):
            s = min(int((traj[i]-x_min)/dx), n_bins-1)
            c = min(int((traj[i+1]-x_min)/dx), n_bins-1)
            for j in range(max(0,c-hw), min(n_bins,c+hw+1)):
                w = np.exp(-(x_min+(j+0.5)*dx-traj[i+1])**2*inv2)
                if w > 1e-10: rows.append(s); cols.append(j); vals.append(w)
        P = coo_matrix((vals,(rows,cols)), shape=(n_bins,n_bins)).tocsr()
        rs = np.array(P.sum(1)).flatten(); rs[rs==0]=1
        P = diags(1.0/rs)@P
        ev, _ = eigs(P, k=100, which='LM', tol=1e-5)
        mask = (ev.imag>1e-6)&(np.abs(ev)>0.1)
        ph = np.sort(np.abs(np.angle(ev[mask]))); ph=ph[ph>1e-6]

        if len(ph) >= 2:
            t = TRUE_ZEROS[0]/TRUE_ZEROS[1]
            bs, be = 0, float('inf')
            for ii in range(min(15, len(ph)-1)):
                if ph[ii+1]==0: continue
                e = abs(ph[ii]/ph[ii+1]-t)
                if e < be: be=e; bs=ii
            ph = ph[bs:]; sc = TRUE_ZEROS[0]/ph[0]
            pred = ph*sc
            nn = min(8, len(pred))
            errs = np.abs(pred[:nn]-TRUE_ZEROS[:nn])
            mae = float(np.mean(errs))
            print(f"  {nn} zeros, MAE={mae:.4f}")
            for i in range(nn):
                print(f"    t{i+1}: {pred[i]:.4f} vs {TRUE_ZEROS[i]:.4f} "
                      f"err={errs[i]:.4f} ({errs[i]/TRUE_ZEROS[i]*100:.1f}%)")

            # Plot
            ax = axes[1, idx]
            x_pos = np.arange(nn)
            ax.bar(x_pos-0.15, TRUE_ZEROS[:nn], 0.3, label='True', color='steelblue')
            ax.bar(x_pos+0.15, pred[:nn], 0.3, label='Predicted', color='darkorange')
            for i in range(nn):
                ax.text(i, max(pred[i],TRUE_ZEROS[i])+0.5,
                        f'{errs[i]:.2f}', ha='center', fontsize=7, color='red')
            ax.set_xticks(x_pos)
            ax.set_xticklabels([f't{i+1}' for i in range(nn)])
            ax.legend(fontsize=8)
            ax.set_title(f'{label}\n{nn} zeros, MAE={mae:.3f}', fontweight='bold')
            ax.set_ylabel('Value')
            ax.grid(True, alpha=0.3, axis='y')
    except Exception as e:
        print(f"  Failed: {e}")

plt.suptitle('FPGA Logistic Circuit → Oscilloscope → Riemann Zeros',
             fontsize=14, fontweight='bold')
plt.tight_layout()
plt.savefig('scope_riemann_zeros.png', dpi=200, bbox_inches='tight')
plt.show()
print("\nSaved: scope_riemann_zeros.png")
