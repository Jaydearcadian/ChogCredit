# Chog Credit: Use Cases

This document lists the user-facing use cases for Chog Credit. Each case is a table with the same fields so that design, build and QA can refer to a single ID.

Screen names (S0 to S15) and their order are defined in [diagrams/screen-map.md](diagrams/screen-map.md).

## Product rules used throughout

- The Chog Genesis NFT is the key to a small on-chain account with its own vault. While the vault holds assets or the account owes money, the Chog stays in escrow.
- The Chog is never priced, never collateral and never seized. Only assets in the vault back the loan.
- Vault assets: WMON (collateral), Uniswap V3 USDC/WMON positions (valued at the oracle price, up to 2 positions), and the $CHOG token (held, worth zero credit, always withdrawable).
- Release of the Chog back to the wallet requires an empty vault (no tokens, no positions) and zero debt.
- Health states: Safe, Watch, At risk, Liquidatable, plus "Prices paused" when the oracle is unavailable. Thresholds come from the pool settings.
- Fail closed: if prices are unavailable, Borrow and withdrawing while in debt are off. Repay, adding assets and debt-free withdrawals still work.
- Transactions show three states to the user: Submitted, Confirmed, Final.
- Everything runs on TESTNET with MOCK assets and a MOCK oracle. Not audited.

---

## UC-001 Open a vault

| Field | Value |
|---|---|
| ID | UC-001 |
| Name | Open a vault |
| Actors | Borrower (Chog holder), Wallet |
| Preconditions | Wallet is connected on the supported network (S0). The borrower holds a Chog Genesis NFT that is not already escrowed. |
| Main flow | 1. Connect the wallet and confirm the network on S0.<br>2. Pick the Chog on S1.<br>3. On S2, read that opening the account escrows the Chog.<br>4. Confirm and sign the open-vault transaction.<br>5. The transaction moves through Submitted, Confirmed and Final.<br>6. S3 shows the Account Card with an empty vault, zero debt and the Chog in escrow. |
| Alternative and error flows | A. Wrong network: S0 asks the user to switch. No transaction is sent.<br>B. User rejects in the wallet: state is Rejected, the user returns to S2 and can retry.<br>C. Transaction reverts: state is Reverted with the reason shown on S2. The Chog is not escrowed. |
| Postconditions | The account exists with its own vault. The Chog is in escrow. S3 is the home screen for this account. |

---

## UC-002 Add WMON

| Field | Value |
|---|---|
| ID | UC-002 |
| Name | Add WMON to the vault |
| Actors | Borrower, Wallet |
| Preconditions | Account is open (UC-001). Wallet holds WMON. |
| Main flow | 1. On S3, choose Add assets to open S5.<br>2. Choose WMON as the asset type.<br>3. Enter the amount.<br>4. Review the amount on S5.<br>5. Sign any approval or transfer the wallet asks for, then confirm.<br>6. The transaction moves through Submitted, Confirmed and Final.<br>7. S4 (Collateral detail) shows the WMON amount, value, price source, freshness, how much counts and the exit.<br>8. S3 shows the updated health. |
| Alternative and error flows | A. Amount is more than the wallet balance: S5 shows an error and nothing is sent.<br>B. Prices paused: adding assets still works. The value of WMON shows as unavailable until prices return. Borrow stays off.<br>C. Transaction reverts or is rejected: the state is shown on S5 and the vault is unchanged. |
| Postconditions | The vault holds the WMON. S3 and S4 show the new asset. |

---

## UC-003 Add a Uniswap position

