"""
Shared module: circuit physics models, Markov builder, spectral extractor.
Implements the 5-layer circuit perturbation pipeline for logistic and Henon maps.
"""
import os
os.environ['OMP_NUM_THREADS'] = '1'
os.environ['OPENBLAS_NUM_THREADS'] = '1'
os.environ['MKL_NUM_THREADS'] = '1'

import numpy as np
from dataclasses import dataclass, field
from scipy.sparse import coo_matrix, diags, csr_matrix
from scipy.sparse.linalg import eigs
from numba import njit
import time

from riemann_zeros import TRUE_ZEROS_100

# Boltzmann constant
kB = 1.380649e-23


@dataclass
class CircuitParams:
    """Physical parameters for analog circuit simulation."""
    T: float = 300.0          # Temperature (K)
    R: float = 1000.0         # Resistance (Ohm)
    BW: float = 5e6           # Bandwidth (Hz) — default: half Nyquist
    V_sat: float = 12.0       # Op-amp supply voltage (V)
    sat_knee: float = 0.95    # Saturation knee fraction
    gain_err: float = 0.002   # Multiplier gain error
    offset: float = 0.001     # Multiplier offset
    f_sample: float = 10e6    # Sample rate (Hz)
    jitter: float = 1e-9      # Aperture jitter (s)

    @property
    def sigma_thermal(self):
        """Johnson-Nyquist noise voltage RMS."""
        return np.sqrt(4 * kB * self.T * self.R * self.BW)

    @property
    def sigma_state(self):
        """Thermal noise in normalized state-space units."""
        V_ref = self.V_sat * self.sat_knee
        return self.sigma_thermal / V_ref if V_ref > 0 else 0.0

    @property
    def lp_alpha(self):
        """IIR low-pass filter coefficient."""
        return 1.0 - np.exp(-2 * np.pi * self.BW / self.f_sample)


def _soft_saturate(x, k=1.5):
    """Smooth op-amp saturation via tanh."""
    return np.tanh(x * k) / np.tanh(k)


class CircuitLogistic:
    """Non-autonomous logistic map with optional circuit physics."""

    def __init__(self, circuit=None, mu_c=1.5437, k=0.02, c_offset=10.0, x0=0.5):
        self.circuit = circuit
        self.mu_c = mu_c
        self.k = k
        self.c_offset = c_offset
        self.x0 = x0

    def iterate(self, total_steps, autonomous=False, mu_fixed=None, seed=42,
                extra_sigma=0.0):
        """Run iteration. Returns trajectory array.

        Args:
            extra_sigma: additional noise on top of circuit thermal noise
        """
        rng = np.random.RandomState(seed)
        x = self.x0
        x_filt = x  # for IIR filter state
        trajectory = np.zeros(total_steps)
        c = self.circuit

        for n in range(total_steps):
            # 1. Compute mu(n)
            if autonomous and mu_fixed is not None:
                mu = mu_fixed
            else:
                mu = self.mu_c + self.k / np.log(n + self.c_offset) ** 2

            # 2. Multiplier imperfection
            if c is not None:
                x_sq = (1.0 + c.gain_err) * x ** 2 + c.offset
            else:
                x_sq = x ** 2

            # 3. Ideal map
            x_next = 1.0 - mu * x_sq

            # 4. Thermal noise + extra noise
            if c is not None:
                x_next += c.sigma_state * rng.randn()
            if extra_sigma > 0:
                x_next += extra_sigma * rng.randn()

            # 5. Bandwidth filter (IIR)
            if c is not None:
                x_filt = c.lp_alpha * x_next + (1.0 - c.lp_alpha) * x_filt
            else:
                x_filt = x_next

            # 6. Soft saturation
            if c is not None:
                x_out = _soft_saturate(x_filt)
            else:
                x_out = np.clip(x_filt, -1.0, 1.0)

            trajectory[n] = x_out
            x = x_out

        return trajectory


