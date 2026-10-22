# Monad Reference for Chog Credit

**Version:** 0.2.1
**Date:** 22 October 2026
**Evidence level:** `LIVE_READ_PASS` for every address in the tables below, as of mainnet block 115,697,336 and testnet block 73,328,862. Reproduce with `python3 -I scripts/verify_monad_reference.py mainnet|testnet`. Machine-readable copy: `config/monad-reference.json`.

> **Scope of this document.** These are third-party contracts and public facts that Chog Credit may integrate with. A `LIVE_READ_PASS` means the address has code, answers the expected read calls on the expected chain, and matches the named source. It does **not** mean the contract is audited, safe to integrate, or approved as collateral. Nothing here is a Chog Credit deployment. Market numbers are point-in-time snapshots.

## 1. Networks

| | Mainnet | Testnet |
|---|---|---|
| Chain ID | `143` (`0x8f`) | `10143` (`0x279f`) |
| Currency | MON | MON |
| Public RPC | `https://rpc.monad.xyz` (also `https://rpc1.monad.xyz`) | `https://testnet-rpc.monad.xyz` |
| WebSocket | `wss://rpc.monad.xyz` | `wss://testnet-rpc.monad.xyz` |
| Explorers | monadvision.com, monadscan.com | testnet.monadvision.com, testnet.monadscan.com |
| Faucet | n/a | https://faucet.monad.xyz |
| Version (Monad docs) | v0.16.1, revision `MONAD_TEN` | v0.16.2, revision `MONAD_TEN` |

Testnet was reset from genesis on 2025-12-16. Source: https://docs.monad.xyz/ai/current-facts and https://docs.monad.xyz/developer-essentials/network-information

**Execution facts that affect design** (Monad docs): block time about 300 ms, speculative finality 1 slot, finality 2 slots (about 600 ms); 150M block gas limit; **30M per-transaction gas limit**; **gas is charged on the gas limit, not gas used**, so set tight limits; 128 KB contract size limit and 256 KB initcode limit; Fusaka opcodes and precompiles supported; receipts first appear when a block is `Proposed` (speculative), so the UI must not treat "receipt seen" as final.

## 2. Chog assets (mainnet)

| Asset | Address | Verified reads |
|---|---|---|
| **Chog Genesis (ERC-721)** | `0xc96d31f8626c6d03fae5dcd3d61e3fb9f4a73763` | name `Chog Genesis`, symbol `CHOG`, `totalSupply` **1,969** (matches the official mint page, "All 1,969 Chogs minted"), ERC-721 + ERC-721Metadata + ERC-2981 supported, **not** ERC-721Enumerable, not an EIP-1967 proxy, 17,264 bytes of code |
| $CHOG token (ERC-20) | `0x350035555E10d9AfAF1566AaebfCeD5BA6C27777` | name `Chog`, 18 decimals, supply 999,999,989; address printed on www.chog.xyz |

Observations about the collection contract (from on-chain reads, not from source code):

- Token IDs start at 1 (`ownerOf(1)` and `ownerOf(1969)` resolve). `tokenURI(532)` is `ipfs://bafybei…/24.json`, so IDs and metadata file names do not line up one to one.
- Royalty: `royaltyInfo(532, 1e18)` returns 5% to `0x84113421a8a564b594ee9ae78c875310332d7023`.
- `owner()` reverts and `DEFAULT_ADMIN_ROLE()` resolves, so access control is role-based (OpenZeppelin AccessControl pattern). The deployer/admin powers are **unknown**.
- No transfer-validator hook: `getTransferValidator()` reverts, and no `pause`/`paused` selector was found in the bytecode, so a plain `approve` + `safeTransferFrom` into escrow is expected to work. This must be proven with a fork test (see `BUILD_PLAN.md`, section 5).
- The contract has about 120 selectors, more than a plain ERC-721, and it is **not verified on Sourcify** (queried 2026-10-22). Obtain the verified source or ABI from the Chog team or an explorer before relying on admin behaviour.
- There is **no Chog Genesis code on testnet** (`eth_getCode` returns `0x`). Testnet work needs a mock collection.

Official-source status: the official mint page (mint.chog.xyz) states 1,969 supply and links the OpenSea collection `opensea.io/collection/chog-genesis` (shown as Verified). The on-chain supply and name match. I did **not** find the contract address printed on an official Chog-controlled page. Treat the address as strongly corroborated but still ask the Chog team to confirm it in writing (`WHITEPAPER.md` section 12, decision 2).

## 3. Tokens and infrastructure (mainnet)

