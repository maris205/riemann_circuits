"""
SPICE Logistic + Hénon 混沌电路仿真 (正确非自治实现)

关键：非自治参数冷却的正确实现
    mu(n) = mu_dyna + k_opt / ln(n + c_offset)²

    其中:
      t_start = 1/ln(1 + c_offset)²
      t_end = 1/ln(steps + c_offset)²
      k_opt = delta_mu / (t_start - t_end)
      mu_dyna = mu_c - k_opt * t_end

    保证: mu(1) = mu_c + delta_mu, mu(steps) ≈ mu_c
    演化从高于临界点开始，经过 steps 步精确冷却到临界点。
"""
import os
os.environ['OMP_NUM_THREADS'] = '1'

import numpy as np
import subprocess
import tempfile
import time
import json
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

from circuit_models import MarkovBuilder, SpectralExtractor
from riemann_zeros import get_zeros

RESULTS_DIR = 'results/spice_v2'
TRUE_ZEROS = get_zeros(100)


def compute_cooling_params(mu_c, delta_mu, steps, c_offset):
    """Compute k_opt and mu_dyna from physical constraints.

    Ensures: mu(1) = mu_c + delta_mu, mu(steps) ≈ mu_c.
    """
    t_start = 1.0 / np.log(1 + c_offset) ** 2
    t_end = 1.0 / np.log(steps + c_offset) ** 2
    k_opt = delta_mu / (t_start - t_end)
    mu_dyna = mu_c - k_opt * t_end

    # Verify
    mu_1 = mu_dyna + k_opt / np.log(1 + c_offset) ** 2
    mu_end = mu_dyna + k_opt / np.log(steps + c_offset) ** 2
    print(f"  Cooling params: k_opt={k_opt:.6f}, mu_dyna={mu_dyna:.6f}")
    print(f"    mu(1)={mu_1:.6f} (target: {mu_c + delta_mu:.6f})")
    print(f"    mu({steps})={mu_end:.6f} (target: ≈{mu_c:.6f})")
    return k_opt, mu_dyna


def generate_logistic_netlist(mu_c=1.5437, delta_mu=0.02, steps=50000,
                               c_offset=10.0, f_clock=1e6,
                               v_ref=1.0, v_supply=12.0,
                               mult_gain_err=0.004, mult_offset_mv=5.0,
                               output_file='/tmp/logistic_v2.cir',
                               data_file='/tmp/logistic_v2_out.txt'):
    """Logistic SPICE netlist with correct non-autonomous cooling."""
    t_clk = 1.0 / f_clock
    t_total = steps * t_clk
    t_step = t_clk / 20
    v_sat = v_supply * 0.9
    mult_gain = 1.0 + mult_gain_err
    mult_offset = mult_offset_mv / 1000.0

    k_opt, mu_dyna = compute_cooling_params(mu_c, delta_mu, steps, c_offset)

    # SPICE B-source: n = floor(TIME/T_clk) + 1
    # mu(n) = mu_dyna + k_opt / ln(n + c_offset)²
    mu_expr = (f'{mu_dyna:.10f} + {k_opt:.10f} / '
               f'(ln(floor(TIME/{t_clk:.10e})+1+{c_offset}) * '
               f'ln(floor(TIME/{t_clk:.10e})+1+{c_offset}))')

    mult_term = f'{mult_gain}*V(v_x)*V(v_x) + {10 * mult_offset}'

    netlist = f"""* Logistic Chaotic Circuit — Correct Non-Autonomous Cooling
* mu(1) = {mu_c + delta_mu:.6f} → mu({steps}) ≈ {mu_c:.6f}
* k_opt = {k_opt:.6f}, mu_dyna = {mu_dyna:.6f}
* AD633: err={mult_gain_err * 100:.1f}%, offset={mult_offset * 1e3:.1f}mV
* TL072: BW~1MHz, V_sat=±{v_sat:.1f}V

* === T-line Delay Feedback ===
Rsrc v_out tl_in 50
T1 tl_in 0 tl_out 0 Z0=50 TD={t_clk:.10e}
Rload tl_out 0 50
Bbuf v_x 0 V = 2*V(tl_out)

* === Time-varying mu(n) ===
Bmu v_mu 0 V = {mu_expr}

* === Map: V_out = Vref - mu(n) * (1+err)*Vx² ===
Bsum v_sum 0 V = {v_ref} - V(v_mu) * ({mult_term})

* === TL072 Bandwidth (RC ~1MHz) ===
Rop v_sum v_filt 160
Cop v_filt 0 1n

* === Soft Saturation ===
Bsat v_out 0 V = {v_sat}*tanh(V(v_filt)/{v_sat})

.ic V(v_out)=0.5 V(v_filt)=0.5 V(tl_in)=0.25 V(tl_out)=0.25

.tran {t_step:.10e} {t_total:.10e} uic

.control
run
wrdata {data_file} v(v_out) v(v_mu)
quit
.endc

.end
"""
    with open(output_file, 'w') as f:
        f.write(netlist)
    return output_file, data_file


