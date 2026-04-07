"""
Lab 4: 从 FPGA 轨迹中提取黎曼零点

读取 Vivado 仿真输出的 riemann_trajectory.txt，
用 Markov 和 Hankel-DMD 两种方法提取零点，对比真实值。

使用: python analyze_zeros.py
"""
import numpy as np
import matplotlib.pyplot as plt
from scipy.sparse import coo_matrix, diags
from scipy.sparse.linalg import eigs
from scipy.linalg import svd

# 前 20 个黎曼零点 (真值)
TRUE_ZEROS = np.array([
    14.1347, 21.0220, 25.0108, 30.4248, 32.9350, 37.5861,
    40.9187, 43.3270, 48.0051, 49.7738, 52.9703, 56.4462,
    59.3470, 60.8317, 65.1125, 67.0798, 69.5464, 72.0671,
    75.7046, 77.1448
])

# ============================================================
# 1. 读取轨迹
# ============================================================
print("Loading trajectory from Vivado simulation...")
traj = np.loadtxt('riemann_trajectory.txt')
print(f"  {len(traj)} points, std={traj.std():.4f}, "
      f"range=[{traj.min():.3f}, {traj.max():.3f}]")

# ============================================================
# 2. 方法一: Markov 本征相位
# ============================================================
print("\n--- Method 1: Markov Eigenphase ---")

def build_markov_1d(trajectory, n_bins=1000, eps=0.01):
    """Build 1D Markov matrix via Gaussian kernel splatting."""
    x_min, x_max = trajectory.min() - 0.05, trajectory.max() + 0.05
    dx = (x_max - x_min) / n_bins
    inv_2eps2 = 1.0 / (2.0 * eps**2)
    half_w = max(int(5 * eps / dx), 2)

    x_indices = np.clip(((trajectory[:-1] - x_min) / dx).astype(int), 0, n_bins-1)
    x_next = trajectory[1:]

    rows, cols, vals = [], [], []
    for i in range(len(x_indices)):
        src = x_indices[i]
        center = int((x_next[i] - x_min) / dx)
        center = np.clip(center, 0, n_bins-1)
        lo, hi = max(0, center-half_w), min(n_bins, center+half_w+1)
        for j in range(lo, hi):
            c_j = x_min + (j + 0.5) * dx
            w = np.exp(-(c_j - x_next[i])**2 * inv_2eps2)
            if w > 1e-10:
                rows.append(src); cols.append(j); vals.append(w)

    P = coo_matrix((vals, (rows, cols)), shape=(n_bins, n_bins)).tocsr()
    row_sums = np.array(P.sum(axis=1)).flatten()
    row_sums[row_sums == 0] = 1.0
    return diags(1.0 / row_sums) @ P

P = build_markov_1d(traj, n_bins=1000, eps=0.015)
eigenvalues, _ = eigs(P, k=100, which='LM', tol=1e-5)

# 提取相位
mask = (eigenvalues.imag > 1e-6) & (np.abs(eigenvalues) > 0.1)
pos_vals = eigenvalues[mask]
if len(pos_vals) >= 2:
    phases = np.sort(np.abs(np.angle(pos_vals)))
    phases = phases[phases > 1e-6]

    # 比率指纹扫描
    target_ratio = TRUE_ZEROS[0] / TRUE_ZEROS[1]
    best_start = 0
    best_err = float('inf')
    for i in range(min(15, len(phases)-1)):
        if phases[i+1] == 0: continue
        err = abs(phases[i]/phases[i+1] - target_ratio)
        if err < best_err: best_err = err; best_start = i

    phases = phases[best_start:]
    scale = TRUE_ZEROS[0] / phases[0]
    predicted = phases * scale
    n = min(6, len(predicted))
    errors = np.abs(predicted[:n] - TRUE_ZEROS[:n])
    mae = np.mean(errors)

    print(f"  Phases found: {len(phases)}, MAE (first {n}): {mae:.4f}")
    print(f"  {'n':<4} {'Predicted':<12} {'True':<12} {'Error':<10} {'Rel%':<8}")
    print(f"  {'-'*46}")
    for i in range(n):
        rel = errors[i] / TRUE_ZEROS[i] * 100
        print(f"  {i+1:<4} {predicted[i]:<12.4f} {TRUE_ZEROS[i]:<12.4f} "
              f"{errors[i]:<10.4f} {rel:<8.2f}")