class CircuitHenon:
    """Non-autonomous Henon map with optional circuit physics."""

    def __init__(self, circuit=None, a_c=1.02, k=0.02, c_offset=10.0,
                 b=0.3, x0=0.1, y0=0.1):
        self.circuit = circuit
        self.a_c = a_c
        self.k = k
        self.c_offset = c_offset
        self.b = b
        self.x0 = x0
        self.y0 = y0

    def iterate(self, total_steps, seed=42, extra_sigma=0.0):
        """Run iteration. Returns (traj_x, traj_y)."""
        rng = np.random.RandomState(seed)
        x, y = self.x0, self.y0
        x_filt, y_filt = x, y
        traj_x = np.zeros(total_steps)
        traj_y = np.zeros(total_steps)
        c = self.circuit
        limit = 1.5  # Henon attractor is in [-1.3, 1.3]

        for n in range(total_steps):
            a_n = self.a_c + self.k / np.log(n + self.c_offset) ** 2

            # Multiplier imperfection on x^2
            if c is not None:
                x_sq = (1.0 + c.gain_err) * x ** 2 + c.offset
            else:
                x_sq = x ** 2

            # Ideal Henon
            x_next = 1.0 - a_n * x_sq + y
            y_next = self.b * x

            # Thermal noise
            if c is not None:
                x_next += c.sigma_state * rng.randn()
                y_next += c.sigma_state * rng.randn()
            if extra_sigma > 0:
                x_next += extra_sigma * rng.randn()
                y_next += extra_sigma * rng.randn()

            # Bandwidth filter
            if c is not None:
                x_filt = c.lp_alpha * x_next + (1.0 - c.lp_alpha) * x_filt
                y_filt = c.lp_alpha * y_next + (1.0 - c.lp_alpha) * y_filt
            else:
                x_filt = x_next
                y_filt = y_next

            # Soft saturation (scaled for Henon range)
            if c is not None:
                x_out = _soft_saturate(x_filt / limit) * limit
                y_out = _soft_saturate(y_filt / limit) * limit
            else:
                x_out = np.clip(x_filt, -limit, limit)
                y_out = np.clip(y_filt, -limit, limit)

            traj_x[n] = x_out
            traj_y[n] = y_out
            x, y = x_out, y_out

        return traj_x, traj_y


# ============================================================
# Numba-accelerated Markov builder kernels
# ============================================================

@njit(fastmath=True)
def _splat_1d_kernel(x_indices, x_next_vals, n_bins, bin_left, dx, inv_2eps2, half_width):
    """Numba kernel for 1D Gaussian splatting."""
    N = len(x_indices)
    max_entries = N * (2 * half_width + 1)
    rows = np.empty(max_entries, dtype=np.int32)
    cols = np.empty(max_entries, dtype=np.int32)
    vals = np.empty(max_entries, dtype=np.float64)
    count = 0

    for i in range(N):
        src = x_indices[i]
        x_next = x_next_vals[i]
        center_idx = int((x_next - bin_left) / dx)
        if center_idx < 0:
            center_idx = 0
        if center_idx >= n_bins:
            center_idx = n_bins - 1

        lo = center_idx - half_width
        hi = center_idx + half_width + 1
        if lo < 0:
            lo = 0
        if hi > n_bins:
            hi = n_bins

        w_sum = 0.0
        for j in range(lo, hi):
            c_j = bin_left + (j + 0.5) * dx
            diff = c_j - x_next
            w = np.exp(-diff * diff * inv_2eps2)
            w_sum += w

        if w_sum < 1e-30:
            continue

        inv_sum = 1.0 / w_sum
        for j in range(lo, hi):
            c_j = bin_left + (j + 0.5) * dx
            diff = c_j - x_next
            w = np.exp(-diff * diff * inv_2eps2) * inv_sum
            if w > 1e-10:
                rows[count] = src
                cols[count] = j
                vals[count] = w
                count += 1

    return rows[:count], cols[:count], vals[:count]


