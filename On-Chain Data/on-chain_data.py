import warnings
from datetime import datetime, timedelta

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from scipy import stats as scipy_stats

warnings.filterwarnings('ignore')

# Professional publication style
plt.rcParams['font.family'] = 'serif'
plt.rcParams['font.size'] = 10
plt.rcParams['axes.linewidth'] = 1.0

print("Loading data...")

# Load data
eth_prices = pd.read_csv('Ethereum_Historical_Price_Data.csv')
eth_prices['Date(UTC)'] = pd.to_datetime(eth_prices['Date(UTC)'])
eth_prices = eth_prices.sort_values('Date(UTC)')

makerdao = pd.read_csv('Ethereum_MakerDAO_Governor_Voting_DATA.csv')
compound = pd.read_csv('Ethereum_CompoundDAO_Governor_Voting_DATA.csv')
uniswap = pd.read_csv('Ethereum_UniswapDAO_Governor_Voting_DATA.csv')
arbitrum = pd.read_csv('Arbitrum_ArbitrumDAO__Governor_voting.csv')
polygon = pd.read_csv('Polygon_Transactions_Latest_50_random.csv')

def parse_age_to_date(age_str):
    reference_date = datetime(2024, 3, 15)
    if pd.isna(age_str):
        return reference_date
    try:
        age_str = str(age_str).lower()
        if 'min' in age_str or 'sec' in age_str:
            return reference_date
        elif 'hr' in age_str or 'hour' in age_str:
            hours = int(age_str.split()[0])
            return reference_date - timedelta(hours=hours)
        elif 'day' in age_str:
            days = int(age_str.split()[0])
            return reference_date - timedelta(days=days)
        else:
            return reference_date
    except:
        return reference_date

def process_ethereum_dao(df, dao_name):
    df = df.copy()
    df['DAO'] = dao_name
    df['Chain'] = 'Ethereum'
    df['Date'] = df['Age'].apply(parse_age_to_date)
    df['ETH_Price'] = df['Date'].apply(lambda x: 
        eth_prices[eth_prices['Date(UTC)'] <= x]['Value'].iloc[-1] 
        if x is not None else 3500)
    df['Cost_USD'] = df['Txn Fee'] * df['ETH_Price']
    return df[['DAO', 'Chain', 'Date', 'Txn Fee', 'ETH_Price', 'Cost_USD']]

def process_arbitrum_dao(df):
    df = df.copy()
    df['DAO'] = 'Arbitrum DAO'
    df['Chain'] = 'Arbitrum'
    df['Date'] = pd.to_datetime(df['DateTime (UTC)'])
    df['ETH_Price'] = df['Date'].apply(lambda x: 
        eth_prices[eth_prices['Date(UTC)'] <= x]['Value'].iloc[-1] 
        if x is not None else 3500)
    df['Cost_USD'] = df['Txn Fee'] * df['ETH_Price']
    return df[['DAO', 'Chain', 'Date', 'Txn Fee', 'ETH_Price', 'Cost_USD']]

def process_polygon_txs(df):
    df = df.copy()
    df['DAO'] = 'Polygon Network'
    df['Chain'] = 'Polygon'
    df['Date'] = pd.to_datetime(df['DateTime (UTC)'])
    df['MATIC_Price'] = 1.00
    df['Cost_USD'] = df['Txn Fee'] * df['MATIC_Price']
    return df[['DAO', 'Chain', 'Date', 'Txn Fee', 'MATIC_Price', 'Cost_USD']]

print("Processing transactions...")
eth_makerdao = process_ethereum_dao(makerdao, 'MakerDAO')
eth_compound = process_ethereum_dao(compound, 'Compound')
eth_uniswap = process_ethereum_dao(uniswap, 'Uniswap')
arb_dao = process_arbitrum_dao(arbitrum)
poly_txs = process_polygon_txs(polygon)

all_data = pd.concat([eth_makerdao, eth_compound, eth_uniswap, arb_dao, poly_txs], 
                     ignore_index=True)

def calculate_ci(data, confidence=0.95):
    n = len(data)
    mean = data.mean()
    se = scipy_stats.sem(data)
    ci = se * scipy_stats.t.ppf((1 + confidence) / 2., n-1)
    return mean, ci

# Statistics
chains = ['Ethereum', 'Arbitrum', 'Polygon']
chain_labels = ['Ethereum\n(Mainnet)', 'Arbitrum\n(Layer 2)', 'Polygon\n(Layer 2)']
chain_stats = {}
for chain in chains:
    data = all_data[all_data['Chain'] == chain]['Cost_USD']
    mean, ci = calculate_ci(data)
    chain_stats[chain] = {
        'mean': mean,
        'ci': ci,
        'median': data.median(),
        'min': data.min(),
        'max': data.max(),
        'n': len(data)
    }

