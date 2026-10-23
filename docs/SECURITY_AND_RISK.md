# Chog Credit: Security and Risk Register

**Version:** 0.2  
**Status:** revised target controls; not an audit report  
**Date:** 22 October 2026

## 1. Security posture

Chog Credit combines an external NFT collection, a smart-account vault, an escrow lock, a credit pool and collateral recovery logic. Its core risks arise from ownership/authorization boundaries, oracle valuation, pool accounting and safe transfer behavior. The existing prototype does not implement the revised Chog collection identity and must not be used with real funds.

This is a proposed threat model, not a completed audit. A passing unit-test suite is necessary but insufficient for production lending.

## 2. Risk scale

- **Critical:** direct asset loss, hidden debt bypass, unrecoverable pool insolvency or broad unauthorized control.
- **High:** significant loss, broken account control, unavailable repayment/exit, incorrect collateral valuation or misleading credit capacity.
- **Medium:** partial functionality failure, data inconsistency or bounded economic impact.
- **Low:** mostly cosmetic or recoverable issue with limited financial effect.

Likelihood labels are provisional until threat modeling, testing and audit.

## 3. Risk register

| ID | Risk | Severity | Required mitigation / gate |
|---|---|---|---|
| R-01 | Wrong or counterfeit Chog collection is accepted | Critical | Verify exact official collection address, chain ID, bytecode and ERC-721 behavior; allowlist by full address; never trust name/art/metadata; G0 |
| R-02 | New Position NFT remains product identity, contradicting the original Chog NFT design | High | Refactor identity to `(chainId, collection, tokenId)`; registry uniqueness tests; block release until docs/code/UI align |
| R-03 | Duplicate vaults or token IDs collide across collections/chains | Critical | Canonical account key includes chain, full collection address and token ID; idempotent factory; fuzz uniqueness |
| R-04 | External ERC-721 transfer bypasses debt consent because original collection has no hook | Critical | Escrow original Chog NFT before first portfolio deposit/credit activation; prohibit release while secured obligations remain; all debt-bearing ownership changes via coordinator; G1/G3 |
| R-05 | Escrow lets admin/caller redirect NFT or beneficial owner | Critical | Narrow functions, immutable/controlled collection config, multisig/timelock; no unrestricted recovery/owner setter; adversarial tests and audit |
| R-06 | NFT accidentally released while assets, positions, debt, interest, fee, liquidation or adapter operation remains | Critical | On-chain debt/pending-operation checks at release; atomic state transition; state-machine invariant tests |
| R-07 | Escrow safe-transfer callback accepts unsolicited/fake NFT | High | Expected-deposit nonce/state, collection allowlist, sender/owner check and callback tests |
| R-08 | User misunderstands escrow and thinks a portfolio-bearing NFT remains in wallet/listable externally | High | Preflight disclosure, wallet-vs-beneficial-owner state, visible escrow status and release requirements; user testing |
| R-09 | Debt-bearing sale is treated as an ordinary marketplace transfer | Critical | Coordinator-only transfer when debt active; signed buyer consent bound to account state/nonce/debt/health/deadline; no direct release; G4+ |
| R-10 | Chog floor-price manipulation produces excess credit | Critical | NFT collectible value is zero until approved sale/auction recovery, conservative pricing, depth/liquidity analysis, caps and stress tests |
| R-11 | Portfolio position price is stale/manipulated or decimals are wrong | Critical | Verified oracle/adapter, freshness checks, sanity boundaries, full-precision arithmetic, downward collateral/upward debt rounding, fuzz tests |
| R-12 | A position is marked as collateral but cannot be unwound in liquidation | Critical | Position-specific reviewed liquidation adapter; exact token amount valuation, slippage bounds and fork/integration testing; unsupported value zero |
| R-13 | Borrow exceeds collateral capacity or pool cash | Critical | On-chain cap, liquidity and health checks; invariant/fuzz tests; client calculations are informational only |
| R-14 | Lender shares/cash/debt/interest/loss accounting diverges | Critical | Full reconciliation model, accounting invariants, stress tests and audit before public liquidity |
| R-15 | Illiquid lenders expect immediate withdrawal of lent funds | High | Explicit liquidity/queue model, withdrawable amount display, pool caps and stress simulation |
| R-16 | Interest and rounding understate debt | Critical | Fixed-point debt index, rounding policy, long-duration/multi-account tests, aggregate reconciliation |
| R-17 | Liquidation over-seizes collateral or leaves hidden bad debt | Critical | Close factor, repayment cap, tested seizure formula, bad-debt accounting, position-specific unwind and fuzz tests |
| R-18 | Admin price setting is mistaken for a safe oracle | Critical | Admin-set collateral prices only for local/testnet mocks; production borrowing disabled without reviewed valuation; UI labels and config guard |
| R-19 | Arbitrary calls/delegatecall drain a vault | Critical | Adapter/target/selector allowlists; no unrestricted low-level calls; delegate limits; code review and adversarial tests |
| R-20 | External protocol upgrades alter custody or unwind assumptions | Critical | Pin addresses/versions, monitor upgrade events, disable new risk on change, revalidate adapter and unwind route |
| R-21 | Admin compromise changes collateral/risk or redirects accounts | Critical | Multisig, timelock, role separation, event monitoring and recovery playbook; no direct NFT seizure power |
| R-22 | Emergency pause blocks repayment or safe recovery | High | Explicit pause matrix; keep repay route available where safe; test liquidation/oracle outage combinations |
| R-23 | Backend/indexer stale data is presented as chain truth | High | Chain/block provenance, fresh state reads for preflight, reorg rollback, lag alerts and reconciliation |
| R-24 | Mock USDC or simulated market shown as live | High | Manifest-driven environment, obvious mode banner, transaction-blocking mock guards and end-to-end UI tests |
| R-25 | Account history is misrepresented as the current owner's personal performance | High | Store actor/beneficial owner at event time; separate account history from individual/operator record; disclosure |
| R-26 | Borrowed USDC leaves vault while dashboard still counts it as collateral | High | Default delivery to vault; encode receiver in transaction; reflect transfers as assets leaving account and retain debt |
| R-27 | Recursive leverage/correlated positions break additive LTV assumptions | Critical | Initial adapter allowlist/caps; exposure concentration limits; disable unbounded loops; portfolio stress tests |
| R-28 | Debt-transfer signature replay or stale state accepted | High | Typed signatures include chain, coordinator, account key, nonce/state hash, exact debt cap, health condition and expiry; replay tests |
| R-29 | Collection configuration migration strands accounts | Critical | Versioned configuration, timelock, per-account migration plan, no silent collection replacement, migration tests |
| R-30 | Legal/consumer-lending/market structure requirements are missed | High | Jurisdiction-specific legal review before public lending, custody-like escrow, external capital or public marketplace |
| R-31 | The optional escrow rescuer (recovers tokens sent by plain `transferFrom`) is a privileged role; a compromised or malicious rescuer could take stranded Chogs, and it cannot be rotated | High | Disable it (address(0)) or make it a multisig/timelock; 3-day public delay and events; it can never touch recorded tokens (tested and in the invariant suite); UI must only use `safeTransferFrom` |
| R-32 | The one-time credit-module bind is irreversible; a wrong or hostile module could lock every funded account | Critical | Bind in the deployment transaction (Gate D); bind is probed; module reads cannot revert or be return-bombed and fail closed; binder is a multisig or deployment contract |
| R-33 | A signed buyer acceptance is replayed or revived after the account changed (deposit, sweep, ownership round trip) | High | Acceptance binds vault state nonce and escrow ownership epoch; digest single-use; chain-bound EIP-712 domain; buyer `cancel` (all covered by tests) |
| R-34 | Live Chog Genesis collection admin: single 7702-delegated key holds `ADMIN_ROLE`; source unverified | Medium | Bytecode analysis found no burn, pause, filter or forced-transfer function and no executable delegatecall; still obtain verified source and written confirmation; metadata and royalty changes remain possible |
| R-35 | Oracle outage or source disagreement blocks liquidation (the pool fails closed), letting bad debt build up in a fast market | High | Tested behaviour (`GATE_D.md` section 7.1); tune deviation bound and freshness windows from verified feed heartbeats; keep LTV conservative; consider an independent circuit-breaker/auction design before real funds |
| R-36 | Feed parameters (`maxAge`, deviation bounds) are guesses; real heartbeats and thresholds of the Monad feeds are unverified | High | Confirm with the oracle operators and observe over time before any deployment; the default deployments use a mock oracle |
| R-37 | Liquidators receive WMON and must sell into thin on-chain liquidity (about $1.2M best pool); LTV, bonus and caps are not derived from a market-impact model | High | Build a liquidity/impact model; start with small caps; no `$CHOG` collateral |
| R-38 | No cross-asset-wide cap per collateral; one depositor can dominate WMON exposure | Medium | PARTLY MITIGATED: per-account `maxCounted` per collateral bounds any single liquidation (tested, mutation-checked). Pool-wide tracking is not possible because deposits bypass the pool; `borrowCap` and `accountDebtCap` bound total exposure. CHOG token must not be enabled as collateral (no liquidity) |
| R-39 | Pool parameters, oracle and collateral list are immutable and there is no pause; a wrong parameter cannot be fixed in place | Medium | Deploy via the factory with reviewed parameters; plan migration; timelocked governance only if a multisig exists |
| R-40 | Loan-token (USDC) administrator powers (blacklist, pause) could freeze the pool or vaults; collateral tokens that rebase would desynchronise vault accounting | Medium | Disclose; allowlist plain tokens only; monitor |
| R-41 | Lender bad-debt socialisation with no reserve or withdrawal queue; lenders can only redeem up to pool cash | Medium | Disclosed in lender documentation; caps; reserve/queue design before public liquidity |