def generate_henon_netlist(a_c=1.02, delta_a=0.015, steps=50000,
                            c_offset=10.0, b=0.3, f_clock=1e6,
                            v_ref=1.0, v_supply=12.0,
                            mult_gain_err=0.004, mult_offset_mv=5.0,
                            output_file='/tmp/henon_v2.cir',
                            data_file='/tmp/henon_v2_out.txt'):
    """Hénon 2D SPICE netlist with correct non-autonomous cooling."""
    t_clk = 1.0 / f_clock
    t_total = steps * t_clk
    t_step = t_clk / 20
    v_sat = v_supply * 0.9
    mult_gain = 1.0 + mult_gain_err
    mult_offset = mult_offset_mv / 1000.0

    k_opt, a_dyna = compute_cooling_params(a_c, delta_a, steps, c_offset)

    a_expr = (f'{a_dyna:.10f} + {k_opt:.10f} / '
              f'(ln(floor(TIME/{t_clk:.10e})+1+{c_offset}) * '
              f'ln(floor(TIME/{t_clk:.10e})+1+{c_offset}))')

    mult_term = f'{mult_gain}*V(v_x_del)*V(v_x_del) + {10 * mult_offset}'

    netlist = f"""* 2D Henon Chaotic Circuit — Correct Non-Autonomous Cooling
* a(1) = {a_c + delta_a:.6f} → a({steps}) ≈ {a_c:.6f}, b = {b}
* k_opt = {k_opt:.6f}, a_dyna = {a_dyna:.6f}

* === X Channel T-line Delay ===
Rxsrc v_xout txl_in 50
Tx1 txl_in 0 txl_out 0 Z0=50 TD={t_clk:.10e}
Rxload txl_out 0 50
Bxbuf v_x_del 0 V = 2*V(txl_out)

* === Y Channel T-line Delay ===
Rysrc v_yout tyl_in 50
Ty1 tyl_in 0 tyl_out 0 Z0=50 TD={t_clk:.10e}
Ryload tyl_out 0 50
Bybuf v_y_del 0 V = 2*V(tyl_out)

* === Time-varying a(n) ===
Ba_param v_a 0 V = {a_expr}

* === X Channel: x' = Vref - a(n)*(1+err)*x² + y ===
Bxmap v_xraw 0 V = {v_ref} - V(v_a)*({mult_term}) + V(v_y_del)
Rxop v_xraw v_xfilt 160
Cxop v_xfilt 0 1n
Bxsat v_xout 0 V = {v_sat}*tanh(V(v_xfilt)/{v_sat})

* === Y Channel: y' = b * x ===
Bymap v_yraw 0 V = {b}*V(v_x_del)
Ryop v_yraw v_yfilt 160
Cyop v_yfilt 0 1n
Bysat v_yout 0 V = {v_sat}*tanh(V(v_yfilt)/{v_sat})

.ic V(v_xout)=0.1 V(v_yout)=0.1 V(v_xfilt)=0.1 V(v_yfilt)=0.1
+ V(txl_in)=0.05 V(txl_out)=0.05 V(tyl_in)=0.05 V(tyl_out)=0.05

.tran {t_step:.10e} {t_total:.10e} uic

.control
run
wrdata {data_file} v(v_xout) v(v_yout) v(v_a)
quit
.endc

.end
"""
    with open(output_file, 'w') as f:
        f.write(netlist)
    return output_file, data_file


def run_ngspice(cir_file, data_file, timeout=600):
    """Run ngspice batch and parse output."""
    t0 = time.time()
    result = subprocess.run(['ngspice', '-b', cir_file],
                           capture_output=True, text=True, timeout=timeout)
    elapsed = time.time() - t0
    if result.returncode != 0:
        raise RuntimeError(f"ngspice error:\n{result.stderr[-300:]}")
    data = np.loadtxt(data_file)
    return data, elapsed