| Field | Value |
|---|---|
| ID | UC-003 |
| Name | Add a Uniswap V3 USDC/WMON position |
| Actors | Borrower, Wallet |
| Preconditions | Account is open. Wallet holds a Uniswap V3 USDC/WMON position. The vault holds fewer than 2 positions. |
| Main flow | 1. On S3, choose Add assets to open S5.<br>2. Choose Uniswap position.<br>3. Pick the position from the wallet.<br>4. Review on S5 that the position is valued at the oracle price.<br>5. Confirm and sign.<br>6. The transaction moves through Submitted, Confirmed and Final.<br>7. S4 shows the position, its value, price source and freshness.<br>8. S3 shows the updated health. |
| Alternative and error flows | A. The vault already holds 2 positions: S5 does not allow a third and says why.<br>B. Position is not a USDC/WMON position: it is not offered.<br>C. Prices paused: the position can be added, but its value shows as unavailable and Borrow stays off.<br>D. Transaction reverts or is rejected: the vault is unchanged and the state is shown on S5. |
| Postconditions | The vault holds the position. Its value counts toward credit at the oracle price. |

---

## UC-004 Borrow USDC

| Field | Value |
|---|---|
| ID | UC-004 |
| Name | Borrow USDC from the pool |
| Actors | Borrower, Wallet, Pool, Oracle |
| Preconditions | Account is open. Vault holds collateral that counts. Prices are available. The pool has USDC cash. |
| Main flow | 1. On S3, choose Borrow to open S6.<br>2. Enter an amount. S6 shows how much can be borrowed (credit preview).<br>3. S6 shows the health after the borrow and the state that health implies.<br>4. Read the terms on S12 if needed.<br>5. Confirm and sign.<br>6. The transaction moves through Submitted, Confirmed and Final.<br>7. S3 shows the new debt and the updated health. |
| Alternative and error flows | A. Prices paused: Borrow is off. S6 shows Prices paused and does not send a transaction.<br>B. Amount is above what the collateral supports: the preview blocks it and shows the maximum.<br>C. Amount is above the pool cash: the preview blocks it.<br>D. Preview shows a state of At risk or Liquidatable: the user sees it before signing.<br>E. Transaction reverts: state is Reverted with the reason on S6. No debt is added.<br>F. User rejects in the wallet: state is Rejected and the user can edit the amount. |
| Postconditions | Debt is increased by the amount borrowed. The Chog stays in escrow. S3 shows the new debt and health. |

---

## UC-005 Repay in full

| Field | Value |
|---|---|
| ID | UC-005 |
| Name | Repay the loan in full |
| Actors | Borrower, Wallet, Pool |
| Preconditions | The account has debt. The wallet holds enough USDC. |
| Main flow | 1. On S3, choose Repay to open S7.<br>2. S7 shows the full amount owed.<br>3. Choose repay in full.<br>4. Sign any approval the wallet asks for, then confirm.<br>5. The transaction moves through Submitted, Confirmed and Final.<br>6. S3 shows zero debt and the state DebtFree. |
| Alternative and error flows | A. Partial repayment: the user enters a smaller amount. Debt goes down by that amount and the health state updates.<br>B. Wallet has less USDC than owed: S7 shows the shortfall and nothing is sent.<br>C. Prices paused: Repay still works.<br>D. Transaction reverts or is rejected: the debt is unchanged and the state is shown on S7. |
| Postconditions | Debt is zero. The account is DebtFree. The Chog is still in escrow until the vault is also empty (see UC-007). |

---

## UC-006 Withdraw assets

| Field | Value |
|---|---|
| ID | UC-006 |
| Name | Withdraw an asset from the vault |
| Actors | Borrower, Wallet |
| Preconditions | The vault holds the asset. Prices are available if the account has debt. |
| Main flow | 1. On S4, open the asset and choose Exit to open S8.<br>2. Enter the amount to withdraw.<br>3. S8 shows the health after the withdrawal before the user signs.<br>4. Confirm and sign.<br>5. The transaction moves through Submitted, Confirmed and Final.<br>6. The asset returns to the wallet. S3 and S4 update. |
| Alternative and error flows | A. Prices paused and the account has debt: withdrawal is off. S8 shows Prices paused.<br>B. Prices paused and the account is debt-free: withdrawal still works.<br>C. $CHOG: always withdrawable, including while prices are paused.<br>D. Transaction reverts or is rejected: the vault is unchanged and the state is shown on S8. |
| Postconditions | The asset is in the wallet. The vault and health reflect the withdrawal. |

