# Holder terms: priority access and the tenure card are built; a rate discount is not

**Question.** Chog Credit's account is keyed to a Chog. Should holders get terms that others cannot?

**First, what is already true.** The pool only lends to accounts whose Chog is escrowed (`ChogCreditPool.borrow`, "only while its Chog is escrowed"). So every borrower is already a holder. A "holders get a better rate than non-holders" perk has nothing to compare against until a public tier exists, and a public tier would widen the pool's risk to people with no account at all. That is why this was not built as a quick change.

## Why a discount is not a one-day change

The pool charges one rate to everyone through a global debt index (`borrowIndex`, "interest accrues per second to every account without per-account writes", `ChogCreditPool.sol:32`). A per-account discount needs a second index or per-account interest tracking, which touches the accounting every invariant test depends on. It also changes lender returns, so it needs the loss model and an audit, and a redeploy (the testnet deployer holds about 0.03 MON, a redeploy costs about 1.8 MON).

## Options, cheapest and safest first

| Option | What it does | Changes pool accounting? | Risk |
| --- | --- | --- | --- |
| **1. Tenure badge (read only)** | A vault open for N days shows a "Holder since" mark. No terms change. | No | None. Proves the idea with the app alone. |
| **2. Priority access to capacity** | When utilization is above a line (say 90%), only vaults older than N days can borrow. Everyone else waits. | No. A check in `borrow` | Low. It allocates scarce capacity and does not price risk. |
| **3. Rebate, paid outside the pool** | Lenders or a treasury fund a periodic USDC rebate to long-held vaults, claimed by the vault's controller. | No | Medium. It is a payment programme, so it needs the securities and payments review in `docs/research/NFT_CREDIT_PRIOR_ART_AND_PAYMENTS.md` section 4. |
| **4. Per-account rate discount** | Lower rate by X bps for tenured vaults. | **Yes** (second index or per-account interest) | High. Needs a redesign of accrual, new invariants and an audit. |

## Recommendation

Do option 1 and option 2 first. They are enforceable on-chain (the registry can record when a vault was created), they never price the NFT, and they leave the interest accounting alone. Hold option 4 until after an audit.

Rules for any option:
1. A perk may change who gets capacity or a small rebate. It may never raise a loan limit because a Chog looks valuable.
2. Frame it as access and discounts, not income. An NFT that pays holders income can look like a security.
3. Tenure (how long a vault has been open) is a better key than rarity. It cannot be bought in one block.

## What option 2 needs

- `AccountVault` or the registry exposes `openedAt`. The vault is created in `ChogAccountRegistry.openVault`, so a timestamp can be stored there.
- `ChogCreditPool.borrow` reads utilization after the borrow and checks `openedAt` when it is above the configured line.
- New config: `priorityUtilBps`, `priorityMinAge`. Both are constructor values, so a testnet redeploy is needed.
- Tests: below the line anyone can borrow; above it only tenured vaults; the line moves with repayments.
- App: show "Priority access" on Borrow when the pool is above the line, and say why a new vault is waiting.

## Status

Built and live on testnet:
- **Tenure card** (option 1): the account shows "Holder since" the date the vault was opened, from the registry's own `createdAt`.
- **Priority access** (option 2): `ChogCreditPool` takes `priorityUtilBps` (90%) and `priorityMinAge` (1 day) at deploy. A borrow that would leave the pool more than 90% used is refused with `PriorityAccessOnly` unless the vault has been open at least a day. It changes who gets scarce capacity and nothing else: not a limit, not a rate. The Borrow screen asks the pool first (`priorityRestricted`) and says why, how long the vault has been open and how long is left, before anything is signed. Tests: `contracts/test/credit/PriorityAccess.t.sol` (7) and `app/e2e/priority.mjs`.

Not built: a per-account rate discount (option 4) and an off-pool rebate (option 3). Both stay out until after an audit and the payments review.
