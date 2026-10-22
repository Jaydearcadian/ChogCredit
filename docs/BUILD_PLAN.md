# Chog Credit Build Plan

**Version:** 0.2.1
**Date:** 22 October 2026
**Status:** Proposed plan. Nothing in it is built yet. It follows the Gate A to F order in `IMPLEMENTATION_STATUS.md` and uses the verified facts in `MONAD_REFERENCE.md`.

## 1. What the research changed

| Finding | Source | Effect on the plan |
|---|---|---|
| Chogathon scores Novelty 30%, Fun 20%, Retention 20%, Clarity 15%, plus optional $CHOG bonus. "The Chog NFT must be essential." 14 days to build, 7 days of judging, 50 winners, $15K pool. | chogathon.chog.xyz | The first deliverable is a clear, fun, working testnet or fork demo, not a production lending market. 40% of the score is Fun and Retention, which the specs barely cover (section 7). |
| Chog Genesis is live on Monad mainnet: 1,969 tokens, ERC-721 + ERC-2981, **not enumerable**, no transfer validator, role-based admin, not verified on Sourcify. | on-chain reads | Escrow by `approve` + `safeTransferFrom` should work, but admin powers are unknown and must be checked. Wallet discovery cannot use `tokenOfOwnerByIndex`. |
| No Chog collection on testnet. | `eth_getCode` = `0x` | Testnet uses a mock collection; live-collection behaviour is tested on a **mainnet fork**. These are separate evidence classes. |
| Floor is about $110 to $130 per Chog and weekly volume is under $5K. | OpenSea snapshot (unverified) | NFT collateral value stays zero. Credit has to come from assets in the vault. |
| USDC/WMON liquidity is about $1.2M at best (Uniswap V3 0.3%); CHOG pools hold a few hundred dollars. | on-chain balances | Liquidation by swapping needs small caps. No `$CHOG` collateral. |
| Chainlink and RedStone both publish MON/USD and USDC/USD on mainnet and agree to about 0.1%. | on-chain reads | A real two-source oracle is possible for WMON collateral. Pyth is available as a third source. |
| Uniswap V3 and Pancake V3 position managers are live with 19K and 24K positions. | on-chain reads | A real LP-position adapter is feasible as a later step after the WMON loop works. |
| Monad gas is charged on the gas limit; receipts appear at `Proposed`. | Monad docs | Tight gas limits in scripts; the UI must separate "seen", "included" and "finalized". |
| NFT-lending exploits: Omni (2022, $1.4M, reentrancy through `onERC721Received`) and Gondi (Mar 2026, about $230K, a missing caller-ownership check in a sell-and-repay bundler). | public post-mortems | Added to the test list in section 6. |

## 2. Scope tiers

| Tier | Goal | Evidence target | Contains |
|---|---|---|---|
| **1. Chogathon demo** | A judge can open the app, pick a Chog, open its account, deposit collateral, borrow, repay, and release. Every screen says what is mock and what is live. | `LOCAL_BUILD_PASS`, `TESTNET_DEPLOY_PASS`, `INTEGRATION_PASS` on testnet with a mock collection and mock USDC; escrow behaviour proven on a mainnet fork | Gates A to C and E, with a simple WMON-style mock collateral and a mock oracle clearly labelled |
| **2. Real-position pilot** | One real collateral type with a real oracle and unwind path, still without outside funds | Gate D complete, fork tests against real pools | Chainlink + RedStone WMON collateral, then a Uniswap V3 USDC/WMON LP adapter |
| **3. Production** | Capped beta | Gate F: audit, multisig/timelock, legal review | Everything in `SECURITY_AND_RISK.md` |

Only Tier 1 fits the Chogathon window. Tiers 2 and 3 stay on the roadmap and must not be claimed in the pitch.

## 3. Workstreams

Each workstream lists the files, what must be true, and the tests that prove it.

### W0 Tooling (Gate A)

- Install Foundry 1.8 or later and set `network = "monad"` in `contracts/foundry.toml`. Pin the Solidity version and OpenZeppelin release (the existing baseline is 0.8.24; confirm it builds under the Monad execution profile before relying on a newer EVM target).
- Vendor dependencies under `contracts/lib` with a lockfile or submodule commits, and add CI that runs `forge fmt --check`, `forge build`, `forge test`.
- Replace `contracts/script/Deploy.s.sol` safety: assert `block.chainid`, assert token decimals, refuse mock deployment unless the manifest says `mock`.
- First check: build and test the existing prototype so we know the baseline, then delete or archive `ChogPositionNFT`.