---

## UC-007 Release the Chog

| Field | Value |
|---|---|
| ID | UC-007 |
| Name | Release the Chog back to the wallet |
| Actors | Borrower, Wallet |
| Preconditions | The vault is empty (no tokens and no positions). Debt is zero. |
| Main flow | 1. On S3, choose Withdraw and release to open S8.<br>2. S8 shows two checks: vault empty and zero debt. Both must pass.<br>3. Confirm and sign the release.<br>4. The transaction moves through Submitted, Confirmed and Final.<br>5. The Chog is back in the wallet. S3 no longer shows it as escrowed. |
| Alternative and error flows | A. Vault has assets: S8 lists what is left and blocks the release. The user withdraws each asset first (UC-006). $CHOG counts as an asset here and must be withdrawn too.<br>B. Debt is above zero: S8 blocks the release and links to Repay on S7.<br>C. Prices paused: the release is blocked only if the vault or debt checks fail. Debt-free withdrawals still work.<br>D. Transaction reverts or is rejected: the Chog stays in escrow and the state is shown on S8. |
| Postconditions | The Chog is in the wallet. The account has no escrowed Chog. |

---

## UC-008 Prices go down: Pause Drill (oracle unavailable)

| Field | Value |
|---|---|
| ID | UC-008 |
| Name | Pause Drill: oracle becomes unavailable |
| Actors | Borrower, Oracle (system), UI |
| Preconditions | The account has debt. The oracle stops giving a usable price. This is the drill case on testnet with the mock oracle. |
| Main flow | 1. The UI detects that prices are unavailable.<br>2. S3 shows the Prices paused state.<br>3. The same Prices paused state appears on S4, S6 and S7 where relevant.<br>4. On S6, Borrow is off and the screen explains why.<br>5. On S8, withdrawing while in debt is off and the screen explains why.<br>6. Repay on S7 stays on.<br>7. Adding assets on S5 stays on.<br>8. Debt-free withdrawals stay on.<br>9. When the oracle returns, the UI recalculates the health and shows the state that current prices imply. |
| Alternative and error flows | A. A borrow or debt-bearing withdrawal is attempted anyway: it is refused. Nothing is sent or the transaction reverts with a clear reason.<br>B. The oracle returns at a lower price: the account may now show At risk or Liquidatable (see UC-009).<br>C. The oracle returns but the price is still not usable: the state stays Prices paused. |
| Postconditions | Nothing about the debt or vault changes because of the pause. The account shows its current computed state when prices return. |

---

## UC-009 Health worsens to At risk and Liquidatable (borrower view)

| Field | Value |
|---|---|
| ID | UC-009 |
| Name | Health worsens to At risk, then Liquidatable |
| Actors | Borrower, Oracle (system), UI |
| Preconditions | The account has debt. Vault assets are priced by the oracle. |
| Main flow | 1. The price of vault assets falls.<br>2. S3 moves from Safe to Watch and then to At risk. The health banner and the three numbers update.<br>3. At At risk, S3 offers the actions to repay (S7) or add assets (S5).<br>4. The borrower repays or adds assets. The state moves back toward Safe.<br>5. If the account is not healthy enough, the state becomes Liquidatable. S3 shows Liquidatable and says that anyone may liquidate the account. |
| Alternative and error flows | A. Prices recover: the state moves back up without any action.<br>B. Prices become unavailable during the decline: the state shows Prices paused (UC-008).<br>C. Alerts: S15 controls sound and haptics for risk alerts. The user can turn them on or off. |
| Postconditions | The account state reflects the latest prices and actions. |

---

## UC-010 Get liquidated: what the borrower sees afterwards

