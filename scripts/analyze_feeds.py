#!/usr/bin/env python3
"""Measure update cadence and deviation of Chainlink-style (AggregatorV3) feeds on Monad mainnet.

Read-only: eth_blockNumber, eth_getBlockByNumber, eth_call (latestRoundData, getRoundData,
decimals, description). No keys, no transactions. Python stdlib only.
All reads are pinned to one block number so the walk is internally consistent.

Usage: python3 -I scripts/analyze_feeds.py [--max-rounds 200] [--out docs/evidence/FEED_ANALYSIS.md]
"""
import argparse, json, math, pathlib, sys, time, urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
CFG = json.loads((ROOT / "config" / "monad-reference.json").read_text())
NET = CFG["networks"]["mainnet"]
RPCS = NET["rpc"]  # primary first, second used as fallback
TIMEOUT = 15
SLEEP = 0.15

SEL = {
    "latestRoundData": "0xfeaf968c",
    "getRoundData": "0x9a6fc8f5",  # getRoundData(uint80)
    "decimals": "0x313ce567",
    "description": "0x7284e416",
}


class RpcError(Exception):
    pass


class Revert(Exception):
    pass


def rpc(method, params):
    """JSON-RPC over the configured endpoints. Transport failures fall back to the next RPC."""
    body = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params}).encode()
    errs = []
    for url in RPCS:
        for attempt in range(2):
            try:
                req = urllib.request.Request(url, body, {"content-type": "application/json"})
                with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
                    out = json.loads(resp.read())
                time.sleep(SLEEP)
                return out
            except Exception as e:  # network / HTTP / JSON error
                errs.append(f"{url}: {type(e).__name__}: {e}")
                time.sleep(1)
    raise RpcError("; ".join(errs))


def eth_call(to, data, block):
    out = rpc("eth_call", [{"to": to, "data": data}, block])
    if "error" in out:
        # The node returned an execution error: treat as revert.
        raise Revert(out["error"].get("message", "error"))
    return out["result"]


def words(h):
    b = bytes.fromhex(h[2:])
    return [int.from_bytes(b[i:i + 32], "big") for i in range(0, len(b), 32)], b


def signed(v):
    return v - (1 << 256) if v >> 255 else v


def round_tuple(h):
    w, _ = words(h)
    return {"roundId": w[0], "answer": signed(w[1]), "startedAt": w[2], "updatedAt": w[3], "answeredInRound": w[4]}


def latest(addr, block):
    return round_tuple(eth_call(addr, SEL["latestRoundData"], block))


def get_round(addr, rid, block):
    return round_tuple(eth_call(addr, SEL["getRoundData"] + f"{rid:064x}", block))


def decode_string(h):
    w, b = words(h)
    if len(b) == 32:
        return b.rstrip(b"\0").decode(errors="replace")
    off = w[0]
    ln = int.from_bytes(b[off:off + 32], "big")
    return b[off + 32:off + 32 + ln].decode(errors="replace")


def pct(xs, p):
    """Linear-interpolation percentile (numpy default)."""
    s = sorted(xs)
    if not s:
        return None
    k = (len(s) - 1) * p / 100.0
    f, c = math.floor(k), math.ceil(k)
    return s[f] + (s[c] - s[f]) * (k - f)


def walk(addr, block, max_rounds):
    """Walk back from latestRoundData. Returns (rounds, stop_reason, latest_round)."""
    cur = latest(addr, block)
    rounds = [cur]
    stop = "max_rounds reached"
    rid = cur["roundId"]
    for _ in range(max_rounds - 1):
        rid -= 1
        if rid <= 0:
            stop = "roundId reached 0"
            break
        try:
            r = get_round(addr, rid, block)
        except Revert as e:
            stop = f"getRoundData({rid}) reverted"
            break
        except RpcError as e:
            stop = f"RPC failure at getRoundData({rid}): {e}"
            break
        if r["updatedAt"] == 0 or r["answer"] <= 0:
            stop = f"round {rid} empty (updatedAt=0 or answer<=0)"
            break
        rounds.append(r)
    return rounds, stop, cur


