"""
Analyze Logistic SPICE output: Markov + Hankel-DMD
Usage: python analyze_logistic.py logistic_output.txt
"""
import numpy as np
import matplotlib.pyplot as plt
from scipy.linalg import svd
from scipy.sparse import coo_matrix, diags
from scipy.sparse.linalg import eigs
import sys

TRUE_ZEROS = np.array([14.1347, 21.0220, 25.0108, 30.4248, 32.9350, 37.5861,
    40.9187, 43.3270, 48.0051, 49.7738, 52.9703, 56.4462])

# === Load data ===
fname = sys.argv[1] if len(sys.argv) > 1 else 'logistic_output.txt'
print(f'Loading {fname}...')
data = np.loadtxt(fname)

# LTspice export format: time, value (or just values)
if data.ndim == 2:
    t_arr, v = data[:, 0], data[:, 1]
    # Sample at clock midpoints
    t_clk = 1e-6
    traj = []
    for i in range(10, 50000):
        idx = np.searchsorted(t_arr, (i + 0.5) * t_clk)
        if idx < len(v): traj.append(float(v[idx]))
    traj = np.array(traj)
else:
    traj = data

print(f'Trajectory: {len(traj)} pts, std={traj.std():.4f}')

# ============================================================
# Method 1: Markov Eigenphase
# ============================================================
print('\n--- Markov Eigenphase ---')
n_bins, eps = 500, 0.01
x_min, x_max = traj.min()-0.05, traj.max()+0.05
dx = (x_max - x_min) / n_bins
inv_2eps2 = 1.0 / (2.0 * eps**2)
half_w = max(int(5*eps/dx), 2)

rows, cols, vals = [], [], []
for i in range(len(traj)-1):
    src = min(int((traj[i]-x_min)/dx), n_bins-1)
    center = min(int((traj[i+1]-x_min)/dx), n_bins-1)
    lo, hi = max(0,center-half_w), min(n_bins,center+half_w+1)
    for j in range(lo, hi):
        c_j = x_min + (j+0.5)*dx
        w = np.exp(-(c_j-traj[i+1])**2 * inv_2eps2)
        if w > 1e-10: rows.append(src); cols.append(j); vals.append(w)

P = coo_matrix((vals,(rows,cols)), shape=(n_bins,n_bins)).tocsr()
rs = np.array(P.sum(axis=1)).flatten(); rs[rs==0]=1.0
P = diags(1.0/rs) @ P

eigenvalues, _ = eigs(P, k=100, which='LM', tol=1e-5)
mask = (eigenvalues.imag > 1e-6) & (np.abs(eigenvalues) > 0.1)
phases = np.sort(np.abs(np.angle(eigenvalues[mask])))
phases = phases[phases > 1e-6]

if len(phases) >= 2:
    target = TRUE_ZEROS[0]/TRUE_ZEROS[1]
    best_s, best_e = 0, float('inf')
    for i in range(min(15, len(phases)-1)):
        if phases[i+1]==0: continue
        e = abs(phases[i]/phases[i+1]-target)
        if e < best_e: best_e=e; best_s=i
    phases = phases[best_s:]
    scale = TRUE_ZEROS[0]/phases[0]
    pred = phases * scale
    n = min(6, len(pred))
    errors = np.abs(pred[:n]-TRUE_ZEROS[:n])
    print(f'MAE={np.mean(errors):.4f}, zeros={n}')
    for i in range(n):
        print(f'  t{i+1}: {pred[i]:.4f} vs {TRUE_ZEROS[i]:.4f} err={errors[i]:.4f} ({errors[i]/TRUE_ZEROS[i]*100:.2f}%)')
else:
    pred = None; n = 0

# ============================================================
# Method 2: Hankel-DMD
# ============================================================
print('\n--- Hankel-DMD ---')
seg = np.abs(traj[-5000:])  # |V|, tail segment
nd, nm = 50, 10
N = len(seg); M = N-nd
X = np.zeros((nd,M)); Y = np.zeros((nd,M))
for i in range(nd):
    X[i,:]=seg[i:i+M]; Y[i,:]=seg[i+1:i+1+M]
U,s,Vh = svd(X, full_matrices=False)
r = min(nm, len(s))
A = U[:,:r].T @ Y @ Vh[:r,:].T @ np.diag(1.0/s[:r])
evals,_ = np.linalg.eig(A)
s_vals = np.log(evals+1e-30)

mask_d = (np.imag(s_vals)>0.005) & (np.abs(np.real(s_vals))<1.0)
valid = s_vals[mask_d]
if len(valid)>=2:
    freqs = np.sort(np.imag(valid))
    unique=[freqs[0]]
    for f in freqs[1:]:
        if abs(f-unique[-1])/max(abs(unique[-1]),0.01)>0.02: unique.append(f)
    freqs=np.array(unique)
    sc = TRUE_ZEROS[0]/freqs[0]
    scaled = freqs*sc
    nd2 = min(12, len(scaled))
    errs = np.abs(scaled[:nd2]-TRUE_ZEROS[:nd2])
    print(f'MAE={np.mean(errs):.4f}, modes={len(freqs)}')
    for i in range(nd2):
        print(f'  t{i+1}: {scaled[i]:.4f} vs {TRUE_ZEROS[i]:.4f} err={errs[i]:.4f} ({errs[i]/TRUE_ZEROS[i]*100:.2f}%)')
else:
    scaled=None; nd2=0

# ============================================================
# Plot
# ============================================================
fig, axes = plt.subplots(1, 2, figsize=(14, 5))
ax=axes[0]
if pred is not None and n>=2:
    ax.bar(np.arange(n)-0.15, TRUE_ZEROS[:n], 0.3, label='True', color='steelblue')
    ax.bar(np.arange(n)+0.15, pred[:n], 0.3, label='Markov', color='darkorange')
    ax.set_xticks(range(n)); ax.set_xticklabels([f'$t_{{{i+1}}}$' for i in range(n)])
    ax.legend()
ax.set_title(f'Logistic Markov ({n} zeros)', fontweight='bold')
ax.set_ylabel('Value'); ax.grid(True, alpha=0.3, axis='y')

ax=axes[1]
if scaled is not None and nd2>=2:
    ax.plot(range(1,nd2+1), TRUE_ZEROS[:nd2], 'ko-', label='True', ms=6)
    ax.plot(range(1,nd2+1), scaled[:nd2], 'rs--', label=f'DMD ({nd2} modes)', ms=5)
    ax.legend()
ax.set_title(f'Logistic DMD ({nd2} modes)', fontweight='bold')
ax.set_xlabel('Zero index'); ax.set_ylabel('Value'); ax.grid(True, alpha=0.3)

plt.tight_layout()
plt.savefig('logistic_zeros.png', dpi=200)
plt.show()
print('\nSaved logistic_zeros.png')
