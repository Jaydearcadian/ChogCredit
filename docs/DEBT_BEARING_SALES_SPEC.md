# Debt-Bearing Package Sales: Specification (draft v0.1)

Status: **design only, nothing implemented.** Builds on the debt-free sale in `AccountTransferCoordinator`. Open decisions are in section 9. Risk reference: R-09 (Critical), R-30 (legal).

## 1. What is being sold

A "package" is one Chog account: the escrowed Chog NFT, the vault and everything in it, **and the debt**. The buyer receives all of it.

What the buyer is really buying is **equity**:

```
equity = counted collateral value - debt
```

A seller with 10,000 USDC of collateral and 4,000 USDC of debt is selling about 6,000 USDC of equity. The price should be discussed in those terms. The protocol does not force the price to match equity, because the buyer's signature is the consent. The protocol enforces that the buyer **saw and bounded** the debt, the collateral and the health.

## 2. Why this is mostly a consent problem

Verified in the current code:

- Debt is stored per account key in the pool (`debtScaled[key]`). It is not stored per person.
- Control follows `escrow.beneficialOwnerOf(key)`. So `transferBeneficialOwnership` already moves control, and with it the right to repay, borrow and withdraw, to the buyer. **The debt moves with no pool change.**
- The coordinator today refuses any sale where `liabilityBlocker != None`, so the debt-free path stays exactly as it is.
- The vault `stateNonce` bumps on deposit, withdrawal and seizure. A liquidation therefore voids a signed acceptance. It does **not** bump on a borrow, and interest accrues with no nonce change. Both must be bounded by signed ceilings.

## 3. Scope

In v1:
- Sale of a debt-bearing, funded account through the coordinator.
- Optional atomic **payoff**: part of the buyer's payment repays the debt before the transfer, so the buyer receives a smaller loan.

Not in v1: partial debt transfer (leaving some debt with the seller), a different lender on the buyer's side, any marketplace other than the coordinator, and unsigned or off-chain price discovery.

## 4. New signed message

A separate type, so the existing debt-free path and its typehash are untouched.

```
DebtAcceptance {
  bytes32 key;            // account
  address seller;
  address buyer;
  address paymentToken;
  uint256 price;          // paid buyer -> seller, in paymentToken
  uint256 stateNonce;     // vault nonce at signing (existing)
  uint256 epoch;          // escrow ownership epoch at signing (existing)
  uint256 deadline;
  uint256 salt;
  address pool;           // must equal registry.creditModule()
  uint256 maxDebt;        // debt after any payoff must be <= this (loan-token units)
  uint256 minCollateralValue; // counted collateral value must be >= this (loan-token units)
  uint256 minHealthBps;   // liquidationValue/debt after payoff must be >= this
  uint256 debtRepay;      // repaid from the buyer's payment before transfer (0 = assume all debt)
}
```

EIP-712 domain is unchanged (chain id, coordinator address). Signature handling is unchanged: the buyer's key first, then ERC-1271.

## 5. Execution: `executeDebtSale(acceptance, buyerSignature)`

Only the seller may call it. In order:

1. All existing checks: seller is caller, parties are valid and not protocol contracts, seller is beneficial owner, not expired, digest unused, signature valid, `stateNonce` and `epoch` unchanged.
2. `liabilityBlocker(key)` must be exactly `HasDebt`. `None` means use the debt-free path. `PendingOperation`, `ModuleUnavailable` and `UnknownAccount` revert.
3. `pool == registry.creditModule()`. Otherwise a fake pool could report friendly numbers.
4. Read the pool's `accountData(key)`. If the oracle reports failure, **revert**. A sale never proceeds on a missing price (same fail-closed rule as borrowing).
5. If the account is already liquidatable (health below 100%), revert. A sale must not be a way to hand someone a position that can be liquidated in the next block.
6. Mark the digest used (effects first).
7. If `debtRepay > 0`: require `paymentToken == pool.loanToken()`, pull `debtRepay` from the buyer, repay through the pool for the key, and check the key's debt dropped by exactly what was paid (balance-delta check, as the pool already does).
8. Re-read the account after payoff and require: `debt <= maxDebt`, `counted collateral value >= minCollateralValue`, `health >= minHealthBps`.
9. Transfer beneficial ownership (this bumps the epoch).
10. Pay the seller `price - debtRepay`, with the existing balance-delta check on the seller. `debtRepay` must be `<= price`.