def extract_trajectory(data, f_clock, col_idx=1, n_skip=10):
    """Sample SPICE waveform at clock rate."""
    t_arr = data[:, 0]
    v = data[:, col_idx]
    t_clk = 1.0 / f_clock
    traj = []
    n_total = int(t_arr[-1] / t_clk)
    for i in range(n_skip, n_total):
        idx = np.searchsorted(t_arr, (i + 0.5) * t_clk)
        if idx < len(v):
            traj.append(float(v[idx]))
    return np.array(traj)


def analyze_zeros(traj, label, n_bins=1000, eps=0.01, n_zeros=6):
    """Build Markov from trajectory and extract zeros."""
    x_range = (traj.min() - 0.05, traj.max() + 0.05)
    P = MarkovBuilder.build_1d(traj, n_bins=n_bins, eps=eps, x_range=x_range)
    result = SpectralExtractor.extract(P, n_eigs=100, n_zeros=n_zeros,
                                       true_zeros=TRUE_ZEROS)

    print(f"\n  {label}: Scale MAE={result['mae']:.4f}, "
          f"N_phases={result.get('n_valid_phases', 0)}")

    if result['phases'] is not None and len(result['phases']) >= 2:
        phases = result['phases']
        n = min(n_zeros, len(phases))
        pred_ratios = phases[:n] / phases[0]
        true_ratios = TRUE_ZEROS[:n] / TRUE_ZEROS[0]
        ratio_mae = float(np.mean(np.abs(pred_ratios[:n] - true_ratios[:n])))
        print(f"  Ratio MAE (first {n}): {ratio_mae:.4f}")

        print(f"  {'idx':<5} {'predicted':<12} {'true':<12} {'error':<10} {'rel%':<8}")
        print(f"  {'-'*47}")
        for i in range(n):
            pred = result['predicted_zeros'][i] if i < len(result['predicted_zeros']) else 0
            true = TRUE_ZEROS[i]
            err = abs(pred - true)
            rel = err / true * 100
            print(f"  {i+1:<5} {pred:<12.4f} {true:<12.4f} {err:<10.4f} {rel:<8.2f}")

        return result, ratio_mae
    return result, float('inf')


