# Gate E3: $CHOG held in vaults (not collateral)

Scope: allow the Chog token inside Chog vaults so it travels with the Chog, while giving it **zero** credit value.

## Decision and why

- **Not collateral.** Measured (`docs/evidence/LIQUIDITY_MODEL.md`): the CHOG/WMON pool holds about 47 CHOG in total and selling 10,000 CHOG returns about 2.4 WMON. There is nothing to liquidate into.
- **Held in the vault: yes.** It costs no contract change. `ChogCreditFactory.Params.extraTokens` already adds vault-only tokens. A holder keeps their $CHOG in their Chog's vault, and a buyer of the package receives it.
- Honest value: modest. It supports the "sell the whole vault" idea. It is not claimed as the optional $CHOG hackathon bonus.

## What changed

- No change to `src/` contracts.
- `script/DeployCredit.s.sol`: test deployments deploy a mock $CHOG and pass it as `extraTokens`; the verification step also checks it is vault-allowed and **not** a collateral. The existing guard still refuses the real CHOG token as collateral.
- `script/SmokeCredit.s.sol`: deposits 1,000,000 mock $CHOG into the vault, requires borrowing power unchanged, and withdraws it before releasing the Chog.
- `config/monad-reference.json`: `vaultOnlyTokens` lists the real token with `countsAsCredit: false`, and `collateralPolicy.chogToken` records `enable: false, vaultAllowlist: true`.
- Tests: `ChogTokenHeld.t.sol` (7 tests) and one mainnet-fork test.

## Evidence (run locally; GitHub CI has not run)

| Check | Result |
|---|---|
| Held token adds no credit | A 5,000,000-unit balance leaves collateral value, borrowing power and liquidation value unchanged, and a borrow one unit over the limit still reverts |
| Never blocks an exit | Withdrawable while indebted at the borrowing limit, and with the oracle down; the real collateral stays locked |
| Chog stays in escrow while it is held | `isEmpty` is false and release reverts until the token is withdrawn; then release works |
| Travels with the package sale | After a sale the buyer withdraws the seller's held balance |
| Unlisted tokens still refused | `TokenNotAllowed` for a token nobody allowed |
| Mutation | Breaking the factory's `extraTokens` handling fails the tests |
| Real token on a mainnet fork | A real $CHOG deposit into a real Chog's vault succeeded (the vault's balance-delta check would reject a fee-on-transfer token), added no borrowing power, and was withdrawable at the borrowing limit |
| Real token behaviour | A 10-token transfer on a fork arrived in full: no transfer fee |
| Local chain, real transactions | Deploy 16 txs and smoke 32 txs, 0 failed |

## Limits

- The real token is a 45-byte minimal clone of a shared implementation (7,417 bytes). I read its public functions (name, symbol, decimals, supply) and measured a transfer, but did **not** review the implementation's code. It has no `owner()` or `paused()` function that I could call, but a hidden control or an upgrade path cannot be excluded from this evidence.
- If the token ever blocked transfers, a vault holding it could not withdraw it. That would block releasing the Chog from escrow until the block lifted. Holders can avoid this by simply not depositing $CHOG; the feature is optional per holder.
- Not audited.
