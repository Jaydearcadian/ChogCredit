# Implementation Status and Evidence Ledger

**Product:** Chog Credit  
**Status date:** 22 October 2026  
**Evidence ceiling:** source bundle available; compilation, tests, deployment and audit not verified in this environment

## 1. Summary

The currently bundled implementation is an earlier prototype organized around a newly minted `ChogPositionNFT`. That architecture conflicts with the revised product requirement: the existing Chog NFT must be the canonical identity and the product must not require a second Position NFT.

The existing package is useful as a reference for a simple credit-account experiment, but **it is not yet the Chog Credit implementation specified in the revised whitepaper, PRD and technical specification**. Do not deploy it with real funds or describe it as integrating the existing Chog collection.

## 2. Evidence states

- `SOURCE_PRESENT`: files are included in the bundle.
- `LOCAL_BUILD_PASS`: compiler/build was run successfully on an identified commit.
- `TEST_PASS`: relevant tests passed and logs exist.
- `LIVE_READ_PASS`: target chain/contract state was read and verified.
- `VERIFIED_REMOTE`: deployed address/code and transaction evidence were independently checked.
- `AUDIT_REVIEWED`: a named independent review was completed for a pinned commit/scope.

Current status only establishes `SOURCE_PRESENT` for the earlier prototype. Do not infer other states from source existence.

## 3. Current source inventory

The previous MVP archive contains:

- `contracts/src/ChogPositionNFT.sol`: a newly minted account NFT, not the existing Chog collection.
- `contracts/src/ChogCredit.sol`: small credit-contract experiment with one fungible collateral type and administrator-set price.
- `contracts/src/MockTokens.sol`: mock tokens for test environments.
- `contracts/script/Deploy.s.sol`: early Monad testnet deployment script.
- `contracts/test/ChogCredit.t.sol`: Foundry test source, not evidence of passing tests.
- `backend/src/server.ts`: read-only Express/viem API.
- `backend/src/abi.ts`: ABI declarations for the prior contracts.
- `index.html`: interactive demo UI, not wired to the contracts.
- older `docs/architecture.md`: prior source-slice description.

## 4. What the earlier source implements or attempts

These are static source observations, not build/test claims:

- Separate ERC-721 contract named `ChogPositionNFT` with token IDs.
- Single fungible collateral asset tracked by the credit contract.
- USDC-like token configuration, including mock-token path.
- Admin-configured collateral price, not a production oracle.
- Prototype borrow/repay/interest and a liquidation-oriented function path.
- A restriction on transfers of the newly minted NFT while debt is non-zero.
- Read-only API routes for config/pool/account state.
- Sample-data UI with simulated credit actions.

## 5. Missing or misaligned with the revised Chog Credit specification

1. **Canonical collection integration:** no verified read/ownership integration for the official existing Chog collection.
2. **Correct account key:** no registry mapping `(chainId, collectionAddress, tokenId)` to exactly one account vault.
3. **No second Position NFT:** current source does the opposite; it mints a separate account token.
4. **Original-NFT escrow:** no escrow contract holds the original Chog NFT while portfolio assets/positions or secured debt are attached.
5. **Beneficial ownership model:** no separation between escrow's ERC-721 ownership and the account's beneficial owner.
6. **Active-debt transfer model:** no debt-bearing transfer coordinator with buyer acceptance or account-market settlement.
7. **Actual positions:** no real LP/DeFi position adapter that can value and unwind a live Monad position.
8. **Robust valuation:** current admin-set price is not suitable for real collateral credit.
9. **Production pool accounting:** no full supplier-share, interest, reserve, withdrawal-queue and bad-debt reconciliation.
10. **Second market:** no verified on-chain adapter to deploy borrowed USDC into another market.
11. **Frontend integration:** UI is not wallet-connected to the contracts, and it presents a simulated account.
12. **Verification evidence:** current build/test/deployment/audit state is not proven.

## 6. Collection-address research lead

Public marketplace records identify Chog Genesis items on Monad as ERC-721s under:

`0xc96d31f8626c6d03fae5dcd3d61e3fb9f4a73763`

Evidence lead: https://opensea.io/item/monad/0xc96d31f8626c6d03fae5dcd3d61e3fb9f4a73763/532

This is not final collection approval. Verify from an official Chog source or explicit hackathon/collection-owner confirmation before using in code or deploying. If Chogathon expects a different NFT collection, update the manifest and specification before integration.

## 7. Required refactor order

### Gate A: product/collection ground truth

- Confirm exact target collection and official address.
- Verify Monad chain ID and actual ERC-721 ownership/transfer methods.
- Determine whether collectible NFT value itself will be collateral or only an account identity and escrow anchor.
- Accept or reject the escrow trade-off while portfolio assets/positions are attached, and define the package-market behavior.

### Gate B: refactor account identity

- Stop minting `ChogPositionNFT` as primary identity.
- Add configurable collection adapter and registry keyed by chain, collection and token ID.
- Add one account vault per key.
- Test ownership-derived control when wallet-held and debt-free.

### Gate C: escrow and package-transfer safety