| Item | Address | Notes |
|---|---|---|
| USDC (Circle) | `0x754704Bc059F8C67012fEd69BC8A327a5aafb603` | 6 decimals; listed on developers.circle.com/stablecoins/usdc-contract-addresses; re-verify at release |
| WMON | `0x3bd359C1119dA7Da1D913D1C4D2B7c461115433A` | 18 decimals; `WETH9` of the Uniswap and Pancake deployments |
| Multicall3 | `0xcA11bde05977b3631167028862bE2a173976CA11` | use for batched `ownerOf` reads |
| Permit2 | `0x000000000022d473030f116ddee9f6b43ac78ba3` | |
| CreateX | `0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed` | |
| Create2Deployer | `0x13b0D85CcB8bf860b6b79AF3029fCA081AE9beF2` | |
| Deterministic factory (EIP-7997) | `0x4e59b44847b379578588920ca78fbf26c0b4956c` | |
| ERC-4337 EntryPoint v0.7 | `0x0000000071727De22E5E9d8BAf0edAc6f37da032` | |
| ERC-6551 registry (Tokenbound v3) | `0x000000006551c19487814612e58FE06813775758` | same address on testnet; account impl v3 `0x41C8f39463A868d3A88af00cd0fe7102F30E44eC` |
| OpenSea Seaport (Marketplace) | `0x0000000000000068F116a894984e2DB1123eB395` | |

Testnet: USDC (Circle listing) `0x534b2f3A21130d7a60830c2Df862319e593943A3` (6 decimals), Multicall3 and the ERC-6551 registry at the same addresses as mainnet, Pyth price feed contract `0x2880aB155794e7179c9eE2e38200202908C17B43`.

## 4. Candidate collateral and liquidation venues (mainnet)

| Venue | Contract | Address | Notes |
|---|---|---|---|
| Uniswap V3 | Factory | `0x204faca1764b154221e35c0d20abb3c525710498` | |
| Uniswap V3 | NonfungiblePositionManager | `0x7197e214c0b767cfb76fb734ab638e2c192f4e53` | name `Uniswap V3 Positions NFT-V1`, 19,240 positions |
| Uniswap V3 | SwapRouter02 / QuoterV2 | `0xfe31f71c1b106eac32f1a19239c9a9a72ddfb900` / `0x661e93cca42afacb172121ef892830ca3b70f08d` | |
| Uniswap V4 | PoolManager / PositionManager | `0x188d586ddcf52439676ca21a244753fa19f9ea8e` / `0x5b7ec4a94ff9bedb700fb82ab09d5846972f4016` | v4 positions are harder to value; defer |
| PancakeSwap V3 | Factory / NonfungiblePositionManager | `0x0BFbCF9fa4f9C56B0F40a671Ad40E0805A091865` / `0x46A15B0b27311cedF172AB29E4f4766fbE7F4364` | 23,599 positions |
| Morpho Blue | Morpho | `0xD5D960E8C380B724a48AC59E2DfF1b2CB4a1eAee` | |
| Neverland (Aave v3 fork) | Pool | `0x80F00661b13CC5F6ccd3885bE7b4C9c67545D585` | |
| Curvance | CentralRegistry | `0x1310f352f1389969Ece6741671c4B919523912fF` | |
| Kuru | Router | `0xd651346d7c789536ebf06dc72aE3C8502cd695CC` | hybrid orderbook/AMM; USDC and MON markets listed in the Monad registry |

Source for all of the above: https://github.com/monad-crypto/protocols (mainnet folder), with code and token metadata confirmed on-chain.

### Pool depth snapshot (2026-10-22, on-chain balances)

| Pool | USDC | WMON | Approx. value |
|---|---:|---:|---:|
| Uniswap V3 USDC/WMON 0.30% `0x659bd0bc…a9da` | 225,787 | 44,476,103 | about $1.16M |
| Pancake V3 USDC/WMON 0.05% `0x63e48b72…53f2` | 31,978 | 4,711,655 | about $0.13M |
| Pancake V3 USDC/WMON 1.00% | 1,975 | 666,796 | about $0.016M |
| Other USDC/WMON fee tiers | under 700 | under 60,000 | negligible |
| Uniswap V3 CHOG/WMON 0.30% | 0 | 2.8 | negligible |
| Pancake V3 CHOG/WMON 1.00% | 0 | 11,049 | about $230 |

(WMON priced at about $0.0209 from the Chainlink MON/USD feed at the time of reading.) **Consequence:** on-chain liquidity is thin. Any liquidation path that swaps through these pools needs hard exposure caps, and `$CHOG` is not usable as collateral.

## 5. Oracles (mainnet)

