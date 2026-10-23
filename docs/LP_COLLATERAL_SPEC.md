# Uniswap V3 LP Positions as Collateral: Specification (draft v0.1)

Status: **implemented in source (Gate E2, `docs/evidence/GATE_E2.md`); not deployed, not audited.** Differences from this draft: liquidation unwinds ALL positions first and applies the loan-token proceeds to the debt with no bonus before any token seizure; positions arrive by `transferFrom` and safe transfers are refused; the factory adds the loan token to the vault allowlist when LP is configured; the deploy script uses LTV 2,800 bps because its WMON LTV is 4,000 bps. Scope is one position type and one pool. Decisions in section 10 are settled.

## 1. What and why

Today a vault holds plain ERC-20 tokens (for example WMON), and only those count as collateral. Many holders keep value in liquidity positions instead. This spec lets a Chog vault hold a **Uniswap V3 position NFT** and count its underlying value toward borrowing power, with the same fail-closed rules as token collateral.

## 2. Verified facts (Monad mainnet, read 2026-10-23)

| Fact | Value |
|---|---|
| Position manager | `0x7197e214c0b767cfb76fb734ab638e2c192f4e53`, name "Uniswap V3 Positions NFT-V1" |
| Positions minted so far | 19,239 (`totalSupply`); some ids are burned (`positions(3)` reverts "Invalid token ID") |
| Factory (matches our reference) | `0x204FAca1764B154221e35c0d20aBb3c525710498` |
| Example positions | ids 1 and 2: USDC/WMON, fee 0.30%, full range (ticks -887220 to 887220) |
| Reference pool | USDC/WMON 0.30%, `0x659bd0bc4167ba25c62e05656f78043e7ed4a9da`. QuoterV2 measured about 2% impact on a $50k sale (see `evidence/LIQUIDITY_MODEL.md`) |

Not verified: whether Pancake V3 positions behave identically here, and any Uniswap V4 behaviour. Both are out of scope.

## 3. Scope

In v1:
- Positions from exactly the configured position manager, in exactly the whitelisted pools. First pool: USDC/WMON 0.30%.
- Both tokens of the pool must be priced by our oracle.
- At most **2 positions per vault**, to bound gas on Monad (gas is charged on the limit).
- Positions are **deposited as existing NFTs**. The vault does not mint or add liquidity.

Out of scope for v1: Uniswap V4, Pancake V3, positions in pools with fee-on-transfer or rebasing tokens, and any pool not on the whitelist.

## 4. Custody

The vault becomes the owner of the position NFT (ERC-721 `ownerOf` is the vault). That gives a clean rule: **only vault code can touch the position.**

- The vault accepts a position only through a dedicated function, and `onERC721Received` rejects anything else. The sender must be the configured position manager, so a counterfeit collection cannot be registered.
- The vault tracks its positions in a small array. `isEmpty()` must treat any held position as an asset, so the Chog stays in escrow while positions are present. The registry's `HasAssets` check then covers it with no further change.
- Depositing or removing a position bumps the vault `stateNonce`, so debt-free and debt-bearing sale acceptances (and the signed disclosure) are voided by it.
- The position goes with the vault in a package sale. No special handling is needed.

## 5. Valuation (the dangerous part)

**Never read the pool's `slot0` price to value collateral.** A flash-loan can move it within one transaction. Instead:

1. Take the oracle USD price of each token and form the price ratio. With token decimals `d0` and `d1`:
   `sqrtPriceX96 = sqrt( p0 / p1 * 10^(d1 - d0) ) * 2^96`.
2. Using the position's `tickLower`, `tickUpper` and `liquidity` from the position manager, compute the token amounts at that oracle price with the standard Uniswap formulas (the same maths as `LiquidityAmounts.getAmountsForLiquidity`). This is a port into our own library on top of OpenZeppelin `Math.mulDiv`, with fuzz tests against known values.
   - Price below the range: all token0. Above the range: all token1. Inside: both.
3. Value each amount through the oracle and add them up.
4. Apply a **haircut** (section 6) to get the counted value.
5. **Uncollected fees are ignored** in the value. They stay retrievable but never back a loan. (They are computed from fee-growth state that is expensive and easy to get wrong, and ignoring them is the conservative direction.)

Impermanent loss needs no special term: the amounts are computed at the current oracle price, so the value already reflects it.

**Pool-price sanity check.** Liquidation unwinds into the real pool. If the pool's `slot0` price differs from the oracle ratio by more than a configured bound (starting proposal: 2%), the position is treated as **unpriceable**. Borrowing against it, withdrawing it while indebted, and liquidating it all fail closed, and repay always works. This is the same stance as an oracle outage.

Any failure to read the position (burned id, reverting call, tokens not matching the whitelisted pool) also means unpriceable.

## 6. Risk parameters

Each whitelisted pool gets its own entry, like a token collateral:

