# Gate C Evidence: NFT escrow and package-safety rules

**Date:** 22 October 2026
**Source commit tested:** `0156112126c776ec48f643ce991c1a5a8acac15e` (branch `claude/chog-credit-brand-27ooac`)
**Evidence states reached:** `LOCAL_BUILD_PASS` for the escrow, registry and vault. Fork runs are local simulations against Monad mainnet state. Nothing is deployed, nothing is audited.
**Toolchain:** as in `GATE_A.md` (Foundry 1.8.6, `network = "monad"`, solc 0.8.24, OpenZeppelin 5.1.0). Fuzz runs 1,000; invariant runs 64, depth 100.

## What Gate C was meant to deliver (from `IMPLEMENTATION_STATUS.md`)

| Gate C item | Result |
|---|---|
| Add `ChogCreditEscrow` and beneficial-owner registry state | Done. `ChogCreditEscrow` is created by the registry's constructor and records `key -> beneficial owner`. It has no owner, admin, pause or rescue function (`test_escrowHasNoAdminSurface_onlyReleaseMovesTokens`). |
| Require escrow deposit before the first portfolio asset deposit or credit activation | Done for assets: `canAcceptAssets` is true only while the Chog is escrowed; the Gate B test-only wallet-held flag is **removed**. Credit activation belongs to Gate D. |
| Block release while any debt or secured pending operation remains | Done through the `ICreditModule` interface (`debtOf`, `hasPendingOperation`), tested with a mock module. Also blocked while the vault holds any accounted asset, and when the module reverts (fail closed). The real credit pool does not exist yet. |
| Test that ordinary external NFT transfers cannot bypass the restrictions because the NFT is held by escrow | Done. While escrowed the owner, a stranger, and an approved-for-all marketplace-style operator all fail to move the token; asserted in a simulation and on the real collection in a fork. |

## How it works

1. `registry.createAccount(collection, tokenId)`: the current holder opens the account (vault) while the Chog is still in the wallet. The vault cannot hold assets in this state.
2. `collection.safeTransferFrom(holder, escrow, tokenId)`: escrow's `onERC721Received` accepts it only from an allowlisted collection, only for an open account, only if `ownerOf` really is the escrow now, and records `from` as the beneficial owner. (Two transactions; a single-call open-and-deposit was deliberately not added to keep the privileged surface small.)
3. While escrowed, `registry.isController(key, who)` is true only for the beneficial owner, and the vault accepts deposits.
4. `escrow.release(collection, tokenId, to)`: beneficial owner only, only when `registry.releaseBlocker(key) == None` (vault empty, and, once bound, the credit module reports no debt and no pending operation). The record is cleared before the transfer.
5. `registry.bindCreditModule(module)`: deployer only, once, never zero. This is the single privileged action in the system.

## Results

```
forge test            -> 71 passed; 0 failed; 5 skipped (fork tests, no RPC)
                         legacy 11 | registry 22 | vault 16 | escrow 21 | invariants 1 suite (6 invariants)
MONAD_MAINNET_RPC_URL=https://rpc.monad.xyz forge test --match-path "test/fork/*"
                      -> 5 passed
forge fmt --check     -> OK
```

Runtime sizes (bytes): `ChogAccountRegistry` 3,742, `ChogCreditEscrow` 2,459, `AccountVault` 3,756.

**Stateful invariants** (random sequences over 3 actors and 3 Chogs, including the dangerous misuse of a plain `transferFrom` into escrow and unsolicited token donations; about 800 calls per action across the run): funded accounts always have their Chog in escrow; an escrow record always matches real custody; accounted balance never exceeds the vault's real balance; the sum of accounted balances equals deposits minus withdrawals; one vault per key at the predicted address.

**Live collection (fork simulation):** for the real holders of Chog 1 (plain EOA) and Chog 2 (EIP-7702-delegated EOA): open an account, `safeTransferFrom` into the escrow, confirm beneficial owner and custody, confirm the previous owner cannot `transferFrom` and a stranger cannot `release`, then release and confirm the real token is back with its holder.

### Do the tests have teeth? (manual mutation check)

