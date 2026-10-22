#!/usr/bin/env python3
"""Single-tick constant-product liquidation-liquidity model for Monad mainnet (chain 143).

Read-only JSON-RPC via the Python 3 standard library. No keys, no transactions.
Usage: python3 -I scripts/liquidity_model.py
Writes: docs/evidence/LIQUIDITY_MODEL.md

Model (Uniswap V3 style pools; the pool fee is reported but not in the impact figure):
  Within the current tick the pool is treated as x*y=k with virtual reserves
  x = L/sqrtP and y = L*sqrtP (L = pool liquidity, sqrtP = sqrtPriceX96 / 2^96).
  Selling dx of token0 moves sqrtP to L*sqrtP / (L + dx*sqrtP).
  Selling dy of token1 moves sqrtP to sqrtP + dy/L.
  Price impact = 1 - (price of the sold token after / before).

  Tick crossing is ignored. If a sell would leave the current tick range, the
  same L is assumed to continue, and the row is marked "extrap.". Concentrated
  liquidity elsewhere means real depth is larger than shown (understated depth).
"""
import json
import os
import sys
import urllib.request
from datetime import datetime, timezone
from decimal import Decimal, getcontext

getcontext().prec = 80

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONFIG_PATH = os.path.join(ROOT, "config", "monad-reference.json")
OUT_PATH = os.path.join(ROOT, "docs", "evidence", "LIQUIDITY_MODEL.md")
RPC_URL = "https://rpc.monad.xyz"
EXPECTED_CHAIN_ID = 143
SIZES_USD = [1000, 10000, 50000, 100000]
TYPICAL_USD = 10000            # ASSUMPTION: no typical position size exists in the repo
IMPACT_CAP_PCT = Decimal("5")  # target from the task
LTV_ASSUMED = Decimal("0.5")   # ASSUMPTION: illustrative only, not a Chog Credit parameter

# 4-byte selectors (standard Uniswap V3 / Chainlink AggregatorV3 / ERC-20 ABI).
SEL = {
    "slot0": "0x3850c7bd",
    "liquidity": "0x1a686502",
    "token0": "0x0dfe1681",
    "token1": "0xd21220a7",
    "fee": "0xddca3f43",
    "tickSpacing": "0xd0c93a7c",
    "decimals": "0x313ce567",
    "latestRoundData": "0xfeaf968c",
}

# (config pool key, collateral symbol, other side symbol)
POOL_SPECS = [
    ("uniswapV3_USDC_WMON_3000", "WMON", "USDC"),
    ("pancakeV3_USDC_WMON_500", "WMON", "USDC"),
    ("uniswapV3_CHOG_WMON_3000", "CHOG", "WMON"),
]


class RpcError(Exception):
    pass