### W1 Registry and mock collection (Gate B)

- `ChogAccountRegistry`: maps `keccak256(chainId, collection, tokenId)` to one account record and one vault, with a collection allowlist set at deployment and not changeable by an EOA. One record per key; no duplicates.
- `MockChogGenesis` for tests and testnet: ERC-721 with IDs 1 to 1969, ERC-2981, AccessControl, same interface surface as the live contract. A second `HostileCollection` mock (malicious callbacks, lying `ownerOf`) for negative tests.
- Account creation only for a token the caller owns (wallet-held) or that escrow records for the caller.
- Tests: duplicate create, wrong collection, zero address, non-owner create, key derivation determinism.

### W2 Escrow (Gate C)

- `ChogCreditEscrow` holds the original NFT and records the **beneficial owner**. Entry through `safeTransferFrom` into `onERC721Received`, accepted only from the allowlisted collection and only when the registry says the sender is the previous owner.
- Release only when the account has no assets, no positions, no debt, and no pending operation. No admin path can move an escrowed NFT.
- `nonReentrant` on every state-changing function, state updated before any external call (the Omni lesson), and `transferFrom` rather than `safeTransferFrom` when sending to an address known to be an EOA or trusted contract.
- Tests: release blocked with $1 of collateral; release blocked with 1 wei of debt; reentrancy through a hostile receiver; wrong-collection NFT sent directly; re-entry that tries to create a second account; beneficial-owner change only through the documented path.

### W3 Vault and custody (Gate B/C)

- `AccountVaultFactory` deploys one EIP-1167 clone per account. `AccountVault` holds allowlisted ERC-20s, checks the **balance delta** on deposit, and has no generic `call(target, data)`.
- Optional: implement the minimal `IERC6551Account` view surface later so explorers and the Tokenbound SDK can recognise the vault. Do not use the stock ERC-6551 account directly: once the NFT is in escrow, `ownerOf` is the escrow contract, so the stock account would be controlled by escrow, not by the beneficial owner.
- Tests: fee-on-transfer and rebasing mocks rejected; unsupported token visible but valued at zero; unauthorized withdrawal; state nonce increments.

### W4 Collateral registry and oracle (Gate D)

- `CollateralRegistry` with the struct from `TECHNICAL_SPECIFICATION.md` (LTV, liquidation threshold, bonus, caps, max price age, enabled flag).
- `OracleAdapter` for Chainlink-style feeds: positive answer, `updatedAt` within a per-feed window, round completeness, decimals read from the feed, revert on failure (fail closed for borrow, defined behaviour for liquidation).
- Cross-check: second source (RedStone) must agree within a configured deviation, otherwise new borrowing is blocked.
- Tier 1 uses a clearly named `MockOracle` with an owner-set price **only on testnet**; Tier 2 switches the same interface to the Chainlink and RedStone feeds in `config/monad-reference.json`.
- Tests: zero/negative/stale/future timestamp, reverting feed, 6/8/18/24 decimal tokens, feed disagreement, price gap.

### W5 Credit pool (Gate D)

- `ChogCreditPool`: USDC supply with share accounting, debt index, utilization-based rate, per-account and pool caps, borrow to the **vault** by default, repay by anyone, partial liquidation with a close factor, bad-debt recognition.
- Tier 1 may cap and label liquidity as test liquidity, but it still uses shares and a debt index so Tier 2 does not require a rewrite.
- Tests: the invariants in `TECHNICAL_SPECIFICATION.md` section 12 as Foundry invariants with a bounded handler; the existing "borrowing requires liquidity" test rewritten so the pool-cash branch is actually hit.

### W6 Package transfer, debt-free first (Gate C/E)

- `AccountTransferCoordinator` for escrowed accounts: EIP-712 buyer acceptance over chain ID, contract, account key, state nonce, price, expiry, and (later) debt ceiling and minimum health factor. Atomic payment and beneficial-owner change.
- Tests: replay, wrong chain, expired, nonce changed after a deposit or borrow, caller is not the beneficial owner (the Gondi lesson: check ownership of the thing being sold, not just the caller of a bundle), payment failure reverts the whole transfer.

### W7 Frontend and wallet (Gate E)

- wagmi + viem (2.40 or later for the Monad chain), manifest-driven addresses, chain ID gate, persistent mode banner (`LOCAL`, `TESTNET MOCK`, `MAINNET FORK`), no fallback to sample data when a read fails.
- **Finding a user's Chogs without an indexer:** the live collection is not enumerable, but it has only 1,969 tokens. Read `ownerOf(1..1969)` through Multicall3 in a few batches of about 500 calls and filter by the connected address. Escrowed tokens are found through the registry. Add an indexer only if this proves too slow.
- Transaction state machine from the spec, extended for Monad: show "seen at Proposed" separately from "finalized".
- Screens: pick a Chog, account overview, positions, borrow, repay, release/transfer, activity, security status.

