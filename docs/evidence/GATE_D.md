# Gate D Evidence: credit pool, oracle and liquidation

**Date:** 22 October 2026
**Source commit tested:** `c9c5f93ff9861f9c486f57d16323e212b8094a12` (branch `claude/chog-credit-brand-27ooac`)
**Evidence states reached:** `LOCAL_BUILD_PASS`; local-chain deployment and end-to-end run with real transactions; mainnet-fork simulations against real contracts and real feeds. **Not reached:** testnet deployment, independent audit, any real-funds approval.
**Toolchain:** as in `GATE_A.md` (Foundry 1.8.6, `network = "monad"`, solc 0.8.24, OpenZeppelin 5.1.0).

> Everything below is a test-only credit system. The default deployment uses mock tokens and an owner-priced mock oracle, and the real-feed configuration has been exercised only on a fork. No parameter in this document has been risk-approved or simulated for economics.

## 1. What Gate D asked for, and what was delivered

| Gate D item (`IMPLEMENTATION_STATUS.md`) | Result |
|---|---|
| Choose one collateral with an executable liquidation route | **WMON (ERC-20) only.** Liquidation seizes collateral in kind to the liquidator, who is then responsible for selling it; the protocol does not swap. This is workable only while liquidators can sell WMON; on-chain depth is thin (`MONAD_REFERENCE.md` section 4). |
| Replace the admin price with a reviewed valuation, or keep borrowing mock-only | **Both exist.** `ChainlinkPairOracle` (Chainlink + RedStone-style feeds, freshness, deviation bound, lower price, loan-token feed included) is tested against the real feeds on a fork. `MockOracle` (owner-set) is used by the default deployment scripts and is labelled in the manifest (`mockOraclePricing: true`). "Reviewed" here means tested and statically analysed, **not** independently reviewed. |
| Reconcile borrowing, interest, pool cash, lender claims and bad debt | **Done and invariant-tested** (section 4). |
| Second-market adapter, or label as demo-only | **Not built.** Borrowed USDC goes to the borrower's wallet; nothing in the system deploys it into another market, and the UI must not imply otherwise. |
| LP-position collateral (Uniswap/Pancake position NFTs) | **Not built** (Tier 2). ERC-20 collateral only. |

Also closed from the previous round: **the credit-module binder trust**. `ChogCreditFactory` deploys the registry and the pool and binds the pool in its own constructor, so the factory is the registry's `binder`, has no other function, and the bind cannot happen again (`test_factoryBindsPoolOnce_andHasNoOtherPower`). The pool is now the trusted module, and its parameters are immutable.

## 2. What was built

- **`ChogCreditPool`** (no owner, admin, pause or upgrade; every parameter is an immutable constructor argument, so changing one means deploying a new pool).
  - *Lenders:* `supply` and `redeem` with internal (non-transferable) shares and virtual shares/assets (1e6) against the first-depositor inflation attack. No protocol fee or reserve; all interest accrues to lenders. `redeem` is limited by the cash actually in the pool.
  - *Interest:* global debt index (RAY) accruing per second at a utilization-based rate with an optimal-utilization kink (`base + slope1·U/Uopt`, then `+ slope2·(U−Uopt)/(1−Uopt)`). Debt rounds up, lender claims round down.
  - *Borrowing:* only the account's controller, only while its Chog is escrowed, proceeds sent to the borrower's **wallet** (never into the vault, so the vault only holds collateral and liquidation can reach everything that backs the loan). Limits: per-collateral LTV, per-account cap and pool borrow cap, all checked against the debt that will actually be *stored*. Fails closed if a price is unavailable.
  - *Repaying:* anyone, for any account; takes at most the debt; works without a price.
  - *Collateral withdrawal:* `withdrawAllowed` is consulted by the vault. No debt: always allowed, no price needed. Debt: the account must stay within its post-withdrawal borrowing power; an unavailable price blocks it.
  - *Liquidation:* when debt exceeds `Σ value·liquidationThreshold`. Repays at most `closeFactor` of the debt (all of it when the debt is at or below `dustDebt`); the liquidator receives collateral worth the repayment plus each token's bonus, walking the configured collaterals in order; seizure rounds down in the borrower's favour. If the last collateral is taken and debt remains, the remainder is **written off against lenders**. Needs a working price.
  - *Views:* `accountData` (debt, collateral value, borrowing power, liquidation value, health factor, exact borrowable room; reports a price problem instead of reverting), `totalAssets`, `utilizationBps`, `borrowRateBps`, `maxRedeem`.
