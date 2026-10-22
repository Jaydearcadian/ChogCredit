# Monad mainnet feed analysis (Chainlink-interface feeds)

Measured by `scripts/analyze_feeds.py` (read-only JSON-RPC, each feed read pinned to the block in its Block column, RPC `https://rpc.monad.xyz`). Up to 200 rounds walked back per feed from `latestRoundData()`; walk stops at the first `getRoundData` revert.

Limits: one snapshot, one run. Walk length is limited by how far back the feed's current phase keeps rounds, so counts differ per feed. Deviation is the percent change between consecutive answers, not the feed's configured deviation threshold, which is not read on-chain here.

## Results

| Feed | Address | Description | Block | Rounds | Window (h) | Gap min / median / p95 / max (s) | Move median / p95 / max (%) | Age now (s) | Stop reason |
|---|---|---|---:|---:|---:|---|---|---:|---|
| chainlink_MON_USD | `0xBcD78f76005B7515837af6b50c7C52BCf73822fb` | MON / USD | 115,734,088 | 200 | 2.6 | 29 / 30 / 91 / 300 | 0.048 / 0.146 / 0.271 | 20 | max_rounds reached |
| chainlink_USDC_USD | `0xf5F15f188AbCb0d165D1Edb7f37F7d6fA2fCebec` | USDC / USD | 115,734,088 | 200 | 199.3 | 3,601 / 3,606 / 3,607 / 3,609 | 0.002 / 0.005 / 0.008 | 2,902 | max_rounds reached |
| chainlink_ETH_USD | `0x1B1414782B859871781bA3E4B0979b9ca57A0A04` | ETH / USD | 115,734,088 | 200 | 5.4 | 9 / 60 / 290 / 892 | 0.059 / 0.090 / 0.115 | 114 | max_rounds reached |
| chainlink_BTC_USD | `0xc1d4C3331635184fA4C3c22fb92211B2Ac9E0546` | BTC / USD | 115,734,088 | 200 | 4.0 | 9 / 40 / 232 / 391 | 0.026 / 0.043 / 0.053 | 4 | max_rounds reached |
| redstone_MON_USD | `0x1C9582E87eD6E99bc23EC0e6Eb52eE9d7C0D6bcd` | RedStone Price Feed for MON | 115,737,994 | 1 | 0.0 | n/a / n/a / n/a / n/a | n/a / n/a / n/a | 1 | roundId reached 0 |
| redstone_USDC_USD | `0x7A9b672fc20b5C89D6774514052b3e0899E5E263` | RedStone Price Feed for USDC | 115,737,994 | 1 | 0.0 | n/a / n/a / n/a / n/a | n/a / n/a / n/a | 2 | roundId reached 0 |

Feeds with no walkable history (roundId never increments, so getRoundData(roundId-1) reverts):

| Feed | Samples | Sampling interval (s) | Distinct roundIds | updatedAt advanced in | Advance min / median / max (s) | Age of last sampled update at report time (s) |
|---|---:|---:|---:|---:|---|---:|
| redstone_MON_USD | 20 | 30 | 1 | 19/19 | 30 / 30 / 33 | 638 |
| redstone_USDC_USD | 20 | 30 | 1 | 19/19 | 30 / 30 / 32 | 49 |

## Failures and notes (recorded as observed)

- **redstone_MON_USD**: only 1 rounds walkable (roundId reached 0); sampling latestRoundData over time
- **redstone_USDC_USD**: only 1 rounds walkable (roundId reached 0); sampling latestRoundData over time
- **redstone_MON_USD** sampling: 20 distinct updatedAt values in 20 samples over 600 s; 0 sample errors.
- **redstone_USDC_USD** sampling: 20 distinct updatedAt values in 20 samples over 600 s; 0 sample errors.
- Pyth (`pyth_PriceFeed`) is pull-based and does not expose `AggregatorV3` rounds; it was **not** measured here.
- Stork (listed in docs/MONAD_REFERENCE.md, not in the config) was not measured.
- Sampled feeds: updatedAt moved between every pair of 30 s samples, so the true update interval is at most about 30 s. The sampling interval is the only bound; no heartbeat or deviation threshold is measured for these feeds.

## Recommendations (from a limited sample; not authoritative)

Method: `maxAge` = 2 x observed p95 update gap, rounded up to 60 s. `maxDeviation` = 2 x observed p95 round-to-round move, rounded up to 0.1 %, floor 0.5 %. These are starting points for a staleness check and a single-update jump check. Confirm against each feed's published heartbeat and deviation before use.

| Feed | Suggested maxAge (s) | Suggested maxDeviation (%) | Basis |
|---|---:|---:|---|
| chainlink_MON_USD | 240 | 0.5 | p95 gap 91 s; p95 move 0.146 %; 199 gaps |
| chainlink_USDC_USD | 7,260 | 0.5 | p95 gap 3,607 s; p95 move 0.005 %; 199 gaps |
| chainlink_ETH_USD | 600 | 0.5 | p95 gap 290 s; p95 move 0.090 %; 199 gaps |
| chainlink_BTC_USD | 480 | 0.5 | p95 gap 232 s; p95 move 0.043 %; 199 gaps |
| redstone_MON_USD | not recommended | not recommended | single round; updatedAt advances about every 30 s (sampled); see sampling table |
| redstone_USDC_USD | not recommended | not recommended | single round; updatedAt advances about every 30 s (sampled); see sampling table |

Raw reads, one row per feed: decimals, description and latest roundId are in the script output; re-run the script to reproduce. Results change with every block, so compare the method, not the exact numbers.