def sample_latest(addr, block_fn, n, interval):
    """Fallback: sample latestRoundData over time when rounds cannot be walked."""
    obs = []
    for i in range(n):
        if i:
            time.sleep(interval)
        try:
            b = block_fn()
            r = latest(addr, b)
            obs.append({"roundId": r["roundId"], "answer": r["answer"], "updatedAt": r["updatedAt"]})
        except (RpcError, Revert) as e:
            obs.append({"error": str(e)})
    return obs


def sample_summary(sample, interval):
    """Summarise a latestRoundData sampling run. Gaps here are bounded by the sampling interval."""
    obs = [o for o in sample if "updatedAt" in o]
    ts = [o["updatedAt"] for o in obs]
    ids = {o["roundId"] for o in obs}
    changes = [b - a for a, b in zip(ts, ts[1:])]
    moved = sum(1 for d in changes if d > 0)
    return {
        "samples": len(obs),
        "interval_s": interval,
        "distinct_roundIds": len(ids),
        "updatedAt_advanced_in": f"{moved}/{len(changes)}",
        "advance_min": min((d for d in changes if d > 0), default=None),
        "advance_median": pct([d for d in changes if d > 0], 50),
        "advance_max": max(changes) if changes else None,
    }


def block_timestamp(block):
    out = rpc("eth_getBlockByNumber", [block, False])
    return int(out["result"]["timestamp"], 16)


def analyse(rounds, decimals, now):
    rounds = sorted(rounds, key=lambda r: r["updatedAt"])
    ts = [r["updatedAt"] for r in rounds]
    gaps = [b - a for a, b in zip(ts, ts[1:]) if b > a]
    prices = [r["answer"] / 10 ** decimals for r in rounds]
    moves = [abs(b - a) / a * 100 for a, b in zip(prices, prices[1:]) if a > 0]
    res = {
        "rounds": len(rounds),
        "window_s": ts[-1] - ts[0] if len(ts) > 1 else 0,
        "gaps": len(gaps),
        "gap_min": min(gaps) if gaps else None,
        "gap_median": pct(gaps, 50),
        "gap_p95": pct(gaps, 95),
        "gap_max": max(gaps) if gaps else None,
        "moves": len(moves),
        "move_median": pct(moves, 50),
        "move_p95": pct(moves, 95),
        "move_max": max(moves) if moves else None,
        "latest_price": prices[-1] if prices else None,
        "latest_updatedAt": ts[-1] if ts else None,
        "age_s": now - ts[-1] if ts else None,
    }
    return res


def fmt(x, nd=0):
    if x is None:
        return "n/a"
    return f"{x:,.{nd}f}"


def ceil_to(x, step):
    return math.ceil(x / step) * step