| Parameter | Proposal for USDC/WMON 0.30% | Reason |
|---|---|---|
| LTV | 70% of the lower of the two tokens' LTVs | LP value moves with price and range, and unwinding adds slippage |
| Liquidation threshold and bonus | the stricter of the two tokens | keeps the existing solvency rule: threshold x (1 + bonus) <= 100% |
| Max counted value per account | cap in loan-token units, starting at the WMON cap's USD equivalent | reuses the `maxCounted` idea and bounds one liquidation |
| Out-of-range handling | valued as the single token it has turned into | no extra bonus for being out of range |
| Max pool price deviation | 2% | section 5 |

These are proposals only. They need review against the liquidity model, which is a one-time measurement.

## 7. Withdrawal and borrowing rules

- **Borrow:** the position adds to borrowing power only if it is priceable.
- **Indebted withdrawal of a position:** allowed only if, with the position's counted value removed, the account stays within borrowing power. This extends the existing `withdrawAllowed` check, which is token-based today, to positions.
- **Fees:** the owner may collect uncollected fees at any time. They are not counted, so collecting them cannot weaken the account.
- **Removing liquidity while indebted** is not a vault function in v1. The position can only leave whole, through the rule above.

## 8. Liquidation

The credit pool must be able to turn a position into tokens. Two steps in one transaction:

1. The pool calls a **module-only** vault function that does `decreaseLiquidity` (all of it), then `collect` to the vault itself. The resulting tokens are recorded in the vault's accounted balances. The vault checks balance deltas, as it does for deposits, and refuses any token outside the whitelist.
2. The existing seizure path then takes tokens for the repayment plus bonus, using the existing close factor.

Notes:
- The unwind happens in the real pool, so its slippage and fee are real. The haircut and the pool-price check exist for this reason.
- A partially liquidated account may still hold other tokens or the emptied position NFT. An emptied position has no value and can be withdrawn.
- Only the module may call the unwind function. Mutation tests must show that anyone else is refused.
- Collecting sends tokens to the vault, not to the liquidator, so the liquidator cannot choose a destination.

## 9. Attack and failure analysis

| # | Scenario | Defence |
|---|---|---|
| 1 | Flash-loan moves the pool price to inflate value | Valuation uses oracle price, never `slot0`; deviation check fails closed |
| 2 | Counterfeit position collection | Only the configured manager is accepted; `onERC721Received` rejects all else |
| 3 | Position in a non-whitelisted or malicious pool | Pool is derived from the factory by token pair and fee, and compared with the whitelist |
| 4 | Burned or reverting position | Treated as unpriceable; fail closed |
| 5 | Out-of-range position treated as two-sided | Maths clamps to a single token |
| 6 | Owner removes liquidity while indebted | Not a vault function; whole-position withdrawal is health-checked |
| 7 | Fees counted, then collected | Fees are not counted |
| 8 | Unwind pulls an unexpected token | Vault refuses tokens outside the whitelist and checks balance deltas |
| 9 | Many positions make liquidation too costly | At most 2 positions per vault |
| 10 | Package sale does not disclose the position | The position is an asset; sale disclosure and the state nonce cover it |
| 11 | Oracle outage | Same as tokens: no borrow, no indebted withdrawal, no liquidation; repay always works |
| 12 | Reentrancy via the position manager | Existing `nonReentrant` guards, effects before interactions |

Residual risks: the Uniswap V3 deployment on Monad is third-party code we rely on; unwinding a very large position can still move the pool; LP value is correlated with the price of its own tokens, so a crash hits both collateral and borrowing power.

## 10. Decisions (accepted: all five recommendations below were approved by the project owner)

1. **Scope:** Uniswap V3 USDC/WMON 0.30% only? Recommendation: yes.
2. **Positions per vault:** 2. Recommendation: yes.
3. **Ignore uncollected fees in value?** Recommendation: yes.
4. **Haircut:** LTV 70% of the lower token LTV; deviation bound 2%? Recommendation: start there, then tune with data from a testnet run.
5. **Order against the debt-bearing sale:** this feature touches the vault, the registry, the pool and `withdrawAllowed`. Recommendation: build the debt-bearing sale first (smaller change), then this.

## 11. Test and verification plan

- Unit tests for the valuation library against hand-computed vectors: in range, below, above, full range, zero liquidity.
- Fuzz tests: value is monotonic in liquidity and never above the exact amounts valued at the same price.
- Fork tests: deposit a real position (ids 1 and 2, or a freshly minted one) into a vault on the mainnet fork, value it, borrow against it, force the oracle off and check fail-closed, and liquidate it for real through the pool.
- Invariants: no sequence of actions leaves an account above its borrowing power; the Chog never leaves escrow while a position is held.
- Mutation checks: remove the oracle-price use (use `slot0`), the deviation check, the caller check on the unwind, the health check on withdrawal, and the manager check on receive. Each must be caught.
- Re-run Slither and review all new findings.

## 12. Build order

1. Valuation library with tests (pure maths, no state).
2. Vault custody: receive, track, withdraw, `isEmpty`, nonce.
3. Pool valuation and `withdrawAllowed` extension.
4. Module-only unwind and liquidation path.
5. Fork tests, invariants, mutation checks, evidence document, risk-register updates.
