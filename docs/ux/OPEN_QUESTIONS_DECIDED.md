# Open UX questions: recommended answers

Four questions came out of the flow docs. Each answer below is checked against the contracts as they stand.

## 1. Can a debt-free account show "Prices paused"?

**Recommendation: no.** Health only exists when there is debt. A debt-free account has nothing a price can put at risk, so it never gets the Prices paused chip or the dashed ring.

What it sees instead: a quiet line on the Borrow tab, "Borrowing is paused while prices are unavailable." Adding assets stays open. This keeps the scary state for the people it actually affects.

## 2. Is selling blocked while prices are paused?

**Recommendation: blocked for a sale that carries debt, open for a debt-free sale.**

- Debt-bearing sale: confirmed in code. `executeDebtSale` reverts `PriceUnavailable` when the pool cannot price the account (`AccountTransferCoordinator.sol`, line 220). The buyer's whole decision rests on health after the sale, so this is correct. The UI disables Sign and buy and says why.
- Debt-free sale: the buyer takes on no risk and no price is involved, so allow it. I have not traced the debt-free path line by line for a price read, so treat this as to-verify before the screen copy is final.

## 3. Which component cancels a sale automatically?

**Recommendation: none, and the wireframe was wrong.** I drew an automatic cancel and a frozen account. The contracts do neither.

- A sale is a signature from the buyer over exact terms, including the vault's state nonce, the ownership epoch and a debt ceiling. It is not a locked order.
- If the seller changes the vault (deposit, withdraw, sweep), the nonce changes and the signature stops working. If the account becomes liquidatable, `executeDebtSale` reverts `AlreadyLiquidatable`. If prices pause, it reverts `PriceUnavailable`.
- The buyer can void their own signature at any time with `cancel` or `cancelDebt`.

So the app does the noticing, not a contract. It watches the same conditions and shows the offer as "can't complete" with the reason. The seller's account is never frozen. The wireframe board D has been corrected.

## 4. What state is the account in after the Chog is released?

**Recommendation: the account stays, the Chog leaves.**

- The registry has no close function. `createAccount` reverts `AccountExists` for a key that already has a vault, and the vault address is deterministic per Chog.
- Release only needs zero debt and an empty vault (`releaseBlocker`). Afterwards the vault exists but holds nothing, and the Chog is back in the wallet.
- To use it again, the Chog is put back into escrow against the same vault. No second vault is created.

UI: after release, show "Chog released" in Activity, and on the Account tab show an empty vault with a "Lock this Chog again" action. Do not call it a closed account.