- Add `ChogCreditEscrow` and beneficial-owner registry state.
- Require escrow deposit before the first portfolio asset/position deposit or before credit activation.
- Block release while any debt or secured pending operation remains.
- Test that ordinary external NFT transfers cannot bypass restrictions because the actual NFT is held by escrow.
- Only after this, design the debt-bearing account market/coordinator.

### Gate D: correct first financial integration

- Choose one collateral asset/position with an executable liquidation route.
- Replace admin price with a reviewed valuation method or keep all borrowing in mock-only mode.
- Reconcile borrowing, interest, pool cash, lender claims and bad debt.
- If promising a second-market use, add one verified adapter or label it demo-only.

### Gate E: end-to-end testnet product

- Compile with pinned versions, run unit/fuzz/invariant tests, deploy to Monad testnet.
- Verify actual addresses/bytecode and publish deployment manifest.
- Connect wallet frontend and read API to that manifest.
- Exercise Chog selection (mock collection on testnet), account creation, collateral, escrow, borrow, repay, release and transaction history.
- Keep mock collection/USDC labels persistent.

### Gate F: limited pilot readiness

- Independent smart-contract/security review and remediation.
- Economic simulations and liquidity model review.
- Multisig/timelock, monitor/alert and incident process.
- Legal review for lending, escrow, third-party asset integrations and any public pool.

## 8. Deployment evidence ledger

| Evidence item | Current state | Required artifact |
|---|---|---|
| Exact Chog collection confirmed | **Partly.** `LIVE_READ_PASS` 2026-10-22: `0xc96d31f8626c6d03fae5dcd3d61e3fb9f4a73763` on chain 143 reports `Chog Genesis`, supply 1,969 (matches the official mint page), ERC-721/2981. Address not yet printed on an official Chog page; contract not verified on Sourcify | Written confirmation from the Chog team + verified source/ABI; `scripts/verify_monad_reference.py mainnet` output |
| Monad third-party addresses (USDC, WMON, Multicall3, Uniswap/Pancake V3, oracles, ERC-6551) | `LIVE_READ_PASS` 2026-10-22, mainnet block 115,697,336 and testnet block 73,328,862. Reference only, not approved integrations | `config/monad-reference.json`, `docs/MONAD_REFERENCE.md`, verifier script output |
| Live-collection escrow behaviour | **Partly:** fork simulation of the full registry + escrow round trip (open, `safeTransferFrom` in, previous owner and strangers blocked, release) on the real contract for a plain and a 7702-delegated holder. Operator/marketplace flow on the live contract, admin-role behaviour and real on-chain transactions not tested | `contracts/test/fork/ChogGenesisFork.t.sol`, `docs/evidence/GATE_C.md` |
| Chogathon application terms | Judging criteria seen; eligibility, license, prize terms and dates not established | Read the application page and rules; record answers |
| Solidity compile | **Prototype only:** `LOCAL_BUILD_PASS` with Foundry 1.8.6, `network = "monad"`, solc 0.8.24, OZ 5.1.0 (commit `6bc452a`, fresh clone). v0.2 contracts do not exist yet | `docs/evidence/GATE_A.md` |
| Foundry test suite | **Prototype only:** 11/11 unit tests pass; 3 mainnet-fork tests pass (local simulation). No fuzz/invariant tests | `docs/evidence/GATE_A.md` |
| Identity/registry tests | **Done in source (Gate B):** 29 unit/fuzz tests + 1 fork test of the registry against the real collection; 5/5 manual mutants caught. Wallet-held mode only; escrow not built | `docs/evidence/GATE_B.md` (commit `69b6d6c`) |
| Escrow safety tests | **Done in source (Gate C):** 21 escrow tests, 6 stateful invariants, 11/11 manual mutants caught, live-collection escrow round trip on a mainnet fork (simulation). Credit module is a mock; no real pool yet | `docs/evidence/GATE_C.md` (commit `0156112`) |
| Static analysis | **Done (Slither 0.11.6, `src/core`):** only intentional or false-positive items; listed in `GATE_C2.md` | `docs/evidence/GATE_C2.md` |
| Package sale (debt-free) | **Done in source:** buyer-signed, atomic, epoch/nonce-bound, 7702 and ERC-1271 buyers; fork simulation with real Chog and real USDC. Debt-bearing transfer not implemented | `docs/evidence/GATE_C2.md` |
| Deployment script, local deployment | **Local chain only:** `DeployCore` + `SmokeCore` on Anvil, 7 txs, 0 failed. Testnet dry run only (about 1.6 MON); not broadcast | `docs/evidence/GATE_C2.md` |
| Automated code review | One pass (`code-review` skill, high effort): 9 findings, 6 valid and fixed. Not independent | `docs/evidence/GATE_C2.md` |
| Position valuation/recovery | Not implemented | Adapter spec, tests and recovery evidence |
| Pool/lender accounting | Prototype-level | Invariant report and accounting reconciliation |
| Testnet deployment | Not performed/verified | Chain ID, deploy tx hashes, addresses, explorer links and code verification |
| UI-to-contract E2E | Not implemented | E2E report + tx hashes + screenshots/video |
| Independent audit | Not performed | Audit report, commit hash and remediation status |

The next claim of completion must cite these artifacts, not just the presence of new files.