### W8 Read API and events (Gate E)

- Keep the existing read-only Express/viem service; fix CORS to an allowlist and add input validation. Event-backed history can start as direct `getLogs` reads. Envio HyperIndex or Goldsky are the options if reorg-safe history is needed later.

### W9 Fork and integration tests (Gate C/D/E)

- Mainnet-fork suite (`anvil --fork-url https://rpc.monad.xyz`, or `forge test --fork-url`):
  1. Impersonate the current holder of a real token (token 532 is held by `0x802f66721b20557ffe3a5363263e7e173006e79a` at the time of reading) and run approve, `safeTransferFrom` into escrow, and release against the **real** collection. This is the proof that live escrow works.
  2. Confirm no hidden transfer restriction (paused state, operator filter, blocked receiver) affects a contract recipient.
  3. Read the real Chainlink and RedStone feeds through the adapter.
  4. Tier 2: deposit a real Uniswap V3 position NFT into a vault, value it, unwind it.
- Testnet suite: deploy via the same script, run the full flow, save tx hashes into the deployment ledger.

## 4. Sequence (proposal, not a promise)

The Chogathon pages show a 14-day build window. Exact start and deadline dates were not confirmed, so these are relative days.

| Days | Work | Exit evidence |
|---|---|---|
| 1 | W0, then confirm collection address with the Chog team, get contract source/ABI, read application terms | `LOCAL_BUILD_PASS` on the baseline; written confirmations recorded |
| 2 to 4 | W1, W2, W3 with mock collection | Unit and fuzz tests green; fork test of live-collection escrow |
| 5 to 7 | W4 (mock oracle for Tier 1), W5 | Invariant suite green |
| 8 to 9 | W7 first working vertical slice on testnet; W8 | `TESTNET_DEPLOY_PASS` with tx hashes |
| 10 to 11 | Fun/Retention layer, W6 if time allows | Demo script rehearsed on testnet |
| 12 to 14 | Hardening, labels, README, pitch assets, demo recording | `INTEGRATION_PASS` evidence ledger filled |

If time runs short, cut W6, the second-market adapter, and any real-position work. Do not cut the labels, the escrow tests, or the evidence ledger.

## 5. Decisions needed from the team

1. Is the Chog Genesis contract above the collection in scope, and can the Chog team confirm the address in writing?
2. Can we get the verified source/ABI of the live contract, and who holds its admin role?
3. Is the Chog artwork cleared for use in the product, in what form, and under whose approval?
4. Do we submit as a testnet plus mainnet-fork demo, or is a capped mainnet deployment expected? (The specs say no real funds before the audit gates.)
5. Is `$CHOG` integration wanted for the bonus? Any version of it needs its own risk review; the pools are too thin for it to be collateral.
6. Who funds test liquidity, and is the Circle testnet USDC faucet acceptable instead of a mock?

## 6. Security additions from the research

- Treat `onERC721Received` as an attacker-controlled entry point: guard, update state first, and test with a hostile receiver (Omni, 2022).
- Every function that sells, releases or moves a Chog must check that the **account owner** authorized it, not only that the caller is a contract that was told to do it (Gondi, 2026).
- Check the stock ERC-6551 warning if a token-bound account is ever used: a seller can drain the account just before a sale, which is why package transfers here bind to a state nonce and are atomic.
- Do not trust an `ownerOf` answer from an unlisted collection; compare the collection address to the allowlist on every entry point.
- Read oracle heartbeats from the feed documentation before setting freshness windows. The observed USDC/USD age was over 40 minutes.

## 7. Fun and Retention (proposals, not requirements)

These are ideas to get the 40% of the score that the existing documents do not address. They are unvalidated.

- The Chog's expression follows account state (curious, focused, relieved after repayment, worried near the liquidation line). This is already in the brand direction and costs only art and copy.
- A visible "account health" history for each Chog, so there is a reason to open the app after the first session.
- A one-click "demo mode" that walks a judge through the whole loop in under two minutes on testnet.
- Any `$CHOG` use (for example fee discounts) must be optional and must not appear in the credit calculation.

## 8. Not covered here

Legal and regulatory review, audit scheduling, tokenomics, and mainnet liquidity sourcing. They remain gates in `SECURITY_AND_RISK.md` and `PRD.md`.