print("\n" + "="*60)
print("EMPIRICAL COST ANALYSIS")
print("="*60)
for chain in chains:
    s = chain_stats[chain]
    print(f"\n{chain}:")
    print(f"  Mean:   ${s['mean']:.4f} (±${s['ci']:.4f})")
    print(f"  Median: ${s['median']:.4f}")
    print(f"  Range:  ${s['min']:.4f} - ${s['max']:.4f}")
    print(f"  N:      {s['n']} transactions")

# Cost reduction
eth_mean = chain_stats['Ethereum']['mean']
arb_mean = chain_stats['Arbitrum']['mean']
poly_mean = chain_stats['Polygon']['mean']

print("\n" + "="*60)
print("COST REDUCTION vs ETHEREUM")
print("="*60)
print(f"Arbitrum: {((eth_mean - arb_mean) / eth_mean * 100):.1f}% reduction")
print(f"Polygon:  {((eth_mean - poly_mean) / eth_mean * 100):.1f}% reduction")

# ========== FIGURE 1: Bar Chart with Linear + Log Comparison ==========
fig1, (ax1, ax2) = plt.subplots(1, 2, figsize=(12, 4.5))

colors = ['#2c3e50', '#3498db', '#27ae60']
x = np.arange(len(chains))
means = [chain_stats[c]['mean'] for c in chains]
cis = [chain_stats[c]['ci'] for c in chains]
ns = [chain_stats[c]['n'] for c in chains]

# Left: Linear scale
bars1 = ax1.bar(x, means, width=0.6, color=colors, edgecolor='black', 
                linewidth=1.5, yerr=cis, capsize=7, 
                error_kw={'linewidth': 1.5, 'ecolor': 'black'})

ax1.set_ylabel('Average Cost (USD)', fontsize=11, fontweight='bold')
ax1.set_xlabel('Blockchain Network', fontsize=11, fontweight='bold')
ax1.set_xticks(x)
ax1.set_xticklabels(chain_labels, fontsize=9.5)
ax1.spines['top'].set_visible(False)
ax1.spines['right'].set_visible(False)
ax1.set_title('(a) Linear Scale', fontsize=11, fontweight='bold', pad=10)

# Labels with sample sizes
for i, (m, c, n) in enumerate(zip(means, cis, ns)):
    if m > 0.01:
        ax1.text(i, m + c + max(means)*0.05, f'${m:.3f}\n(n={n})', 
                ha='center', va='bottom', fontsize=9, fontweight='bold')
    else:
        ax1.text(i, m + c + max(means)*0.05, f'${m:.4f}\n(n={n})', 
                ha='center', va='bottom', fontsize=9, fontweight='bold')

# Right: Log scale
bars2 = ax2.bar(x, means, width=0.6, color=colors, edgecolor='black', 
                linewidth=1.5, yerr=cis, capsize=7,
                error_kw={'linewidth': 1.5, 'ecolor': 'black'})

ax2.set_ylabel('Average Cost (USD)', fontsize=11, fontweight='bold')
ax2.set_xlabel('Blockchain Network', fontsize=11, fontweight='bold')
ax2.set_xticks(x)
ax2.set_xticklabels(chain_labels, fontsize=9.5)
ax2.set_yscale('log')
ax2.spines['top'].set_visible(False)
ax2.spines['right'].set_visible(False)
ax2.set_title('(b) Logarithmic Scale', fontsize=11, fontweight='bold', pad=10)

# Labels with reduction percentages
eth_mean_val = chain_stats['Ethereum']['mean']
reductions = [0, 
              ((eth_mean_val - chain_stats['Arbitrum']['mean']) / eth_mean_val * 100),
              ((eth_mean_val - chain_stats['Polygon']['mean']) / eth_mean_val * 100)]

for i, (m, red, n) in enumerate(zip(means, reductions, ns)):
    label_y = m * 2.2 if i == 0 else m * 1.8
    if i == 0:
        label_text = f'${m:.3f}\n(n={n})'
    else:
        label_text = f'${m:.4f}\n-{red:.1f}%\n(n={n})'
    
    ax2.text(i, label_y, label_text, 
            ha='center', va='bottom', fontsize=8.5, fontweight='bold')

plt.tight_layout()
plt.savefig('figure1_cost_comparison.png', dpi=300, bbox_inches='tight')
print("\nFigure 1 saved")

