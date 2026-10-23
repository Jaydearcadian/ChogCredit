# Gate E2: Uniswap V3 positions as collateral, plus a test-method defect found on the way

Scope: `docs/LP_COLLATERAL_SPEC.md` implemented in source. Not deployed anywhere except a local Anvil chain; not audited.

## What was built

- `LpMath` (own implementation, MIT; constants generated with 120-digit decimal arithmetic; no Uniswap GPL code copied): tick to square-root price, liquidity to amounts (rounds down), oracle values to square-root price, price-gap measure.
- `AccountVault`: custody of up to 2 position NFTs (`depositPosition`, `withdrawPosition`, `collectFees`, module-only `unwindPosition`). Positions arrive only by `transferFrom` from the controller; a safe transfer to the vault is refused. `isEmpty` counts positions, so the Chog stays in escrow while one is held. Deposits and withdrawals bump `stateNonce`.
- `ChogAccountRegistry`: three fail-closed passthroughs to the credit module (`positionManager`, `positionAccepted`, `positionWithdrawAllowed`).
- `ChogCreditPool`: optional `LpConfig` (position manager, up to 2 whitelisted pools). Each position is valued at the ORACLE price, never the pool's price; a pool more than `maxDeviationBps` from the oracle, an unreadable or burned position, a missing price, or a malformed reply makes the whole account unpriceable (borrow, indebted withdrawal and liquidation fail closed; repay and debt-free exit never need a price). Per-account cap, per-pool LTV, threshold and bonus. Uncollected fees are not counted.
- Liquidation: positions are unwound first (all liquidity removed, proceeds become accounted vault balances), the loan-token share of the proceeds repays the debt at no bonus, and the call ends there if that restores health (the liquidator pays nothing). Otherwise the normal token seizure continues on the unwound state.
- `ChogCreditFactory`: adds the loan token to the vault allowlist when LP is configured.
- Mocks (`MockUniswapV3`: factory, pool with settable price, position manager with real liquidity maths) and deploy/smoke script support (`ENABLE_LP=true`).

## Evidence (run locally; GitHub CI has not run)

| Check | Result |
|---|---|
| Liquidity maths against the REAL position manager on a mainnet fork | A real full-range position's real `decreaseLiquidity` paid 23286775353856109165996 token0 and 499999999 token1; `LpMath` gave exactly the same figures |
| Tick maths against live pools | The live price of the USDC/WMON and CHOG/WMON pools lies between the prices of its tick and the next, using `LpMath` |
| Independent vectors | 17 tick vectors from 120-digit decimals, plus properties (monotonic, symmetric, edges, rounding, swapped bounds) |
| Real end to end (fork) | Real Chog holder, real position minted in the real pool, real USDC loan, a REAL swap that moved the pool to about 35% of its price with feeds following, liquidation that unwound the position through the real manager and repaid debt |
| Unit/integration tests | `LpCollateral.t.sol` 33 tests plus 1 for the disabled configuration, `LpMath.t.sol` 13 |
| Invariants (256 runs x depth 300) | no borrow or withdrawal leaves an account over its power; a Chog holding a position stays in escrow; every position is where its vault says; at most 2 positions; accounted <= balance. Non-vacuity test reaches deposits, borrows and unwinding liquidations. Breaking the position-withdrawal check makes the invariant fail |
| Mutation checks | 37 LP mutants: 5 survived the first run and all are now caught after adding 4 tests (malformed reply handling, withdraw nonce bump, deposit ownership check, registry fail-closed passthroughs); the reply-size check is otherwise redundant with the tick-validity check and is kept as defence in depth |
| Local chain, real transactions | `DeployCredit` (ENABLE_LP) 15 txs and `SmokeCredit` 28 txs, 0 failed; largest deploy tx 11.47M gas |
| Full suite, CI settings (invariants 128 x 200, fork included) | 279 passed, 0 failed |
| Sizes | Pool 18.1 KB runtime, vault 9.6 KB, registry 22.4 KB (all under 24.5 KB). Factory initcode is now 61 KB: fine on Monad (256 KB initcode limit per `MONAD_REFERENCE.md`) but above Ethereum's 49,152 limit, so local Anvil needs `--code-size-limit 131072` and `forge script` needs `--disable-code-size-limit` |
| Testnet dry run (no broadcast) | 21.5M gas, about 4.4 MON at the quoted max fee. This replaces the earlier 2.6 MON figure, which was for the smaller system |

## Test-method defect found (affects earlier gates)

In Foundry 1.8.6, `vm.expectRevert(...)` followed directly by `new Contract(...)` ends the test at the first revert and reports a pass. Every constructor-validation test that chained several `expectRevert` + `new` cases only ever checked its FIRST case. This hid untested checks in the Gate C and D registry, oracle and pool constructors, and in this gate's first constructor test. Fixed by routing each attempt through an external helper (`this.mkPool(...)`, `mkRegistry`, `mkOracle`), so the revert is a real call and the test continues. All cases then passed with their original expectations. A mechanical mutation sweep of every `if (...) revert` line in the three constructors found 7 unchecked ones; tests were added and a rerun left 0 survivors. A scan of all tests for the same pattern found no other occurrence.

A second, smaller lesson from the same work: a `vm.prank` is consumed by the first external call after it, including a helper that reads an address. The first LP invariant handler had this flaw, so its borrow and withdraw paths passed vacuously until the non-vacuity test failed.

## Slither (new findings reviewed)

- `reentrancy-balance` (High) and `reentrancy-no-eth` (Medium) in `ChogCreditPool.liquidate/_unwindPositions`: balance read before a vault call, state writes after calls. All pool entry points are `nonReentrant`; the callees are the immutable vault and position manager and allowlisted tokens. Judged benign, not independently reviewed.
- `uninitialized-local`: intentional zero defaults. `unused-return`, `incorrect-equality`: same classes as before.
- `arbitrary-send-erc20` on the new buyer-payment transfers: `from` is the signature-verified buyer, same as the existing sale.

## Limits

- Parameters (LTV 28-35%, threshold, 2% price-gap bound, 50,000 USDC cap) are proposals; tune them with data from a testnet run. LTV 2,800 bps in the deploy script is 70% of its 4,000 bps token LTV.
- Only Uniswap V3 USDC/WMON 0.30% is intended. Pancake V3 and Uniswap V4 are unsupported. The Pancake pool's `slot0` has a different shape, so it must not be whitelisted without changes.
- The real Uniswap deployment on Monad is third-party code we rely on.
- Unwinding at a pool price up to 2% off the oracle can cost the position a small amount; larger gaps are refused.
- Not audited; legal review pending.