- **`ChainlinkPairOracle`** (no owner, no setters). Values a token in loan-token units as `amount · USD(token) / USD(loanToken)`, so a loan-token depeg changes collateral values. Per token: a primary feed, an optional secondary, `maxAge`, and a deviation bound (at most 20%); with two sources the **lower** price is used and a disagreement beyond the bound reverts. Every failure reverts, which the pool reads as "price unavailable". Not checked: `answeredInRound`.
- **`ChogCreditFactory`**, vault `seizeCollateral` (callable only by the bound module), registry `withdrawAllowed`, `DeployCredit` and `SmokeCredit` scripts.

## 3. Defects found by the tests and fixed

Two real defects, both discovered by the stateful and fuzz tests rather than by inspection:

1. **One-unit overshoot of the borrowing limit.** `borrow` checked `debtBefore + amount`, but the stored debt is `ceil(scaled · index / RAY)`, which can be one base unit higher once the index has moved. An account could end one unit (1e-6 USDC) above its limit. Fixed by checking the debt that will actually be stored; regression tests added. The same rounding applies to the per-account and pool caps.
2. **`availableToBorrow` could name an amount `borrow` then rejected** (`AccountCapExceeded` by one unit), found by a fuzz test after the first fix. A one-step adjustment was not enough in general (when the index is large, rounding can overshoot by more than one unit), so the figure is now computed in closed form: the largest total scaled balance under a limit is `floor(limit·RAY/index)`, and the room follows exactly.

## 4. Verification results

```
forge test                      -> 181 passed; 0 failed; 11 skipped (fork tests, no RPC)
                                   pool 44 | oracle 17 | integration 4 | pool invariants 1 suite (8 invariants)
MONAD_MAINNET_RPC_URL=https://rpc.monad.xyz forge test --match-path "test/fork/*"
                                -> 11 passed (6 core/escrow/sale + 5 credit)
forge fmt --check               -> OK
FOUNDRY_INVARIANT_RUNS=256 FOUNDRY_INVARIANT_DEPTH=500, both invariant suites
                                -> 15 invariants passed (escrow 7, pool 8), about 130k calls each, 0 failures
```

- **Pool invariants** (lenders, borrowers, price moves, time, repayments, liquidations interleaved): scaled-debt sum equals total; share sum equals total; lender claims never exceed assets; the index never falls; no borrow or withdrawal leaves debt above borrowing power; collateral is conserved (deposits = vault balances + withdrawals + seizures, and vault balance = accounted); the share price falls only through a recorded write-off; assets = cash + debt. A scripted non-vacuity test proves the handler's borrow, repay and liquidation paths execute, and a probe confirmed random campaigns reach write-offs.
- **Real-feed fork tests** (real Chog holders for tokens 1 and 2, real Circle USDC, real WMON wrapped from native MON, real Chainlink + RedStone feeds, via `vm.mockCall` for price moves): oracle value of 1,000 WMON was 20.958363 USDC (about $0.021 per MON) and equals the manual two-source computation; a full lend, borrow, blocked withdrawal, repay, withdraw and release round trip for both holder types; liquidation after both feeds fall 40% (close factor respected, liquidator receives real WMON); **fail-closed when only one feed moves** (liquidation refused with `OracleFailure`, but the borrower can still repay and leave); a feed outage blocks borrowing but not repayment or a debt-free partial withdrawal.
- **Local chain, real transactions:** `DeployCredit` then `SmokeCredit` on Anvil (`--network monad`): the full flow (supply, open, escrow, deposit, borrow, refused full withdrawal, repay, withdraw, release, redeem) in 14 transactions, 0 failed receipts. Mock assets and mock oracle; not Monad.
- **Testnet dry run (no broadcast):** about 13.06M gas, estimated 2.62 MON at the quoted fee; factory deployment 9.46M gas (per-transaction cap is 30M). The manifest such a run writes is not evidence of a deployment and was deleted.
- **Sizes:** `ChogCreditPool` 10,780 bytes runtime; `ChogCreditFactory` initcode 38,950 bytes against EIP-3860's 49,152 (Monad's own initcode limit is 262,144); it has about 10 KB of headroom and any growth should be checked.
- **Gas (Foundry test numbers, not live receipts):** `supply` up to 149k, `redeem` 106k, `repay` 120k, `borrow` 288k, `liquidate` 365k (two collaterals), `seizeCollateral` 69k.
- **Slither 0.11.6 (whole `src`, excluding mocks/tests/scripts):** nothing above informational except two intended patterns: the signed-buyer `transferFrom` in the sale coordinator, and zero-sentinel comparisons flagged as "dangerous equality". Remaining items are calls inside loops bounded by `MAX_COLLATERALS = 4`, variables defaulting to zero, and absent zero-checks on parameters where zero means "disabled".
- **Manual mutation check, final code, consolidated over the whole system (vault, registry, escrow, sale coordinator, pool, oracle):** **62 mutants applied, 62 caught.** An earlier round found five survivors (debt rounding direction, debt-free withdrawal needing a price, redeem ignoring cash, the borrow rounding bug, open `seizeCollateral`) plus two more in the cap logic; each exposed a real test gap and was closed with a targeted test before the consolidated run. One mutant in the consolidated run did not apply because its pattern was wrong and was run separately and caught. This is a hand-run check, not a mutation-testing tool.