@njit(fastmath=True)
def _splat_2d_kernel(ix_src, iy_src, x_next_vals, y_next_vals,
                     n_bins, bin_left, dx, inv_2eps2, half_w):
    """Numba kernel for 2D Gaussian splatting."""
    N = len(ix_src)
    max_per_point = (2 * half_w + 1) ** 2
    max_entries = N * max_per_point
    # Cap at 50M to avoid memory issues
    if max_entries > 50_000_000:
        max_entries = 50_000_000
    rows = np.empty(max_entries, dtype=np.int32)
    cols = np.empty(max_entries, dtype=np.int32)
    vals = np.empty(max_entries, dtype=np.float64)
    count = 0

    for i in range(N):
        src = ix_src[i] * n_bins + iy_src[i]
        x_next = x_next_vals[i]
        y_next = y_next_vals[i]

        cix = int((x_next - bin_left) / dx)
        ciy = int((y_next - bin_left) / dx)
        if cix < 0: cix = 0
        if cix >= n_bins: cix = n_bins - 1
        if ciy < 0: ciy = 0
        if ciy >= n_bins: ciy = n_bins - 1

        lox = cix - half_w
        hix = cix + half_w + 1
        loy = ciy - half_w
        hiy = ciy + half_w + 1
        if lox < 0: lox = 0
        if hix > n_bins: hix = n_bins
        if loy < 0: loy = 0
        if hiy > n_bins: hiy = n_bins

        w_sum = 0.0
        for jx in range(lox, hix):
            cx_val = bin_left + (jx + 0.5) * dx
            wx = np.exp(-(cx_val - x_next) ** 2 * inv_2eps2)
            for jy in range(loy, hiy):
                cy_val = bin_left + (jy + 0.5) * dx
                wy = np.exp(-(cy_val - y_next) ** 2 * inv_2eps2)
                w_sum += wx * wy

        if w_sum < 1e-30:
            continue

        inv_sum = 1.0 / w_sum
        for jx in range(lox, hix):
            cx_val = bin_left + (jx + 0.5) * dx
            wx = np.exp(-(cx_val - x_next) ** 2 * inv_2eps2)
            for jy in range(loy, hiy):
                cy_val = bin_left + (jy + 0.5) * dx
                wy = np.exp(-(cy_val - y_next) ** 2 * inv_2eps2)
                w = wx * wy * inv_sum
                if w > 1e-10 and count < max_entries:
                    rows[count] = src
                    cols[count] = jx * n_bins + jy
                    vals[count] = w
                    count += 1

    return rows[:count], cols[:count], vals[:count]


@njit(fastmath=True, nogil=True)
def _prob_propagate_2d(eps, a_c, delta_a, c_offset, steps, n_bins, limit,
                       gain_err, offset_val, sigma_state, use_circuit):
    """Probability-propagation Markov builder for 2D Henon (numba).

    Propagates a probability cloud through the Henon map, accumulating
    transition probabilities. Correct approach for 2D fractal attractors.
    """
    n_states = n_bins * n_bins
    dx = (2.0 * limit) / n_bins

    eps_eff = np.sqrt(eps**2 + sigma_state**2) if use_circuit else eps
    inv_2eps2 = 1.0 / (2.0 * eps_eff**2)
    radius = int(3.0 * eps_eff / dx) + 1

    t_start = 1.0 / (np.log(1 + c_offset)**2)
    t_end = 1.0 / (np.log(steps + c_offset)**2)
    k_opt = delta_a / (t_start - t_end) if abs(t_start - t_end) > 1e-30 else 0.0
    a_dyna = a_c - k_opt * t_end

    center_idx = int(limit / dx)
    start_state = center_idx * n_bins + center_idx
    V = np.zeros(n_states, dtype=np.float64)
    V[start_state] = 1.0

    max_edges = 5_000_000
    edge_rows = np.empty(max_edges, dtype=np.int32)
    edge_cols = np.empty(max_edges, dtype=np.int32)
    edge_vals = np.empty(max_edges, dtype=np.float64)
    n_edges = 0

    for n in range(1, steps + 1):
        a_n = a_dyna + k_opt / (np.log(n + c_offset)**2.0)
        V_next = np.zeros(n_states, dtype=np.float64)

        for state in range(n_states):
            if V[state] < 1e-12:
                continue

            i_x = state // n_bins
            i_y = state % n_bins
            x_curr = -limit + dx * 0.5 + i_x * dx
            x_prev = -limit + dx * 0.5 + i_y * dx

            if use_circuit:
                x_sq = (1.0 + gain_err) * x_curr**2 + offset_val
            else:
                x_sq = x_curr**2

            x_next = 1.0 - a_n * x_sq - x_prev
            y_next = x_curr

            if abs(x_next) > limit or abs(y_next) > limit:
                V_next[start_state] += V[state]
                continue

            j_x_center = int((x_next + limit) / dx)
            j_y_center = int((y_next + limit) / dx)
            jx_start = max(0, j_x_center - radius)
            jx_end = min(n_bins - 1, j_x_center + radius)
            jy_start = max(0, j_y_center - radius)
            jy_end = min(n_bins - 1, j_y_center + radius)

            w_sum = 0.0
            for jx in range(jx_start, jx_end + 1):
                cx_val = -limit + dx * 0.5 + jx * dx
                wx = np.exp(-(cx_val - x_next)**2 * inv_2eps2)
                for jy in range(jy_start, jy_end + 1):
                    cy_val = -limit + dx * 0.5 + jy * dx
                    wy = np.exp(-(cy_val - y_next)**2 * inv_2eps2)
                    w_sum += wx * wy

            if w_sum > 1e-18:
                inv_sum = 1.0 / w_sum
                for jx in range(jx_start, jx_end + 1):
                    cx_val = -limit + dx * 0.5 + jx * dx
                    wx = np.exp(-(cx_val - x_next)**2 * inv_2eps2)
                    for jy in range(jy_start, jy_end + 1):
                        cy_val = -limit + dx * 0.5 + jy * dx
                        wy = np.exp(-(cy_val - y_next)**2 * inv_2eps2)
                        prob = wx * wy * inv_sum
                        flow = V[state] * prob
                        target_state = jx * n_bins + jy
                        V_next[target_state] += flow
                        if n_edges < max_edges:
                            edge_rows[n_edges] = state
                            edge_cols[n_edges] = target_state
                            edge_vals[n_edges] = flow
                            n_edges += 1
            else:
                jxc = min(max(0, j_x_center), n_bins - 1)
                jyc = min(max(0, j_y_center), n_bins - 1)
                target_state = jxc * n_bins + jyc
                V_next[target_state] += V[state]
                if n_edges < max_edges:
                    edge_rows[n_edges] = state
                    edge_cols[n_edges] = target_state
                    edge_vals[n_edges] = V[state]
                    n_edges += 1

        V = V_next

    return edge_rows[:n_edges], edge_cols[:n_edges], edge_vals[:n_edges], n_states