else:
    print("  Not enough valid eigenvalues")
    predicted = None; n = 0; mae = float('inf')

# ============================================================
# 3. 方法二: Hankel-DMD (无需 binning)
# ============================================================
print("\n--- Method 2: Hankel-DMD (binning-free) ---")

seg = traj[-5000:]  # 末段 (临界点附近)
n_delays, n_modes = 150, 30
N = len(seg); M = N - n_delays
X = np.zeros((n_delays, M)); Y = np.zeros((n_delays, M))
for i in range(n_delays):
    X[i,:] = seg[i:i+M]; Y[i,:] = seg[i+1:i+1+M]
U, s, Vh = svd(X, full_matrices=False)
r = min(n_modes, len(s))
A = U[:,:r].T @ Y @ Vh[:r,:].T @ np.diag(1.0/s[:r])
evals_dmd, _ = np.linalg.eig(A)
s_vals = np.log(evals_dmd + 1e-30)

mask_d = (np.imag(s_vals) > 0.005) & (np.abs(np.real(s_vals)) < 1.0)
valid_d = s_vals[mask_d]
if len(valid_d) >= 2:
    freqs = np.sort(np.imag(valid_d))
    unique = [freqs[0]]
    for f in freqs[1:]:
        if abs(f - unique[-1]) / max(abs(unique[-1]), 0.01) > 0.02:
            unique.append(f)
    freqs = np.array(unique)
    scale_d = TRUE_ZEROS[0] / freqs[0]
    scaled_d = freqs * scale_d
    n_d = min(20, len(scaled_d))
    errors_d = np.abs(scaled_d[:n_d] - TRUE_ZEROS[:n_d])
    mae_d = np.mean(errors_d)

    print(f"  Modes found: {len(freqs)}, MAE (first {n_d}): {mae_d:.4f}")
    print(f"  {'n':<4} {'Predicted':<12} {'True':<12} {'Error':<10} {'Rel%':<8}")
    print(f"  {'-'*46}")
    for i in range(n_d):
        rel = errors_d[i] / TRUE_ZEROS[i] * 100
        print(f"  {i+1:<4} {scaled_d[i]:<12.4f} {TRUE_ZEROS[i]:<12.4f} "
              f"{errors_d[i]:<10.4f} {rel:<8.2f}")
else:
    scaled_d = None; n_d = 0; mae_d = float('inf')

# ============================================================
# 4. 画图
# ============================================================
fig, axes = plt.subplots(1, 2, figsize=(14, 5))

# Markov
ax = axes[0]
if predicted is not None and n >= 2:
    ax.bar(np.arange(n)-0.15, TRUE_ZEROS[:n], 0.3, label='True', color='steelblue')
    ax.bar(np.arange(n)+0.15, predicted[:n], 0.3, label='Markov', color='darkorange')
    ax.set_xticks(range(n))
    ax.set_xticklabels([f'$t_{{{i+1}}}$' for i in range(n)])
    ax.legend()
ax.set_title(f'Markov (MAE={mae:.3f}, {n} zeros)', fontweight='bold')
ax.set_ylabel('Zero value'); ax.grid(True, alpha=0.3, axis='y')

# DMD
ax = axes[1]
if scaled_d is not None and n_d >= 2:
    ax.plot(range(1,n_d+1), TRUE_ZEROS[:n_d], 'ko-', label='True', ms=6)
    ax.plot(range(1,n_d+1), scaled_d[:n_d], 'rs--', label=f'DMD ({n_d} modes)', ms=5)
    ax.legend()
ax.set_title(f'Hankel-DMD (MAE={mae_d:.3f}, {n_d} modes, no binning)', fontweight='bold')
ax.set_xlabel('Zero index'); ax.set_ylabel('Value'); ax.grid(True, alpha=0.3)

plt.tight_layout()
plt.savefig('riemann_zeros_fpga.png', dpi=200)
plt.show()

print(f"\n{'='*50}")
print(f"SUMMARY:")
print(f"  Markov:  {n} zeros, MAE = {mae:.4f}")
print(f"  DMD:     {n_d} modes, MAE = {mae_d:.4f} (no binning!)")
print(f"{'='*50}")
print("Saved riemann_zeros_fpga.png")