# ========== FIGURE 2: Individual Transaction Scatter ==========
fig2, ax = plt.subplots(figsize=(10, 5))

scatter_labels = ['Ethereum (Mainnet)', 'Arbitrum (Layer 2)', 'Polygon (Layer 2)']

for i, chain in enumerate(chains):
    data = all_data[all_data['Chain'] == chain]['Cost_USD'].values
    y = np.random.normal(i, 0.08, len(data))  
    ax.scatter(data, y, alpha=0.5, s=40, color=colors[i], 
               edgecolors='black', linewidth=0.3, label=f'{scatter_labels[i]} (n={len(data)})')
    
    # Mean marker
    mean_val = chain_stats[chain]['mean']
    ax.scatter([mean_val], [i], s=150, marker='D', color=colors[i], 
               edgecolors='black', linewidth=2, zorder=5, label=f'Mean: ${mean_val:.4f}')

ax.set_xscale('log')
ax.set_xlabel('Transaction Cost (USD, log scale)', fontsize=11, fontweight='bold')
ax.set_yticks([0, 1, 2])
ax.set_yticklabels(scatter_labels, fontsize=10)
ax.set_ylim(-0.5, 2.5)
ax.spines['top'].set_visible(False)
ax.spines['right'].set_visible(False)
ax.legend(loc='upper right', bbox_to_anchor=(1.0, 1.0), frameon=True, 
          fontsize=9, ncol=1, framealpha=0.98, edgecolor='black',
          labelspacing=2.2, borderpad=1.2, handletextpad=1.0, markerscale=1.3,
          fancybox=False, shadow=False, columnspacing=1.0)

plt.tight_layout()
plt.savefig('figure2_transaction_scatter.png', dpi=300, bbox_inches='tight')
print("Figure 2 saved")

# ========== FIGURE 3: DAO Breakdown ==========
fig3, ax = plt.subplots(figsize=(9, 5))

dao_stats = all_data.groupby('DAO')['Cost_USD'].agg(['mean', 'median', 'count']).sort_values('mean')
dao_chains = all_data.groupby('DAO')['Chain'].first().loc[dao_stats.index]

# Map DAOs to proper labels
dao_label_map = {
    'MakerDAO': 'MakerDAO (Ethereum L1)',
    'Compound': 'Compound (Ethereum L1)',
    'Uniswap': 'Uniswap (Ethereum L1)',
    'Arbitrum DAO': 'Arbitrum DAO (Layer 2)',
    'Polygon Network': 'Polygon Network (Layer 2)'
}
dao_labels_formatted = [dao_label_map.get(dao, dao) for dao in dao_stats.index]

y = np.arange(len(dao_stats))
color_map = {'Ethereum': '#2c3e50', 'Arbitrum': '#3498db', 'Polygon': '#27ae60'}
bar_colors = [color_map[dao_chains[dao]] for dao in dao_stats.index]

bars = ax.barh(y, dao_stats['mean'].values, height=0.65, color=bar_colors, 
               edgecolor='black', linewidth=1.5, alpha=0.85)

ax.set_yticks(y)
ax.set_yticklabels(dao_labels_formatted, fontsize=9.5)
ax.set_xlabel('Average Cost (USD, log scale)', fontsize=11, fontweight='bold')
ax.set_xscale('log')
ax.spines['top'].set_visible(False)
ax.spines['right'].set_visible(False)

# Labels with sample sizes
for i, (dao, mean_val) in enumerate(zip(dao_stats.index, dao_stats['mean'].values)):
    n = dao_stats.loc[dao, 'count']
    label_x = mean_val * 2.5 if mean_val > 0.01 else mean_val * 3
    ax.text(label_x, i, f'${mean_val:.4f} (n={int(n)})', 
            va='center', fontsize=8.5, fontweight='bold')

plt.tight_layout()
plt.savefig('figure3_dao_breakdown.png', dpi=300, bbox_inches='tight')
print("Figure 3 saved")

# Export summary
summary = pd.DataFrame({
    'Network': chains,
    'Mean (USD)': [f"{chain_stats[c]['mean']:.4f}" for c in chains],
    'CI (±)': [f"{chain_stats[c]['ci']:.4f}" for c in chains],
    'Median (USD)': [f"{chain_stats[c]['median']:.4f}" for c in chains],
    'Transactions': [chain_stats[c]['n'] for c in chains]
})
summary.to_csv('summary_statistics.csv', index=False)
print("\nSummary saved: summary_statistics.csv")
print("\nAll figures generated successfully!")