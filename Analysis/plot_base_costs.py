#!/usr/bin/env python3
"""Plot the measured per-operation cost of the PnR DAO contracts on Base mainnet.
Reads the summary produced by base_live_costs.py and writes the paper figure.
"""
import csv, os
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

HERE = os.path.dirname(__file__)
CSV_IN = os.path.join(HERE, "..", "On-Chain Data", "base_live_cost_summary.csv")
OUT = os.path.join(HERE, "..", "paper_bcra", "figure4_measured_gas.png")

ops, gas, usd = [], [], []
with open(CSV_IN) as f:
    for r in csv.DictReader(f):
        ops.append(r["operation"])
        gas.append(int(r["mean_gas"]))
        usd.append(float(r["mean_fee_usd"]))

# sort by gas ascending
order = sorted(range(len(ops)), key=lambda i: gas[i])
ops = [ops[i] for i in order]
gas = [gas[i] for i in order]
usd = [usd[i] for i in order]

fig, ax = plt.subplots(figsize=(8, 4.5))
bars = ax.barh(ops, gas, color="#c0392b", alpha=0.85)
ax.set_xlabel("Gas used (mean over executed transactions)")
ax.set_title("Measured cost of PnR DAO operations on Base mainnet")
ax.set_xlim(0, max(gas) * 1.18)
for b, g, u in zip(bars, gas, usd):
    ax.text(b.get_width() + max(gas) * 0.01, b.get_y() + b.get_height() / 2,
            f"{g:,} gas  (${u:.4f})", va="center", fontsize=9)
ax.grid(axis="x", alpha=0.3)
plt.tight_layout()
plt.savefig(OUT, dpi=200)
print("wrote", OUT)