All feeds below answered `latestRoundData()` on the Chainlink interface with 8 decimals and a positive answer at read time.

| Feed | Address | Reading at verification |
|---|---|---|
| Chainlink MON/USD | `0xBcD78f76005B7515837af6b50c7C52BCf73822fb` | 0.0209, age 27 s |
| Chainlink USDC/USD | `0xf5F15f188AbCb0d165D1Edb7f37F7d6fA2fCebec` | 0.99981, age 2,623 s |
| Chainlink ETH/USD | `0x1B1414782B859871781bA3E4B0979b9ca57A0A04` | about 2,385 |
| Chainlink BTC/USD | `0xc1d4C3331635184fA4C3c22fb92211B2Ac9E0546` | about 81,300 |
| RedStone MON/USD | `0x1C9582E87eD6E99bc23EC0e6Eb52eE9d7C0D6bcd` | 0.02093, age 0 s |
| RedStone USDC/USD | `0x7A9b672fc20b5C89D6774514052b3e0899E5E263` | 0.99981, age 3 s |
| Pyth price feed contract | `0x2880aB155794e7179c9eE2e38200202908C17B43` (newer `0xB754BA51E3861Ac0Cb67f73CD046dE790A36508d`) | pull-style; feed IDs in `config/monad-reference.json`; **read path not yet exercised** |
| Stork | `0xacC0a0cF13571d30B4b8637996F5D6D774d4fd62` | not read |

Design notes: the Chainlink MON/USD and RedStone MON/USD readings agree to within about 0.1% at read time, which makes them a usable primary plus cross-check pair. The USDC/USD heartbeat looked long (age over 40 minutes), so freshness windows must be set per feed from observed heartbeats and the feed documentation, not from one global constant. Feed heartbeat and deviation parameters have **not** been independently confirmed here.

## 6. Market snapshot for Chog Genesis (not verified on-chain)

From the OpenSea collection page and a third-party tracker as returned by search: floor about 5,100 to 6,240 MON, 978 to 1,027 owners, 24h volume about $1,000, 7d volume about $4,800. At 0.0209 USD per MON that is roughly **$110 to $130 per Chog**.

Implications: (1) the NFT is a poor collateral asset, which matches the existing rule that the NFT's own collateral value is zero; (2) any credit line has to come from assets deposited in the vault, not from the Chog.

## 7. Build tooling notes

- Foundry **v1.8 or later**, with `network = "monad"` in `foundry.toml`, uses Monad's gas model, precompiles and size limits. Fork with `anvil --fork-url https://rpc.monad.xyz`; the hardfork is selected from the fork block automatically. Source: https://docs.monad.xyz/tooling-and-infra/toolkits/foundry
- Verification, MonadVision (Sourcify): `forge verify-contract <addr> <Name> --chain 143 --verifier sourcify --verifier-url https://sourcify-api-monad.blockvision.org/`. Monadscan: `--verifier etherscan --etherscan-api-key <key>`. Source: https://docs.monad.xyz/guides/verify-smart-contract/foundry
- `viem >= 2.40.0` includes the `monad` chain definition.
- Indexing options listed by Monad: Envio HyperIndex, Goldsky, The Graph, Ghost, others (https://docs.monad.xyz/tooling-and-infra/indexers/indexing-frameworks). Not required for the first demo, see `BUILD_PLAN.md`.
- ERC-6551 (Tokenbound v3) is deployed at canonical addresses on both networks (https://docs.monad.xyz/guides/erc-6551). It is an optional account pattern, not a requirement; see `BUILD_PLAN.md` for why the escrow design still uses a dedicated vault.

## 8. Not verified or still open

- Official written confirmation of the Chog Genesis contract address from the Chog team.
- Verified source/ABI of the Chog Genesis contract and the powers of its admin role.
- Whether any other official Chog NFT collection is meant by "Chog NFT" in the Chogathon brief.
- Heartbeat and deviation parameters of each oracle feed; Pyth and Stork read paths.
- Whether Uniswap/Pancake position managers have any behaviour that blocks custody by a third-party vault (to be tested on a fork).
- Chogathon application terms beyond the judging page (eligibility, license, prize payment) and the exact start and deadline dates.

## 9. Sources consulted

Monad docs (current facts, network information, Foundry, verification, ERC-6551, oracles, indexers), `monad-crypto/protocols` registry, Circle USDC address page, mint.chog.xyz, www.chog.xyz, chogathon.chog.xyz, OpenSea collection page, Uniswap/Pancake deployment docs. Search was run through the Parallel Search API; on-chain facts were then re-read directly from Monad RPC.