Everything is atomic. Any failure reverts the whole sale.

Note: `price` is what the buyer pays in total. When `debtRepay > 0`, that part goes to the pool and the remainder goes to the seller. This keeps one number for the buyer to reason about.

## 6. Interface changes

- A read-only interface for the pool's `accountData`, `loanToken`, and `repay`. The pool code needs **no change**: `repay(key, amount)` already accepts any payer.
- The coordinator is created by the escrow's constructor, before the pool exists. It must read the pool from `registry.creditModule()` at call time, never from a constructor argument.
- Collateral beyond a collateral's `maxCounted` cap does not count toward `collateralValue`. The disclosure shown to the buyer must say so, or a buyer may think extra tokens in the vault back the loan when they do not.

## 7. Attack and failure analysis

| # | Scenario | Defence |
|---|---|---|
| 1 | Seller borrows the maximum after the buyer signs | `maxDebt` bounds the debt at execution |
| 2 | Seller withdraws collateral after signing | Vault nonce changes, so `StateChanged` |
| 3 | A liquidation lands between signing and execution | Seizure bumps the nonce, so `StateChanged` |
| 4 | Price moves against the buyer before execution | `minCollateralValue` and `minHealthBps` revert the sale |
| 5 | Interest accrues between signing and execution | Covered by `maxDebt` and `minHealthBps`. Buyers should leave headroom |
| 6 | Oracle outage at execution | Sale reverts (fail closed). Nothing is lost, the seller retries later |
| 7 | Seller supplies a fake pool | `pool == registry.creditModule()`, which is bound once and cannot be changed |
| 8 | Old acceptance revived after an ownership change and change-back | Existing `epoch` check |
| 9 | Replay of the same acceptance | Existing `used[digest]` |
| 10 | Buyer is a protocol contract | Existing `BadParties` rules |
| 11 | Payment token charges a fee or misreports | Existing balance-delta checks on both the pool and the seller |
| 12 | Reentrancy through a token | Existing `nonReentrant`, effects before interactions |
| 13 | Sale used to dodge a pending liquidation | Liquidatable accounts revert (step 5) |
| 14 | Debt exactly zero after payoff | Allowed. The account then looks debt-free, and a later release still needs the vault to be empty |

Residual risks, to document and not hide:
- A buyer who sets `maxDebt`, `minCollateralValue` or `minHealthBps` too loosely accepts the worse outcome. The interface must show these in plain language.
- The pool's health is only as good as its oracle. Oracle quality is governed by the feed analysis in `docs/evidence/FEED_ANALYSIS.md`.
- Legal: taking over a loan may count as extending or assuming credit in some jurisdictions (R-30). This needs legal review before any public use.

## 8. Test and verification plan

- Unit tests: success with and without payoff, each revert reason, and each field of the signature (flip one field and the sale must fail).
- Fuzz tests: random debt, collateral, price, and floors. The sale succeeds only when every bound holds.
- Invariants (extend the existing escrow and pool invariant handlers):
  - pool total debt never changes in a sale, except by `debtRepay`;
  - the account's debt after a sale equals the debt before minus `debtRepay`;
  - a sale never leaves an account with health below its signed floor;
  - the Chog never leaves escrow in a sale.
- Mutation checks: remove each of the eight gates in section 5 and confirm a test fails.
- Fork test: a real Chog with a real USDC loan on the mainnet fork, including an oracle-outage case.
- Static analysis: re-run Slither and review new findings.

## 9. Decisions needed before building

1. **Payoff in v1?** It adds a repay step and a token restriction. Recommendation: yes, because it is the cleanest way for a seller to hand over a smaller loan.
2. **Payment token.** Recommendation: any token when `debtRepay == 0`, and the loan token only when `debtRepay > 0`.
3. **Protocol minimum health.** Recommendation: reject any sale with health below 100%, and let the buyer choose any higher floor.
4. **Fees.** None in v1.
5. **Legal review** of assumed-debt transfers before any public pool.
6. **Does the UI need a pre-signing simulation?** Recommendation: yes, a read-only call that returns all the numbers the buyer will be signing against.

## 10. Build order

1. Interface and `DebtAcceptance` type hash with tests for the signature only.
2. `executeDebtSale` without payoff, with the full gate set.
3. Payoff step.
4. Invariants, mutation checks, fork test.
5. Evidence document and risk-register updates (R-09 status).