class MarkovBuilder:
    """Build Markov transition matrices from chaotic trajectories."""

    @staticmethod
    def build_1d(trajectory, n_bins=3000, eps=0.001, x_range=(-1.0, 1.0)):
        """Build 1D Markov matrix via Gaussian kernel splatting."""
        t0 = time.time()
        bin_left = x_range[0]
        dx = (x_range[1] - x_range[0]) / n_bins
        inv_2eps2 = 1.0 / (2.0 * eps ** 2)
        half_width = max(int(5 * eps / dx), 2)

        x_indices = np.clip(
            ((trajectory[:-1] - bin_left) / dx).astype(np.int32),
            0, n_bins - 1
        )
        x_next_vals = trajectory[1:]

        rows, cols, vals = _splat_1d_kernel(
            x_indices, x_next_vals, n_bins, bin_left, dx, inv_2eps2, half_width
        )

        P = coo_matrix((vals, (rows, cols)), shape=(n_bins, n_bins)).tocsr()
        row_sums = np.array(P.sum(axis=1)).flatten()
        row_sums[row_sums == 0] = 1.0
        D_inv = diags(1.0 / row_sums)
        P = D_inv @ P
        print(f"  MarkovBuilder.build_1d: n_bins={n_bins}, eps={eps:.6f}, "
              f"nnz={P.nnz}, time={time.time()-t0:.1f}s")
        return P

    @staticmethod
    def build_2d(traj_x, traj_y, n_bins_per_axis=100, eps=0.045, limit=None):
        """Build 2D Markov matrix via Gaussian kernel splatting.

        If limit is None, auto-detects range from trajectory with 10% padding.
        Both axes are normalized to [-1, 1] before binning for uniform resolution.
        """
        t0 = time.time()
        n_bins = n_bins_per_axis
        total_states = n_bins * n_bins

        # Auto-detect ranges
        if limit is None:
            x_min, x_max = traj_x.min(), traj_x.max()
            y_min, y_max = traj_y.min(), traj_y.max()
            pad_x = (x_max - x_min) * 0.1
            pad_y = (y_max - y_min) * 0.1
            x_min -= pad_x; x_max += pad_x
            y_min -= pad_y; y_max += pad_y
        else:
            x_min, x_max = -limit, limit
            y_min, y_max = -limit, limit

        # Normalize to [-1, 1]
        sx = 2.0 / (x_max - x_min)
        sy = 2.0 / (y_max - y_min)
        norm_x = (traj_x - x_min) * sx - 1.0
        norm_y = (traj_y - y_min) * sy - 1.0

        # Scale eps to normalized coordinates
        eps_norm = eps * max(sx, sy)

        bin_left = -1.0
        dx = 2.0 / n_bins
        inv_2eps2 = 1.0 / (2.0 * eps_norm ** 2)
        half_w = max(int(5 * eps_norm / dx), 2)

        ix_src = np.clip(
            ((norm_x[:-1] - bin_left) / dx).astype(np.int32),
            0, n_bins - 1
        )
        iy_src = np.clip(
            ((norm_y[:-1] - bin_left) / dx).astype(np.int32),
            0, n_bins - 1
        )

        rows, cols, vals = _splat_2d_kernel(
            ix_src, iy_src, norm_x[1:], norm_y[1:],
            n_bins, bin_left, dx, inv_2eps2, half_w
        )

        P = coo_matrix((vals, (rows, cols)),
                        shape=(total_states, total_states)).tocsr()
        row_sums = np.array(P.sum(axis=1)).flatten()
        row_sums[row_sums == 0] = 1.0
        D_inv = diags(1.0 / row_sums)
        P = D_inv @ P
        print(f"  MarkovBuilder.build_2d: n_bins={n_bins}x{n_bins}, eps={eps:.6f}, "
              f"nnz={P.nnz}, time={time.time()-t0:.1f}s")
        return P

    @staticmethod
    def build_2d_propagation(eps, delta_a, steps=500, n_bins=150, limit=1.5,
                             c_offset=10.0, a_c=1.00560676, circuit=None):
        """Build 2D Markov via probability propagation (correct for fractal attractors).

        This follows the henon5.py approach: propagate a probability cloud
        through the Henon map, accumulating transition probabilities.

        Args:
            eps: Gaussian smoothing scale
            delta_a: bifurcation parameter offset
            steps: number of propagation steps
            n_bins: bins per axis (total states = n_bins^2)
            limit: state space range [-limit, limit]
            c_offset: logarithmic cooling offset
            a_c: critical a parameter
            circuit: CircuitParams or None
        """
        t0 = time.time()
        use_circuit = circuit is not None
        gain_err = circuit.gain_err if use_circuit else 0.0
        offset_val = circuit.offset if use_circuit else 0.0
        sigma_state = circuit.sigma_state if use_circuit else 0.0

        rows, cols, vals, n_states = _prob_propagate_2d(
            eps, a_c, delta_a, c_offset, steps, n_bins, limit,
            gain_err, offset_val, sigma_state, use_circuit
        )

        P = coo_matrix((vals, (rows, cols)),
                        shape=(n_states, n_states)).tocsr()
        row_sums = np.array(P.sum(axis=1)).flatten()
        row_sums[row_sums == 0] = 1.0
        D_inv = diags(1.0 / row_sums)
        P = D_inv @ P
        print(f"  MarkovBuilder.build_2d_propagation: n_bins={n_bins}x{n_bins}, "
              f"eps={eps:.6f}, delta_a={delta_a:.6f}, steps={steps}, "
              f"nnz={P.nnz}, circuit={use_circuit}, time={time.time()-t0:.1f}s")
        return P


