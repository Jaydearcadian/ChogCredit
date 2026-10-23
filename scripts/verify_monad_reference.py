#!/usr/bin/env python3
"""Re-verify config/monad-reference.json against live Monad RPC.

Read-only: eth_chainId, eth_getCode, eth_call. No keys, no transactions.
Usage: python3 -I scripts/verify_monad_reference.py [mainnet|testnet]
Exit code 1 if any entry fails. Output is the evidence for LIVE_READ_PASS.
"""
import json, sys, time, urllib.request, pathlib

cfg = json.load(open(pathlib.Path(__file__).resolve().parent.parent / "config" / "monad-reference.json"))
net = sys.argv[1] if len(sys.argv) > 1 else "mainnet"
n = cfg["networks"][net]
rpc = n["rpc"][0]


def call(method, params):
    req = urllib.request.Request(rpc, json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params}).encode(), {"content-type": "application/json"})
    return json.load(urllib.request.urlopen(req, timeout=30))


def eth_call(to, data):
    r = call("eth_call", [{"to": to, "data": data}, "latest"])
    return r.get("result") if "result" in r else None


def text(h):
    if not h:
        return None
    b = bytes.fromhex(h[2:])
    if len(b) == 32:
        return b.rstrip(b"\0").decode(errors="replace")
    off = int.from_bytes(b[:32], "big")
    ln = int.from_bytes(b[off:off + 32], "big")
    return b[off + 32:off + 32 + ln].decode(errors="replace")


def num(h):
    return int(h, 16) if h else None


fails = []
chain = int(call("eth_chainId", [])["result"], 16)
block = int(call("eth_blockNumber", [])["result"], 16)
print(f"network={net} rpc={rpc} chainId={chain} block={block}")
if chain != n["chainId"]:
    print(f"FAIL chainId expected {n['chainId']}"); sys.exit(1)


def check(group, name, e):
    a = e["address"]
    code = (len(call("eth_getCode", [a, "latest"])["result"]) - 2) // 2
    line = f"{group}/{name} {a} code={code}B"
    if code == 0:
        fails.append(name); print("FAIL", line); return
    kind = e.get("kind")
    try:
        if kind in ("erc20", "erc721"):
            line += f" name={text(eth_call(a, '0x06fdde03'))!r} symbol={text(eth_call(a, '0x95d89b41'))!r}"
        if kind == "erc20":
            dec = num(eth_call(a, "0x313ce567")); line += f" decimals={dec}"
            if "decimals" in e and e["decimals"] != dec: fails.append(name); line += " MISMATCH-DECIMALS"
        if kind == "erc721":
            sup = num(eth_call(a, "0x18160ddd")); line += f" totalSupply={sup}"
            line += f" erc721={num(eth_call(a, '0x01ffc9a7' + '80ac58cd' + '0' * 56))}"
            if "totalSupply" in e and e["totalSupply"] != sup: fails.append(name); line += " MISMATCH-SUPPLY"
        if kind == "chainlink":
            d = num(eth_call(a, "0x313ce567")); lr = eth_call(a, "0xfeaf968c")
            w = [int(lr[2 + 64 * i:2 + 64 * (i + 1)], 16) for i in range(5)]
            age = int(time.time()) - w[3]
            line += f" desc={text(eth_call(a, '0x7284e416'))!r} answer={w[1] / 10 ** d} age={age}s"
            if d != e["decimals"] or w[1] <= 0: fails.append(name); line += " BAD-FEED"
    except Exception as ex:
        fails.append(name); line += f" ERROR {ex}"
    print("ok  " if name not in fails else "FAIL", line)


for group in ("contracts", "pools", "oracles"):
    for name, e in n.get(group, {}).items():
        check(group, name, e)
print("RESULT:", "PASS" if not fails else f"FAIL {fails}")
sys.exit(1 if fails else 0)