| Field | Value |
|---|---|
| ID | UC-010 |
| Name | Account is liquidated |
| Actors | Borrower, Liquidator (anyone), UI |
| Preconditions | The account is Liquidatable (UC-009). |
| Main flow | 1. Anyone may repay part of the account's debt.<br>2. The account's positions are unwound first.<br>3. The liquidator takes vault assets plus a bonus.<br>4. The borrower opens S3 and sees the new debt, the remaining vault contents and the new health.<br>5. The borrower opens S9 (Activity) and finds the liquidation entry with its details.<br>6. The Chog stays in escrow while the vault holds assets or debt remains. |
| Alternative and error flows | A. Account is still unhealthy after the liquidation: it stays Liquidatable or moves to At risk, as the new health implies.<br>B. Liquidation clears all debt and all assets: the borrower can release the Chog through UC-007.<br>C. Borrower repays before liquidation: the account is no longer Liquidatable. |
| Postconditions | Debt and vault contents are reduced. The borrower's assets were taken by the liquidator as described. S9 keeps the record. |

---

## UC-011 Sell a debt-free package

| Field | Value |
|---|---|
| ID | UC-011 |
| Name | Sell a debt-free package with Sell with Vault |
| Actors | Seller (account owner), Buyer, Coordinator contract, Wallet |
| Preconditions | The seller's account is funded and has zero debt. The buyer has a wallet and the funds for the agreed price. |
| Main flow | 1. Seller opens S10 (Sell with Vault).<br>2. S10 shows the package: the Chog, the vault assets and zero debt.<br>3. Seller creates the sale offer and shares it with the buyer.<br>4. Buyer opens S11 (Buyer acceptance) and reviews the package.<br>5. Buyer sets the bounds: vault value at least Y, health at least Z, loan at most 0, a deadline. Buyer signs the bounds.<br>6. Seller executes the sale through the coordinator.<br>7. The sale completes atomically. The transaction moves through Submitted, Confirmed and Final.<br>8. The buyer now owns the account package. Both sides see the result in S9. |
| Alternative and error flows | A. Prices or other inputs move outside the signed bounds before execution: the sale is cancelled automatically (see UC-013).<br>B. Execution reverts: the sale does not complete in part. Nothing transfers. The reason is shown on S10 and S11.<br>C. Buyer does not sign or rejects: no sale is created.<br>D. Deadline passes before execution: the signed bounds no longer allow execution. |
| Postconditions | The package is transferred to the buyer as one unit, or nothing moved. S9 records the result. |

---

## UC-012 Sell a package with a loan (seller)

| Field | Value |
|---|---|
| ID | UC-012 |
| Name | Sell a funded account that has a loan (seller side) |
| Actors | Seller, Buyer, Coordinator contract, Pool |
| Preconditions | The seller's account is funded and owes money. Prices are available. |
| Main flow | 1. Seller opens S10 (Sell with Vault).<br>2. S10 shows the package, the current loan, the vault value, the health and the payoff option.<br>3. Seller sets the price and shares the offer.<br>4. Seller waits while the buyer reviews and signs bounds on S11.<br>5. When the bounds are signed, the seller executes the sale.<br>6. The coordinator checks the bounds. If they hold, the sale completes atomically. If the payoff option was signed, the payoff is taken from the price and sent to the Pool.<br>7. The transaction moves through Submitted, Confirmed and Final. S9 records the sale. |
| Alternative and error flows | A. Prices or the loan move outside the signed bounds before execution: the sale is cancelled automatically. S10 shows Cancelled and the reason. The account is unchanged.<br>B. Execution reverts: state is Reverted with the reason on S10. Nothing transfers.<br>C. Prices paused: execution is not offered while prices are paused, because the bounds depend on vault value and health. (To confirm with the coordinator spec.)<br>D. Seller changes the price: the buyer must review and sign again. |
| Postconditions | The buyer owns the account with the loan as bounded, or the payoff has cleared it. Or the sale was cancelled and nothing changed. |

---

## UC-013 Buyer accepts a package with a loan (buyer side)