class SpectralExtractor:
    """Extract Riemann zero estimates from Markov matrix eigenvalues."""

    @staticmethod
    def extract(P, n_eigs=250, n_zeros=100, true_zeros=None):
        """Extract and match Riemann zeros from Markov eigenvalues.

        Returns dict with: predicted_zeros, mae, eigenvalues, phases, scale_factor
        """
        if true_zeros is None:
            true_zeros = TRUE_ZEROS_100

        try:
            eigenvalues, _ = eigs(P, k=min(n_eigs, P.shape[0] - 2),
                                  which='LM', tol=1e-5)
        except Exception as e:
            print(f"  SpectralExtractor: eigendecomposition failed: {e}")
            return {'predicted_zeros': None, 'mae': float('inf'),
                    'eigenvalues': None, 'phases': None, 'scale_factor': None}

        # Filter: positive imaginary part, relaxed magnitude threshold
        mask = (eigenvalues.imag > 1e-6) & (np.abs(eigenvalues) > 0.1)
        pos_vals = eigenvalues[mask]

        if len(pos_vals) < 2:
            return {'predicted_zeros': None, 'mae': float('inf'),
                    'eigenvalues': eigenvalues, 'phases': None,
                    'scale_factor': None}

        # Extract and sort phases
        phases = np.sort(np.abs(np.angle(pos_vals)))
        phases = phases[phases > 1e-6]  # remove near-zero

        if len(phases) < 2:
            return {'predicted_zeros': None, 'mae': float('inf'),
                    'eigenvalues': eigenvalues, 'phases': None,
                    'scale_factor': None}

        # Ratio fingerprint scan: find the start index where consecutive
        # phase ratios match the Riemann zero ratio pattern (~0.67)
        target_ratio = true_zeros[0] / true_zeros[1]  # ~0.672
        best_start = 0
        best_ratio_err = float('inf')
        for i in range(min(15, len(phases) - 1)):
            if phases[i + 1] == 0:
                continue
            ratio = phases[i] / phases[i + 1]
            err = abs(ratio - target_ratio)
            if err < best_ratio_err:
                best_ratio_err = err
                best_start = i

        phases = phases[best_start:]
        if len(phases) < 2:
            return {'predicted_zeros': None, 'mae': float('inf'),
                    'eigenvalues': eigenvalues, 'phases': None,
                    'scale_factor': None}

        # Single-point linear scaling
        scale = true_zeros[0] / phases[0] if phases[0] != 0 else 1.0
        predicted = phases * scale

        # Compute MAE
        n_compare = min(n_zeros, len(predicted), len(true_zeros))
        mae = float(np.mean(np.abs(predicted[:n_compare] - true_zeros[:n_compare])))

        return {
            'predicted_zeros': predicted[:n_compare],
            'mae': mae,
            'eigenvalues': eigenvalues,
            'phases': phases,
            'scale_factor': scale,
            'n_valid_phases': len(phases)
        }

    @staticmethod
    def extract_propagation(P, n_eigs=350, n_zeros=100, true_zeros=None):
        """Extract Riemann zeros from propagation-built Markov matrix.

        Uses LR eigenvalues with strict filter (|val|>0.6, imag>1e-4),
        matching the henon5.py approach.
        """
        if true_zeros is None:
            true_zeros = TRUE_ZEROS_100

        try:
            eigenvalues, _ = eigs(P, k=min(n_eigs, P.shape[0] - 2),
                                  which='LR', tol=1e-5)
        except Exception as e:
            print(f"  SpectralExtractor: eigendecomposition failed: {e}")
            return {'predicted_zeros': None, 'mae': float('inf'),
                    'eigenvalues': None, 'phases': None, 'scale_factor': None}

        mask = (eigenvalues.imag > 1e-4) & (np.abs(eigenvalues) > 0.6)
        pos_vals = eigenvalues[mask]

        if len(pos_vals) < 2:
            return {'predicted_zeros': None, 'mae': float('inf'),
                    'eigenvalues': eigenvalues, 'phases': None,
                    'scale_factor': None, 'n_valid_phases': 0}

        phases = np.unwrap(np.sort(np.angle(pos_vals)))

        # Ratio fingerprint scan
        best_start = 0
        for i in range(min(10, len(phases) - 1)):
            ratio = phases[i] / phases[i + 1] if phases[i + 1] != 0 else 0
            if 0.55 < ratio < 0.80:
                best_start = i
                break

        phases = phases[best_start:]
        if len(phases) < 2:
            return {'predicted_zeros': None, 'mae': float('inf'),
                    'eigenvalues': eigenvalues, 'phases': None,
                    'scale_factor': None, 'n_valid_phases': 0}

        scale = true_zeros[0] / phases[0] if phases[0] != 0 else 1.0
        predicted = phases * scale

        n_compare = min(n_zeros, len(predicted), len(true_zeros))
        if n_compare < n_zeros:
            mae = 1e6 + (n_zeros - n_compare) * 1e4
        else:
            mae = float(np.mean(np.abs(predicted[:n_compare] - true_zeros[:n_compare])))

        return {
            'predicted_zeros': predicted[:n_compare],
            'mae': mae,
            'eigenvalues': eigenvalues,
            'phases': phases,
            'scale_factor': scale,
            'n_valid_phases': len(phases)
        }