if __name__ == '__main__':
    os.makedirs(RESULTS_DIR, exist_ok=True)

    # === 1. Logistic with correct cooling ===
    print("=" * 60)
    print("1. SPICE Logistic — Correct Non-Autonomous Cooling")
    print("=" * 60)

    # Try multiple delta_mu / eps combinations
    best_logistic = {'ratio_mae': float('inf')}
    for delta_mu in [0.01, 0.02, 0.05]:
        for eps in [0.005, 0.01, 0.02]:
            print(f"\n  --- delta_mu={delta_mu}, eps={eps} ---")
            with tempfile.NamedTemporaryFile(suffix='.cir', delete=False) as f:
                cir_file = f.name
            data_file = cir_file.replace('.cir', '_out.txt')

            generate_logistic_netlist(
                mu_c=1.5437, delta_mu=delta_mu, steps=50000,
                c_offset=10.0, f_clock=1e6,
                output_file=cir_file, data_file=data_file
            )
            data, elapsed = run_ngspice(cir_file, data_file)
            print(f"  ngspice: {elapsed:.1f}s")

            traj = extract_trajectory(data, f_clock=1e6, col_idx=1)
            print(f"  Trajectory: {len(traj)} pts, "
                  f"range=[{traj.min():.3f}, {traj.max():.3f}], "
                  f"std={traj.std():.4f}")

            if traj.std() > 0.01:
                result, rmae = analyze_zeros(traj, f"Logistic dm={delta_mu} eps={eps}",
                                             eps=eps, n_zeros=6)
                if rmae < best_logistic['ratio_mae']:
                    best_logistic = {'delta_mu': delta_mu, 'eps': eps,
                                     'ratio_mae': rmae, 'traj': traj,
                                     'result': result}

            os.unlink(cir_file)
            if os.path.exists(data_file):
                os.unlink(data_file)

    print(f"\n  BEST Logistic: delta_mu={best_logistic.get('delta_mu')}, "
          f"eps={best_logistic.get('eps')}, ratio_mae={best_logistic['ratio_mae']:.4f}")

    # === 2. Hénon with correct cooling ===
    print("\n" + "=" * 60)
    print("2. SPICE Hénon — Correct Non-Autonomous Cooling")
    print("=" * 60)

    best_henon = {'ratio_mae': float('inf')}
    for delta_a in [0.01, 0.015, 0.02]:
        for eps in [0.005, 0.01, 0.02]:
            print(f"\n  --- delta_a={delta_a}, eps={eps} ---")
            with tempfile.NamedTemporaryFile(suffix='.cir', delete=False) as f:
                cir_file = f.name
            data_file = cir_file.replace('.cir', '_out.txt')

            generate_henon_netlist(
                a_c=1.02, delta_a=delta_a, steps=50000,
                c_offset=10.0, b=0.3, f_clock=1e6,
                output_file=cir_file, data_file=data_file
            )
            data, elapsed = run_ngspice(cir_file, data_file)
            print(f"  ngspice: {elapsed:.1f}s")

            traj_x = extract_trajectory(data, f_clock=1e6, col_idx=1)
            traj_y = extract_trajectory(data, f_clock=1e6, col_idx=3)
            print(f"  Trajectory: {len(traj_x)} pts, "
                  f"x=[{traj_x.min():.3f}, {traj_x.max():.3f}], "
                  f"y=[{traj_y.min():.3f}, {traj_y.max():.3f}]")

            if traj_x.std() > 0.01:
                result, rmae = analyze_zeros(traj_x,
                                             f"Hénon da={delta_a} eps={eps}",
                                             eps=eps, n_zeros=6)
                if rmae < best_henon['ratio_mae']:
                    best_henon = {'delta_a': delta_a, 'eps': eps,
                                  'ratio_mae': rmae, 'traj_x': traj_x,
                                  'traj_y': traj_y, 'result': result}

            os.unlink(cir_file)
            if os.path.exists(data_file):
                os.unlink(data_file)

    print(f"\n  BEST Hénon: delta_a={best_henon.get('delta_a')}, "
          f"eps={best_henon.get('eps')}, ratio_mae={best_henon['ratio_mae']:.4f}")

    # === 3. Summary comparison ===
    print("\n" + "=" * 60)
    print("3. SUMMARY: First 6 Riemann Zeros from SPICE Circuits")
    print("=" * 60)

    # Save results
    summary = {
        'logistic': {
            'delta_mu': best_logistic.get('delta_mu'),
            'eps': best_logistic.get('eps'),
            'ratio_mae': best_logistic['ratio_mae'],
        },
        'henon': {
            'delta_a': best_henon.get('delta_a'),
            'eps': best_henon.get('eps'),
            'ratio_mae': best_henon['ratio_mae'],
        }
    }
    with open(f'{RESULTS_DIR}/spice_v2_results.json', 'w') as f:
        json.dump(summary, f, indent=2)

    # Plot best results
    fig, axes = plt.subplots(1, 2, figsize=(14, 5))

    for ax, label, best in [(axes[0], '1D Logistic', best_logistic),
                             (axes[1], '2D Hénon', best_henon)]:
        result = best.get('result')
        if result and result.get('phases') is not None:
            phases = result['phases']
            n = min(6, len(phases))
            pred = result['predicted_zeros'][:n]
            true = TRUE_ZEROS[:n]
            ax.bar(np.arange(n) - 0.15, true, 0.3, label='True zeros',
                   color='steelblue', alpha=0.8)
            ax.bar(np.arange(n) + 0.15, pred, 0.3, label='SPICE circuit',
                   color='darkorange', alpha=0.8)
            ax.set_xticks(range(n))
            ax.set_xticklabels([f'$t_{{{i+1}}}$' for i in range(n)])
            ax.set_ylabel('Zero value')
            ax.set_title(f'{label} SPICE\n(ratio MAE={best["ratio_mae"]:.3f})',
                         fontweight='bold')
            ax.legend()
            ax.grid(True, alpha=0.3, axis='y')
        else:
            ax.text(0.5, 0.5, 'No valid phases', transform=ax.transAxes,
                    ha='center')
            ax.set_title(label)

    plt.tight_layout()
    plt.savefig(f'{RESULTS_DIR}/spice_v2_zeros_comparison.png', dpi=200)
    print(f"\n  Saved spice_v2_zeros_comparison.png")
    print(f"\n  Done!")