## 4. Mandatory security invariants

1. **Correct identity:** account authority is derived from the configured official collection and exact token ID, not metadata.
2. **One account:** one unique account record/vault per chain, collection and token ID unless a versioned migration explicitly defines otherwise.
3. **Escrow enforcement:** active secured credit implies the original Chog NFT is escrowed, unless an independently verified collection-level hook enforces equivalent rules.
4. **No silent ownership change:** beneficial owner changes only through verified wallet-held ownership, controlled release or the signed transfer coordinator.
5. **No early release:** NFT cannot leave escrow while any asset/position, debt, interest, fee, pending liquidation, secured adapter call or blocked settlement remains.
6. **Custody truth:** recorded collateral never exceeds what the contracts can actually recover.
7. **Capacity:** borrowing is bounded by eligible conservative collateral, caps, pool cash and on-chain health checks.
8. **Valuation safety:** stale/invalid prices never support a risk-increasing action.
9. **Debt safety:** debt can change only through defined borrow, accrual, repayment, liquidation, approved write-off or valid atomic transfer/settlement logic.
10. **Liquidation correctness:** healthy accounts cannot be liquidated under the same valid state; seized collateral is bounded by repayment and allowed incentive.
11. **Pool reconciliation:** cash, debt, lender claims, reserves, fees and bad debt reconcile after every state transition.
12. **Least privilege:** no delegate, adapter, admin or backend has broader permission than documented.
13. **No hidden mocks:** mock tokens, sample values and simulated transactions cannot appear as live financial state.
14. **Transfer disclosure:** active-debt transfer previews exact portfolio, debt, interest, health, permissions, state nonce and settlement terms.