def rpc(method, params):
    body = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params}).encode()
    req = urllib.request.Request(
        RPC_URL,
        data=body,
        headers={"Content-Type": "application/json", "User-Agent": "chog-credit-liquidity-model"},
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        payload = json.loads(resp.read().decode())
    if "error" in payload:
        raise RpcError(str(payload["error"]))
    return payload["result"]


def call(to, sig, block):
    return rpc("eth_call", [{"to": to, "data": SEL[sig]}, block])


def words(hexdata):
    raw = hexdata[2:] if hexdata.startswith("0x") else hexdata
    if not raw or len(raw) % 64:
        raise RpcError("empty or malformed return data: %r" % hexdata[:20])
    return [int(raw[i:i + 64], 16) for i in range(0, len(raw), 64)]


def signed(v):
    return v - 2 ** 256 if v >= 2 ** 255 else v


def addr_of(w):
    return "0x" + format(w, "064x")[-40:]


def sqrt_at_tick(t):
    """Real sqrt(price) at tick t, price = token1 raw per token0 raw."""
    return Decimal("1.0001") ** (Decimal(t) / Decimal(2))


def swap_impact(L, s, collat_is_token0, dx_raw):
    """Price impact (percent, fee excluded) of selling dx_raw of the collateral token."""
    if collat_is_token0:
        s_new = L * s / (L + dx_raw * s)
        ratio = (s_new / s) ** 2
    else:
        s_new = s + dx_raw / L
        ratio = (s / s_new) ** 2
    return (1 - ratio) * 100, s_new


def fmt_pct(x):
    return f"{x:.4f}%"


def fmt_usd(x):
    return f"${x:,.0f}"


def main():
    cfg = json.load(open(CONFIG_PATH))
    mainnet = cfg["networks"]["mainnet"]
    token_addr = {
        "WMON": mainnet["contracts"]["wmon"]["address"].lower(),
        "USDC": mainnet["contracts"]["usdc"]["address"].lower(),
        "CHOG": mainnet["contracts"]["chogToken"]["address"].lower(),
    }
    sym_of = {v: k for k, v in token_addr.items()}
    errors = []

    chain_id = int(rpc("eth_chainId", []), 16)
    if chain_id != EXPECTED_CHAIN_ID:
        raise SystemExit("wrong chain id %d" % chain_id)
    block = rpc("eth_blockNumber", [])
    block_info = rpc("eth_getBlockByNumber", [block, False])
    ts = int(block_info["timestamp"], 16)
    as_of = datetime.fromtimestamp(ts, timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")

    # Collateral USD price: Chainlink MON/USD (8 decimals), the primary feed in the reference doc.
    mon_feed = mainnet["oracles"]["chainlink_MON_USD"]["address"]
    mon_usd = None
    mon_age = None
    try:
        w = words(call(mon_feed, "latestRoundData", block))
        dec = words(call(mon_feed, "decimals", block))[0]
        mon_usd = Decimal(signed(w[1])) / Decimal(10) ** dec
        mon_age = ts - w[3]
    except Exception as e:  # record, do not guess
        errors.append("chainlink_MON_USD read failed: %r" % e)

    results = []
    for key, collat, other in POOL_SPECS:
        addr = mainnet["pools"][key]["address"]
        rec = {"key": key, "address": addr, "collateral": collat, "other": other, "status": "FAILED"}
        results.append(rec)
        try:
            s0 = words(call(addr, "slot0", block))
            sqrt_raw = s0[0]
            tick = signed(s0[1])
            L = Decimal(words(call(addr, "liquidity", block))[0])
            t0 = addr_of(words(call(addr, "token0", block))[0])
            t1 = addr_of(words(call(addr, "token1", block))[0])
            fee = words(call(addr, "fee", block))[0]
            spacing = signed(words(call(addr, "tickSpacing", block))[0])
            if {sym_of.get(t0.lower()), sym_of.get(t1.lower())} != {collat, other}:
                raise ValueError("pool tokens %s/%s do not match %s/%s" % (t0, t1, collat, other))
            d0 = words(call(t0, "decimals", block))[0]
            d1 = words(call(t1, "decimals", block))[0]
            collat_is_token0 = t0.lower() == token_addr[collat]
            d_c = d0 if collat_is_token0 else d1
            rec.update({
                "token0": sym_of[t0.lower()], "token1": sym_of[t1.lower()],
                "d0": d0, "d1": d1, "fee": fee, "tickSpacing": spacing, "tick": tick,
                "sqrtPriceX96": sqrt_raw, "liquidity": int(L),
            })
            if L == 0:
                raise ValueError("pool liquidity is zero")

            s = Decimal(sqrt_raw) / Decimal(2 ** 96)
            P = s * s * Decimal(10) ** (d0 - d1)          # token1 per token0, whole units
            wmon_is_token0 = token_addr["WMON"] == t0.lower()
            if collat == "WMON":
                p_c = mon_usd
            else:  # CHOG: pool price in WMON times Chainlink MON/USD
                wmon_per_collat = P if collat_is_token0 else 1 / P
                p_c = wmon_per_collat * mon_usd
            if p_c is None:
                raise ValueError("no collateral USD price (oracle read failed)")
            rec["mid_price_token1_per_token0"] = P
            rec["collateral_usd"] = p_c
            if other == "USDC":
                usdc_per_wmon = P if wmon_is_token0 else 1 / P
                rec["pool_implied_wmon_usd_usdc_at_1"] = usdc_per_wmon

            lo_t = (tick // spacing) * spacing
            hi_t = lo_t + spacing
            s_lo, s_hi = sqrt_at_tick(lo_t), sqrt_at_tick(hi_t)
            if collat_is_token0:
                max_in_tick_raw = L / s_lo - L / s
            else:
                max_in_tick_raw = L * (s_hi - s)
            rec["max_in_tick_usd"] = max_in_tick_raw / Decimal(10) ** d_c * p_c
            # Measured impact if the sale stops exactly at the current tick edge (no extrapolation).
            rec["edge_impact"], _ = swap_impact(L, s, collat_is_token0, max_in_tick_raw)

            sizes = {}
            for usd in SIZES_USD:
                dx_raw = Decimal(usd) / p_c * Decimal(10) ** d_c
                imp, _ = swap_impact(L, s, collat_is_token0, dx_raw)
                sizes[usd] = {"impact": imp, "in_tick": dx_raw <= max_in_tick_raw,
                              "tokens": dx_raw / Decimal(10) ** d_c}
            rec["sizes"] = sizes

            # Largest sale with impact <= IMPACT_CAP_PCT, closed form from the same model.
            r = (1 - IMPACT_CAP_PCT / 100).sqrt()
            if collat_is_token0:
                x_raw = L * (1 / r - 1) / s
            else:
                x_raw = L * s * (1 / r - 1)
            rec["x_star_usd"] = x_raw / Decimal(10) ** d_c * p_c
            rec["x_star_in_tick"] = x_raw <= max_in_tick_raw
            rec["status"] = "OK"
        except Exception as e:
            rec["error"] = repr(e)
            errors.append("%s: %r" % (key, e))

    write_report(results, errors, block, as_of, mon_usd, mon_age)
    print("wrote", OUT_PATH)
    for rec in results:
        print(rec["key"], rec["status"], rec.get("error", ""))


def write_report(results, errors, block, as_of, mon_usd, mon_age):
    L = []
    add = L.append
    add("# Liquidation-Liquidity Model (Monad mainnet, chain 143)")
    add("")
    add("**Status:** approximation. Generated by `scripts/liquidity_model.py` (read-only, stdlib JSON-RPC). "
        "Every pool value below was read from `https://rpc.monad.xyz` at block %d (%s). "
        "Re-run to refresh." % (int(block, 16), as_of))
    add("")
    add("## Method and limits")
    add("")
    add("- Single-tick constant-product approximation: within the current tick the pool is x*y=k with "
        "x = L/sqrtP and y = L*sqrtP. Impact = 1 - (sold-token price after / before), **pool fee excluded**.")
    add("- **Tick crossing is ignored.** A sell that would leave the current tick range is computed with the "
        "same L and marked `(extrap.)`. This understates depth only when liquidity is concentrated elsewhere; "
        "where it sits outside the current tick, these figures can be wrong in either direction.")
    add("- Collateral sold: WMON into the USDC/WMON pools, and the CHOG token into the CHOG/WMON pool. "
        "WMON USD = Chainlink MON/USD (`chainlink_MON_USD` in config). CHOG USD = pool mid in WMON times that price.")
    add("- Sizes are the USD value of collateral sold at the pool mid price, with no slippage on the valuation.")
    add("- Assumptions, not measurements: typical position size $%s (no value in repo); "
        "illustrative LTV %d%% for converting collateral size to a borrow cap." % (
            format(TYPICAL_USD, ","), int(LTV_ASSUMED * 100)))
    add("- The pancakeV3 1.00% WMON pool listed in the reference doc has no address in `config/monad-reference.json`, "
        "so it was not read.")
    add("")
    add("## Oracle")
    add("")
    if mon_usd is not None:
        add("- Chainlink MON/USD: %.6f USD, feed age %s s at read time." % (mon_usd, mon_age))
    else:
        add("- Chainlink MON/USD: READ FAILED (see failed calls).")
    add("")
    add("## Pool state")
    add("")
    add("| Pool | Address | Status | token0 / token1 | Fee | Tick spacing | Tick | Liquidity (L) | Mid price (token1/token0) | Collateral USD | Max in-tick sale (USD) |")
    add("|---|---|---|---|---:|---:|---:|---:|---:|---:|---:|")
    for r in results:
        if r["status"] == "OK":
            add("| %s | `%s` | OK | %s / %s | %d (%.2f%%) | %d | %d | %d | %.6g | %.6f | %s |" % (
                r["key"], r["address"], r["token0"], r["token1"], r["fee"], r["fee"] / 1e4,
                r["tickSpacing"], r["tick"], r["liquidity"], r["mid_price_token1_per_token0"],
                r["collateral_usd"], fmt_usd(r["max_in_tick_usd"])))
        else:
            add("| %s | `%s` | FAILED | | | | | | | | |" % (r["key"], r["address"]))
    add("")
    for r in results:
        if r["status"] == "OK" and "pool_implied_wmon_usd_usdc_at_1" in r:
            add("- Cross-check `%s`: pool-implied WMON price %.6f USD (assumes USDC = $1) vs Chainlink %s." % (
                r["key"], r["pool_implied_wmon_usd_usdc_at_1"],
                ("%.6f" % mon_usd) if mon_usd is not None else "n/a"))
    add("")
    add("## Impact by size (collateral sold into pool, price impact %, fee excluded)")
    add("")
    add("`(extrap.)` = the sale leaves the current tick, so the figure assumes the same L beyond it.")
    add("")
    add("| Pool | Collateral | $1k | $10k | $50k | $100k |")
    add("|---|---|---:|---:|---:|---:|")
    for r in results:
        if r["status"] != "OK":
            add("| %s | %s | n/a | n/a | n/a | n/a |" % (r["key"], r["collateral"]))
            continue
        cells = []
        for usd in SIZES_USD:
            z = r["sizes"][usd]
            cells.append(fmt_pct(z["impact"]) + ("" if z["in_tick"] else " (extrap.)"))
        add("| %s | %s | %s |" % (r["key"], r["collateral"], " | ".join(cells)))
    add("")
    add("Tokens sold at each size: " + "; ".join(
        "%s %s" % (r["key"], ", ".join("%s: %s %s" % (fmt_usd(u), format(r["sizes"][u]["tokens"], ",.0f"), r["collateral"])
                                        for u in SIZES_USD))
        for r in results if r["status"] == "OK") + ".")
    add("")
    add("## Largest single sale with impact <= %s%% (per pool)" % IMPACT_CAP_PCT)
    add("")
    add("| Pool | Collateral | Max collateral sold at 5% (USD, extrapolated) | Within current tick? | Max in-tick sale (USD, measured) | Impact at tick edge (measured) |")
    add("|---|---|---:|---|---:|---:|")
    for r in results:
        if r["status"] == "OK":
            add("| %s | %s | %s | %s | %s | %s |" % (r["key"], r["collateral"], fmt_usd(r["x_star_usd"]),
                                                    "yes" if r["x_star_in_tick"] else "no (extrap.)",
                                                    fmt_usd(r["max_in_tick_usd"]), fmt_pct(r["edge_impact"])))
        else:
            add("| %s | %s | n/a | n/a | n/a | n/a |" % (r["key"], r["collateral"]))
    add("")
    add("## Recommendations (from the approximation, not guarantees)")
    add("")
    add("These are recommendations derived from the single-tick approximation above. They are not measured "
        "guarantees, do not account for tick crossing or routing, and the LTV is an illustrative placeholder.")
    add("")
    for collat in ["WMON", "CHOG"]:
        pools = [r for r in results if r["status"] == "OK" and r["collateral"] == collat]
        add("### %s" % collat)
        add("")
        if not pools:
            add("- No readable pool for this collateral. No cap or bonus is recommended from this model.")
            add("")
            continue
        deepest = max(pools, key=lambda r: r["x_star_usd"])
        cap_notional = deepest["x_star_usd"]
        in_tick_pool = max(pools, key=lambda r: r["max_in_tick_usd"])
        in_tick_usd = in_tick_pool["max_in_tick_usd"]
        bonus = max(r["sizes"][TYPICAL_USD]["impact"] for r in pools)
        add("- **Pool-wide borrow cap, measured in-tick (recommendation):** the deepest pool within the current "
            "tick is `%s`, which absorbs about %s of collateral before leaving the tick (impact at that edge: %s). "
            "At an illustrative %d%% LTV that gives a borrow cap of about %s. This is the defensible figure from "
            "this model." % (
                in_tick_pool["key"], fmt_usd(in_tick_usd), fmt_pct(in_tick_pool["edge_impact"]),
                int(LTV_ASSUMED * 100), fmt_usd(in_tick_usd * LTV_ASSUMED)))
        add("- **Extrapolated 5%% ceiling (not recommended on its own):** the same L beyond the tick gives a "
            "%s%% impact limit at about %s of collateral in `%s` (borrow about %s at %d%% LTV). "
            "Confirm with tick-level liquidity before relying on it. %s" % (
                IMPACT_CAP_PCT, fmt_usd(cap_notional), deepest["key"], fmt_usd(cap_notional * LTV_ASSUMED),
                int(LTV_ASSUMED * 100),
                "" if deepest["x_star_in_tick"] else "The figure lies outside the current tick."))
        add("- **Liquidation bonus floor (recommendation):** at least %s%%, the largest impact at a typical "
            "$%s position across the %d readable pool(s) for %s (conservative). The impact excludes the pool fee "
            "(%s), so the bonus should also cover the fee." % (
                fmt_pct(bonus).replace("%", ""), format(TYPICAL_USD, ","), len(pools), collat,
                ", ".join("%.2f%%" % (r["fee"] / 1e4) for r in pools)))
        if bonus >= 50:
            add("- The bonus figure is not meaningful: the model finds almost no in-tick depth, so the impact is an "
                "extrapolation. No bonus level is supportable from this model for %s." % collat)
        add("")
    add("## Failed calls")
    add("")
    if errors:
        for e in errors:
            add("- %s" % e)
    else:
        add("- None. All reads in this run succeeded.")
    add("")
    with open(OUT_PATH, "w") as f:
        f.write("\n".join(L))


if __name__ == "__main__":
    sys.exit(main())
