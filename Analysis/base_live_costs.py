#!/usr/bin/env python3
"""Build the real per-operation cost table for the PnR DAO contracts deployed
on Base mainnet. Reads the BaseScan transaction export, pulls gasUsed and the
effective gas price for each transaction straight from the Base RPC, and reports
the gas and USD cost of every governance operation.

No hardcoded gas numbers: everything comes from the on-chain receipts.
"""
import csv, json, statistics, urllib.request, os

RPC = "https://mainnet.base.org"
CSV_IN = os.path.join(os.path.dirname(__file__), "..", "On-Chain Data",
                      "PnR_DAO_Base_Transactions.csv")
CSV_OUT = os.path.join(os.path.dirname(__file__), "..", "On-Chain Data",
                       "base_live_cost_summary.csv")
ETH_USD = 2000.0  # ETH price on 2026-06-22, consistent with the explorer's USD column


def rpc(method, params):
    req = urllib.request.Request(
        RPC, data=json.dumps({"jsonrpc": "2.0", "id": 1,
                              "method": method, "params": params}).encode(),
        headers={"Content-Type": "application/json", "User-Agent": "curl/8.0"})
    return json.load(urllib.request.urlopen(req, timeout=30))["result"]


rows = []
with open(CSV_IN, encoding="utf-8-sig") as f:
    for r in csv.DictReader(f):
        h = r["Transaction Hash"]
        rec = rpc("eth_getTransactionReceipt", [h])
        gas = int(rec["gasUsed"], 16)
        price = int(rec["effectiveGasPrice"], 16)
        fee_eth = gas * price / 1e18
        rows.append({"method": r["Method"], "hash": h, "gas": gas,
                     "fee_eth": fee_eth, "fee_usd": fee_eth * ETH_USD})

# group by operation
ops = {}
for r in rows:
    ops.setdefault(r["method"], []).append(r)

print(f"{'Operation':<22}{'n':>3}{'mean gas':>12}{'fee (ETH)':>14}{'fee (USD)':>12}")
print("-" * 63)
summary = []
for op in sorted(ops):
    g = [x["gas"] for x in ops[op]]
    fe = [x["fee_eth"] for x in ops[op]]
    fu = [x["fee_usd"] for x in ops[op]]
    mg, mfe, mfu = statistics.mean(g), statistics.mean(fe), statistics.mean(fu)
    print(f"{op:<22}{len(g):>3}{mg:>12,.0f}{mfe:>14.8f}{mfu:>12.6f}")
    summary.append([op, len(g), round(mg), f"{mfe:.8f}", f"{mfu:.6f}"])

tot_eth = sum(x["fee_eth"] for x in rows)
print("-" * 63)
print(f"{'TOTAL (22 txns)':<22}{len(rows):>3}{'':>12}{tot_eth:>14.8f}{tot_eth*ETH_USD:>12.6f}")

with open(CSV_OUT, "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["operation", "n", "mean_gas", "mean_fee_eth", "mean_fee_usd"])
    w.writerows(summary)
print(f"\nwrote {CSV_OUT}")