## 5. Admin and incident controls

Production admin/configuration roles must be separated and held by a multisig. Risk-increasing changes are timelocked and evented. A narrow guardian may pause new borrowing and selected adapters but must not be able to seize NFTs or redirect user assets. Pause policy must state behavior for new borrow, repayment, liquidation, withdrawal, escrow release, NFT transfer and adapter execution under each incident class.

Incident procedure:

1. Detect and classify the issue.
2. Pause the narrowest risk-increasing surface that safely contains the issue.
3. Preserve safe repayment/recovery routes where doing so does not worsen the exploit.
4. Check affected accounts and chain state independently.
5. Publish the known impact and uncertainties.
6. Use only approved governance paths for repairs/config changes.
7. Regression-test and re-verify deployed bytecode/manifest before reopening.
8. Document remediation and any required user action.

## 6. Audit-readiness package

Before an independent review, provide the pinned commit and compiler/dependency settings, all contracts/adapters, architecture and privilege map, escrow state machine, debt/accounting equations, collateral configuration, liquidation assumptions, test outputs, invariant/fuzz corpus, deployment manifest, admin multisig/timelock, pause matrix, monitoring plan, runbook, known limitations and a list of unsupported assets/flows.

All critical/high findings must be fixed and retested. An audit applies to a specific commit and scope, does not prove the protocol safe, and does not cover unreviewed changes made later.

## 7. Mainnet go/no-go checklist

- [ ] Exact official Chog NFT collection confirmed and approved.
- [ ] Collection bytecode, ERC-721 methods and transfer/escrow behavior verified on Monad.
- [ ] Account identity uses collection + token ID; no new Position NFT is required.
- [ ] Escrow custody and beneficial ownership state machine passes adversarial tests.
- [ ] A non-empty portfolio and active debt both block NFT release and unauthorized transfer; package transfers use the coordinator.
- [ ] Any NFT market-value component has executable recovery and conservative valuation; otherwise value is configured as zero.
- [ ] First position collateral and liquidation path are reviewed and tested.
- [ ] Official USDC address re-verified at deployment; pool liquidity exists and is accounted for.
- [ ] Supplier claims, debt, interest, fees, reserves and bad-debt accounting reconcile.
- [ ] Compiler, unit, fuzz, invariant, integration and fork tests pass.
- [ ] Testnet transaction flow and UI/manifest addresses are verified.
- [ ] No unresolved critical/high audit findings.
- [ ] Multisig, timelock, pause matrix, monitoring and incident process tested.
- [ ] Lending/escrow/marketplace legal requirements reviewed.
- [ ] UI clearly distinguishes actual Chog NFT, test collection, mock token, simulated market and live contract state.

Any unchecked item is a no-go for public real-funds lending.