Eleven deliberate breakages, applied one at a time, each followed by a full run; every one was caught and the files restored byte for byte:

| Mutation | Caught by |
|---|---|
| `canAcceptAssets` always true | 2 invariants + wallet-held deposit test + release test |
| release ignores blockers | 2 invariants + both release-blocking tests |
| deposit skips collection allowlist | unlisted-collection and stranger-callback tests |
| deposit skips the custody check | forged-callback test |
| `isEmpty` also counts raw balance (dust-grief) | dust test + 2 invariants (first attempt hard-coded the wrong token address and was redone against the mock's real address) |
| `isController` ignores beneficial owner | 4+ tests |
| release does not clear the record | 2 invariants + release tests |
| anyone may release | `test_release_onlyBeneficialOwner` |
| withdrawal ignores debt | `test_withdrawBlockedWhileDebtReported_thenAllowed` |
| account-must-exist check removed | `test_deposit_withoutOpenAccount_revertsAndNftStaysPut` |

This is a hand-run check, not a mutation-testing tool.

## Design decisions worth reviewing

1. **`release` uses `transferFrom`, not `safeTransferFrom`.** The first version used `safeTransferFrom`; a test with an EIP-7702-delegated holder exposed that the transfer would run the delegate's code, which may lack the ERC-721 receiver hook, and then the release reverts. Marketplaces such as Seaport use `transferFrom`. The consequence: no callback into the recipient (no reentrancy surface in release), but releasing to a contract that cannot hold ERC-721s strands the token (`test_release_toNonReceivingContract_works_butIsTheCallersRisk`).
2. **Accounted balances, not `balanceOf`.** Otherwise anyone could send 1 wei of an allowlisted token to a vault and block release of the Chog forever. Stray tokens can be recovered with `sweepUnaccounted`.
3. **Fail closed on the credit module:** if the module reverts, release is blocked (`ModuleUnavailable`) and withdrawals are blocked (`debtOf` reports the maximum).
4. **Beneficial owner is the `from` address of the transfer**, not the operator. A sale before escrow credits the buyer (`test_deposit_afterSale_creditsTheNewHolder`).

## Known limits and trust assumptions

1. **Plain `transferFrom` into the escrow strands the Chog.** No callback means no record, and there is deliberately no rescue function. The same applies to Chogs sent from non-allowlisted collections via plain `transferFrom`. The UI must only ever use `safeTransferFrom`. This is covered by `test_plainTransferFromStrandsTheNft_documentedLimit`.
2. **The credit module is trusted.** The deployer binds it once. A module that reports phantom debt locks the user's Chog and assets; a module that under-reports debt weakens the lender's protection. In production the binder must be a multisig/timelock, or the pool must be bound in the deployment transaction. Until then, no real funds.
3. **The allowlisted collection is trusted to answer `ownerOf` honestly,** and the live Chog Genesis admin role's powers are still unknown (no verified source).
4. **No beneficial-owner transfer exists yet.** To sell a funded Chog today the owner must empty the account, release the Chog and sell it normally. The package transfer (buyer-signed, atomic) is Gate E.
5. **Only ERC-20 custody.** No ERC-721 positions, no native MON.
6. **No solvency math.** Withdrawals are blocked outright while any debt is reported; the health-factor check arrives with the pool (Gate D).
7. **Not done:** static analysis (Slither or similar), an independent review, gas review under Monad's charge-on-limit rule, a deployment script for the new core (`Deploy.s.sol` still deploys the legacy prototype), and the GitHub Actions workflow has still never run. The invariant suite uses 64 runs by default; a longer run (256 runs, about 5 minutes, all six invariants passing) was done once, but **before** `release` was switched from `safeTransferFrom` to `transferFrom`, so it does not cover the final code. Re-run with `forge test --match-contract EscrowInvariantTest --invariant-runs 256` before relying on it.

## Next: Gate D

Credit pool (`ICreditModule` implementation) with share accounting and a debt index, a collateral registry with a real two-source oracle adapter (Chainlink MON/USD with RedStone cross-check), a first real collateral (WMON), liquidation with a close factor, and replacing the blanket withdrawal block with a post-withdrawal solvency check.