## 5. Test-harness mistakes made and corrected during this round

- A first mutation harness passed `--match-path` twice, and forge honours only the last one, so every pool mutant "survived" because the pool tests were not running. Caught because a 100% survival rate was implausible.
- A test withdrew the *whole* collateral balance while the oracle was down, which hid the missing "debt-free withdrawals need no price" rule; it now withdraws a partial amount.
- An invariant handler that borrowed random amounts almost never reached accounts near their limit, so liquidation and write-off paths were barely exercised; it now sizes actions from real account state, which is also what exposed defect 1.
- One integration test I wrote only demonstrated that the escrow trusts its coordinator; it was removed instead of kept under a name promising more.

## 6. Parameters used (illustrative, not risk-approved)

| Parameter | Fork-test / default value | Basis |
|---|---|---|
| WMON LTV / liquidation threshold / bonus | 40% / 65% / 8% | Conservative guess for a volatile, thinly traded asset; satisfies `threshold·(1+bonus) ≤ 100%` (70.2%). **No simulation was run.** |
| Close factor / dust | 50% / 10 USDC | Common defaults |
| Rate model | 2% base, +4% to 80% utilization, +60% beyond | Placeholder |
| Caps (fork config) | supply 1,000,000 USDC; borrow 100,000; per account 10,000 | Placeholder |
| Feed `maxAge` | MON: 2 hours; USDC: 25 hours | Chosen from observed ages (MON feeds 27–33 s old, USDC/USD about 44 minutes old). **Real heartbeats and deviation thresholds were not verified.** Deviation bounds 3% (MON) and 2% (USDC). |

## 7. Known limits and trust assumptions

1. **Oracle availability decides liquidations.** If the feeds are stale, reverting, or disagree by more than the bound, `liquidate` reverts (`OracleFailure`) while borrowers can still repay and, if debt-free, exit. A fast crash seen by only one source therefore delays liquidation until both agree again, and bad debt can accumulate in that window (R-11). Choosing the deviation bound trades manipulation resistance against that risk and has not been tuned.
2. **Liquidation liquidity.** Liquidators receive WMON and must sell it; the deepest USDC/WMON pool held about $1.2M at the time of reading, and the CHOG pools hold almost nothing. Caps and LTV must reflect that; none has been derived from a market-impact model.
3. **No per-asset collateral cap across accounts** (R-27); only pool, borrow and per-account caps. A single large depositor could dominate the pool's exposure to WMON.
4. **Loan token risk.** USDC is a Circle-administered token that can blacklist addresses or pause; a blacklisted pool or vault would freeze funds. The pool also assumes no fee-on-transfer or rebasing behaviour in USDC (checked by balance delta on every pull).
5. **Collateral token behaviour.** The vault's balance-delta check rejects fee-on-transfer deposits, but a *rebasing* collateral could still desynchronise accounted and real balances; only plain tokens should ever be allowlisted.
6. **Immutable parameters.** A wrong parameter, oracle or collateral list cannot be fixed in place; a new pool must be deployed and users migrate. There is no pause: the only emergency behaviours are the fail-closed ones above.
7. **Lenders carry the bad debt** (written off against share value) and can only redeem up to the cash in the pool; there is no withdrawal queue and no reserve.
8. **No debt-bearing account sale, no LP-position collateral, no second-market adapter, no keeper or automation for liquidations.**
9. **Not analysed:** flash-loan or same-block price manipulation scenarios against the feeds, MEV around liquidations, interest-rate and utilization stress simulations, long-run rounding drift beyond what the invariants cover.
10. **No independent audit; no testnet deployment.** The oracle configuration for the real feeds exists only in a fork test; the default deployment scripts use a mock oracle.

## 8. Next

Per `IMPLEMENTATION_STATUS.md`, Gate E is an end-to-end testnet product: deploy `DeployCredit` to Monad testnet (needs a funded testnet key, about 2.6 MON by the dry run), record the deployment evidence, and connect a wallet frontend and read API to the manifest. Before any real funds: confirm the Chog contract address and source with the Chog team, verify the feeds' heartbeats and thresholds with their operators, derive caps and LTV from a liquidity model, and obtain an independent review.