def recommend(res):
    """Heuristic recommendations from a limited sample. Not a substitute for feed docs."""
    if res.get("gap_p95") is None:
        return None, None, "no gaps measured"
    max_age = ceil_to(2 * res["gap_p95"], 60)
    if res["gaps"] < 30:
        conf = f"low confidence ({res['gaps']} gaps)"
    else:
        conf = f"{res['gaps']} gaps"
    if res.get("move_p95") is None:
        dev = None
    else:
        dev = max(0.5, ceil_to(2 * res["move_p95"], 0.1))
    return max_age, dev, conf


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--max-rounds", type=int, default=200)
    ap.add_argument("--cache", default="", help="dir for per-feed results so a run can be split across calls")
    ap.add_argument("--out", default=str(ROOT / "docs" / "evidence" / "FEED_ANALYSIS.md"))
    args = ap.parse_args()

    block_hex = rpc("eth_blockNumber", [])["result"]
    block_num = int(block_hex, 16)
    block = hex(block_num)
    now = block_timestamp(block)

    feeds = [(k, v) for k, v in CFG["networks"]["mainnet"]["oracles"].items() if v.get("kind") == "chainlink"]
    results = []
    cache_dir = pathlib.Path(args.cache) if args.cache else None
    for key, meta in feeds:
        addr = meta["address"]
        cache_file = cache_dir / f"{key}.json" if cache_dir else None
        if cache_file and cache_file.exists():
            results.append(json.loads(cache_file.read_text()))
            print(f"{key}: loaded from cache", file=sys.stderr)
            continue
        row = {"key": key, "address": addr, "errors": [], "block": block_num, "block_ts": now}
        try:
            dec_h = eth_call(addr, SEL["decimals"], block)
            row["decimals"] = int(dec_h, 16)
        except (RpcError, Revert) as e:
            row["errors"].append(f"decimals(): {e}")
            row["decimals"] = meta.get("decimals", 8)
        try:
            row["description"] = decode_string(eth_call(addr, SEL["description"], block))
        except (RpcError, Revert) as e:
            row["errors"].append(f"description(): {e}")
            row["description"] = "n/a"
        if row["decimals"] != meta.get("decimals", row["decimals"]):
            row["errors"].append(f"decimals mismatch: chain={row['decimals']} config={meta.get('decimals')}")
        try:
            rounds, stop, cur = walk(addr, block, args.max_rounds)
            row["stop"] = stop
            row["latest_roundId"] = hex(cur["roundId"])
            row["stats"] = analyse(rounds, row["decimals"], now)
            if len(rounds) < 10:
                row["errors"].append(f"only {len(rounds)} round(s) walkable ({stop}); sampled latestRoundData over time instead")
                obs = sample_latest(addr, lambda: rpc("eth_blockNumber", [])["result"], 20, 30)
                row["sample"] = obs
                seen = {}
                for o in obs:
                    if "updatedAt" in o:
                        seen[o["updatedAt"]] = o
                row["sample_distinct_updates"] = len(seen)
                row["sample_window_s"] = 20 * 30
                row["sample_summary"] = sample_summary(obs, 30)
        except RpcError as e:
            row["errors"].append(f"walk failed: {e}")
            row["stats"] = None
            row["stop"] = "RPC failure"
        results.append(row)
        if cache_file:
            cache_file.parent.mkdir(parents=True, exist_ok=True)
            cache_file.write_text(json.dumps(row, default=str))
        print(key, row.get("stop"), row.get("stats", {}) and row["stats"]["rounds"], file=sys.stderr)

    for r in results:  # backfill summary for rows cached before sample_summary existed
        if r.get("sample") and "sample_summary" not in r:
            r["sample_summary"] = sample_summary(r["sample"], 30)

    # Table
    lines = []
    lines.append("# Monad mainnet feed analysis (Chainlink-interface feeds)")
    lines.append("")
    lines.append(f"Measured by `scripts/analyze_feeds.py` (read-only JSON-RPC, each feed read pinned to the block in its Block column, "
                 f"RPC `{RPCS[0]}`). Up to {args.max_rounds} rounds walked back per feed "
                 "from `latestRoundData()`; walk stops at the first `getRoundData` revert.")
    lines.append("")
    lines.append("Limits: one snapshot, one run. Walk length is limited by how far back the feed's current phase "
                 "keeps rounds, so counts differ per feed. Deviation is the percent change between consecutive "
                 "answers, not the feed's configured deviation threshold, which is not read on-chain here.")
    lines.append("")
    lines.append("## Results")
    lines.append("")
    lines.append("| Feed | Address | Description | Block | Rounds | Window (h) | Gap min / median / p95 / max (s) | Move median / p95 / max (%) | Age now (s) | Stop reason |")
    lines.append("|---|---|---|---:|---:|---:|---|---|---:|---|")
    for r in results:
        s = r.get("stats")
        if s:
            gap = f"{fmt(s['gap_min'])} / {fmt(s['gap_median'])} / {fmt(s['gap_p95'])} / {fmt(s['gap_max'])}"
            mv = f"{fmt(s['move_median'], 3)} / {fmt(s['move_p95'], 3)} / {fmt(s['move_max'], 3)}"
            lines.append(f"| {r['key']} | `{r['address']}` | {r['description']} | {r['block']:,} | {s['rounds']} | "
                         f"{fmt(s['window_s'] / 3600, 1)} | {gap} | {mv} | {fmt(s['age_s'])} | {r['stop']} |")
        else:
            lines.append(f"| {r['key']} | `{r['address']}` | {r['description']} | {r['block']:,} | 0 | n/a | n/a | n/a | n/a | {r['stop']} |")
    lines.append("")
    lines.append("Feeds with no walkable history (roundId never increments, so getRoundData(roundId-1) reverts):")
    lines.append("")
    lines.append("| Feed | Samples | Sampling interval (s) | Distinct roundIds | updatedAt advanced in | Advance min / median / max (s) | Age of last sampled update at report time (s) |")
    lines.append("|---|---:|---:|---:|---:|---|---:|")
    for r in results:
        if "sample_summary" in r:
            ss = r["sample_summary"]
            age = r["sample"][-1].get("updatedAt")
            age_s = (now - age) if age else "n/a"
            lines.append(f"| {r['key']} | {ss['samples']} | {ss['interval_s']} | {ss['distinct_roundIds']} | {ss['updatedAt_advanced_in']} | "
                         f"{fmt(ss['advance_min'])} / {fmt(ss['advance_median'])} / {fmt(ss['advance_max'])} | {age_s} |")
    lines.append("")
    lines.append("## Failures and notes (recorded as observed)")
    lines.append("")
    any_err = False
    for r in results:
        for e in r["errors"]:
            any_err = True
            lines.append(f"- **{r['key']}**: {e}")
    if not any_err:
        lines.append("- None.")
    for r in results:
        if "sample_distinct_updates" in r:
            errs = [o["error"] for o in r["sample"] if "error" in o]
            lines.append(f"- **{r['key']}** sampling: {r['sample_distinct_updates']} distinct updatedAt values in "
                         f"{len(r['sample'])} samples over {r['sample_window_s']} s; {len(errs)} sample errors.")
    lines.append("- Pyth (`pyth_PriceFeed`) is pull-based and does not expose `AggregatorV3` rounds; it was **not** measured here.")
    lines.append("- Stork (listed in docs/MONAD_REFERENCE.md, not in the config) was not measured.")
    lines.append("- Sampled feeds: updatedAt moved between every pair of 30 s samples, so the true update interval is at most about 30 s. The sampling interval is the only bound; no heartbeat or deviation threshold is measured for these feeds.")
    lines.append("")
    lines.append("## Recommendations (from a limited sample; not authoritative)")
    lines.append("")
    lines.append("Method: `maxAge` = 2 x observed p95 update gap, rounded up to 60 s. "
                 "`maxDeviation` = 2 x observed p95 round-to-round move, rounded up to 0.1 %, floor 0.5 %. "
                 "These are starting points for a staleness check and a single-update jump check. "
                 "Confirm against each feed's published heartbeat and deviation before use.")
    lines.append("")
    lines.append("| Feed | Suggested maxAge (s) | Suggested maxDeviation (%) | Basis |")
    lines.append("|---|---:|---:|---|")
    for r in results:
        s = r.get("stats")
        if "sample_summary" in r and (not s or not s.get("gaps")):
            if True:
                lines.append(f"| {r['key']} | not recommended | not recommended | single round; updatedAt advances about every 30 s (sampled); see sampling table |")
                continue
            lines.append(f"| {r['key']} | not measured | not measured | walk failed |")
            continue
        ma, dev, conf = recommend(s)
        if ma is None:
            lines.append(f"| {r['key']} | not measured | not measured | {conf} |")
            continue
        lines.append(f"| {r['key']} | {ma:,} | {dev:.1f} | p95 gap {fmt(s['gap_p95'])} s; p95 move {fmt(s['move_p95'], 3)} %; {conf} |")
    lines.append("")
    lines.append("Raw reads, one row per feed: decimals, description and latest roundId are in the script output; "
                 "re-run the script to reproduce. Results change with every block, so compare the method, not the exact numbers.")
    lines.append("")

    out = pathlib.Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text("\n".join(lines))
    print(f"wrote {out}", file=sys.stderr)


if __name__ == "__main__":
    main()