| Field | Value |
|---|---|
| ID | UC-013 |
| Name | Buyer signs bounds and accepts a funded package with a loan |
| Actors | Buyer, Seller, Coordinator contract, Wallet |
| Preconditions | The buyer has received a sale offer. The buyer has a wallet and the funds for the price. |
| Main flow | 1. Buyer opens S11 from the offer.<br>2. Buyer reviews the package: the Chog, the vault assets and the loan. Buyer reads S12 (Risk and terms).<br>3. Buyer sets the bounds: loan at most X, vault value at least Y, health at least Z, whether the payoff is taken from the price, and a deadline.<br>4. Buyer signs the bounds in the wallet.<br>5. Buyer waits for the seller to execute.<br>6. S11 and S9 show the result: Final, Cancelled or Reverted. |
| Alternative and error flows | A. Buyer changes any bound: the earlier signature no longer applies and the buyer signs again.<br>B. Prices or the loan move outside the signed bounds before execution: the sale is cancelled automatically and the buyer's signed bounds no longer apply.<br>C. Deadline passes: the sale cannot execute.<br>D. Execution reverts: nothing transfers and the reason is shown.<br>E. Buyer rejects in the wallet: no bounds are signed. |
| Postconditions | Either the buyer has the package, or the sale was cancelled or reverted and nothing changed. |

---

## UC-014 Lender supplies USDC

| Field | Value |
|---|---|
| ID | UC-014 |
| Name | Supply USDC to the pool |
| Actors | Lender, Wallet, Pool |
| Preconditions | The wallet holds USDC. |
| Main flow | 1. Open S13 (Lend) and choose Supply.<br>2. Enter the amount.<br>3. Review the amount and the shares to be received.<br>4. Sign any approval the wallet asks for, then confirm.<br>5. The transaction moves through Submitted, Confirmed and Final.<br>6. The lender holds pool shares. S13 shows the position. |
| Alternative and error flows | A. Amount is more than the wallet balance: nothing is sent.<br>B. Transaction reverts or is rejected: no shares are issued and the state is shown on S13. |
| Postconditions | The lender holds shares in the pool. |

---

## UC-015 Lender redeems

| Field | Value |
|---|---|
| ID | UC-015 |
| Name | Redeem pool shares for USDC |
| Actors | Lender, Wallet, Pool |
| Preconditions | The lender holds pool shares. |
| Main flow | 1. Open S13 (Lend) and choose Redeem.<br>2. Enter the amount to redeem. S13 shows the maximum that can be redeemed now.<br>3. Review the USDC to be received and the shares burned.<br>4. Confirm and sign.<br>5. The transaction moves through Submitted, Confirmed and Final.<br>6. USDC is returned to the wallet and the position updates. |
| Alternative and error flows | A. Amount is above the pool cash: the preview blocks it. A lender can redeem up to the pool's cash, so when cash is low the redeemable amount is lower.<br>B. Transaction reverts or is rejected: the shares are unchanged and the state is shown on S13. |
| Postconditions | Shares are burned and USDC is returned. The position is smaller. |

---

## UC-016 Hold $CHOG in the vault

| Field | Value |
|---|---|
| ID | UC-016 |
| Name | Hold $CHOG token in the vault |
| Actors | Borrower, Wallet |
| Preconditions | The account is open. The wallet holds $CHOG. |
| Main flow | 1. On S3, choose Add assets to open S5.<br>2. Choose the $CHOG token and enter the amount.<br>3. Confirm and sign.<br>4. The transaction moves through Submitted, Confirmed and Final.<br>5. S4 shows $CHOG with its amount and a credit value of zero.<br>6. S3 shows $CHOG as held. It adds no credit. |
| Alternative and error flows | A. Borrowing: $CHOG adds no credit. The borrow limit does not change because of it.<br>B. Withdrawal: the user can withdraw $CHOG at any time, including while prices are paused (UC-006).<br>C. Release: $CHOG counts as an asset in the vault, so it must be withdrawn before the Chog can be released (UC-007).<br>D. Transaction reverts or is rejected: the vault is unchanged and the state is shown on S5. |
| Postconditions | The vault holds $CHOG with zero credit value. The Chog stays in escrow because the vault is not empty. |
